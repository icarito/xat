extends SceneTree

# Diálogo de formularios XEP-0004: render de campos y recolección de valores
# (hidden preservado, boolean 1/0, list-single por metadata).

var _fail := 0

func _init():
	var Dialog = load("res://addons/xat_xmpp/ui/command_dialog.gd")
	var Forms = load("res://addons/xat_xmpp/xmpp/forms.gd")
	var Stanza = load("res://addons/xat_xmpp/xmpp/stanza.gd")

	var form = Forms.parse(Stanza.parse('<x xmlns="jabber:x:data" type="form">' \
		+ '<field var="FORM_TYPE" type="hidden"><value>cmd</value></field>' \
		+ '<field var="minutes" type="text-single" label="Min"><value>10</value></field>' \
		+ '<field var="confirm" type="boolean"><value>1</value></field>' \
		+ '<field var="mode" type="list-single"><value>on</value><option label="On"><value>on</value></option><option label="Off"><value>off</value></option></field>' \
		+ '</x>'))

	var d = Dialog.new()
	get_root().add_child(d)
	d.open_form("t", form)
	check(d._fields.size() == 4, "cuatro campos")
	check(d._inputs[0] == null, "hidden sin control")

	var out = d.collect()
	check(out.size() == 4, "collect 4")
	check(out[0]["var"] == "FORM_TYPE" and out[0]["values"] == ["cmd"], "hidden preservado")
	check(out[1]["values"] == ["10"], "valor de texto")
	check(out[2]["values"] == ["1"], "boolean true")
	check(out[3]["values"] == ["on"], "list-single valor")

	d._inputs[1].text = "20"
	check(d.collect()[1]["values"] == ["20"], "texto editado se recoge")

	# Campos reabiertos no se acumulan.
	d.open_form("t2", form)
	check(d._fields.size() == 4, "reabrir no acumula")

	d.free()
	if _fail == 0:
		print("COMMAND_DIALOG_CHECK_OK")
	quit()

func check(cond: bool, label: String) -> void:
	if cond:
		print("ok %s" % label)
	else:
		_fail += 1
		print("FAIL %s" % label)
		OS.exit_code = 1
