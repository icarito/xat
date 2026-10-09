# Notificaciones fuera de primer plano

El plan de v1 fijaba notificaciones **sólo in-app**. Con la app en iOS/Android ya
publicada, el objetivo es avisar cuando xat **no está en primer plano** (background
o cerrada), replicando lo que ya funciona en `gtk-llm-chat-android`.

## Cómo lo resolvió gtk-llm-chat-android

Es una app React Native, y usó **tres capas** independientes:

1. **Servicio en primer plano (Android)** —
   `XmppForegroundService.java`: `startForeground()` con una notificación
   `ongoing` de baja prioridad y un `PARTIAL_WAKE_LOCK` (failsafe 12 h). Mantiene
   vivo el socket XMPP y los timers JS cuando la pantalla se apaga (Doze/Standby
   suspende timers sin wake lock). `START_STICKY` para que el sistema lo levante.
2. **Notificación local** — `src/xmpp/notifications.ts` (expo-notifications):
   - sólo notifica si la app **no** está en foreground, salvo que el chat abierto
     no sea el emisor;
   - descarta *replay* (`<delay>` XEP-0203 > 10 min) y una **ventana de gracia**
     de 15 s post-conexión (el servidor vuelca carbons/pendientes al reconectar);
   - filtra "ruido" (progreso de herramientas, recibos, "Command submitted"),
   - dedupe por `msg.id`, id de notificación estable por conversación
     (`xmpp-msg:<bare>`) para reemplazar en vez de apilar, y botones de
     aprobación (categorías).
3. **Push remoto XEP-0357** — `enableExpoPushIfAvailable()`: al conectar,
   `iq type=set` con `<enable xmlns='urn:xmpp:push:0' jid='expo-push.hablar…'
   node='<expo-token>'/>`. Sirve para cuando la app está **cerrada**; el servidor
   entrega al servicio Expo, que emite la notificación al SO. iOS/apagado usan la
   misma vía.

Reglas clave que conviene copiar:
- notificar **sólo en background** (en foreground ya avisa la UI);
- gracia post-conexión y corte de replay para no inundar al reconectar;
- dedupe por id y notificación estable por conversación;
- el **servicio en primer plano** es lo único que hace fiable la entrega *en
  background* en Android; iOS no permite socket persistente.

## Política anti-ruido (notificaciones "inteligentes")

El cliente Android anterior notificaba de más, repetitivo y poco informativo.
Como con la app cerrada **no corre el cliente**, la mayor parte de la
inteligencia vive en el **gateway**, no en GDScript. Reglas:

1. **Sólo cuando estás ausente.** `mod_cloud_notify` sólo empuja si no hay un
   recurso conectado; con xat abierta no hay push (avisa la UI in-app).
2. **Sólo contenido sustantivo.** Se descartan las ediciones intermedias de
   streaming (el gateway las marca con `<no-store/>`; `mod_push_hints_filter`
   corta su push) y el ruido de progreso/recibos (`xat_push_policy.is_noise`).
3. **Agrupar por conversación, no por mensaje.** Ventana configurable (default
   60 s) que colapsa una ráfaga en **una** notificación, con **id estable** (el
   bare del remitente) para que el SO **reemplace** en vez de apilar
   (`tag`/`collapseKey` en FCM, `threadId`/`collapseId` en APNs). El cuerpo es el
   preview del último mensaje + `(+N)`.
4. **Informativas.** El servidor debe mandar el remitente y el cuerpo reales
   (`push_notification_with_body`/`_with_sender = true`); sin eso el push era
   "Tienes un mensaje nuevo".
5. **Acciones primero.** Un pedido de aprobación/acción se notifica **ya**
   (sin esperar la ventana) y con prioridad alta.
6. **Filtros del servidor (Tigase), activados por el cliente** en el `<enable>`:
   `ignore-unknown` (no push de desconocidos — los agentes son contactos),
   `muted` (conversaciones silenciadas) y `groupchat` (salas: sólo si te
   mencionan). Los módulos `mod_cloud_notify_filters`/`_priority_tag` ya están
   instalados en el gateway.
7. **Silencio nocturno** opcional (`*_push_quiet_enabled`) para lo no-accionable.

