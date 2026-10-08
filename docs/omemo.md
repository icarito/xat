# xat — SPEC de cifrado OMEMO (XEP-0384)

Estado: **no implementado**. Este documento junta lo aprendido para hacerlo
bien. Mientras tanto rige la política interina (abajo).

## Por qué hace falta

xat es un cliente XMPP general (agentes **y** personas). Los contactos que
usan Cheogram, Conversations, Gajim, Dino o gtk-llm-chat esperan OMEMO; los
agentes OpenClaw con `omemo.enabled` cifran hacia toda cuenta que publique
dispositivos OMEMO. La cuenta del usuario ya los publica (Cheogram,
gtk-llm-chat-android), así que **a xat le llegan mensajes cifrados**.

Observado en vivo (2026-10-08): Bob (OpenClaw) responde con
`<encrypted xmlns="urn:xmpp:omemo:2"><header sid=…><keys jid=…><key rid=…>`
sin `<body>` en claro. Las ediciones 0308 de streaming también van cifradas
(OpenClaw mantiene `<replace>` en la stanza exterior y cifra sólo el body).

## Política interina (vigente)

- xat muestra "🔒 Mensaje cifrado con OMEMO: xat todavía no puede leerlo" en
  vez de descartar en silencio (`session.gd`, `OMEMO_PLACEHOLDER`).
- openclaw-xmpp **espeja** el cifrado del último mensaje directo del peer
  (`src/omemo/inbound-mirror.ts`, config `omemo.mirrorInbound`, default
  true): si xat escribe en claro, el agente responde en claro. Peers sin
  historial (mensajes proactivos) siguen cifrados; `requireEncryption` gana.
  Requiere redeploy de los agentes.
- Limitación: un mensaje proactivo del agente (o de una persona con OMEMO)
  sigue llegando cifrado a xat hasta que xat implemente OMEMO.

## Alcance de la implementación

Requisito: leer y escribir **OMEMO 2** (`urn:xmpp:omemo:2`, el que usan
OpenClaw v2/dual y clientes modernos). **Legacy** (`eu.siacs.conversations.axolotl`,
OMEMO 0.3 / libsignal) en una segunda etapa: Conversations/Cheogram aún lo
usan mucho, así que es necesario para "seres queridos".

Nodos PEP (2.0): `urn:xmpp:omemo:2:devices` (lista de dispositivos, item
`current`) y `urn:xmpp:omemo:2:bundles` (un item por device id). Legacy:
`eu.siacs.conversations.axolotl.devicelist` y `…bundles:<deviceid>`.

## Criptografía (OMEMO 2)

- Identidad Ed25519 (se convierte a X25519 para X3DH).
- X3DH para iniciar sesión: identity key, signed prekey (firma Ed25519),
  ~100 prekeys de un solo uso publicadas en el bundle.
- Double Ratchet con HKDF-SHA-256; mensaje cifrado con AES-256-CBC +
  HMAC-SHA-256 (truncado), como define XEP-0384 §4.
- Payload envuelto en SCE (XEP-0420): `<envelope><content><body/></content>
  <rpad/><from/></envelope>`; el `<payload>` es el envelope cifrado con una
  clave aleatoria, y esa clave va cifrada por dispositivo en `<key rid>`
  (`kex="true"` cuando es un KeyExchange inicial).
- Mensajes internos en protobuf (OMEMOMessage, OMEMOAuthenticatedMessage,
  OMEMOKeyExchange): pocos campos, se codifican a mano sin librería.

## Arquitectura en xat

- **Nativo**, en `modules/xmpp` del fork (no GDScript): la cripto no se
  escribe en un lenguaje sin tiempos constantes ni tipos de bytes adecuados.
- Primitivas: el mbedTLS del motor da AES-CBC, HMAC-SHA-256, HKDF, SHA-512;
  **no** trae Ed25519. Vendorizar **monocypher** (pequeño, BSD/CC0, X25519 +
  EdDSA/Ed25519 + conversión) en `modules/xmpp/thirdparty/`. No escribir
  curvas a mano.
- Estado (identidad, prekeys, sesiones ratchet, device lists, confianza) en
  el SQLite existente (`history.db` u otro archivo `0600`), sólo desde el
  hilo principal (regla de AGENTS.md: nunca desde el hilo de libstrophe).
- API GDScript mínima en un nodo/binding `Omemo`: `encrypt(bare, text) ->
  xml`, `decrypt(stanza_xml) -> {body, sender_device, trust}`, más
  publicación de bundle/devicelist vía la sesión (PEP 0163, ya existe
  `pep.gd`).
- Caps: anunciar `urn:xmpp:omemo:2:devices+notify` (y legacy luego) y subir
  `XAT_VER`.
- Un device id estable por instalación (como el recurso estable).

## Confianza

BTBV (blind trust before verification), como Conversations: se confía en
dispositivos nuevos hasta que el usuario verifica alguno; después, los nuevos
quedan sin confianza. UI: fingerprints en el perfil del contacto, indicador
de candado por burbuja (cifrado / no cifrado / dispositivo no confiable).
Con agentes, mostrar el candado en el panel "mente".

## Interop y pruebas

- Vectores: OpenClaw usa la librería Python `omemo` de Syndace
  (`SessionManager` en `openclaw-xmpp/src/omemo/sidecar.py`); sirve como
  par de interop local sin servidor real.
- Prosody local con dos cuentas: xat ↔ sidecar Python, ambos sentidos,
  KeyExchange inicial, mensajes posteriores, ediciones 0308 cifradas, MAM de
  mensajes cifrados (se descifran al llegar; guardar el texto plano con
  `was_encrypted=1`, la columna ya existe en `store.gd`).
- Casos que deben fallar: firma de signed prekey inválida, HMAC alterado,
  mensaje para otro rid.
