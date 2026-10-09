extends AcceptDialog

# Diálogo genérico de una línea: pide un texto (tema de sala, razón, etc.).
# Emite `submitted(text)`.

signal submitted(text)

var _edit: LineEdit
var _placeholder := ""

func _init() -> void:
	name = "TextPromptDialog"
	window_title = "Texto"
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	add_child(box)
	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_edit)
	connect("confirmed", self, "_on_confirmed")
	_edit.connect("text_entered", self, "_on_entered")

func open(p_title: String, p_initial: String = "", p_placeholder: String = "") -> void:
	window_title = p_title
	_edit.text = p_initial
	_edit.placeholder_text = p_placeholder
	popup_centered(Vector2(360, 0))
	_edit.grab_focus()
	_edit.select_all()

func _on_entered(_text: String) -> void:
	emit_signal("confirmed")  # Enter = aceptar (emite confirmed -> submitted)

func _on_confirmed() -> void:
	emit_signal("submitted", _edit.text.strip_edges())