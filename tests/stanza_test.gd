extends SceneTree

# Round-trip del modelo de stanza: parseo, texto con entidades, subelementos,
# atributos y serialización.

var _fail := 0

func _init():
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")
	var xml = '<message to="agente@hablar.fuentelibre.org" from="yo@hablar.fuentelibre.org/xat" type="chat" id="m1">' \
		+ '<body>hola &amp; chau &lt;3</body>' \
		+ '<delay xmlns="urn:xmpp:delay" stamp="2026-01-01T00:00:00Z"/>' \
		+ '</message>'
	var m = Stanza.parse(xml)
	check(m != null, "parse devuelve raiz")
	check(m.name == "message", "nombre message")
	check(m.get_attr("type") == "chat", "attr type")
	check(m.get_attr("id") == "m1", "attr id")
	check(m.get_attr("from") == "yo@hablar.fuentelibre.org/xat", "attr from")

	var body = m.get_child("body")
	check(body != null, "tiene body")
	check(body.get_text() == "hola & chau <3", "texto desescapado")

	var delay = m.get_child("delay", "urn:xmpp:delay")
	check(delay != null, "delay con xmlns")
	check(delay.get_attr("stamp") == "2026-01-01T00:00:00Z", "attr stamp")
	check(delay.to_xml() == '<delay xmlns="urn:xmpp:delay" stamp="2026-01-01T00:00:00Z"/>', "delay self-closing")

	var out = m.to_xml()
	check(out.find("hola &amp; chau &lt;3") >= 0, "re-escapa texto")
	check(out.find('<delay xmlns="urn:xmpp:delay" stamp="2026-01-01T00:00:00Z"/>') >= 0, "conserva delay")

	var m2 = Stanza.parse(out)
	check(m2 != null and m2.get_child("body").get_text() == "hola & chau <3", "re-parse estable")

	# Sin hijos -> self closing.
	var iq = Stanza.parse('<iq type="get" id="x1"/>')
	check(iq.to_xml() == '<iq type="get" id="x1"/>', "iq self-closing")

	# Builders: crear desde cero y serializar.
	var ping = Stanza.new("iq")
	ping.set_attr("type", "get")
	ping.set_attr("id", "p1")
	var ping_child = Stanza.new("ping")
	ping_child.set_attr("xmlns", "urn:xmpp:ping")
	ping.add_child_stanza(ping_child)
	check(ping.to_xml() == '<iq type="get" id="p1"><ping xmlns="urn:xmpp:ping"/></iq>', "builder iq ping")

	if _fail == 0:
		print("STANZA_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
