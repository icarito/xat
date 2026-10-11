#!/bin/sh
# Interop de identidad OMEMO contra la implementación de referencia (xeddsa de
# Syndace / OpenClaw). Verifica que la clave pública Ed25519, la conversión a
# X25519 y la FIRMA que produce el código nativo de xat son aceptadas por la
# referencia.
#
# Requiere un venv con `twomemo[xml]==2.1.0` (trae xeddsa/x3dh/doubleratchet):
#   python3 -m venv /tmp/xat-omemo-venv
#   /tmp/xat-omemo-venv/bin/pip install 'twomemo[xml]==2.1.0'
#
# Uso:
#   XAT_OMEMO_VENV=/tmp/xat-omemo-venv tests/interop/omemo_identity_interop.sh
set -e

XAT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${GODOT:-$XAT/bin/godot-xat}"
VENV="${XAT_OMEMO_VENV:-/tmp/kilo/omemo-venv}"
PY="$VENV/bin/python"

[ -x "$BIN" ] || { echo "falta el binario $BIN (corré tools/build.sh)"; exit 1; }
[ -x "$PY" ] || { echo "falta el venv de OMEMO ($PY); ver comentario de este script"; exit 1; }

out=$(env -u WAYLAND_DISPLAY -u DISPLAY SDL_VIDEODRIVER=offscreen AUDIODRIVER=Dummy \
	XAT_AUTOCONNECT=0 XAT_SILENT=1 timeout 60 \
	"$BIN" --no-window --path "$XAT/app" -s "$XAT/tests/interop/dump_identity.gd" 2>&1)

sig=$(printf '%s\n' "$out" | awk '/^SIG /{print $2}')
pub=$(printf '%s\n' "$out" | awk '/^PUB /{print $2}')
x25519=$(printf '%s\n' "$out" | awk '/^X25519 /{print $2}')
[ -n "$sig" ] && [ -n "$pub" ] && [ -n "$x25519" ] || { echo "no se obtuvo el volcado"; printf '%s\n' "$out"; exit 1; }

"$PY" - "$sig" "$pub" "$x25519" <<'PY'
import sys
import xeddsa

sig = bytes.fromhex(sys.argv[1])
pub = bytes.fromhex(sys.argv[2])
x25519 = bytes.fromhex(sys.argv[3])
seed = bytes(range(32))

assert xeddsa.priv_to_ed25519_pub(xeddsa.seed_to_priv(seed)) == pub, "clave pública Ed25519 distinta"
assert xeddsa.ed25519_verify(sig, pub, b"xat signed prekey"), "la firma nativa fue rechazada"
assert xeddsa.ed25519_pub_to_curve25519_pub(pub) == x25519, "conversión a X25519 distinta"
print("OMEMO_IDENTITY_INTEROP_OK")
PY
