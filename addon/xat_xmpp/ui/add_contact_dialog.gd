extends AcceptDialog

# Diálogo para añadir un contacto: JID (obligatorio) y nombre (opcional). Emite
# `submitted(jid, name)`; el llamador decide qué stanza enviar. El botón Aceptar
# queda deshabilitado hasta que el JID sea válido.

signal submitted(jid, name)

const Jid = preload("res://addons/xat_xmpp/xmpp/jid.gd")

var _jid: LineEdit
var _name: LineEdit
var _error: Label

func _init() -> void:
	name = "AddContactDialog"
	window_title = "Añadir contacto"
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	add_child(box)
	_jid = _row(box, "JID", "persona@hablar.fuentelibre.org")
	_name = _row(box, "Nombre", "")
	_error = Label.new()
	_error.add_color_override("font_color", Color("ff5c7a"))
	box.add_child(_error)
	connect("confirmed", self, "_on_confirmed")
	get_ok().text = "Añadir"
	for e in [_jid, _name]:
		e.connect("text_changed", self, "_validate")
	_validate("")

func _row(p_parent: VBoxContainer, p_label: String, p_placeholder: String) -> LineEdit:
	var h = HBoxContainer.new()
	var l = Label.new()
	l.text = p_label
	l.rect_min_size = Vector2(90, 0)
	h.add_child(l)
	var e = LineEdit.new()
	e.placeholder_text = p_placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(e)
	p_parent.add_child(h)
	return e

func open() -> void:
	_jid.text = ""
	_name.text = ""
	_error.text = ""
	_validate("")
	popup_centered()
	_jid.grab_focus()

func _validate(_text: String) -> void:
	var jid = _jid.text.strip_edges()
	var valid = _is_valid(jid)
	get_ok().disabled = not valid
	if jid == "":
		_error.text = ""
	elif not valid:
		_error.text = "JID inválido (usá usuario@dominio)."

func _is_valid(p_jid: String) -> bool:
	if p_jid == "":
		return false
	var j = Jid.new()
	j.parse(p_jid)
	return j.is_valid() and j.node != "" and j.domain != ""

func _on_confirmed() -> void:
	var jid = _jid.text.strip_edges()
	if not _is_valid(jid):
		return
	emit_signal("submitted", jid, _name.text.strip_edges())
