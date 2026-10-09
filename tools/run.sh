#!/bin/sh
# Ejecuta xat de escritorio (Linux) siempre con el último motor/módulos.
#
# Los scripts .gd de app/ y addon/ se cargan en vivo (no requieren rebuild); el
# binario sólo se recompila cuando cambia el checkout del motor o el overlay del
# fork desde el último build. El ref usado queda en bin/.xat-build-ref.
#
# Uso: tools/run.sh [args de godot...]
#   GODOT=... FORK=... tools/run.sh
set -e

XAT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
GODOT="${GODOT:-/home/icarito/Proyectos/godot3-box3d/godot-gdtk-slug}"
FORK="${FORK:-/home/icarito/Proyectos/godot3-box3d/godot-box3d-3}"
BIN="$XAT/bin/godot-xat"
STAMP="$XAT/bin/.xat-build-ref"

REV="$(git -C "$GODOT" rev-parse HEAD 2>/dev/null) $(git -C "$FORK" rev-parse HEAD 2>/dev/null)"

if [ ! -x "$BIN" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$REV" ]; then
	echo "xat: sin build al día ($REV) -> compilando con tools/build.sh"
	GODOT="$GODOT" FORK="$FORK" sh "$XAT/tools/build.sh"
	printf '%s\n' "$REV" > "$STAMP"
fi

exec "$BIN" --path "$XAT/app" "$@"
