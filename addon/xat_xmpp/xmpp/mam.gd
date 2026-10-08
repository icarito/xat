extends Reference

# XEP-0313 (MAM) + RSM: construcción de la query y parseo de `fin`/`result`.
# Helper puro, testeable headless. La política (agua/backfill, fail-closed,
# dedupe) vive en store/session; acá sólo el wire-format.

const Stanza = preload("res://addons/xat_xmpp/xmpp/stanza.gd")
const NS = preload("res://addons/xat_xmpp/xmpp/namespaces.gd")
const Message = preload("res://addons/xat_xmpp/xmpp/message.gd")

# Construye el IQ-set de MAM. `p_with` filtra por bare JID (opcional).
# `p_after`: archive id desde el que traer (catch-up). `p_before`: para scroll.
# `p_last_page`: pide la ÚLTIMA página (RSM `<before/>` vacío) — así se recupera
# la sesión reciente en vez de los mensajes más viejos del archivo.
static func build_query(p_to: String, p_queryid: String, p_id: String, p_with: String = "", p_max: int = 50, p_after: String = "", p_before: String = "", p_start: String = "", p_end: String = "", p_last_page: bool = false):
	var iq = Stanza.new("iq")
	iq.set_attr("type", "set")
	iq.set_attr("to", p_to)
	iq.set_attr("id", p_id)
	var query = Stanza.new("query")
	query.set_attr("xmlns", NS.MAM)
	query.set_attr("queryid", p_queryid)
	query.add_child_stanza(_data_form(p_with, p_start, p_end))
	query.add_child_stanza(_rsm(p_max, p_after, p_before, p_last_page))
	iq.add_child_stanza(query)
	return iq

static func _data_form(p_with: String, p_start: String, p_end: String):
	var x = Stanza.new("x")
	x.set_attr("xmlns", NS.DATA_FORMS)
	x.set_attr("type", "submit")
	x.add_child_stanza(_field("FORM_TYPE", NS.MAM, "hidden"))
	if p_with != "":
		x.add_child_stanza(_field("with", p_with))
	if p_start != "":
		x.add_child_stanza(_field("start", p_start))
	if p_end != "":
		x.add_child_stanza(_field("end", p_end))
	return x

static func _field(p_var: String, p_value: String, p_type: String = ""):
	var field = Stanza.new("field")
	field.set_attr("var", p_var)
	if p_type != "":
		field.set_attr("type", p_type)
	var value = Stanza.new("value")
	value.append_text(p_value)
	field.add_child_stanza(value)
	return field

static func _rsm(p_max: int, p_after: String, p_before: String, p_last_page: bool = false):
	var set = Stanza.new("set")
	set.set_attr("xmlns", NS.RSM)
	if p_max > 0:
		var maxn = Stanza.new("max")
		maxn.append_text(str(p_max))
		set.add_child_stanza(maxn)
	if p_after != "":
		var after = Stanza.new("after")
		after.append_text(p_after)
		set.add_child_stanza(after)
	if p_before != "":
		var before = Stanza.new("before")
		before.append_text(p_before)
		set.add_child_stanza(before)
	if p_last_page:
		# <before/> vacío: XEP-0313 lo define como "la última página".
		set.add_child_stanza(Stanza.new("before"))
	return set

# Parsea el <fin/> de la respuesta MAM.
static func parse_fin(p_iq) -> Dictionary:
	var out := {"complete": false, "rsm_last": "", "rsm_first": "", "count": 0}
	if p_iq == null:
		return out
	var fin = p_iq.get_child("fin", NS.MAM)
	if fin == null:
		return out
	out["complete"] = fin.get_attr("complete", "false") == "true"
	var set = fin.get_child("set", NS.RSM)
	if set != null:
		var last = set.get_child("last")
		var first = set.get_child("first")
		var count = set.get_child("count")
		if last != null:
			out["rsm_last"] = last.get_text()
		if first != null:
			out["rsm_first"] = first.get_text()
		if count != null and count.get_text().is_valid_integer():
			out["count"] = int(count.get_text())
	return out

# Parsea un <message><result xmlns='urn:xmpp:mam:2'>...<message> como registro.
static func parse_result(p_message) -> Dictionary:
	return Message.parse(p_message)
