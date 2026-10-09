# Puesta en marcha del push (XEP-0357) — pasos manuales

Lo que ya quedó hecho por la automatización y lo que requiere tu cuenta de
Firebase/Apple. Package Android y bundle iOS: **`org.fuentelibre.xat`**.

## Ya hecho

- **Gateway (`hablar.fuentelibre.org`)**: Prosody con `cloud_notify` +
  `fcm_push` + `apns_push` + `push_hints_filter`; `push_notification_with_body`
  y `push_notification_with_sender` en `true` (push informativo con remitente y
  cuerpo). Los bridges apuntan a `http://127.0.0.1:8787/push/{fcm,apns}`.
- **push-sender**: corriendo como servicio systemd `xat-push-sender` en
  `/opt/xat-push-sender` (Node), con `PUSH_SECRET` ya configurado y las
  dependencias instaladas. Responde `/health` → `{"ok":true}`. Falla limpio
  hasta cargar credenciales de proveedor.
- **APNs (iOS)**: key cargada (`AuthKey_APNS.p8`, Key ID `7R3JZHA2V5`, Team ID
  `9FR93PNNRC`, topic `org.fuentelibre.xat`, producción). Validada contra APNs
  con un token de prueba (`BadDeviceToken` = auth/relación OK, token inválido).
- **FCM (Android)**: clave de cuenta de servicio cargada
  (`fcm-service-account.json`) y validada contra FCM con un token de prueba
  ("registration token is not a valid FCM registration token" = auth OK).
- **Motor**: release `v0.5.10-xmpp` en `icarito/godot-box3d-3`: plugin nativo
  `XatNotify` + `firebase-messaging` en la plantilla Android + fix iOS
  `aps-environment` (production en Release).

Backup de la config de Prosody: `/etc/prosody/prosody.cfg.lua.bak.<timestamp>`.

## 1. Firebase (Android / FCM)

Membresía: Firebase es **gratis** (Spark) y FCM no tiene costo.

- Consola: https://console.firebase.google.com/
- Guía FCM Android: https://firebase.google.com/docs/cloud-messaging/android/client
- Claves de servicio: consola → ⚙️ **Configuración del proyecto** →
  **Cuentas de servicio** → **Generar nueva clave privada** (JSON).

Pasos:
1. Crear un proyecto Firebase.
2. **Agregar app → Android**, package name **`org.fuentelibre.xat`**.
3. Descargar **`google-services.json`**.
4. Generar la **clave privada de la cuenta de servicio** (JSON) para FCM HTTP v1.
5. Subir la clave al servidor y reiniciar el sender:
   ```bash
   scp <service-account>.json icarito@hablar.fuentelibre.org:/tmp/fcm.json
   ssh icarito@hablar.fuentelibre.org
   sudo mv /tmp/fcm.json /opt/xat-push-sender/fcm-service-account.json
   sudo chmod 600 /opt/xat-push-sender/fcm-service-account.json
   sudo systemctl restart xat-push-sender
   ```
6. **Motor (hecho, v0.5.10-xmpp)**: la plantilla Android ya incluye
   `firebase-messaging`; la app inicializa Firebase con los valores del
   `google-services.json` vía `XatNotify.configure(...)`, tomados de
   `ProjectSettings` (`xat/firebase_api_key/app_id/project_id/sender_id`, ya
   seteados en `app/project.godot`). No hace falta el plugin Gradle
   `google-services` ni hornear el JSON en la plantilla.

## 2. Apple (iOS / APNs)

Requiere **Apple Developer Program** (USD 99/año).

- Keys (auth por token APNs): https://developer.apple.com/account/resources/authkeys/list
- Identifiers (App ID): https://developer.apple.com/account/resources/identifiers/list
- Certificates, Identifiers & Profiles: https://developer.apple.com/account/resources/
- Docs (conexión por token): https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns

Pasos:
1. **Identifiers**: seleccionar/crear el App ID **`org.fuentelibre.xat`** y
   habilitar **Push Notifications**.
2. **Keys** → **+** → marcar **Apple Push Notifications service (APNs)** →
   descargar el **`.p8`** (sólo se puede descargar **una vez**). Anotar el
   **Key ID**.
3. Anotar el **Team ID** (arriba a la derecha en el portal).
4. Subir el `.p8` y completar el `.env` del servidor:
   ```bash
   scp AuthKey_XXXXXX.p8 icarito@hablar.fuentelibre.org:/tmp/apns.p8
   ssh icarito@hablar.fuentelibre.org
   sudo mv /tmp/apns.p8 /opt/xat-push-sender/AuthKey_APNS.p8
   sudo chmod 600 /opt/xat-push-sender/AuthKey_APNS.p8
   sudo nano /opt/xat-push-sender/.env   # APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC=org.fuentelibre.xat
   sudo systemctl restart xat-push-sender
   ```
5. En el preset de export iOS de xat, activar la capability
   **Push Notifications** (Godot la traduce a `aps-environment`). El callback
   APNs ya vive en el motor (`godot_app_delegate.m`).
   - **Ojo (TestFlight/App Store)**: el motor escribe
     `aps-environment = development` fijo (`platform/iphone/export/export.cpp`
     con `capabilities/push_notifications`). Para builds de **distribución**
     APNs espera `production`. Si al archivar para TestFlight los push no
     llegan (token sandbox vs `APNS_PRODUCTION=true` del sender), hay que
     cambiar esa entitlements a `production` (editar el `.entitlements`
     generado antes del archivo, o parchear el motor para elegir el entorno).

## 3. Cliente xat

En `app/project.godot`:
```
[xat]
push_service_android="fcm-push.hablar.fuentelibre.org"
push_service_ios="apns-push.hablar.fuentelibre.org"
```
Y actualizar `.github/box3d_release` a `v0.5.8-xmpp` (o el tag vigente), luego
reexportar la app.

## 4. Verificación

- Sender: `curl -s http://127.0.0.1:8787/health` en el servidor.
- Prosody: `sudo grep -iE "push bridge loaded" /var/log/prosody/prosody.log`.
- Fin a fin: con la app **cerrada**, mandar un mensaje desde otro contacto y
  recibir la notificación (informativa, sin repetir por ráfaga).

## 5. Filtros y anti-ruido (ya activos)

- El cliente registra con `ignore-unknown` (no push de desconocidos).
- Silenciar conversaciones: pasar `muted` a `session.enable_push(...)`.
- Agrupamiento por conversación (60 s) + notificación estable (reemplaza, no
  apila); las ediciones de streaming no disparan push (`push_hints_filter`).
