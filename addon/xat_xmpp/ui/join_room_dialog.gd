extends AcceptDialog

# Diálogo para unirse/crear una sala MUC. Sólo se pide un nombre; el dominio de
# salas (`conference.<dominio>`, descubierto) se muestra como sufijo fijo, y el
# nick en la sala es el del propio usuario (no se pregunta). Si el texto incluye
# "@" se toma como JID completo. Emite `submitted(room_bare)`.

signal submitted(room)

const Jid = preload("res://addons/xat_xmpp/xmpp/jid.gd")
const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")

var _name: LineEdit
var _suffix: Label
var _error: Label
var _ok_btn: Button
var _domain := ""

func _init() -> void:
	name = "JoinRoomDialog"
	window_title = "Nueva sala"
	rect_min_size = Vector2(300, 0)
	var margin = MarginContainer.new()
	margin.add_constant_override("margin_left", 24)
	margin.add_constant_override("margin_right", 24)
	margin.add_constant_override("margin_top", 22)
	margin.add_constant_override("margin_bottom", 20)
	add_child(margin)
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 14)
	margin.add_child(box)
	# Cabecera con la acción de confirmar arriba: el teclado virtual no la tapa.
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 10)
	box.add_child(head)
	var title = Label.new()
	title.text = "Unirse a una sala"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_font_override("font", XatTheme.font(P.FONT_BOLD, P.FONT_SIZE + 4))
	head.add_child(title)
	_ok_btn = Button.new()
	_ok_btn.text = "Unirse"
	_ok_btn.focus_mode = Control.FOCUS_NONE
	_ok_btn.connect("pressed", self, "_on_submit")
	head.add_child(_ok_btn)
	get_ok().visible = false
	var desc = Label.new()
	desc.text = "Elegí un nombre para la sala. El servidor arma el JID y tu nick es el tuyo."
	desc.autowrap = true
	desc.rect_min_size = Vector2(0, 0)
	desc.add_color_override("font_color", P.TEXT_DIM)
	box.add_child(desc)
	# Campo de nombre + sufijo fijo "@conference.dominio".
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 0)
	box.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = "mi-sala"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.rect_min_size = Vector2(0, 46)
	_name.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE + 3))
	_name.connect("text_changed", self, "_on_changed")
	_name.connect("text_entered", self, "_on_entered")
	row.add_child(_name)
	_suffix = Label.new()
	_suffix.add_color_override("font_color", P.TEXT_DIM)
	_suffix.valign = Label.VALIGN_CENTER
	_suffix.rect_min_size = Vector2(0, 46)
	row.add_child(_suffix)
	_error = Label.new()
	_error.add_color_override("font_color", P.ERROR)
	box.add_child(_error)
	connect("confirmed", self, "_on_submit")
	_update_suffix()
	_validate()

# `p_conference` = dominio de salas descubierto (p.ej. conference.hablar...).
func open(p_conference: String = "") -> void:
	_domain = p_conference
	_name.text = ""
	_error.text = ""
	_update_suffix()
	_validate()
	popup_centered(Vector2(_dialog_width(), 0))
	_name.grab_focus()

# Ancho que entra en pantalla (móvil portrait) y no excede ~520 en escritorio.
func _dialog_width() -> int:
	var vp = get_viewport().get_visible_rect().size
	return int(clamp(vp.x - 32.0, 280.0, 520.0))

func _on_changed(_text: String) -> void:
	_update_suffix()
	_validate()

func _update_suffix() -> void:
	var text = _name.text.strip_edges()
	if text == "" or text.find("@") >= 0 or _domain == "":
		_suffix.text = ""
	else:
		_suffix.text = "@" + _domain

# JID completo: si el texto trae "@" se respeta; si no, se agrega el dominio.
func _full() -> String:
	var text = _name.text.strip_edges()
	if text == "":
		return ""
	if text.find("@") >= 0:
		return text
	if _domain == "":
		return ""
	return text + "@" + _domain

func _validate() -> void:
	var text = _name.text.strip_edges()
	var valid = _is_valid(text)
	_ok_btn.disabled = not valid
	if text == "":
		_error.text = ""
	elif text.find(" ") >= 0 or text.find("/") >= 0:
		_error.text = "El nombre no puede tener espacios ni «/»."
	elif not valid:
		_error.text = "Nombre de sala inválido."
	else:
		_error.text = ""

func _is_valid(p_text: String) -> bool:
	if p_text == "" or p_text.find(" ") >= 0 or p_text.find("/") >= 0:
		return false
	var j = Jid.new()
	j.parse(_full())
	return j.is_valid() and j.node != "" and j.domain != ""

func _on_entered(_text: String) -> void:
	_on_submit()

func _on_submit() -> void:
	if not _is_valid(_name.text.strip_edges()):
		return
	emit_signal("submitted", _full())
	hide()
