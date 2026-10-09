extends Reference

# XEP-0357 (Push Notifications): registro del token de dispositivo con el
# servicio push del servidor, para que el servidor avise (APNs/FCM) cuando xat
# está cerrada o en background. Helper puro, testeable headless.
#
# Flujo:
#   1. El cliente obtiene un token del SO (FCM en Android, APNs en iOS) — eso lo
#      entrega el plugin nativo; acá sólo llega como string.
#   2. Al conectar, `enable` registra `<jid servicio push, node token>`.
#   3. Al desconectar la cuenta (logout), `disable` lo da de baja.
#   4. El servidor, al llegar un mensaje, despierta la app por el servicio push.

const NS := "urn:xmpp:push:0"

# Filtros de push del servidor (Tigase, ya presentes en el gateway): el cliente
# los activa agregándolos al `<enable>`. Sirven para no recibir push de
# desconocidos, de conversaciones silenciadas o de salas donde no te mencionan.
const FILTER_UNKNOWN := "tigase:push:filter:ignore-unknown:0"
const FILTER_MUTED := "tigase:push:filter:muted:0"
const FILTER_GROUPCHAT := "tigase:push:filter:groupchat:0"

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NSs = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")

const STORE_PATH := "user://xat_push.json"

# Setting del proyecto con el `jid` del servicio push, según el proveedor del SO
# (FCM en Android, APNs en iOS): cada uno tiene su bridge en el gateway.
static func setting_key(p_os_name: String) -> String:
	return "xat/push_service_ios" if p_os_name == "iOS" else "xat/push_service_android"

# `<iq type='set'><enable xmlns='urn:xmpp:push:0' jid node/></iq>`.
# `p_options` (Dictionary var->valor) agrega las publish-options de PubSub que
# algunos servicios (FCM/APNs) exigen; vacío = no se manda el bloque `<x>`.
# `p_filters` activa los filtros del servidor: {ignore_unknown:bool,
# muted:[jid...], groupchat:[{jid, when, nick}]}.
static func build_enable(p_id: String, p_service_jid: String, p_node: String, p_options: Dictionary = {}, p_filters: Dictionary = {}):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	var enable = Stanza.new("enable")
	enable.set_attr("xmlns", NS)
	enable.set_attr("jid", p_service_jid)
	enable.set_attr("node", p_node)
	if not p_options.empty():
		var x = Stanza.new("x")
		x.set_attr("xmlns", NSs.DATA_FORMS)
		x.set_attr("type", "submit")
		x.add_child_stanza(_field("FORM_TYPE", NSs.PUBSUB_PUBLISH_OPTIONS))
		for key in p_options.keys():
			x.add_child_stanza(_field(str(key), str(p_options[key])))
		enable.add_child_stanza(x)
	if bool(p_filters.get("ignore_unknown", false)):
		var iu = Stanza.new("ignore-unknown")
		iu.set_attr("xmlns", FILTER_UNKNOWN)
		enable.add_child_stanza(iu)
	var muted = p_filters.get("muted", [])
	if muted is Array and not muted.empty():
		var m = Stanza.new("muted")
		m.set_attr("xmlns", FILTER_MUTED)
		for j in muted:
			var it = Stanza.new("item")
			it.set_attr("jid", str(j))
			m.add_child_stanza(it)
		enable.add_child_stanza(m)
	var rooms = p_filters.get("groupchat", [])
	if rooms is Array and not rooms.empty():
		var g = Stanza.new("groupchat")
		g.set_attr("xmlns", FILTER_GROUPCHAT)
		for r in rooms:
			var room = Stanza.new("room")
			room.set_attr("jid", str(r.get("jid", "")))
			if str(r.get("when", "")) != "":
				room.set_attr("allow", str(r["when"]))
			if str(r.get("nick", "")) != "":
				room.set_attr("nick", str(r["nick"]))
			g.add_child_stanza(room)
		enable.add_child_stanza(g)
	iq.add_child_stanza(enable)
	return iq

# `<iq type='set'><disable xmlns='urn:xmpp:push:0'/></iq>` (todo) o con
# `jid`/`node` para dar de baja un dispositivo puntual.
static func build_disable(p_id: String, p_service_jid: String = "", p_node: String = ""):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	var disable = Stanza.new("disable")
	disable.set_attr("xmlns", NS)
	if p_service_jid != "":
		disable.set_attr("jid", p_service_jid)
	if p_node != "":
		disable.set_attr("node", p_node)
	iq.add_child_stanza(disable)
	return iq

static func _field(p_var: String, p_value: String):
	var field = Stanza.new("field")
	field.set_attr("var", p_var)
	var value = Stanza.new("value")
	value.append_text(p_value)
	field.add_child_stanza(value)
	return field

# Condición del `<error>` de un IQ fallido ("not-allowed", "service-unavailable"…).
# XMLParser de Godot 3 no resuelve namespaces, así que se reconoce por nombre.
static func error_condition(p_iq) -> String:
	var known = [
		"bad-request", "conflict", "feature-not-implemented", "forbidden", "gone",
		"internal-server-error", "item-not-found", "jid-malformed", "not-acceptable",
		"not-allowed", "not-authorized", "policy-violation", "recipient-unavailable",
		"redirect", "registration-required", "remote-server-not-found",
		"remote-server-timeout", "resource-constraint", "service-unavailable",
		"subscription-required", "undefined-condition", "unexpected-request",
	]
	var err = p_iq.get_child("error")
	if err == null:
		return ""
	for child in err.children:
		if child is String:
			continue
		if known.has(child.name):
			return child.name
	return ""

# Servicio push anunciado por el servidor en un disco#info (identity con
# category/type push, o feature urn:xmpp:push:0). "" si no lo anuncia.
static func service_from_disco(p_iq) -> String:
	var query = p_iq.get_child("query", NSs.DISCO_INFO)
	if query == null:
		return ""
	for idn in query.get_children("identity"):
		if idn.get_attr("type", "") == "push" or (idn.get_attr("category", "") == "pubsub" and idn.get_attr("type", "") == "push"):
			return p_iq.get_attr("from", "")
	return ""

# --- Persistencia del registro (para re-registrar al reconectar) ---

static func save(p_path: String, p_service_jid: String, p_node: String) -> void:
	var f = File.new()
	if f.open(p_path, File.WRITE) != OK:
		return
	f.store_string(JSON.print({"service": p_service_jid, "node": p_node}))
	f.close()

static func load(p_path: String) -> Dictionary:
	var f = File.new()
	if not f.file_exists(p_path) or f.open(p_path, File.READ) != OK:
		return {}
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or not parsed.result is Dictionary:
		return {}
	var d = parsed.result
	return {"service": str(d.get("service", "")), "node": str(d.get("node", ""))}
