# xat — arquitectura

`xat` es un cliente XMPP nativo en **Godot 3.6** (fork `godot3-box3d`) para chatear
con los agentes de **OpenClaw** a través del gateway Prosody
(`hablar.fuentelibre.org`). Reemplaza la parte XMPP de `gtk-llm-chat` y a
`gtk-llm-chat-android`; **no** incluye chat con LLMs locales.

Es además un **cliente XMPP general**: también para hablar con personas
(avatares, presencia, OMEMO). Los agentes reciben extras (orbe, telemetría,
aprobaciones), pero nada de la UI asume que el contacto es un agente.

Este documento es la traducción a arquitectura de
`~/.local/share/kilo/plans/1791336573639-xat-godot3-xmpp-client-plan.md` (fuente
única). Si hay conflicto, manda el plan.

## Capas

```
app/                     UI Godot (Control): roster, chat, composer, aprobaciones, cuenta
addon/xat_xmpp/          GDScript: transporte, stanza, sesión, XEPs, historial (headless-testable)
tools/                   build (custom_modules), runner headless, harness de dev
tests/                   tests SceneTree (parsers/modelos puros)
docs/                    esta nota + notas de referencia

godot-box3d-3/modules/xmpp/   nativo, se compila dentro del binario del fork
├── thirdparty/libstrophe/    vendored (+ expat)
├── thirdparty/sqlite/        amalgama sqlite3.c
├── xmpp_connection.*         nodo nativo -> libstrophe (hilo propio, marshalling)
├── tls_mbedtls.c             backend TLS de libstrophe sobre el mbedTLS del motor
├── sqlite_binding.*          binding GDScript mínimo
└── config.py / SCsub / register_types.*
```

El motor se compila con `custom_modules="$FORK","$FORK/modules"` (patrón de
`gdtk/deploy.sh`). xat **no** edita el motor salvo hooks imprescindibles (headers
mbedTLS, ruta del CA bundle), que van en la rama del fork.

## Frontera nativa (híbrida)

- libstrophe hace stream XML, SASL (SCRAM-SHA-1/256), TLS, XEP-0198 (SM) y
  XEP-0138 (compresión). No trae XEPs de alto nivel.
- `tls_mbedtls.c` implementa `conn_interface` de libstrophe sobre mbedTLS,
  **portando** la verificación de cadena + hostname de `StreamPeerSSL`
  (`modules/mbedtls/ssl_context_mbedtls.cpp`, `crypto_mbedtls.cpp`). No inventar
  verificación TLS. CA bundle: el del motor + `XDG`/sistema.
- Nodo `XmppConnection`: `connect/disconnect`, `send_stanza(xml)`, señales
  `stanza_received`, `connected(bound_jid)`, `disconnected(error)`,
  `cert_info(...)`, `log(level,msg)`. `xmpp_run` corre en hilo propio; los eventos
  se encolan y se emiten al hilo principal.
- Helpers nativos **puntuales** sólo donde el XML crudo duela (builder MAM+RSM,
  parseo `jabber:x:data`); empezar mínimo.

## Addon GDScript

Todo el protocolo de alto nivel, testeable headless (estilo gdtk: `extends
SceneTree`, `load().new()`, `check()`, `OS.exit_code`, `quit()`).

| Subsistema | Responsabilidad |
|---|---|
| transporte | adapter sobre `XmppConnection` |
| stanza | parse/serialize con `XMLParser` + builders de string |
| sesión | connect/reconnect con backoff; **recurso estable por dispositivo**; ping 0199; SM resume |
| roster/presencia | `jabber:iq:roster`; presencia agregada por **bare JID** entre recursos; `<status>` |
| mensajería | 1:1; 0085 chat states; 0184 recibos; 0280 carbons; 0203 delay |
| correcciones | 0308: plegar la cadena `<replace>` en una fila (live y MAM) |
| MAM | 0313: preflight disco#info `urn:xmpp:mam:2`; backfill por watermark; RSM; dedupe; **fail-closed** |
| caps/PEP | 0115 caps + 0163 PEP + 0084 avatares + telemetría; detecta agente y full resource JID |
| comandos | 0050 ad-hoc + 0004 forms + 0439 quick responses (aprobaciones) |
| historial | SQLite por bare JID, dedupe por id de MAM, plegado 0308 |

