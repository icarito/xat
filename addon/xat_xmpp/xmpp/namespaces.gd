extends Reference

# Namespaces XMPP usados por xat. Se preloadea como `const NS = preload(...)`
# y se accede `NS.DELAY` (no hay `class_name` para no chocar con nativas).

const CLIENT := "jabber:client"
const ROSTER := "jabber:iq:roster"
const PRESENCE := "jabber:client"
const DELAY := "urn:xmpp:delay"
const CHATSTATES := "http://jabber.org/protocol/chatstates"
const RECEIPTS := "urn:xmpp:receipts"
const CARBONS := "urn:xmpp:carbons:2"
const FORWARD := "urn:xmpp:forward:0"
const CORRECT := "urn:xmpp:message-correct:0"
const MAM := "urn:xmpp:mam:2"
const RSM := "http://jabber.org/protocol/rsm"
const DATA_FORMS := "jabber:x:data"
const DISCO_INFO := "http://jabber.org/protocol/disco#info"
const DISCO_ITEMS := "http://jabber.org/protocol/disco#items"
const COMMANDS := "http://jabber.org/protocol/commands"
const QUICK_RESPONSE := "urn:xmpp:tmp:quick-response"
const QUICK_RESPONSE_0 := "urn:xmpp:quick-response:0"
const SID := "urn:xmpp:sid:0"
const PING := "urn:xmpp:ping"
const CAPS := "http://jabber.org/protocol/caps"
# XEP-0357: notificaciones push. El cliente registra un token de dispositivo con
# el servicio push del servidor para recibir avisos con la app cerrada.
const PUSH := "urn:xmpp:push:0"
const PUBSUB_PUBLISH_OPTIONS := "http://jabber.org/protocol/pubsub#publish-options"
const AVATAR_DATA := "urn:xmpp:avatar:data"
const AVATAR_METADATA := "urn:xmpp:avatar:metadata"
const TELEMETRY := "urn:openclaw:telemetry:0"
const HOOKS_ACTIVITY := "urn:openclaw:hooks:activity:0"
const HOOKS_APPROVAL := "urn:openclaw:hooks:approval:0"
const HOOKS_PROGRESS := "urn:openclaw:hooks:progress:0"
const PUBSUB := "http://jabber.org/protocol/pubsub"
const PUBSUB_EVENT := "http://jabber.org/protocol/pubsub#event"
const PEP := PUBSUB_EVENT
# Adjuntos: XEP-0066 (OOB) para el link y XEP-0363 (HTTP Upload) para subirlo.
const OOB := "jabber:x:oob"
const HTTP_UPLOAD := "urn:xmpp:http:upload:0"
# Variante legacy de disco#items (algunos servidores la usan para el upload).
const DISCO_ITEMS_META := "http://jabber.org/protocol/disco#items"
# Salas multi-usuario (XEP-0045) e invitaciones (XEP-0045 §7.8 / XEP-0249).
const MUC := "http://jabber.org/protocol/muc"
const MUC_USER := "http://jabber.org/protocol/muc#user"
const MUC_OWNER := "http://jabber.org/protocol/muc#owner"
const MUC_ADMIN := "http://jabber.org/protocol/muc#admin"
const MUC_ROOMCONFIG := "http://jabber.org/protocol/muc#roomconfig"
const CONFERENCE_INVITE := "jabber:x:conference"
const STANZAS := "urn:ietf:params:xml:ns:xmpp-stanzas"
