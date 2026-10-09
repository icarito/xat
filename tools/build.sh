#!/bin/sh
# Compila el motor (fork godot3-box3d) con el overlay de módulos propios,
# incluyendo modules/xmpp, y deja el binario en bin/godot-xat.
#
# Uso:
#   tools/build.sh                 # build frt release_debug (app + tests headless)
#   GODOT=... FORK=... tools/build.sh
#
# El módulo xmpp vive en el overlay del fork. La extensión de RichTextLabel se
# aplica desde un parche acotado; no se resetea el checkout del motor.
set -e

XAT="$(cd "$(dirname "$0")/.." && pwd)"
# Checkout del motor (fork 3.6). El overlay de módulos se pasa por custom_modules.
GODOT="${GODOT:-/home/icarito/Proyectos/godot3-box3d/godot-gdtk-slug}"
# Overlay de módulos del fork (box3d, decal, imgui) + modules/xmpp.
FORK="${FORK:-/home/icarito/Proyectos/godot3-box3d/godot-box3d-3}"

sh "$XAT/tools/apply_emoji_patch.sh" "$GODOT"

export SCONS_CACHE="${SCONS_CACHE-$HOME/.cache/scons-godot3}"
export SCONS_CACHE_LIMIT="${SCONS_CACHE_LIMIT:-30000}"

# Módulos que xat no usa: se apagan para acortar build y superficie.
# mbedtls (TLS) y el stack de red se conservan: los usa modules/xmpp.
# stb_vorbis (AudioStreamOGGVorbis) y minimp3 (AudioStreamMP3) SÍ se usan:
# reproducen audio adjunto. `vorbis`/`opus` son dummies de Godot 3.
NO_MODULES="bullet csg gridmap enet upnp webrtc websocket webxr mobile_vr gdnative visual_script theora webm
	vorbis opus ogg gltf jsonrpc camera opensimplex raycast box3d decal imgui"

SUFFIX="${SUFFIX:-xat}"
BIN_NAME="godot.frt.opt.debug.x86_64.${SUFFIX}"

# shellcheck disable=SC2046
(cd "$GODOT" && scons -j"${JOBS:-8}" platform=frt arch=x86_64 target=release_debug tools=no \
	frt_desktop_gl=yes production=yes lto=none use_static_cpp=no progress=no extra_suffix="$SUFFIX" \
	custom_modules="$FORK","$FORK/modules" module_xmpp_enabled=yes \
	$(for m in $NO_MODULES; do printf 'module_%s_enabled=no ' "$m"; done))

mkdir -p "$XAT/bin"
# Se arma en .new y se reemplaza con mv (rename atómico): funciona aunque la
# app esté corriendo ("fichero de texto ocupado" con cp directo).
NEW="$XAT/bin/godot-xat.new"
cp "$GODOT/bin/$BIN_NAME" "$NEW"
# Mismo parche de toolchain que gdtk/deploy.sh: el crt1.o de CachyOS marca el
# binario como x86-64-v4 y el loader lo rechaza en CPUs viejas.
if command -v objcopy >/dev/null 2>&1; then
	objcopy --remove-section=.note.gnu.property "$NEW" "$NEW.tmp" 2>/dev/null \
		&& mv "$NEW.tmp" "$NEW" || rm -f "$NEW.tmp"
fi
mv -f "$NEW" "$XAT/bin/godot-xat"

echo "xat: binario en $XAT/bin/godot-xat"
"$XAT/bin/godot-xat" --version || true
