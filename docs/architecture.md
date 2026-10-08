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

v1: **Linux / gdtk** (core agnóstico; Android/iOS en fases posteriores). Persistencia
SQLite local. Credenciales: archivo `0600` + override por variable de entorno.
Notificaciones: **sólo in-app**.

## XEPs v1

Obligatorias: transmisión + STARTTLS/SASL SCRAM-SHA-1/256 + bind + sesión
(libstrophe); XEP-0199 ping; XEP-0198 SM (libstrophe); roster (`jabber:iq:roster`) +
presence; XEP-0203 delay; XEP-0184 recibos; XEP-0280 carbons; XEP-0085 chat states;
XEP-0313 MAM; XEP-0308 correcciones; XEP-0115 caps; XEP-0163 PEP + XEP-0084 avatares
(+ telemetría); XEP-0050 ad-hoc + XEP-0004 data forms; XEP-0439 quick responses.

Fuera de v1: 0045 MUC, 0066 OOB, 0363 upload, 0357 push. 0384 OMEMO: siguiente
prioridad, ver `docs/omemo.md` (política interina incluida).

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
- Caps 0115: si xat anuncia caps propias, el `ver` es opaco y se sube a mano.
- Overlay del fork: cambios obligan a recompilar/releasear templates.
- SQLite: binding + hilos; no tocarlo desde el hilo de libstrophe.
