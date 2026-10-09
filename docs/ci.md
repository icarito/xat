# CI — build y publicación (Android / iOS / macOS)

`.github/workflows/release.yml` construye el cliente **xat** sin
compilar el motor: baja el **binario headless** y los **export templates** del
release pineado del fork `icarito/godot-box3d-3` (ver `.github/box3d_release`).

El fork publica templates XMPP separados para xat (`*_xmpp`), además de los
templates generales sin libstrophe/SQLite. El pin actual `v0.5.6-xmpp` ya está
publicado y verificado (incluye el plugin nativo iOS `XatMedia`); los jobs de
xat requieren los assets XMPP.

## Qué hace

**`prep`** resuelve `version_name` / `version_code` (o los toma de los inputs),
el pin del fork y qué plataformas construir.

**Android** (`ubuntu-latest`): en push a `main` construye solo Android; en tag
`v*` construye Android+iOS+macOS y en ejecución manual respeta `platform`. Baja
`godot.box3d.linux.x86_64.headless_xmpp` y los templates
`android_release_xmpp.apk` / `android_debug_xmpp.apk` del release pineado al
directorio de templates de la versión del binario (p. ej. `…/templates/3.6.4.rc/`),
configura JDK 17 + Android SDK (`build-tools;34.0.0`, `platform-tools`), escribe
`editor_settings-3.tres` (SDK, JDK, debug keystore) (los formatos de import
`ETC2`/`ETC`/`PVRTC` que exige `can_export()` ya están en `app/project.godot`), estampa
`version/code` y `version/name` en el preset, exporta con `--export "Android"`
desde `app/`, sube el APK como artefacto y, en tags `v*`, lo adjunta al GitHub
Release.

Antes de exportar, `tools/check_runtime.gd` corre con el binario descargado y
falla si faltan `XmppConnection`, `SQLiteBinding`, `SQLiteQuery` o
`RichTextLabel.add_inline_image`. Luego `tools/check_android_template.py` valida
que ambos APK templates contengan `lib/arm64-v8a/libgodot_android.so` y las
marcas de las clases y métodos nativos clave. La inspección de bytes solo confirma
presencia de cadenas compiladas: no demuestra que el APK arranque ni que XMPP/SQLite
funcionen en un teléfono.

- **Con** `ANDROID_KEYSTORE_B64` + `ANDROID_KEYSTORE_PASS` + `ANDROID_KEY_ALIAS`:
  firma release con esa keystore.
- **Sin** ellos: genera un debug keystore y exporta `--export-debug`
  (`xat-<ver>-debug.apk`, marcado con `::warning::`). **No publicable en Play.**

**macOS** (`macos-latest`): instala Godot stock 3.6.2 y su `.tpz`, reemplaza
`osx.zip` con `osx_xmpp.zip` del fork y exporta el preset macOS a un ZIP.
El artefacto no está firmado ni notarizado.

**iOS** (`macos-latest`): un job `ios_gate` chequea los secretos de firma y, si
faltan, el export iOS se **omite limpiamente** (run verde + `::notice::`). Con
secretos: instala Godot stock 3.6.2 + su `.tpz`, **pisa `iphone.zip` con
`iphone_xmpp.zip` del fork**, importa el certificado (`import-codesign-certs`),
instala el provisioning profile, parchea el preset iOS (team id, bundle id
`org.fuentelibre.xat`, UUID del perfil, identidad de firma, `export_method` App
Store, versión), exporta con `--export "iOS"` (Godot corre **xcodebuild**:
archive + export del IPA), sube el IPA como artefacto, opcionalmente lo sube a
**TestFlight** y, en tags `v*`, lo adjunta al Release.

Use `concurrency` por ref/plataforma y `actions/cache` para templates/config de
Godot, igual que Odisea.

## Cómo correrlo

```sh
# Manual (Actions → Release → Run workflow): platform = android | ios | macos | all,
# version_name y version_code opcionales.
gh workflow run release.yml -f platform=all

# Push a main: artefacto Android para smoke test (sin publicar Release).
# Release: tag y push; Android + iOS (si hay secretos iOS).
git tag v0.1.0 && git push origin v0.1.0   # Android + iOS + macOS, adjunta al Release
```

Con `version_name`/`version_code` vacíos: en tag usa el tag sin `v` como
`version_name` y `github.run_number` como `version_code` (monotónico creciente).

## Secretos (Settings → Secrets and variables → Actions)

