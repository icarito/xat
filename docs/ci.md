# CI — build y publicación (Android / iOS)

`.github/workflows/release.yml` construye el cliente **xat** sin
compilar el motor: baja el **binario headless** y los **export templates** del
release pineado del fork `icarito/godot-box3d-3` (ver `.github/box3d_release`).

> Clave: los templates tienen que traer el módulo nativo `modules/xmpp`
> (libstrophe + expat + SQLite + mbedTLS) **compilado adentro**. El pin actual
> `v0.5.5-xmpp` es un placeholder pendiente de publicar/verificar;
> desde este entorno no se pudo consultar GitHub. Hasta que exista con esos assets,
> el job Android falla al descargarlos. Ver *Prerequisitos del fork*.

## Qué hace

**`prep`** resuelve `version_name` / `version_code` (o los toma de los inputs),
el pin del fork y qué plataformas construir.

**Android** (`ubuntu-latest`): en push a `main` construye solo Android; en tag
`v*` construye Android+iOS y en ejecución manual respeta `platform`. Baja
`godot.box3d.linux.x86_64.headless` y los
templates `android_release.apk` / `android_debug.apk` del release pineado al
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

**iOS** (`macos-latest`): un job `ios_gate` chequea los secretos de firma y, si
faltan, el export iOS se **omite limpiamente** (run verde + `::notice::`). Con
secretos: instala Godot stock 3.6.2 + su `.tpz`, **pisa `iphone.zip` con el del
fork** (trae `modules/xmpp`), importa el certificado (`import-codesign-certs`),
instala el provisioning profile, parchea el preset iOS (team id, bundle id
`org.fuentelibre.xat`, UUID del perfil, identidad de firma, `export_method` App
Store, versión), exporta con `--export "iOS"` (Godot corre **xcodebuild**:
archive + export del IPA), sube el IPA como artefacto, opcionalmente lo sube a
**TestFlight** y, en tags `v*`, lo adjunta al Release.

Use `concurrency` por ref/plataforma y `actions/cache` para templates/config de
Godot, igual que Odisea.

## Cómo correrlo

```sh
# Manual (Actions → Release → Run workflow): platform = android | ios | all,
# version_name y version_code opcionales.
gh workflow run release.yml -f platform=all

# Push a main: artefacto Android para smoke test (sin publicar Release).
# Release: tag y push; Android + iOS (si hay secretos iOS).
git tag v0.1.0 && git push origin v0.1.0   # android + ios, adjunta al Release
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

## Prerequisitos del fork (paso humano, fuera de xat)

xat **no** modifica el fork. Antes de que este CI sirva:

1. **Commitear `modules/xmpp`** (`libstrophe`, expat, SQLite, mbedTLS, el nodo
   `XmppConnection`, `tls_mbedtls.c`, binding SQLite, `SCsub`/`config.py`) a
   `icarito/godot-box3d-3`, con los hooks al motor (headers mbedTLS + ruta del CA
   bundle) en la rama del fork.
   Incluir también el parche de `RichTextLabel` en
   `tools/patches/z_emoji_inline_source.patch`: headless y templates deben
   exponer `add_inline_image` para preservar Unicode al copiar.
2. **Verificar que los targets `android-templates` e `ios-templates` compilan con
   el módulo** (`scripts/build.sh android-templates ios-templates`) y que el APK
   contiene `libstrophe`/el nodo XMPP.
3. **Cortar un release** etiquetado, p. ej. `v0.5.5-xmpp`, que publique los
   assets `godot.box3d.linux.x86_64.headless`, `android_release.apk`,
   `android_debug.apk` e `iphone.zip`.
4. **Publicar y verificar el release** en GitHub, luego actualizar
   `.github/box3d_release` en xat. El pin actual `v0.5.5-xmpp` es placeholder:
   no se verificó que el release ni sus assets existan; el entorno de trabajo no
   pudo resolver `api.github.com`.
5. Setear los secretos de arriba en el repo de xat.

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
- **Versión de templates iOS:** el editor macOS es stock 3.6.2 y el
  `iphone.zip` es del fork (3.6.4.rc). Odisea usa este mismo arreglo; si falla,
  considerar un editor del fork para macOS.
- **Firma Android:** el fallback sin secretos produce un APK **debug** firmado
  con el debug keystore — claramente etiquetado y **no apto para Play**.
- **Race del Release:** android e ios adjuntan al mismo tag en paralelo
  (`softprops/action-gh-release` es idempotente; ante un fallo raro, re-correr).
