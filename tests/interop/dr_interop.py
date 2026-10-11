#!/usr/bin/env python3
"""Interop del Double Ratchet nativo de xat contra la librería `twomemo`/
`doubleratchet` de Syndace (la de OpenClaw).

El nativo corre como subproceso (`tests/interop/dr_native.gd`); este script
orquesta un ida y vuelta completo en ambos sentidos, incluido el paso de
ratchet DH y claves salteadas (mensajes fuera de orden).

Requiere el venv con twomemo[xml]. Salida: OMEMO_DR_INTEROP_OK.
"""

import base64
import json
import os
import subprocess
import sys

from doubleratchet import EncryptedMessage, Header
from doubleratchet.recommended import diffie_hellman_ratchet_curve25519

from twomemo.twomemo import (
    AEADImpl,
    DoubleRatchetImpl,
    MessageChainKDFImpl,
    RootChainKDFImpl,
)

XAT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BIN = os.environ.get("GODOT", os.path.join(XAT, "bin", "godot-xat"))
SCRIPT = os.path.join(XAT, "tests", "interop", "dr_native.gd")

DHR = diffie_hellman_ratchet_curve25519.DiffieHellmanRatchet
DOS = 1000
MAX_SKIP = 1000

SS = bytes(range(32))
AD = bytes(range(64))
OWN_RATCHET_PRIV = bytes([2]) * 32   # spk priv de B
# La pública del spk de B (la que usaría el activo como recipient_ratchet_pub).
import xeddsa  # noqa: E402
RECIPIENT_PUB = xeddsa.priv_to_curve25519_pub(OWN_RATCHET_PRIV)


def native(op: str, **params: bytes) -> dict:
    env = dict(os.environ)
    env["XAT_DR_OP"] = op
    env["XAT_DR_INPUT"] = json.dumps({k: v.hex() for k, v in params.items()})
    env["XAT_AUTOCONNECT"] = "0"
    env["XAT_SILENT"] = "1"
    env["SDL_VIDEODRIVER"] = "offscreen"
    env["AUDIODRIVER"] = "Dummy"
    proc = subprocess.run(
        [BIN, "--no-window", "--path", os.path.join(XAT, "app"), "-s", SCRIPT],
        env=env, capture_output=True, text=True, timeout=60,
    )
    for line in proc.stdout.splitlines():
        if line.startswith("XAT_DR_OUT "):
            raw = json.loads(line[len("XAT_DR_OUT "):])
            return {k: (bytes.fromhex(v) if k != "state" or True else v) for k, v in raw.items()}
    raise RuntimeError(f"sin salida nativa ({op}):\n{proc.stdout}\n{proc.stderr}")


def header_of(ciphertext: bytes) -> Header:
    # Extrae el header (dh_pub, pn, n) del OMEMOAuthenticatedMessage/OMEMOMessage.
    from twomemo.twomemo import EncryptedKeyMaterialImpl

    return EncryptedKeyMaterialImpl.parse(ciphertext, "b@x", 1).encrypted_message.header


async def main() -> None:
    p0 = bytes([0xA0]) * 48
    p1 = bytes([0xB1]) * 48
    p2 = bytes([0xC2]) * 48
    p3 = bytes([0xD3]) * 48

    # 1) Nativo activo -> la librería descifra el mensaje inicial.
    a = native("active", ss=SS, recipient_pub=RECIPIENT_PUB, ad=AD, plain=p0)
    dr_p, plain = await DoubleRatchetImpl.decrypt_initial_message(
        DHR, RootChainKDFImpl, MessageChainKDFImpl, DoubleRatchetImpl.MESSAGE_CHAIN_CONSTANT,
        DOS, MAX_SKIP, AEADImpl, SS, OWN_RATCHET_PRIV,
        EncryptedMessage(header_of(a["ciphertext"]), a["ciphertext"]), AD,
    )
    assert plain == p0, "la librería no descifró el mensaje inicial nativo"

    # 2) La librería activa -> el nativo descifra el mensaje inicial.
    dr_p, ekm = await DoubleRatchetImpl.encrypt_initial_message(
        DHR, RootChainKDFImpl, MessageChainKDFImpl, DoubleRatchetImpl.MESSAGE_CHAIN_CONSTANT,
        DOS, MAX_SKIP, AEADImpl, SS, RECIPIENT_PUB, p1, AD,
    )
    b = native("passive", ss=SS, own_ratchet_priv=OWN_RATCHET_PRIV, ad=AD, ciphertext=ekm.ciphertext)
    assert b["plaintext"] == p1, "el nativo no descifró el mensaje inicial de la librería"

    # 3) Nativo -> librería (continuación; dispara el ratchet DH del lado librería).
    c = native("encrypt", state=b["state"], ad=AD, plain=p2)
    em = EncryptedMessage(header_of(c["ciphertext"]), c["ciphertext"])
    plain2 = await dr_p.decrypt_message(em, AD)
    assert plain2 == p2, "la librería no descifró la continuación nativa"

    # 4) Librería -> nativo (continuación).
    em3 = await dr_p.encrypt_message(p3, AD)
    d = native("decrypt", state=c["state"], ad=AD, ciphertext=em3.ciphertext)
    assert d["plaintext"] == p3, "el nativo no descifró la continuación de la librería"

    # 5) Fuera de orden: el nativo manda dos; la librería recibe el segundo y
    #    luego el primero (clave salteada).
    e1 = native("encrypt", state=d["state"], ad=AD, plain=bytes([0xE4]) * 48)
    e2 = native("encrypt", state=e1["state"], ad=AD, plain=bytes([0xF5]) * 48)
    got2 = await dr_p.decrypt_message(EncryptedMessage(header_of(e2["ciphertext"]), e2["ciphertext"]), AD)
    got1 = await dr_p.decrypt_message(EncryptedMessage(header_of(e1["ciphertext"]), e1["ciphertext"]), AD)
    assert got2 == bytes([0xF5]) * 48 and got1 == bytes([0xE4]) * 48, "claves salteadas"

    # 6) Librería -> nativo fuera de orden.
    f1 = await dr_p.encrypt_message(bytes([0x11]) * 48, AD)
    f2 = await dr_p.encrypt_message(bytes([0x22]) * 48, AD)
    g2 = native("decrypt", state=e2["state"], ad=AD, ciphertext=f2.ciphertext)
    g1 = native("decrypt", state=g2["state"], ad=AD, ciphertext=f1.ciphertext)
    assert g2["plaintext"] == bytes([0x22]) * 48 and g1["plaintext"] == bytes([0x11]) * 48, "skipped nativo"

    print("OMEMO_DR_INTEROP_OK")


if __name__ == "__main__":
    import asyncio

    asyncio.run(main())
