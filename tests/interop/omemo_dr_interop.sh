#!/bin/sh
# Interop del Double Ratchet nativo contra twomemo/doubleratchet (Syndace).
set -e

XAT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="${GODOT:-$XAT/bin/godot-xat}"
VENV="${XAT_OMEMO_VENV:-/tmp/kilo/omemo-venv}"
PY="$VENV/bin/python"

[ -x "$BIN" ] || { echo "falta el binario $BIN (corré tools/build.sh)"; exit 1; }
[ -x "$PY" ] || { echo "falta el venv de OMEMO ($PY)"; exit 1; }

GODOT="$BIN" "$PY" "$XAT/tests/interop/dr_interop.py"
