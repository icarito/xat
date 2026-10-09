extends AcceptDialog

# Diálogo para unirse a una sala MUC: JID de la sala (obligatorio) y nick
# (obligatorio). El dominio de salas se prellena con el componente descubierto
# (`conference.<dominio>`). Emite `submitted(room, nick)`.

signal submitted(room, nick)

const Jid = preload("res://addons/xat_xmpp/xmpp/jid.gd")

var _room: LineEdit
var _nick: LineEdit
var _error: Label
var _default_domain := ""
var _default_nick := ""

func _init() -> void:
	name = "JoinRoomDialog"
	window_title = "Unirse a una sala"
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 8)
	add_child(box)
	_room = _row(box, "Sala", "sala@conference.hablar.fuentelibre.org")
	_nick = _row(box, "Nick", "tu-nick")
	_error = Label.new()
	_error.add_color_override("font_color", Color("ff5c7a"))
	box.add_child(_error)
	connect("confirmed", self, "_on_confirmed")
	get_ok().text = "Unirse"
	for e in [_room, _nick]:
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

# `p_conference` = dominio de salas descubierto (p.ej. conference.hablar...),
# `p_nick` = nick por defecto (el bare local del usuario).
func open(p_conference: String = "", p_nick: String = "") -> void:
	_default_domain = p_conference
	_default_nick = p_nick
	_room.text = ("sala@" + p_conference) if p_conference != "" else ""
	_nick.text = p_nick
	_error.text = ""
	_validate("")
	popup_centered()
	_room.grab_focus()

func _validate(_text: String) -> void:
	var room = _room.text.strip_edges()
	var nick = _nick.text.strip_edges()
	var valid = _is_valid(room) and nick != ""
	get_ok().disabled = not valid
	if room == "" or nick == "":
		_error.text = ""
	elif not _is_valid(room):
		_error.text = "JID de sala inválido (usá sala@conference.dominio)."
	else:
		_error.text = ""

func _is_valid(p_room: String) -> bool:
	# La sala es un bare JID con nodo (el nick va aparte, no en el JID).
	if p_room == "":
		return false
	var j = Jid.new()
	j.parse(p_room)
	return j.is_valid() and j.node != "" and j.domain != ""

func _on_confirmed() -> void:
	var room = _room.text.strip_edges()
	var nick = _nick.text.strip_edges()
	if not _is_valid(room) or nick == "":
		return
	emit_signal("submitted", room, nick)