| Secreto | Obligatorio | Para | Notas |
|---|---|---|---|
| `ANDROID_KEYSTORE_B64` | release | Android | `.keystore`/`.jks` en base64. Sin él → APK **debug**. |
| `ANDROID_KEYSTORE_PASS` | release | Android | Store y key password (Godot no pasa `--key-pass`). |
| `ANDROID_KEY_ALIAS` | release | Android | Alias de la clave de release. |
| `IOS_CERT_P12_B64` | iOS | iOS | Certificado `Apple Distribution` `.p12` en base64. |
| `IOS_CERT_PASSWORD` | iOS | iOS | Password del `.p12`. |
| `IOS_PROVISION_B64` | iOS | iOS | Provisioning profile App Store en base64 (bundle `org.fuentelibre.xat`). |
| `APP_STORE_CONNECT_KEY_ID` | opcional | TestFlight | API key de App Store Connect. |
| `APP_STORE_CONNECT_ISSUER_ID` | opcional | TestFlight | Issuer ID. |
| `APP_STORE_CONNECT_API_KEY_P8` | opcional | TestFlight | Contenido del `.p8`. |

Sin los tres `IOS_*` el job iOS se saltea (no falla). Sin los tres
`APP_STORE_CONNECT_*` no se sube a TestFlight (igual exporta el IPA).

## Estado del fork

xat **no** compila el motor. El fork mantiene `modules/xmpp` opt-in: sus builds
regulares y `.tpz` no enlazan libstrophe/SQLite; jobs dedicados compilan el
headless y templates Android/iOS/macOS con el módulo. Para habilitar el CI de xat:

1. Desde `main` del fork, ejecutar `gh workflow run release-xmpp.yml --repo icarito/godot-box3d-3 -f tag=v0.5.6-xmpp`. Ese flujo construye solo XMPP y crea un release sin esperar los builds generales. Verificar los assets `godot.box3d.linux.x86_64.headless_xmpp`,
   `android_release_xmpp.apk`, `android_debug_xmpp.apk`, `iphone_xmpp.zip` y
   `osx_xmpp.zip`.
2. Verificar esos assets y mantener `.github/box3d_release` apuntando a esa
   release. `v0.5.6-xmpp` está publicado y verificado con `iphone_xmpp.zip`
   (con el plugin iOS `XatMedia`), `osx_xmpp.zip` y el headless `_xmpp`.
3. Configurar los secretos de firma indicados arriba.

## Riesgos conocidos / pendientes

- **CA bundle (resuelto en el módulo, sin verificar en dispositivo):** si el
  `cafile` pedido no existe y no hay bundle del sistema (Android/iOS),
  `XmppConnection` usa `network/ssl/certificates` o el bundle embebido del
  motor volcado a `user://xat_ca_bundle.pem`. Confirmar en el primer APK.
- **libstrophe/SQLite/mbedTLS cross-compile no verificado en CI:** que
  `android-templates`/`ios-templates` compilen el módulo para todas las ABIs es
  el prerequisito no validado; el CI de xat asume que los assets del release lo
  traen.
- **Assets crudos:** `sfx/*.wav` y `fonts/*.ttf` se leen con `File` (sin import),
  por eso van en `include_filter`. Verificar que queden **crudos** en el `.pck`
  del APK/IPA (Godot puede importar `.wav`/`.ttf` y empaquetar el remap en vez del
  fuente).
- **iOS minimum OS:** el `iphone.zip` del fork puede traer
  `IPHONEOS_DEPLOYMENT_TARGET` viejo. Apple exige ≥ 15.0; si App Store rechaza el
  IPA, portar el parche de Odisea ("Patch iOS minimum OS version") antes de
  exportar.
- **Versión de templates Apple:** el editor macOS es stock 3.6.2 y los
  templates XMPP son del fork (3.6.4.rc). Si la exportación falla, considerar
  publicar también un editor del fork para macOS.
- **Firma macOS:** el ZIP de macOS se construye sin firma ni notarización; es un
  artefacto de CI, no un paquete listo para distribuir a usuarios de Gatekeeper.
- **Firma Android:** el fallback sin secretos produce un APK **debug** firmado
  con el debug keystore — claramente etiquetado y **no apto para Play**.
- **Race del Release:** Android, iOS y macOS adjuntan al mismo tag en paralelo
  (`softprops/action-gh-release` es idempotente; ante un fallo raro, re-correr).
