extends PanelContainer

# Pane de participantes de una sala (XEP-0045). Lista los ocupantes; los que son
# agentes muestran su orbe/estado y, al tocarlos, se abre su panel "mente"
# (actividad/telemetría) igual que en la vista 1:1. Ver docs/ui.md.
#
# El mapeo ocupante->agente usa el `jid` real (sólo en salas no anónimas) o, si
# no viene, el nick contra los bares de agentes conocidos.

signal occupant_selected(nick, bare)
signal back_requested() # vista de un panel (móvil): volver al chat

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const Presence = preload("res://addons/xat_xmpp/xmpp/presence.gd")
const Orb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")

var _room := ""
var _my_nick := ""
var _occupants := []
var _agents := {} # bare -> estado de agente
var _avatars := {} # bare -> textura
var _online := {} # bare -> bool
var _back: Button
var _title: Label
var _rows: VBoxContainer
var _empty: Label

func _init():
	rect_min_size = Vector2(260, 0)
	add_stylebox_override("panel", XatTheme.box(P.BG1, 0, 12))
	var root := VBoxContainer.new()
	root.add_constant_override("separation", 4)
	add_child(root)
	var bar := HBoxContainer.new()
	root.add_child(bar)
	_back = Button.new()
	_back.text = "←"
	_back.flat = true
	_back.visible = false
	_back.focus_mode = Control.FOCUS_NONE
	_back.rect_min_size = Vector2(40, 32)
	_back.connect("pressed", self, "emit_signal", ["back_requested"])
	bar.add_child(_back)
	_title = Label.new()
	_title.text = "Participantes"
	_title.clip_text = true
	_title.rect_min_size = Vector2(0, 32)
	_title.valign = Label.VALIGN_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_title)
	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_constant_override("separation", 2)
	sc.add_child(v)
	_empty = Label.new()
	_empty.text = "Nadie en la sala."
	_empty.add_color_override("font_color", P.TEXT_DIM)
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_empty)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_constant_override("separation", 2)
	v.add_child(_rows)

func set_back_visible(p_visible: bool) -> void:
	_back.visible = p_visible

func set_room(p_room: String, p_my_nick: String, p_occupants: Array) -> void:
	_room = p_room
	_my_nick = p_my_nick
	_occupants = p_occupants
	_rebuild()

func update_occupants(p_occupants: Array) -> void:
	_occupants = p_occupants
	_rebuild()

# Marca/actualiza el estado de un ocupante agente (bare JID).
func set_agent(p_bare: String, p_state: Dictionary, p_online: bool) -> void:
	if p_bare == "":
		return
	_agents[p_bare] = p_state
	_online[p_bare] = p_online
	_rebuild()

func set_avatar(p_bare: String, p_tex) -> void:
	if p_bare == "":
		return
	_avatars[p_bare] = p_tex
	_rebuild()

func occupant_count() -> int:
	return _occupants.size()

# Bare JID del ocupante: por el `jid` real (sala no anónima) o por nick contra
# los bares de agentes ya conocidos.
func _resolve_bare(p_occ: Dictionary) -> String:
	var jid = str(p_occ.get("jid", ""))
	if jid != "":
		return Presence.bare_of(jid)
	var nick = str(p_occ.get("nick", ""))
	for b in _agents.keys():
		if str(b).split("@")[0] == nick:
			return str(b)
	return ""

func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var n = _occupants.size()
	_empty.visible = n == 0
	_title.text = "Participantes (%d)" % n
	for occ in _occupants:
		_rows.add_child(_make_row(occ))

func _make_row(p_occ: Dictionary) -> Button:
	var bare = _resolve_bare(p_occ)
	var nick = str(p_occ.get("nick", ""))
	var agent = bare != "" and _agents.has(bare)
	var row = Button.new()
	row.toggle_mode = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_stylebox_override("normal", StyleBoxEmpty.new())
	row.add_stylebox_override("focus", StyleBoxEmpty.new())
	row.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 10))
	row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.LINE))
	row.rect_min_size = Vector2(0, 54)
	row.set_meta("nick", nick)
	row.set_meta("bare", bare)
	row.set_meta("agent", agent)
	row.connect("pressed", self, "_on_row", [nick, bare])
	var h = HBoxContainer.new()
	h.anchor_right = 1.0
	h.anchor_bottom = 1.0
	h.margin_left = 8
	h.margin_right = -8
	h.alignment = BoxContainer.ALIGN_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_constant_override("separation", 10)
	row.add_child(h)
	if agent:
		var orb = Orb.new()
		orb.set_compact(true)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(orb)
		orb.set_state(_agents[bare])
		orb.set_connected(_online.get(bare, false))
	else:
		var badge = AvatarBadge.new(40.0)
		badge.bare = bare if bare != "" else nick
		badge.set_texture(_avatars.get(bare))
		badge.set_ring(P.OK if _online.get(bare, false) else Color(0, 0, 0, 0))
		h.add_child(badge)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_constant_override("separation", 0)
	h.add_child(v)
	var name_l = Label.new()
	name_l.text = nick + (" (yo)" if nick == _my_nick else "")
	name_l.clip_text = true
	v.add_child(name_l)
	var st = Label.new()
	st.text = _status_text(p_occ, bare, agent)
	st.clip_text = true
	st.add_color_override("font_color", P.activity_color(str(_agents.get(bare, {}).get("activity", ""))) if agent else P.TEXT_DIM)
	v.add_child(st)
	return row

func _status_text(p_occ: Dictionary, p_bare: String, p_agent: bool) -> String:
	if p_agent:
		var st = _agents[p_bare]
		if str(st.get("tool", "")) != "":
			return "usando " + str(st["tool"])
		var act = str(st.get("activity", ""))
		return "agente · " + {"processing": "pensando…", "busy": "ocupado", "pending": "esperando aprobación", "paused": "en pausa", "available": "disponible"}.get(act, "conectado")
	var bits := []
	var role = str(p_occ.get("role", ""))
	var aff = str(p_occ.get("affiliation", ""))
	if role != "":
		bits.append(role)
	if aff != "" and aff != "none":
		bits.append(aff)
	return PoolStringArray(bits).join(" · ") if not bits.empty() else "ocupante"

func _on_row(p_nick: String, p_bare: String) -> void:
	emit_signal("occupant_selected", p_nick, p_bare)
