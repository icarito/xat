extends Reference

# Registro en banda XMPP (XEP-0077): modelo puro para descubrir y enviar el
# registro de una cuenta, y parsear la respuesta del servidor. No hace I/O.
#
# Flujo estándar:
#   1. El stream anuncia `<register xmlns='http://jabber.org/features/iq-register'/>`
#      (lo comprueba `supports_registration`). Si no está, el servidor no acepta
#      registro en banda (p. ej. `allow_registration = false` en Prosody: se crea
#      la cuenta con `prosodyctl register`).
#   2. `build_discover_iq` pide los campos (get) y devuelve instrucciones +
#      campos del formulario.
#   3. `build_register_iq` envía usuario/contraseña (y extras del formulario).
#
# Namespace: `jabber:iq:register`.

const NS := "jabber:iq:register"
const NS_FEATURE := "http://jabber.org/features/iq-register"

static func _stanza_script():
	return load("res://addons/xat_xmpp/xmpp/stanza.gd")

# El servidor ofrece registro en banda si el stream lo anuncia.
static func supports_registration(p_features) -> bool:
	return p_features != null and p_features.get_child("register", NS_FEATURE) != null

# IQ get para descubrir los campos del formulario de registro.
static func build_discover_iq(p_id: String, p_to: String):
	var Stanza = _stanza_script()
	var iq = Stanza.new("iq")
	iq.set_attr("type", "get")
	iq.set_attr("id", p_id)
	if p_to != "":
		iq.set_attr("to", p_to)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS)
	iq.add_child_stanza(q)
	return iq

# IQ set con los campos del registro. `p_fields` es {nombre: valor}; típicamente
# {username, password} y opcionalmente email/nick.
static func build_register_iq(p_id: String, p_to: String, p_fields: Dictionary):
	var Stanza = _stanza_script()
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("id", p_id)
	if p_to != "":
		iq.set_attr("to", p_to)
	var q = Stanza.new("query")
	q.set_attr("xmlns", NS)
	for k in p_fields.keys():
		var f = Stanza.new(str(k))
		f.append_text(str(p_fields[k]))
		q.add_child_stanza(f)
	iq.add_child_stanza(q)
	return iq

# Parsea la respuesta del servidor al registro. Devuelve:
#   {ok, registered, instructions, fields: {nombre: valor}, error, error_text}
static func parse(p_stanza) -> Dictionary:
	var out := {
		"ok": false,
		"registered": false,
		"instructions": "",
		"fields": {},
		"error": "",
		"error_text": "",
	}
	if p_stanza == null:
		out["error"] = "bad-request"
		return out
	var q = p_stanza.get_child("query", NS)
	var type := str(p_stanza.get_attr("type", ""))
	if type == "error":
		out["error"] = _error_condition(p_stanza)
		out["error_text"] = _error_text(p_stanza)
		return out
	if q == null:
		out["error"] = "bad-request"
		return out
	if type == "result":
		out["ok"] = true
		out["registered"] = q.get_child("registered") != null
		var instr = q.get_child("instructions")
		if instr != null:
			out["instructions"] = instr.get_text().strip_edges()
		for c in q.get_children():
			if c.name == "instructions" or c.name == "registered":
				continue
			out["fields"][c.name] = c.get_text().strip_edges()
	return out

# Nombres de los campos que el servidor pide (para armar el formulario).
static func field_names(p_parsed: Dictionary) -> Array:
	return p_parsed.get("fields", {}).keys()

static func _error_condition(p_stanza) -> String:
	# La condición es el nombre del primer hijo de <error> (p. ej. <conflict/>).
	var err = p_stanza.get_child("error")
	if err == null:
		return "unknown"
	for c in err.get_children():
		if c.name == "text":
			continue
		return c.name
	return "unknown"

static func _error_text(p_stanza) -> String:
	var err = p_stanza.get_child("error")
	if err == null:
		return ""
	var t = err.get_child("text")
	return "" if t == null else t.get_text().strip_edges()
