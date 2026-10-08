extends Reference

# Modelo de stanza XMPP: árbol de elementos + texto, parseado con XMLParser de
# Godot 3 y serializado a string. Helper puro, testeable headless.
#
# Notas:
#  - XMLParser de Godot 3 NO resuelve namespaces: los nombres de elemento y
#    atributo se conservan tal cual (p. ej. "stream:features"), que es justo
#    lo que necesita la frontera híbrida de xat (stanzas crudas + helpers).
#  - El texto se guarda como String dentro de `children` (mezclado con
#    subelementos, en orden), así un mensaje con texto y un <delay/> se
#    preserva en orden.

const _ESCAPE_MAP := {
	"&": "&amp;",
	"<": "&lt;",
	">": "&gt;",
	'"': "&quot;",
}

var name := ""
var attrs := {}
# Array de Stanza (subelementos) y String (nodos de texto), en orden.
var children := []

func _init(p_name: String = "") -> void:
	name = p_name

func set_attr(p_key: String, p_value) -> void:
	attrs[p_key] = str(p_value)

func get_attr(p_key: String, p_default = null):
	return attrs[p_key] if attrs.has(p_key) else p_default

func has_attr(p_key: String) -> bool:
	return attrs.has(p_key)

func add_child_stanza(p_child) -> void:
	children.append(p_child)

func append_text(p_text: String) -> void:
	if p_text == "":
		return
	children.append(p_text)

func get_children(p_name: String = "", p_xmlns: String = "") -> Array:
	var out := []
	for c in children:
		if c is String:
			continue
		if p_name != "" and c.name != p_name:
			continue
		if p_xmlns != "" and c.get_attr("xmlns", "") != p_xmlns:
			continue
		out.append(c)
	return out

func get_child(p_name: String, p_xmlns: String = ""):
	for c in get_children(p_name, p_xmlns):
		return c
	return null

func get_text() -> String:
	var parts := ""
	for c in children:
		if c is String:
			parts += c
	return parts

func to_xml() -> String:
	var out := "<" + name
	for k in attrs.keys():
		out += " " + k + '="' + _escape(str(attrs[k])) + '"'
	if children.empty():
		out += "/>"
		return out
	out += ">"
	for c in children:
		if c is String:
			out += _escape_text(c)
		else:
			out += c.to_xml()
	out += "</" + name + ">"
	return out

static func parse(p_xml: String):
	var stanza_script = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var parser := XMLParser.new()
	var buf := PoolByteArray()
	buf.append_array(p_xml.to_utf8())
	if parser.open_buffer(buf) != OK:
		return null
	var root = null
	var stack := []
	while parser.read() == OK:
		var t := parser.get_node_type()
		if t == XMLParser.NODE_ELEMENT:
			var el = stanza_script.new(parser.get_node_name())
			var ac := parser.get_attribute_count()
			for i in range(ac):
				el.attrs[parser.get_attribute_name(i)] = parser.get_attribute_value(i)
			if stack.empty():
				root = el
			else:
				stack[stack.size() - 1].add_child_stanza(el)
			if not parser.is_empty():
				stack.append(el)
		elif t == XMLParser.NODE_ELEMENT_END:
			if not stack.empty():
				stack.pop_back()
		elif t == XMLParser.NODE_TEXT or t == XMLParser.NODE_CDATA:
			if not stack.empty():
				stack[stack.size() - 1].append_text(parser.get_node_data())
	return root

static func _escape(p_text: String) -> String:
	var out := ""
	for i in range(p_text.length()):
		var ch := p_text[i]
		out += _ESCAPE_MAP.get(ch, ch)
	return out

static func _escape_text(p_text: String) -> String:
	var out := ""
	for i in range(p_text.length()):
		var ch := p_text[i]
		if ch == "&":
			out += "&amp;"
		elif ch == "<":
			out += "&lt;"
		elif ch == ">":
			out += "&gt;"
		else:
			out += ch
	return out
