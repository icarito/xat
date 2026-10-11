#!/bin/sh
# Interop de X3DH: el volcado del nativo (dump_x3dh.gd) se valida contra la
# librería `x3dh` de Syndace. Ver tests/interop/x3dh_interop.py.
set -e

XAT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${GODOT:-$XAT/bin/godot-xat}"
VENV="${XAT_OMEMO_VENV:-/tmp/kilo/omemo-venv}"
PY="$VENV/bin/python"

[ -x "$BIN" ] || { echo "falta el binario $BIN (corré tools/build.sh)"; exit 1; }
[ -x "$PY" ] || { echo "falta el venv de OMEMO ($PY)"; exit 1; }

out=$(env -u WAYLAND_DISPLAY -u DISPLAY SDL_VIDEODRIVER=offscreen AUDIODRIVER=Dummy \
	XAT_AUTOCONNECT=0 XAT_SILENT=1 timeout 60 \
	"$BIN" --no-window --path "$XAT/app" -s "$XAT/tests/interop/dump_x3dh.gd" 2>&1)

printf '%s\n' "$out" | grep -q '^SS_ACTIVE ' || { echo "no se obtuvo el volcado"; printf '%s\n' "$out"; exit 1; }

printf '%s\n' "$out" | "$PY" "$XAT/tests/interop/x3dh_interop.py"
