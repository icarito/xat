#!/bin/sh
# Screenshot headless de una escena: tools/snap.sh <res://scene> <out.png> [frames] [WxH]
# SDL offscreen: no abre ventana (el binario frt si no se cuelga del Wayland vivo).
XAT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${GODOT:-$XAT/bin/godot-xat}"
SCENE="$1"
OUT="$(realpath -m "$2")"
shift 2
FRAMES="${1:-60}"
SIZE="${2:-980x680}"
exec env -u WAYLAND_DISPLAY -u DISPLAY SDL_VIDEODRIVER=offscreen \
	timeout 60 "$BIN" --path "$XAT/app" --audio-driver Dummy --resolution "$SIZE" $SNAP_ARGS \
	-s "$XAT/tools/snap.gd" -- "$SCENE" "$OUT" "$FRAMES"
