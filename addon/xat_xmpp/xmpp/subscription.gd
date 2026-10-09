extends Reference

# Suscripción de presencia (`jabber:client` presence): alta de contactos y
# autorización de solicitudes. Helper puro, testeable headless.
#
# Flujo estándar (RFC 6121 §3):
#   - `subscribe`:     quiero ver la presencia del otro (mi solicitud).
#   - `subscribed`:    autorizo al otro a ver mi presencia (acepto).
#   - `unsubscribe`:   ya no quiero ver su presencia.
#   - `unsubscribed`:  ya no autorizo al otro a verme (rechazo / baja).
#
# La presencia de suscripción NO es presencia disponible: no trae <show> ni
# <priority> y no debe agregarse como recurso. El modelo de presencia sólo ve
# `available`/`unavailable` (ver `session._on_presence`).

const SUBSCRIBE := "subscribe"
const SUBSCRIBED := "subscribed"
const UNSUBSCRIBE := "unsubscribe"
const UNSUBSCRIBED := "unsubscribed"

const TYPES := [SUBSCRIBE, SUBSCRIBED, UNSUBSCRIBE, UNSUBSCRIBED]

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

static func is_subscription_type(p_type: String) -> bool:
	return TYPES.has(p_type)

# `<presence to='jid' type='subscribe|subscribed|unsubscribe|unsubscribed'/>`.
static func build_presence(p_to: String, p_type: String):
	var p = Stanza.new("presence")
	p.set_attr("to", p_to)
	p.set_attr("type", p_type)
	return p

# Si la stanza es una solicitud de suscripción entrante (`type='subscribe'`),
# devuelve `{jid, status}`; si no, `{}`. El `<status>` suele traer un saludo.
static func request_from(p_stanza) -> Dictionary:
	if p_stanza == null or p_stanza.name != "presence":
		return {}
	if p_stanza.get_attr("type", "") != SUBSCRIBE:
		return {}
	var jid = bare_of(p_stanza.get_attr("from", ""))
	if jid == "":
		return {}
	var status_node = p_stanza.get_child("status")
	return {"jid": jid, "status": "" if status_node == null else status_node.get_text()}

static func bare_of(p_jid: String) -> String:
	var slash = p_jid.find("/")
	return p_jid if slash < 0 else p_jid.substr(0, slash)
