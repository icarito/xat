extends SceneTree

# XEP-0004: parseo y construcción de formularios.

var _fail := 0

func _init():
	var Forms = load("res://addons/xat_xmpp/xmpp/forms.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	var form = Forms.parse(Stanza.parse('<x xmlns="jabber:x:data" type="form">' \
		+ '<title>Elevated</title><instructions>Elegí</instructions>' \
		+ '<field var="FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/commands</value></field>' \
		+ '<field var="mode" type="list-single" label="Modo"><value>status</value>' \
		+ '<option label="on"><value>on</value></option><option label="off"><value>off</value></option></field>' \
		+ '<field var="minutes" type="text-single" label="Minutos"><value>10</value></field>' \
		+ '<field var="confirm" type="boolean"><required/><value>1</value></field>' \
		+ '</x>'))
	check(form["type"] == "form", "tipo form")
	check(form["title"] == "Elevated" and form["instructions"] == "Elegí", "título/instrucciones")
	check(form["fields"].size() == 4, "cuatro campos")
	check(Forms.field_value(form, "mode") == "status", "field_value mode")
	check(Forms.field_value(form, "missing", "d") == "d", "field_value default")
	check(form["fields"][1]["options"].size() == 2 and form["fields"][1]["options"][0]["label"] == "on", "opciones")
	check(form["fields"][1]["type"] == "list-single", "tipo list-single")
	check(form["fields"][3]["required"], "required")

	# build_submit conserva var/type (hidden) y valores.
	var submitted = Forms.build_submit([
		{"var": "FORM_TYPE", "type": "hidden", "values": ["http://jabber.org/protocol/commands"]},
		{"var": "mode", "type": "list-single", "values": ["on"]},
	])
	var xml = submitted.to_xml()
	check(xml.find('<x xmlns="jabber:x:data" type="submit">') >= 0, "x submit")
	check(xml.find('<field var="FORM_TYPE" type="hidden"><value>http://jabber.org/protocol/commands</value></field>') >= 0, "hidden preservado")
	check(xml.find('<field var="mode" type="list-single"><value>on</value></field>') >= 0, "valor submit")

	if _fail == 0:
		print("FORMS_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