## Plataforma

v1: **Linux / gdtk** (core agnóstico; Android/iOS ya empaquetados). Persistencia
SQLite local. Credenciales: archivo `0600` + override por variable de entorno.
Notificaciones: in-app; fuera de primer plano en preparación (fachada portable en
`ui/notifier.gd`, plan nativo en `docs/notifications.md`).

## XEPs v1

Obligatorias: transmisión + STARTTLS/SASL SCRAM-SHA-1/256 + bind + sesión
(libstrophe); XEP-0199 ping; XEP-0198 SM (libstrophe); roster (`jabber:iq:roster`) +
presence; XEP-0203 delay; XEP-0184 recibos; XEP-0280 carbons; XEP-0085 chat states;
XEP-0313 MAM; XEP-0308 correcciones; XEP-0115 caps; XEP-0163 PEP + XEP-0084 avatares
(+ telemetría); XEP-0050 ad-hoc + XEP-0004 data forms; XEP-0439 quick responses;
XEP-0045 MUC (entrar/salir, ocupantes, groupchat, sujeto, invitaciones mediadas
XEP-0045 §7.8 y directas XEP-0249, MAM de sala, administración de afiliaciones
`muc#admin`, edición de config `muc#owner` y destrucción de sala).

Fuera de v1: 0066 OOB, 0363 upload, 0357 push. 0384 OMEMO: siguiente
prioridad, ver `docs/omemo.md` (política interina incluida). En salas quedan fuera
PM entre ocupantes (XEP-0045 §7.4), OMEMO, XEP-0402 bookmarks nativos, listar
afiliados/roles en una vista dedicada y XEP-0372 refs de mención (la mención es
texto `@nick ` plano, que interopera con el plugin de OpenClaw y con cualquier
cliente).

## Salas (MUC, XEP-0045)

- `xmpp/muc.gd` — helper puro (testeable headless): builders de join/leave/
  groupchat, parser de presencia de sala (códigos 110 self / 201 creada / 210
  renombrado / 307 expulsado / 301 vetado), parser de invitaciones, estado de
  ocupantes y `disco_has_muc`.
- `session.gd` — `_rooms` (nick/sujeto/joined por sala) + `_muc_state` (nick ->
  ocupante). `_on_presence` rutea a la sala **antes** de `presence_model.update`,
  de modo que una presencia de sala nunca contamina el anillo verde de contactos.
  `_on_message` rutea `type=groupchat` (vivo o MAM) por la sala: sin recibos ni
  chat states, dedupe del eco propio por `origin-id`/id de stanza, guardado con
  `sender=nick`. Autojoin de las salas persistidas tras `send_presence()`.
- `store.gd` — columna `sender` en `messages` y tabla `rooms(bare_jid, nick,
  autojoin)`. El dedupe global de `open()` incluye `sender`, para no plegar a dos
  ocupantes que digan lo mismo en el mismo minuto.
- `roster_panel.gd` — sección "Salas" (bajo Contactos) con unread; el botón
  "Unirse a sala" abre `join_room_dialog.gd` (dominio de salas prellenado con el
  componente descubierto). Invitaciones como tarjeta en la banda de solicitudes.
- `chat_panel.gd` + `bubble.gd` — modo sala: título = sala, botón de ocupantes
  (oprimir un nick inserta `@nick ` en el composer), chip de remitente oprimible
  en la primera burbuja de cada grupo entrante, y se suprimen quick/approvals/
  estados/adjuntos.
- **Menú de sala** (botón `⋯`): "Invitar a contacto" (`invite_dialog.gd`, elige
  contacto del roster + razón), "Cambiar tema" (`text_prompt_dialog.gd`),
  "Ajustes de sala" y "Destruir sala" (estos dos sólo dueño/admin/dueño).
- **Moderación de ocupantes**: en el popup de ocupantes, cada nick ajeno trae un
  `⋯` con acciones según nuestra afiliación/rol: hacer/quitar miembro, admin,
  moderador, expulsar y expulsar+banear. `session.muc_can_moderate()/muc_is_owner()`
  guían la UI.
