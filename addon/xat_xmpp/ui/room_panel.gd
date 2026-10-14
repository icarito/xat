extends PanelContainer

# Pane de participantes de una sala (XEP-0045). Agrupa ocupantes por JID real
# (sala no anónima: mismo bare => una persona con "N dispositivos"); en sala
# anónima no agrupa. Secciona "Agentes" (por caps) y "Personas", muestra roles
# en lenguaje humano (dueño/admin/moderador/miembro) y ofrece acciones al agente
# (Mencionar / Ver mente). El agrupamiento vive en Muc.group_occupants (puro);
# este panel sólo renderiza. Ver docs/ui.md.

signal occupant_selected(nick, bare)
signal mention_requested(nick)
signal back_requested() # vista de un panel (móvil): volver al chat

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const Muc = preload("res://addons/xat_xmpp/xmpp/muc.gd")
const Orb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")

var _room := ""
var _my_nick := ""
var _occupants := []
var _agents := {} # bare -> estado de agente
var _avatars := {} # bare -> textura
var _online := {} # bare -> bool
var _expanded := {} # group key -> bool
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

func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var groups = Muc.group_occupants(_occupants, _agents)
	_empty.visible = groups.empty()
	_title.text = "Participantes (%d)" % _occupants.size()
	var agents := []
	var people := []
	for g in groups:
		if str(g["kind"]) == "agent":
			agents.append(g)
		else:
			people.append(g)
	# Secciones sólo cuando hay agentes (sala mixta o sólo agentes): así una
	# sala de puras personas queda como lista plana.
	if agents.empty():
		for g in people:
			_add_group(g)
	else:
		_rows.add_child(_section_label("Agentes"))
		for g in agents:
			_add_group(g)
		if not people.empty():
			_rows.add_child(_section_label("Personas"))
			for g in people:
				_add_group(g)

func _add_group(p_group: Dictionary) -> void:
	_rows.add_child(_make_group_row(p_group))
	if bool(_expanded.get(p_group["key"], false)):
		var nicks = p_group["nicks"]
		var jids = p_group["jids"]
		for i in range(nicks.size()):
			var jid = str(jids[i]) if i < jids.size() else ""
			_rows.add_child(_make_resource_row(str(nicks[i]), jid, str(p_group["bare"])))

func _section_label(p_text: String) -> Label:
	var l = Label.new()
	l.text = p_text.to_upper()
	l.add_color_override("font_color", P.TEXT_DIM)
	l.rect_min_size = Vector2(0, 30)
	l.valign = Label.VALIGN_BOTTOM
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_group_row(p_group: Dictionary) -> Button:
	var bare = str(p_group["bare"])
	var display = str(p_group["nick"])
	var agent = bool(p_group["is_agent"])
	var devices = int(p_group["devices"])
	var row = Button.new()
	row.toggle_mode = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_stylebox_override("normal", StyleBoxEmpty.new())
	row.add_stylebox_override("focus", StyleBoxEmpty.new())
	row.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 10))
	row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.LINE))
	row.rect_min_size = Vector2(0, 96 if agent else 54)
	row.set_meta("nick", display)
	row.set_meta("bare", bare)
	row.set_meta("agent", agent)
	row.set_meta("devices", devices)
	row.set_meta("key", p_group["key"])
	if devices > 1:
		row.connect("pressed", self, "_toggle_expand", [p_group["key"]])
	else:
		row.connect("pressed", self, "_on_row", [display, bare])
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
		badge.bare = bare if bare != "" else display
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
	name_l.text = display + (" (yo)" if p_group["nicks"].has(_my_nick) else "")
	name_l.clip_text = true
	v.add_child(name_l)
	var st = Label.new()
	st.text = _group_status(p_group)
	st.clip_text = true
	st.add_color_override("font_color", P.activity_color(str(_agents.get(bare, {}).get("activity", ""))) if agent else P.TEXT_DIM)
	v.add_child(st)
	if agent:
		var acts = HBoxContainer.new()
		acts.add_constant_override("separation", 6)
		acts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		acts.add_child(_small_action("Mencionar", "mention", display, bare))
		acts.add_child(_small_action("Ver mente", "mind", display, bare))
		v.add_child(acts)
	if devices > 1:
		var caret = Label.new()
		caret.text = "▾" if bool(_expanded.get(p_group["key"], false)) else "▸"
		caret.add_color_override("font_color", P.TEXT_DIM)
		caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(caret)
	return row

func _small_action(p_label: String, p_action: String, p_nick: String, p_bare: String) -> Button:
	var b = Button.new()
	b.text = p_label
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(0, 44)
	b.clip_text = true
	b.add_color_override("font_color", P.TEXT_DIM)
	b.add_color_override("font_color_hover", P.AGENT_EDGE)
	b.connect("pressed", self, "_on_action", [p_action, p_nick, p_bare])
	return b

func _make_resource_row(p_nick: String, p_jid: String, p_bare: String) -> Button:
	var b = Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(0, 44)
	b.align = Button.ALIGN_LEFT
	b.add_stylebox_override("normal", StyleBoxEmpty.new())
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 8))
	b.add_stylebox_override("pressed", XatTheme.box(P.BG2, 8))
	var slash = p_jid.find("/")
	var res = "" if slash < 0 else p_jid.substr(slash + 1)
	var text = "     ↳ " + p_nick
	if res != "":
		text += "  ·  " + res
	b.text = text
	b.clip_text = true
	b.add_color_override("font_color", P.TEXT_DIM)
	b.connect("pressed", self, "_on_row", [p_nick, p_bare])
	return b

func _group_status(p_group: Dictionary) -> String:
	var bits := []
	if bool(p_group["is_agent"]):
		bits.append(_agent_status(str(p_group["bare"])))
	else:
		var aff = str(p_group["affiliation_label"])
		var role = str(p_group["role_label"])
		if aff != "":
			bits.append(aff)
		if role != "":
			bits.append(role)
	var devices = int(p_group["devices"])
	if devices > 1:
		bits.append("%d dispositivos" % devices)
	var text = PoolStringArray(bits).join(" · ")
	return text if text != "" else "ocupante"

func _agent_status(p_bare: String) -> String:
	var st = _agents.get(p_bare, {})
	if str(st.get("tool", "")) != "":
		return "agente · usando " + str(st["tool"])
	var act = str(st.get("activity", ""))
	return "agente · " + {"processing": "pensando…", "busy": "ocupado", "pending": "esperando aprobación", "paused": "en pausa", "available": "disponible"}.get(act, "conectado")

func _toggle_expand(p_key: String) -> void:
	_expanded[p_key] = not bool(_expanded.get(p_key, false))
	_rebuild()

func _on_action(p_action: String, p_nick: String, p_bare: String) -> void:
	if p_action == "mention":
		emit_signal("mention_requested", p_nick)
	else:
		emit_signal("occupant_selected", p_nick, p_bare)

func _on_row(p_nick: String, p_bare: String) -> void:
	emit_signal("occupant_selected", p_nick, p_bare)