## Estado en xat

**Bloqueante verificado (motor):** en Android el main loop de Godot lo itera
exclusivamente el hilo GL (`GodotRenderer.onDrawFrame` → `GodotLib.step()` →
`Main::iteration()`, `platform/android/os_android.cpp`), y `onActivityStopped`
llama `pauseGLThread()`: en background **no corre GDScript**. Por eso la entrega
con la app cerrada/background depende del **push del servidor (XEP-0357)**.

**Implementado (cliente XEP-0357):**
- `xmpp/push.gd`: builders `enable`/`disable` (con publish-options y **filtros
  Tigase**), parseo de `error_condition`/identidad push, persistencia y
  `setting_key(os)` (JID por proveedor).
- `xmpp/session.gd`: `configure_push`, `enable_push(service, token, filtros)`,
  `disable_push`, `push_registered()`, señal `push_registration_changed`;
  re-registro en cada conexión recordando los filtros.
- `ui/notifier.gd`: `device_token()` (delega en el plugin nativo).
- `app/main.gd`: al conectar registra con el JID del SO y `ignore_unknown`.

**Plugin nativo (implementado como parche del fork):**
`godot-box3d-3/patches/xmpp/xat_notify_native.patch` (verificado `git apply`) crea
el singleton `XatNotify` en Android (`XatNotify.java`) e iOS (`xat_notify_ios.*`),
con `isAvailable`/`requestPermission`/`getDeviceToken`/`notify`/`clear` (y alias
snake_case), registro en `GodotPluginRegistry`/`os_iphone.mm`, `POST_NOTIFICATIONS`
en el manifest y el callback APNs en `godot_app_delegate.m`.

## Gateway (servicio push del servidor)

Corre en `hablar.fuentelibre.org` (Prosody + `mod_cloud_notify`). El cliente
registra un token; el servidor entrega a FCM/APNs:

- **Bridges** (`openclaw-xmpp/prosody-modules/`): `mod_fcm_push.lua` (Android) y
  `mod_apns_push.lua` (iOS) forwardean por HTTP al `push-sender`, que es quien
  habla FCM/APNs. La política compartida vive en `xat_push_policy.lua`.
- **JIDs**: Android → `fcm-push.hablar.fuentelibre.org`; iOS →
  `apns-push.hablar.fuentelibre.org`. Configurados en el cliente vía
  `xat/push_service_android` / `xat/push_service_ios` (fallback `xat/push_service`).
- **Config del VirtualHost** (informativas): `push_notification_with_body = true`
  y `push_notification_with_sender = true`.

### Config en el cliente (ProjectSettings)

```
[xat]
push_service_android="fcm-push.hablar.fuentelibre.org"
push_service_ios="apns-push.hablar.fuentelibre.org"
```

Pasos manuales (credenciales Firebase/Apple, URLs) en **`docs/push-setup.md`**.

### Requisitos por plataforma (no verificables en este entorno)

- **Android**: Firebase Messaging. La app debe agregar `firebase-messaging` +
  `google-services.json` y renombrar `XatMessagingService.java.example`. Sin eso
  `getDeviceToken()` devuelve `""` y no se registra (el build no se rompe).
- **iOS**: marcar la capability **Push Notifications** en el preset de export
  (activa `aps-environment`); el callback APNs ya está en el motor.

## Plan de implementación

- [hecho] Cliente XEP-0357 (`push.gd` + filtros + `session.gd` + tests).
- [hecho] Bridges de gateway FCM/APNs + `push-sender` + política compartida.
- [hecho] Plugin nativo `XatNotify` (parche del fork, verificado `git apply`).
- [pendiente] Desplegar módulos Lua + `push-sender` y setear `push_notification_*`
  en Prosody (manual, por SSH; no hay CI).
- [pendiente] Tokens reales: `google-services.json` (Android) y capability APNs
  (iOS); rebuild de templates (`vX.Y.Z-xmpp`) y subir el pin del release.
- [opcional] Foreground service en Android sólo si se quiere recibir **en vivo**
  con la app en background sin depender del push: la notificación tendría que
  postearse desde el hilo del módulo xmpp (JNI), no desde GDScript.

