# App Store — preparación del release de xat

Checklist operativo para que xat pase la revisión de Apple. La fuente de verdad
del producto sigue siendo el plan; esto es sólo la capa de cumplimiento y de
metadata. Referencias: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
(2.1, 2.5.4/2.5.5, 4.5.4, 1.2, 5.1.1), [App Review](https://developer.apple.com/distribute/app-review/)
y comparación con clientes XMPP libres ya publicados (Monal, Snikket, ChatSecure).

## 1. Metadata en App Store Connect

| Campo | Valor |
|---|---|
| Nombre | `xat` |
| Subtítulo | `Cliente XMPP de código abierto` (≤ 30 caracteres) |
| Bundle ID | `org.fuentelibre.xat` |
| SKU | `xat-ios` (libre) |
| Categoría primaria | **Social Networking** |
| Categoría secundaria | Productividad (opcional) |
| Idiomas | Español (principal), inglés |
| Copyright | `© 2026 Fuentelibre` |
| URL de soporte | `https://hablar.fuentelibre.org/soporte/` |
| URL de política de privacidad | `https://hablar.fuentelibre.org/privacidad/` |
| URL de marketing | `https://hablar.fuentelibre.org/` (opcional) |
| Etiqueta de privacidad | **Data Not Collected** (sin analítica ni rastreo) |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` (sólo TLS estándar) |
| Clasificación por edad | 4+ (chat 1:1; sin contenido público). Responder el cuestionario: *Messaging and Chat* = sí, *User-Generated Content* = sí, *Unrestricted Web Access* = no |

Descripción (borrador, sin placeholders ni “próximamente”):

> xat es un cliente de mensajería XMPP de código abierto. Conéctate a tu
> servidor XMPP (por ejemplo el gateway de agentes OpenClaw) con tu JID y tu
> contraseña, chatea 1:1, comparte fotos, vídeos y notas de voz, y consulta el
> historial del servidor. xat no incluye publicidad, analítica ni rastreo, y no
> recopila datos personales: tu cuenta y tus conversaciones permanecen en tu
> dispositivo y en el servidor que tú elijas. Compatible con servidores estándar
> (Prosody, ejabberd) con TLS y SASL.

## 2. App Review Information (campos de App Store Connect)

- **Sign-In Required:** sí.
- **Demo account username:** `reviewer@hablar.fuentelibre.org`
- **Demo account password:** la contraseña generada está en el gateway, en
  `/root/xat-reviewer-credentials.txt` (0600). **No se versiona aquí.**
- **Contacto de revisión:** nombre, teléfono y email de Fuentelibre.

Review notes (copiar tal cual, sustituyendo la contraseña):

```
xat es un cliente XMPP de código abierto. Para usarlo hay que iniciar sesión
en una cuenta XMPP.

Cuenta de revisión (permanente, activa durante la revisión):
  Usuario/JID: reviewer@hablar.fuentelibre.org
  Contraseña:  ********
  Servidor:    hablar.fuentelibre.org   Puerto: 5222 (STARTTLS)
  El servidor exige TLS con certificado válido (Let's Encrypt) y SASL
  SCRAM-SHA-256.

Pasos para revisar:
  1. Abre la app: verás la pantalla de conexión.
  2. Introduce el usuario y la contraseña (el servidor ya viene por defecto).
  3. Pulsa "Conectar": la app valida TLS y SASL y muestra la lista de contactos.
  4. Abre el chat con bob@hablar.fuentelibre.org (agente de prueba) y envía un
     mensaje; el agente responde.

Notas:
  - La app NO requiere notificaciones push y funciona por completo sin ellas
    (guideline 4.5.4).
  - No solicita contactos, ubicación ni identificación del usuario. No hay
    analítica, publicidad ni rastreo (etiqueta: Data Not Collected).
  - El contenido es chat 1:1 con contactos conocidos: no hay salas públicas,
    chat anónimo ni contenido generado por usuarios visible para terceros
    (guideline 1.2 no aplica).
  - Los permisos de cámara, micrófono y fototeca se solicitan únicamente al
    adjuntar una foto, un vídeo o una nota de voz.
  - Política de privacidad: https://hablar.fuentelibre.org/privacidad/
    Soporte: https://hablar.fuentelibre.org/soporte/
```

## 3. Cómo se genera el cumplimiento en el IPA

- `app/export_presets.cfg` (preset iOS) declara los *required reason APIs* del
  privacy manifest. Godot 3.6 los sustituye en `PrivacyInfo.xcprivacy`, que la
  plantilla `iphone_xmpp.zip` ya incluye en la fase *Resources*.
  - `file_timestamp=3` (DDA9.1 · C617.1), `system_boot_time=1` (35F9.1),
    `disk_space=3` (E174.1 · 85F4.1), `user_defaults=4` (CA92.1).
  - `tracking_enabled=false`, sin dominios de rastreo, sin datos recopilados.
- `ITSAppUsesNonExemptEncryption=false` viene en la plantilla iOS del fork.
- No se habilita `UIBackgroundModes` ni el entitlement de push/voip.
- El job `ios` de `.github/workflows/release.yml` verifica, tras exportar, que
  el IPA contiene `PrivacyInfo.xcprivacy` sin placeholders, declara
  `NSPrivacyAccessedAPICategoryUserDefaults`, fija
  `ITSAppUsesNonExemptEncryption=false` y no trae `UIBackgroundModes`.

## 4. Infraestructura de revisión

- Servidor: Prosody en `hablar.fuentelibre.org:5222` con STARTTLS, certificado
  Let's Encrypt válido, SASL SCRAM-SHA-256.
- Cuenta demo `reviewer@hablar.fuentelibre.org` creada y con roster hacia
  `bob@hablar.fuentelibre.org` (agente de prueba que responde).
- Páginas públicas: `/privacidad/` y `/soporte/` servidas por nginx en el mismo
  host. La app enlaza a la política de privacidad dentro de la propia UI
  (pantalla de conexión y pie del roster), como exige 5.1.1(i).

## 5. Estado frente al checklist de investigación

| Punto | Estado |
|---|---|
| Cuenta demo activa + credenciales en App Review Notes | hecho (falta pegar la contraseña en App Store Connect) |
| Push opcional; app funciona sin push | ok (la app no usa push) |
| `UIBackgroundModes` sólo lo necesario + justificación | ok (vacío) |
| Privacy manifest completo | ok (`PrivacyInfo.xcprivacy`, verificado en CI) |
| URL de soporte + política de privacidad | ok (nginx + enlaces en la app) |
| Capturas en todas las resoluciones | **pendiente** |
| Servidor XMPP por IPv6 + TLS | TLS ok; **falta registro AAAA** |
| Sin crashes en login/envío/recepción | login/envío verificados con la cuenta demo; falta prueba en dispositivo iOS |
| UGC (chat público/anónimo) | no aplica (1:1); declarado en Review Notes |

## 6. Acciones manuales pendientes (fuera del repo)

1. **Aplicar el allowlist del agente.** El `openclaw.json` ya autoriza a
   `reviewer@` en la cuenta `bob`, pero el gateway debe reiniciarse:
   ```sh
   sudo -u icarito env HOME=/home/icarito OPENCLAW_STATE_DIR=/opt/claudio-w/openclaw-home \
     /opt/claudio-w/npm-global/bin/openclaw daemon restart
   ```
   Luego verificar que `bob` responde:
   ```sh
   XAT_E2E_JID=reviewer@hablar.fuentelibre.org XAT_E2E_PASS=<pw> \
   XAT_E2E_PEER=bob@hablar.fuentelibre.org bin/godot-xat --no-window --path app -s tools/e2e_probe.gd
   ```
2. **DNS AAAA** (Namecheap) para `hablar.fuentelibre.org` →
   `2a02:4780:6e:2f71::1`, requisito 2.5.5 (redes sólo IPv6). El servidor ya
   escucha en `[::]:5222` y nginx en `[::]:443`.
3. **Capturas de pantalla** en App Store Connect: 6.7" (1290×2796),
   6.5" (1284×2778) y, si se mantiene `Universal`, iPad 12.9" (2048×2732).
   Tomarlas en dispositivo/simulador con sesión iniciada.
4. **App Store Connect:** crear la app (`org.fuentelibre.xat`), pegar metadata,
   cuenta demo y Review Notes; subir el build (TestFlight/`altool` ya está en el
   CI con los secretos `IOS_*` y `APP_STORE_CONNECT_*`).
5. Confirmar el email de soporte/privacidad publicado
   (`sebastian@fuentelibre.org` en las páginas actuales).
6. (Opcional, hardening) `c2s_require_encryption = true` en el VirtualHost de
   Prosody para rechazar conexiones en claro.

## 7. Riesgos conocidos

- **CA en iOS:** el valor por defecto del campo *CA* es
  `/etc/ssl/certs/ca-certificates.crt`, que no existe en iOS. El módulo nativo
  debe caer al bundle CA del motor; verificar en el primer IPA real (login TLS).
- **`voip`/push:** no añadir `UIBackgroundModes` de `voip` ni entitlement de
  push mientras no existan llamadas/push reales (2.5.4 / 4.5.4).
- **OMEMO futuro:** si se integra OMEMO (XEP-0384), revisar
  `ITSAppUsesNonExemptEncryption` (dejaría de ser criptografía exenta).
