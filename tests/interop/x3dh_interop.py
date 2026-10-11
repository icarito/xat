#!/usr/bin/env python3
"""Interop de X3DH nativo de xat contra la librería `x3dh` de Syndace.

Usa claves fijas y la MISMA efímera/prekey que el volcado nativo
(`tests/interop/dump_x3dh.gd`), de modo que ambos lados deben coincidir byte a
byte. Requiere el venv con twomemo[xml].

Entrada: el volcado nativo por stdin (líneas CLAVE valor_hex).
Salida: "OMEMO_X3DH_INTEROP_OK" o AssertionError.
"""

import asyncio
import secrets
import sys

from x3dh import IdentityKeyFormat, HashFunction
from x3dh.base_state import BaseState
from x3dh.identity_key_pair import IdentityKeyPairSeed
from x3dh.models import BaseStateModel, IdentityKeyPairModel, SignedPreKeyPairModel
from x3dh.types import Header, SecretType


A_SEED = bytes(range(32))
B_SEED = bytes([1]) * 32
B_SPK_PRIV = bytes([2]) * 32
B_PREKEY_PRIV = bytes([3]) * 32
A_EPHEMERAL = bytes([4]) * 32


class St(BaseState):
    """BaseState directo: sin la automatización de rotación/refill de `State`,
    para poder fijar el signed prekey y el prekey usados."""

    def _publish_bundle(self, bundle):
        pass

    @staticmethod
    def _encode_public_key(key_format, pub):
        return pub


def b_state() -> St:
    model = BaseStateModel(
        identity_key=IdentityKeyPairModel(secret=B_SEED, secret_type=SecretType.SEED),
        signed_pre_key=SignedPreKeyPairModel(
            priv=B_SPK_PRIV,
            sig=secrets_stub_sign(),
            timestamp=0,
        ),
        old_signed_pre_key=None,
        pre_keys=frozenset([B_PREKEY_PRIV]),
    )
    return St.from_model(model, IdentityKeyFormat.ED_25519, HashFunction.SHA_256, b"OMEMO X3DH")


def secrets_stub_sign() -> bytes:
    # La firma del spk de B: Ed25519(B_SEED, spk_pub). No hace falta la librería
    # para firmar; usamos xeddsa como en el resto del proyecto.
    import xeddsa

    priv = xeddsa.seed_to_priv(B_SEED)
    spk_pub = xeddsa.priv_to_curve25519_pub(B_SPK_PRIV)
    return xeddsa.ed25519_priv_sign(priv, spk_pub)


def parse(stdin: str) -> dict:
    out = {}
    for line in stdin.splitlines():
        parts = line.split()
        if len(parts) == 2:
            out[parts[0]] = bytes.fromhex(parts[1])
    return out


async def main(dump: dict) -> None:
    native = dump
    b = b_state()
    bundle_b = b.bundle

    # Mismo ephem/prekey que el nativo: fijamos la aleatoriedad del activo
    # reemplazando sólo la referencia `secrets` del módulo base_state (no la
    # global, que xeddsa usa para el nonce de firma).
    import x3dh.base_state as bs

    class _FakeSecrets:
        @staticmethod
        def token_bytes(n):
            return A_EPHEMERAL[:n]

        @staticmethod
        def choice(seq):
            return list(seq)[0]

    bs.secrets = _FakeSecrets()

    a = St.create(
        IdentityKeyFormat.ED_25519,
        HashFunction.SHA_256,
        b"OMEMO X3DH",
        identity_key_pair=IdentityKeyPairSeed(A_SEED),
    )
    ss_a, ad_a, header_a = await a.get_shared_secret_active(bundle_b)

    assert header_a.identity_key == native["A_IK"], "ik del header"
    assert header_a.ephemeral_key == native["HEADER_EK"], "ek del header"
    assert ss_a == native["SS_ACTIVE"], "ss activo (librería vs nativo)"
    assert ad_a == native["AD_ACTIVE"], "ad activo (librería vs nativo)"

    # Pasivo de la librería consumiendo el HEADER NATIVO.
    header_native = Header(
        identity_key=native["A_IK"],
        ephemeral_key=native["HEADER_EK"],
        signed_pre_key=native["B_SPK"],
        pre_key=native["B_PREKEY"],
    )
    ss_p, ad_p, _ = await b.get_shared_secret_passive(header_native)
    assert ss_p == native["SS_ACTIVE"], "pasivo (librería) vs activo nativo"
    assert ad_p == native["AD_PASSIVE"], "ad pasivo (librería) vs nativo"
    assert ss_p == native["SS_PASSIVE"], "ss pasivo nativo vs librería"

    # El pasivo nativo ya lo validó el volcado (SS_PASSIVE == SS_ACTIVE).
    assert native["SS_PASSIVE"] == native["SS_ACTIVE"], "pasivo nativo vs activo nativo"

    print("OMEMO_X3DH_INTEROP_OK")


if __name__ == "__main__":
    asyncio.run(main(parse(sys.stdin.read())))