- **Ajustes de sala**: `session.muc_request_config(room)` pide el formulario
  `muc#owner` y emite `muc_config_form(room, form)`; `main.gd` lo muestra con
  `command_dialog.gd` (XEP-0004, con soporte `list-multi`) y
  `session.muc_submit_config(room, fields)` lo guarda. Invitar a una sala
  sólo-miembros también afilia `member` antes (si somos dueño/admin).

### Notas del spike (Prosody de `hablar.fuentelibre.org`, 2026-10)

- Crear la sala al unirse devuelve códigos `[201, 100, 110]` (creada, no anónima,
  self) y el `<item>` trae `jid` (sala no anónima). La creación sólo está permitida
  en el dominio local (`restrict_room_creation=local`).
- El eco propio llega como `from=room/nick` con `origin-id` (XEP-0359) igual al id
  enviado y `stanza-id by=room`: el dedupe por `origin-id`/id es fiable.
- Un `<message type=groupchat from=room><subject/></message>` vacío llega al
  entrar; se ignora (sin body) y los cambios de sujeto se emiten por `muc_subject`.
- Presencia de salida propia: `type=unavailable` + código 110, `role=none`.
- **Sala recién creada queda BLOQUEADA**: Prosody trae `muc_room_locking=true`
  por defecto; la sala sólo se desbloquea (y entonces admite a otros) cuando el
  dueño envía su configuración inicial. Sin esto, el segundo ocupante recibe
  `<presence type=error><error type=cancel><item-not-found/>`. `session.gd`
  detecta el código 201 al crear, pide el formulario `muc#owner` y lo reenvía tal
  cual (conserva los defaults del servidor: `members_only`, etc.), lo que dispara
  `muc-config-submitted`.
- Las presencias de error de sala (`type=error`) NO deben tratarse como altas de
  ocupante: se descartan, se emite `muc_error(room, condition)` y `muc_left`.
- `muc_room_default_members_only=true`: una sala creada por xat sólo admite al
  dueño hasta agregar afiliados `member`; la UI de invitación ya afilia `member`
  (si somos dueño/admin) antes de invitar, así el invitado puede entrar.
- Verificado en vivo (dos cuentas): invitar+afiliar → el invitado entra como
  `member`; cambio de tema visto por ambos; expulsión (rol `none`) cae el ocupante;
  `muc_request_config` devuelve 22 campos; `muc_destroy` expulsa a los ocupantes.
- El eco propio llega con `<origin-id>` y `<occupant-id>`; MAM de sala devuelve
  el remitente en `from=room/nick` y en `<x><item jid=... affiliation=...>`.

## Validación

- **Headless**: `tools/run_tests.sh` (binario del fork, `--no-window --path app -s
  tests/<test>.gd`): stanza parse/serialize, JID, agregación de presencia, plegado
  de 0308, MAM (dedupe/RSM), detección de caps, parseo de items de aprobación,
  render de markdown.
- **Integración local**: Prosody con dos cuentas; ciclo conexión→mensaje→recibo→
  corrección→reconexión→MAM.
- **Integración real**: gateway `hablar.fuentelibre.org`; roster, chat, MAM,
  aprobación end-to-end con `expires-at-ms`.
- **TLS**: contra el servidor real **y** contra un cert inválido (debe fallar).

## Riesgos

- `tls_mbedtls`: sensible a seguridad; portar la verificación del motor + test de
  cert inválido. Plan B: backend OpenSSL.
- `libstrophe` vendorizado: sincronía; validar SM resume.
- XEP-0308: plegado de cadenas (live y MAM) delicado.
- MUC: la semántica de presencia de sala (códigos 110/201/210/307/301) varía entre
  servicios; el branch de `_on_presence` es lo primero a proteger con test, porque
  contaminar `presence_model` rompería el anillo verde de contactos. Sin `origin-id`
  fiable habría burbujas dobles del eco propio.
- Caps 0115: si xat anuncia caps propias, el `ver` es opaco y se sube a mano.
- Overlay del fork: cambios obligan a recompilar/releasear templates.
- SQLite: binding + hilos; no tocarlo desde el hilo de libstrophe.
