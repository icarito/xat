extends Reference

# Helpers genéricos XEP-0060 para leer items, suscribirse y normalizar eventos.
# No interpreta el payload del item: cada aplicación conserva su propio modelo.

const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")
const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")

static func build_items_request(p_id: String, p_to: String, p_node: String, p_max: int = 0):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", p_id)
	if p_to != "":
		iq.set_attr("to", p_to)
	var pubsub = Stanza.new("pubsub")
	pubsub.set_attr("xmlns", NS.PUBSUB)
	var items = Stanza.new("items")
	items.set_attr("node", p_node)
	if p_max > 0:
		var rsm_set = Stanza.new("set")
		rsm_set.set_attr("xmlns", NS.RSM)
		var max_node = Stanza.new("max")
		max_node.append_text(str(p_max))
		rsm_set.add_child_stanza(max_node)
		items.add_child_stanza(rsm_set)
	pubsub.add_child_stanza(items)
	iq.add_child_stanza(pubsub)
	return iq

# p_subscriber es el JID que solicita la suscripción. El destino puede ser un
# servicio PubSub o el bare JID del publicador cuando se usa PEP.
static func build_subscribe(p_id: String, p_to: String, p_node: String, p_subscriber: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	if p_to != "":
		iq.set_attr("to", p_to)
	var pubsub = Stanza.new("pubsub")
	pubsub.set_attr("xmlns", NS.PUBSUB)
	var subscribe = Stanza.new("subscribe")
	subscribe.set_attr("node", p_node)
	if p_subscriber != "":
		subscribe.set_attr("jid", p_subscriber)
	pubsub.add_child_stanza(subscribe)
	iq.add_child_stanza(pubsub)
	return iq

# Resultado: {node, items:[{id, stanza, payload}]}. Conserva stanzas completos
# para que el consumidor pueda leer payloads específicos sin perder extensiones.
static func parse_items_result(p_iq) -> Dictionary:
	var out := {"node": "", "items": []}
	if p_iq == null:
		return out
	var pubsub = p_iq.get_child("pubsub", NS.PUBSUB)
	var container = pubsub.get_child("items") if pubsub != null else null
	if container == null:
		return out
	out["node"] = container.get_attr("node", "")
	for item in container.get_children("item"):
		out["items"].append(_item_record(item))
	return out

# Evento pubsub#event. Devuelve kind=items|delete|purge|configuration|unknown,
# node, items (mismo formato genérico), y el elemento de acción completo.
static func parse_event(p_message) -> Dictionary:
	var out := {"kind": "", "node": "", "items": [], "action": null}
	if p_message == null:
		return out
	var event = p_message.get_child("event", NS.PUBSUB_EVENT)
	if event == null:
		return out
	for name in ["items", "delete", "purge", "configuration"]:
		var action = event.get_child(name)
		if action != null:
			out["kind"] = name
			out["node"] = action.get_attr("node", "")
			out["action"] = action
			if name == "items":
				for item in action.get_children("item"):
					out["items"].append(_item_record(item))
			elif name == "delete":
				for redirect in action.get_children("redirect"):
					out["redirect"] = redirect.get_attr("uri", "")
			return out
	return out

static func _item_record(p_item) -> Dictionary:
	var payload = null
	for child in p_item.children:
		if not (child is String):
			payload = child
			break
	return {"id": p_item.get_attr("id", ""), "stanza": p_item, "payload": payload}
