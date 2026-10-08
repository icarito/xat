extends Reference

# XEP-0004 (jabber:x:data): parseo y construcción de formularios. Puro.
#
# Modelo de campo (Dictionary):
#   { var, type, label, required(bool), values(Array), value(String, primero
#     de values), options: [{ value, label }] }

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")

static func parse(p_x) -> Dictionary:
	var out := {"type": "", "title": "", "instructions": "", "fields": []}
	if p_x == null:
		return out
	out["type"] = p_x.get_attr("type", "")
	var title = p_x.get_child("title")
	if title != null:
		out["title"] = title.get_text()
	var instructions = p_x.get_child("instructions")
	if instructions != null:
		out["instructions"] = instructions.get_text()
	for field in p_x.get_children("field"):
		var values := []
		for v in field.get_children("value"):
			values.append(v.get_text())
		var options := []
		for opt in field.get_children("option"):
			var ov = opt.get_child("value")
			options.append({
				"value": ov.get_text() if ov != null else "",
				"label": opt.get_attr("label", ov.get_text() if ov != null else ""),
			})
		out["fields"].append({
			"var": field.get_attr("var", ""),
			"type": field.get_attr("type", ""),
			"label": field.get_attr("label", ""),
			"required": field.get_child("required") != null,
			"values": values,
			"value": values[0] if not values.empty() else "",
			"options": options,
		})
	return out

# Construye un <x type='submit'> a partir de campos ya parseados (conserva
# `var` y `type`: los `hidden` deben reenviarse tal cual).
static func build_submit(p_fields: Array):
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.DATA_FORMS)
	x.set_attr("type", "submit")
	for f in p_fields:
		var field = Stanza.new("field")
		field.set_attr("var", str(f.get("var", "")))
		if str(f.get("type", "")) != "":
			field.set_attr("type", str(f["type"]))
		var vals = f.get("values", [])
		if (vals as Array).empty() and f.has("value"):
			vals = [f["value"]]
		for v in vals:
			var value = Stanza.new("value")
			value.append_text(str(v))
			field.add_child_stanza(value)
		x.add_child_stanza(field)
	return x

# Valor de un campo por nombre.
static func field_value(p_form: Dictionary, p_var: String, p_default = ""):
	for f in p_form.get("fields", []):
		if f["var"] == p_var:
			return f["value"]
	return p_default
