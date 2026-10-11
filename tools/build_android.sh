#!/bin/sh
# APK de debug local (arm64) con modules/xmpp, sin CI.
#
# Por defecto exporta con las piezas YA PUBLICADAS del release del fork
# (pin en .github/box3d_release): el editor headless y las plantillas Android
# xmpp. Esta es la ruta confiable: editor y plantilla salen del MISMO build del
# release, así que sus versiones coinciden (el fork usa 3.6.4.rc).
#
# Compilar la plantilla en local (scons + gradle) producía un APK que crashea
# al primer frame en el dispositivo (deref nulo en el GLThread): no usar esa
# ruta salvo que se itere el módulo nativo, con XAT_ANDROID_BUILD_TEMPLATE=1.
#
# Uso: tools/build_android.sh [--install]
# Variables: GODOT (árbol del motor, solo si XAT_ANDROID_BUILD_TEMPLATE=1),
#   FORK (overlay del módulo), XAT_ANDROID_SDK, EDITOR (editor tools=yes),
#   XAT_ANDROID_BUILD_TEMPLATE=1 (compilar la plantilla localmente).
set -e

XAT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/home/icarito/Proyectos/godot3-box3d/godot-gdtk-slug}"
FORK="${FORK:-/home/icarito/Proyectos/godot3-box3d/godot-box3d-3}"
SDK="${XAT_ANDROID_SDK:-/run/media/icarito/DATA/icarito/android-sdk}"
WORK="${XAT_ANDROID_WORK:-/run/media/icarito/DATA/icarito/xat-android-work}"
OUT="$XAT/bin/xat-debug.apk"
FORK_REPO="${FORK_REPO:-icarito/godot-box3d-3}"
VER="$(cat "$XAT/.github/box3d_release" | tr -d '[:space:]')"
[ -n "$VER" ] || { echo "pin .github/box3d_release vacío" >&2; exit 1; }

export ANDROID_SDK_ROOT="$SDK" ANDROID_HOME="$SDK"
export ANDROID_NDK_ROOT="$SDK/ndk/29.0.14206865"
export JAVA_HOME="${JAVA_HOME_17:-/usr/lib/jvm/java-17-openjdk}"
export GRADLE_USER_HOME="$WORK/gradle-home"
export SCONS_CACHE="${SCONS_CACHE-$HOME/.cache/scons-godot3}"

mkdir -p "$WORK/editor" "$WORK/data/godot/templates" "$WORK/config/godot" "$XAT/bin"

# --- Editor headless del fork (versión == plantilla) ---
if [ -z "${EDITOR:-}" ]; then
	EDITOR="$WORK/editor/godot-xat-editor"
	EDITOR_MARKER="$WORK/editor/.xat-release"
	if [ ! -x "$EDITOR" ] || [ "$(cat "$EDITOR_MARKER" 2>/dev/null)" != "$VER" ]; then
		echo "Bajando editor headless del fork ($VER) ..." >&2
		gh release download "$VER" --repo "$FORK_REPO" \
			--pattern 'godot.box3d.linux.x86_64.headless_xmpp' --dir "$WORK/editor" --clobber
		mv "$WORK/editor/godot.box3d.linux.x86_64.headless_xmpp" "$EDITOR"
		chmod +x "$EDITOR"
		printf '%s\n' "$VER" > "$EDITOR_MARKER"
	fi
fi
TPL_VER="$("$EDITOR" --version 2>/dev/null | sed 's/\.official.*//; s/\.custom_build.*//')"
[ -n "$TPL_VER" ] || { echo "no pude derivar la versión de $EDITOR" >&2; exit 1; }
TPL_DIR="$WORK/data/godot/templates/$TPL_VER"
mkdir -p "$TPL_DIR"
TPL_MARKER="$TPL_DIR/.xat-release"

# --- Plantilla Android ---
if [ "${XAT_ANDROID_BUILD_TEMPLATE:-0}" = "1" ]; then
	# Ruta de iteración del módulo nativo: compila la plantilla desde el árbol
	# del motor + overlay. Puede crashear en el dispositivo; preferí el release.
	sh "$XAT/tools/apply_emoji_patch.sh" "$GODOT"
	NO_MODULES="bullet csg gridmap enet upnp webrtc websocket webxr mobile_vr gdnative visual_script theora webm
		vorbis opus ogg gltf jsonrpc camera opensimplex raycast box3d decal imgui"
	# shellcheck disable=SC2046
	(cd "$GODOT" && scons -j"${JOBS:-8}" platform=android target=release_debug tools=no android_arch=arm64v8 \
		production=yes lto=none progress=no \
		custom_modules="$FORK","$FORK/modules" module_xmpp_enabled=yes \
		$(for m in $NO_MODULES; do printf 'module_%s_enabled=no ' "$m"; done))
	(cd "$GODOT/platform/android/java" && ./gradlew --no-daemon copyDebugBinaryToBin)
	cp "$GODOT/bin/android_debug.apk" "$TPL_DIR/android_debug.apk"
	cp "$GODOT/bin/android_debug.apk" "$TPL_DIR/android_release.apk"
	printf '%s\n' "$VER" > "$TPL_MARKER"
else
	if [ ! -s "$TPL_DIR/android_debug.apk" ] || [ "$(cat "$TPL_MARKER" 2>/dev/null)" != "$VER" ]; then
		echo "Bajando plantillas Android del fork ($VER) ..." >&2
		gh release download "$VER" --repo "$FORK_REPO" \
			--pattern 'android_debug_xmpp.apk' --pattern 'android_release_xmpp.apk' --dir "$TPL_DIR" --clobber
		mv "$TPL_DIR/android_debug_xmpp.apk" "$TPL_DIR/android_debug.apk"
		mv "$TPL_DIR/android_release_xmpp.apk" "$TPL_DIR/android_release.apk"
		printf '%s\n' "$VER" > "$TPL_MARKER"
	fi
fi

# --- Keystore y settings aislados ---
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

XDG_CONFIG_HOME="$WORK/config" XDG_DATA_HOME="$WORK/data" \
	"$EDITOR" --no-window --path "$XAT/app" --export-debug "Android" "$OUT"
ls -lh "$OUT"

if [ "$1" = "--install" ]; then
	adb install -r "$OUT"
	adb shell monkey -p org.fuentelibre.xat -c android.intent.category.LAUNCHER 1 >/dev/null
fi
