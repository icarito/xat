#!/bin/sh
# APK de debug local (arm64) con modules/xmpp, sin CI:
#   1) compila la plantilla Android del fork (release_debug, arm64v8) con el
#      overlay del módulo xmpp, 2) la empaqueta con gradle, 3) exporta app/ con
#      un editor Godot 3.6 usando esa plantilla, 4) opcional: instala con adb.
#
# Uso: tools/build_android.sh [--install]
# Variables: GODOT (árbol del motor), FORK (overlay), XAT_ANDROID_SDK,
#   EDITOR (binario editor 3.6 tools=yes), JOBS.
# El SDK/NDK y la caché de gradle viven en DATA: /home no tiene espacio.
set -e

XAT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/icarito/Proyectos/godot3-box3d/godot-gdtk-slug}"
FORK="${FORK:-/home/icarito/Proyectos/godot3-box3d/godot-box3d-3}"
sh "$XAT/tools/apply_emoji_patch.sh" "$GODOT"
SDK="${XAT_ANDROID_SDK:-/run/media/icarito/DATA/icarito/android-sdk}"
EDITOR="${EDITOR:-/usr/lib/godot3-bin/Godot_v3.6.3-stable_x11.64}"
WORK="${XAT_ANDROID_WORK:-/run/media/icarito/DATA/icarito/xat-android-work}"
OUT="$XAT/bin/xat-debug.apk"

export ANDROID_SDK_ROOT="$SDK" ANDROID_HOME="$SDK"
export ANDROID_NDK_ROOT="$SDK/ndk/29.0.14206865"
export JAVA_HOME="${JAVA_HOME_17:-/usr/lib/jvm/java-17-openjdk}"
export GRADLE_USER_HOME="$WORK/gradle-home"
export SCONS_CACHE="${SCONS_CACHE-$HOME/.cache/scons-godot3}"

# Mismos módulos apagados que tools/build.sh (xat no los usa), salvo stb_vorbis
# y minimp3 que reproducen audio adjunto (OGG Vorbis / MP3).
NO_MODULES="bullet csg gridmap enet upnp webrtc websocket webxr mobile_vr gdnative visual_script theora webm
	vorbis opus ogg gltf jsonrpc camera opensimplex raycast box3d decal imgui"

# shellcheck disable=SC2046
(cd "$GODOT" && scons -j"${JOBS:-8}" platform=android target=release_debug tools=no android_arch=arm64v8 \
	production=yes lto=none progress=no \
	custom_modules="$FORK","$FORK/modules" module_xmpp_enabled=yes \
	$(for m in $NO_MODULES; do printf 'module_%s_enabled=no ' "$m"; done))

(cd "$GODOT/platform/android/java" && ./gradlew --no-daemon copyDebugBinaryToBin)

# Editor aislado: settings, plantillas y keystore de debug en WORK (no toca
# la config del usuario). Godot busca plantillas en templates/<versión editor>.
VER="$("$EDITOR" --version | sed 's/\.official.*//; s/\.custom_build.*//')"
mkdir -p "$WORK/config/godot" "$WORK/data/godot/templates/$VER"
cp "$GODOT/bin/android_debug.apk" "$WORK/data/godot/templates/$VER/android_debug.apk"
cp "$GODOT/bin/android_debug.apk" "$WORK/data/godot/templates/$VER/android_release.apk"
KS="$WORK/debug.keystore"
[ -f "$KS" ] || "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KS" -storepass android -keypass android \
	-alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null
cat > "$WORK/config/godot/editor_settings-3.tres" <<EOF
[gd_resource type="EditorSettings" format=2]
[resource]
export/android/android_sdk_path = "$SDK"
export/android/debug_keystore = "$KS"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF

mkdir -p "$XAT/bin"
XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data" \
	"$EDITOR" --no-window --path "$XAT/app" --export-debug "Android" "$OUT"
ls -lh "$OUT"

if [ "$1" = "--install" ]; then
	adb install -r "$OUT"
	adb shell monkey -p org.fuentelibre.xat -c android.intent.category.LAUNCHER 1 >/dev/null
fi
