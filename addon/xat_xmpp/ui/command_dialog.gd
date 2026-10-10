extends AcceptDialog

# Diálogo para formularios XEP-0004 de comandos XEP-0050. Renderiza los campos
# y emite `submitted(fields)` con el formato que espera Commands.build_submit.

signal submitted(fields)

var _box: VBoxContainer
var _fields := [] # { var, type, values }
var _inputs := [] # Control o null (hidden)

func _init() -> void:
	name = "CommandDialog"
	window_title = "Comando"
	# Los formularios de config de sala MUC (y de comandos) pueden traer muchos
	# campos: el contenido va en un ScrollContainer para que no se salga del
	# diálogo.
	var scroll = ScrollContainer.new()
	scroll.rect_min_size = Vector2(520, 420)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)
	connect("confirmed", self, "_on_confirmed")

func open_form(p_title: String, p_form: Dictionary) -> void:
	window_title = p_title
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_fields = []
	_inputs = []
	var title = p_form.get("title", "")
	if title != "":
		var l = Label.new()
		l.text = title
		_box.add_child(l)
	for f in p_form.get("fields", []):
		_add_field(f)

func _add_field(p_field: Dictionary) -> void:
	var var_name = str(p_field.get("var", ""))
	var ftype = str(p_field.get("type", "text-single"))
	var value = str(p_field.get("value", ""))
	var entry = {"var": var_name, "type": ftype, "values": [value]}
	_fields.append(entry)

	if ftype == "hidden":
		_inputs.append(null)
		return

	var h = HBoxContainer.new()
	var label = Label.new()
	label.text = str(p_field.get("label", var_name))
	label.rect_min_size = Vector2(140, 0)
	h.add_child(label)

	var control = _make_control(p_field)
	h.add_child(control)
	_inputs.append(control)
	_box.add_child(h)

func _make_control(p_field: Dictionary):
	var p_type = str(p_field.get("type", "text-single"))
	var p_value = str(p_field.get("value", ""))
	var p_options = p_field.get("options", [])
	if p_type == "boolean":
		var cb = CheckBox.new()
		cb.pressed = (p_value == "1" or p_value.to_lower() == "true")
		return cb
	if p_type == "list-multi":
		# Multi-selección: un checkbox por opción (los valores vienen en la lista).
		var box = VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.set_meta("multi", true)
		var chosen = p_field.get("values", [])
		for opt in p_options:
			var cb = CheckBox.new()
			cb.text = str(opt.get("label", opt.get("value", "")))
			cb.set_meta("value", str(opt.get("value", "")))
			cb.pressed = chosen.has(str(opt.get("value", "")))
			box.add_child(cb)
		return box
	if p_type == "list-single":
		var ob = OptionButton.new()
		var selected := 0
		for i in range(p_options.size()):
			var opt = p_options[i]
			ob.add_item(str(opt.get("label", opt.get("value", ""))))
			ob.set_item_metadata(i, str(opt.get("value", "")))
			if str(opt.get("value", "")) == p_value:
				selected = i
		ob.select(selected)
		return ob
	if p_type == "text-private":
		var le = LineEdit.new()
		le.text = p_value
		le.secret = true
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return le
	var line = LineEdit.new()
	line.text = p_value
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line

func collect() -> Array:
	var out := []
	for i in range(_fields.size()):
		var f = _fields[i]
		var c = _inputs[i]
		var values := []
		if c == null:
			values = f.get("values", [])
		elif c is CheckBox:
			values = ["1" if c.pressed else "0"]
		elif c is OptionButton:
			values = [str(c.get_item_metadata(c.selected))]
		elif c is VBoxContainer and c.has_meta("multi"):
			for ch in c.get_children():
				if ch is CheckBox and ch.pressed:
					values.append(str(ch.get_meta("value")))
		else:
			values = [c.text]
		out.append({"var": f["var"], "type": f["type"], "values": values})
	return out

func _on_confirmed() -> void:
	emit_signal("submitted", collect())
