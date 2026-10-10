extends AcceptDialog

# Diálogo para añadir un contacto: JID (obligatorio) y nombre (opcional). Emite
# `submitted(jid, name)`; el llamador decide qué stanza enviar. El botón Aceptar
# queda deshabilitado hasta que el JID sea válido.

signal submitted(jid, name)

const Jid = preload("res://addons/xat_xmpp/xmpp/jid.gd")
const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

var _jid: LineEdit
var _name: LineEdit
var _error: Label

func _init() -> void:
	name = "AddContactDialog"
	window_title = "Añadir contacto"
	rect_min_size = Vector2(560, 340)
	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 24)
	margin.add_constant_override("margin_right", 24)
	margin.add_constant_override("margin_top", 22)
	margin.add_constant_override("margin_bottom", 20)
	add_child(margin)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 12)
	margin.add_child(box)
	var title = Label.new()
	title.text = "Añadir contacto"
	title.add_font_override("font", XatTheme.font(P.FONT_BOLD, P.FONT_SIZE + 4))
	box.add_child(title)
	var desc = Label.new()
	desc.text = "Agregá a alguien por su JID. El nombre es opcional."
	desc.autowrap = true
	desc.rect_min_size = Vector2(412, 0)
	desc.add_color_override("font_color", P.TEXT_DIM)
	box.add_child(desc)
	_jid = _field(box, "JID", "persona@hablar.fuentelibre.org")
	_name = _field(box, "Nombre (opcional)", "Cómo querés llamarlo")
	_error = Label.new()
	_error.add_color_override("font_color", P.ERROR)
	box.add_child(_error)
	connect("confirmed", self, "_on_confirmed")
	get_ok().text = "Añadir"
	for e in [_jid, _name]:
		e.connect("text_changed", self, "_validate")
	_validate("")

# Etiqueta chica encima de un campo grande.
func _field(p_parent: VBoxContainer, p_label: String, p_placeholder: String) -> LineEdit:
	var l = Label.new()
	l.text = p_label
	l.add_color_override("font_color", P.TEXT_DIM)
	p_parent.add_child(l)
	var e = LineEdit.new()
	e.placeholder_text = p_placeholder
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.rect_min_size = Vector2(0, 46)
	e.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE + 2))
	p_parent.add_child(e)
	return e

func open() -> void:
	_jid.text = ""
	_name.text = ""
	_error.text = ""
	_validate("")
	popup_centered(Vector2(560, 340))
	_jid.grab_focus()

func _validate(_text: String) -> void:
	var jid = _jid.text.strip_edges()
	var valid = _is_valid(jid)
	get_ok().disabled = not valid
	if jid == "":
		_error.text = ""
	elif not valid:
		_error.text = "JID inválido (usá usuario@dominio)."
	else:
		_error.text = ""

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
