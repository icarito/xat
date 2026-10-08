extends Reference

# XEP-0050 (comandos ad-hoc) + XEP-0439 (quick responses) + el selection IQ de
# OpenClaw. Puro, testeable headless.

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")
const Forms = preload("res://addons/xat_xmpp/xmpp/forms.gd")

# <iq type='get' to='bot'><query xmlns='disco#items' node='.../commands'/></iq>
static func build_discovery(p_to: String, p_id: String = ""):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("to", p_to)
	if p_id != "":
		iq.set_attr("id", p_id)
	var query = Stanza.new("query")
	query.set_attr("xmlns", NS.DISCO_ITEMS)
	query.set_attr("node", NS.COMMANDS)
	iq.add_child_stanza(query)
	return iq

# <iq type='set' to='full-jid'><command xmlns='.../commands' node action='execute' [sessionid]/></iq>
# También es el "selection IQ" al elegir un ítem inline (mismo formato).
static func build_execute(p_to: String, p_node: String, p_sessionid: String = "", p_id: String = ""):
	return _command_iq(p_to, p_node, "execute", p_sessionid, null, p_id)

# action='submit' con <x type='submit'>.
static func build_submit(p_to: String, p_node: String, p_sessionid: String, p_fields: Array, p_id: String = ""):
	return _command_iq(p_to, p_node, "submit", p_sessionid, Forms.build_submit(p_fields), p_id)

static func _command_iq(p_to: String, p_node: String, p_action: String, p_sessionid: String, p_form, p_id: String):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("to", p_to)
	if p_id != "":
		iq.set_attr("id", p_id)
	var command = Stanza.new("command")
	command.set_attr("xmlns", NS.COMMANDS)
	command.set_attr("node", p_node)
	command.set_attr("action", p_action)
	if p_sessionid != "":
		command.set_attr("sessionid", p_sessionid)
	if p_form != null:
		command.add_child_stanza(p_form)
	iq.add_child_stanza(command)
	return iq

# Parsea el <command> de una respuesta y su formulario/notas.
static func parse_response(p_iq) -> Dictionary:
	var out := {
		"node": "",
		"status": "",
		"sessionid": "",
		"action": "",
		"form": null,
		"notes": [],
		"actions": {},
		"default": "",
		"error_type": "",
	}
	if p_iq == null:
		return out
	var err = p_iq.get_child("error")
	if err != null:
		out["error_type"] = err.get_attr("type", "")
	var command = p_iq.get_child("command", NS.COMMANDS)
	if command == null:
		return out
	out["node"] = command.get_attr("node", "")
	out["status"] = command.get_attr("status", "")
	out["sessionid"] = command.get_attr("sessionid", "")
	out["action"] = command.get_attr("action", "")
	var x = command.get_child("x", NS.DATA_FORMS)
	if x != null:
		out["form"] = Forms.parse(x)
	for note in command.get_children("note"):
		out["notes"].append({"type": note.get_attr("type", ""), "text": note.get_text()})
	var actions = command.get_child("actions")
	if actions != null:
		for a in actions.get_children():
			if a is String:
				continue
			out["actions"][a.name] = true
		out["default"] = actions.get_attr("execute", "")
	return out

# Ítems de un disco#items (resultado).
static func parse_items(p_iq) -> Array:
	var out := []
	if p_iq == null:
		return out
	var query = p_iq.get_child("query", NS.DISCO_ITEMS)
	if query == null:
		return out
	for item in query.get_children("item"):
		var jid = item.get_attr("jid", "")
		var node = item.get_attr("node", "")
		if jid == "" and node == "":
			continue
		out.append({"jid": jid, "node": node, "name": item.get_attr("name", "")})
	return out

# Próxima acción a enviar según el estado del comando (NEXT/COMPLETE).
static func next_action(p_status: String, p_actions: Dictionary, p_default: String) -> String:
	if p_default == "next" or p_default == "complete":
		return p_default
	if p_actions.has("next"):
		return "next"
	if p_actions.has("complete"):
		return "complete"
	if p_status == "executing":
		return "next"
	return "complete"
