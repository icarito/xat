extends PanelContainer

# Roster: filas con avatar XEP-0084 (o mini-orbe para agentes sin avatar, o
# inicial), nombre y línea de estado, ordenadas por última actividad (como
# gtk-llm-chat). Un clic selecciona. Emite peer_selected.

signal peer_selected(bare)

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const AgentOrb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")
const XatXmpp = preload("res://addons/xat_xmpp/xat_xmpp.gd")

var _peers := []
var _online := {}
var _agents := {} # bare -> último state de agente
var _unread := {} # bare -> mensajes sin leer
var _avatars := {} # bare -> textura de avatar
var _activity := {} # bare -> timestamp ISO del último mensaje (orden)
var _selected := ""
var _box: VBoxContainer
var _scroll: ScrollContainer
var _scrolling := false
var _juice = null
var _sound_btn: Button
var _motion_btn: Button
var _haptic_btn: Button

# La lista es una columna de ancho fijo, centrada en el panel: los avatares
# quedan alineados entre filas (no pegados al borde izquierdo a pantalla completa).
const COLUMN_MAX := 360.0
const COLUMN_MARGIN := 16.0

func _init() -> void:
	name = "RosterPanel"
	rect_min_size = Vector2(240, 0)
	var root = VBoxContainer.new()
	add_child(root)
	var sc = ScrollContainer.new()
	_scroll = sc
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.connect("scroll_started", self, "_on_scroll_started")
	sc.connect("scroll_ended", self, "_on_scroll_ended")
	root.add_child(sc)
	# Recoloca la columna cuando cambia el ancho (móvil portrait/landscape).
	connect("resized", self, "_on_resized")
	# Pie: ajustes de juice (sonido / movimiento reducido).
	var foot = HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGN_CENTER
	root.add_child(foot)
	_sound_btn = _toggle("♪", "sound_enabled", "Sonido")
	foot.add_child(_sound_btn)
	_motion_btn = _toggle("✦", "motion_enabled", "Animación")
	foot.add_child(_motion_btn)
	_haptic_btn = _toggle("≋", "haptics_enabled", "Vibración (móvil / gamepad)")
	foot.add_child(_haptic_btn)
	var about_btn = Button.new()
	about_btn.text = "ⓘ"
	about_btn.hint_tooltip = "Privacidad y soporte"
	about_btn.rect_min_size = Vector2(44, 32)
	about_btn.focus_mode = Control.FOCUS_NONE
	about_btn.connect("pressed", self, "_on_about")
	foot.add_child(about_btn)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE # deja pasar el arrastre táctil entre filas
	_box.add_constant_override("separation", 2)
	var top = MarginContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_constant_override("margin_top", 12)
	top.add_constant_override("margin_bottom", 6)
	sc.add_child(top)
	top.add_child(_box)

func set_juice(p_juice) -> void:
	_juice = p_juice
	_sound_btn.pressed = bool(_juice.settings.get("sound_enabled", true))
	_motion_btn.pressed = bool(_juice.settings.get("motion_enabled", true))
	_haptic_btn.pressed = bool(_juice.settings.get("haptics_enabled", true))

func _toggle(p_text: String, p_key: String, p_tip: String) -> Button:
	var b = Button.new()
	b.text = p_text
	b.hint_tooltip = p_tip
	b.rect_min_size = Vector2(44, 32)
	b.toggle_mode = true
	b.pressed = true
	b.focus_mode = Control.FOCUS_NONE
	b.connect("toggled", self, "_on_setting", [p_key])
	return b

func _on_setting(p_on: bool, p_key: String) -> void:
	if _juice != null:
		_juice.set_setting(p_key, p_on)

func _on_about() -> void:
	OS.shell_open(XatXmpp.PRIVACY_URL)

func set_peers(p_bares: Array) -> void:
	_peers = p_bares
	_rebuild()

# Rehace las filas descartando la fuente cacheada (p. ej. tras cambiar el zoom).
func refresh() -> void:
	_rebuild()

func set_online(p_bare: String, p_online: bool) -> void:
	_online[p_bare] = p_online
	_rebuild()

# ponytail: rebuild completo por evento; con roster grande, actualizar sólo la fila.
func set_agent_state(p_bare: String, p_state: Dictionary) -> void:
	var was_agent = _agents.has(p_bare)
	_agents[p_bare] = p_state
	var row = _box.get_node_or_null(_row_name(p_bare))
	if was_agent and row != null:
		if row.has_meta("orb"):
			row.get_meta("orb").set_state(p_state)
		else:
			row.get_meta("badge").set_ring(_ring(p_bare))
		row.get_meta("status").text = _status_text(p_bare)
	else:
		_rebuild()

func set_avatar(p_bare: String, p_tex) -> void:
	_avatars[p_bare] = p_tex
	_rebuild()

# Último mensaje con el peer: si cambia el orden, se reordena.
func touch(p_bare: String, p_ts: String) -> void:
	if p_ts <= str(_activity.get(p_bare, "")):
		return
	_activity[p_bare] = p_ts
	var shown = []
	for row in _box.get_children():
		shown.append(row.get_meta("bare"))
	if shown != _sorted():
		_rebuild()

# Orden: actividad reciente primero (ISO compara como texto), luego en línea, luego nombre.
func _sorted() -> Array:
	var out = _peers.duplicate()
	out.sort_custom(self, "_before")
	return out

func _before(a, b) -> bool:
	var ta = str(_activity.get(a, ""))
	var tb = str(_activity.get(b, ""))
	if ta != tb:
		return ta > tb
	var oa = _online.get(a, false)
	if oa != _online.get(b, false):
		return oa
	return str(a) < str(b)

func set_unread(p_bare: String, p_n: int) -> void:
	var had = int(_unread.get(p_bare, 0)) > 0
	_unread[p_bare] = p_n
	if p_n == 0:
		if had:
			_rebuild() # restaura el color de estado
		return
	var row = _box.get_node_or_null(_row_name(p_bare))
	if row != null:
		var st = row.get_meta("status")
		st.text = _status_text(p_bare)
		if p_n > 0:
			st.add_color_override("font_color", P.PENDING)

func select(p_bare: String) -> void:
	_selected = p_bare
	for row in _box.get_children():
		row.pressed = row.get_meta("bare") == p_bare

func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	for b in _sorted():
		var row = _make_row(str(b))
		_box.add_child(row)
		# El orbe anima con Tween: aplicar estado ya dentro del árbol.
		if row.has_meta("orb"):
			row.get_meta("orb").set_state(_agents[str(b)])
			row.get_meta("orb").set_connected(_online.get(str(b), false))

func _make_row(p_bare: String) -> Button:
	var row = Button.new()
	row.name = _row_name(p_bare)
	row.toggle_mode = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS # el arrastre debe llegar al ScrollContainer
	row.add_stylebox_override("normal", StyleBoxEmpty.new())
	row.add_stylebox_override("focus", StyleBoxEmpty.new())
	row.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 10))
	row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.LINE))
	row.pressed = p_bare == _selected
	row.rect_min_size = Vector2(0, 60)
	row.set_meta("bare", p_bare)
	row.connect("pressed", self, "_on_row", [p_bare])
	# h llena la fila y centra el contenido; la columna (inner) tiene ancho fijo,
	# así los avatares quedan alineados en vertical.
	var h = HBoxContainer.new()
	h.anchor_right = 1.0
	h.anchor_bottom = 1.0
	h.margin_left = 8
	h.margin_right = -8
	h.alignment = BoxContainer.ALIGN_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_constant_override("separation", 0)
	row.add_child(h)
	var inner = HBoxContainer.new()
	inner.rect_min_size.x = _column_width()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_constant_override("separation", 10)
	h.add_child(inner)
	row.set_meta("inner", inner)
	var online = _online.get(p_bare, false)
	if _agents.has(p_bare) and not _avatars.has(p_bare):
		var orb = AgentOrb.new()
		orb.set_compact(true)
		orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		orb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(orb)
		row.set_meta("orb", orb)
	else:
		var badge = AvatarBadge.new(48.0)
		badge.bare = p_bare
		badge.set_texture(_avatars.get(p_bare))
		badge.set_ring(_ring(p_bare))
		badge.modulate.a = 1.0 if online else 0.55
		inner.add_child(badge)
		row.set_meta("badge", badge)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_constant_override("separation", 0)
	inner.add_child(v)
	var name_l = Label.new()
	name_l.text = p_bare.split("@")[0]
	name_l.clip_text = true
	name_l.hint_tooltip = p_bare
	v.add_child(name_l)
	var st = Label.new()
	st.text = _status_text(p_bare)
	st.clip_text = true
	st.add_color_override("font_color", P.activity_color(_agents[p_bare].get("activity", "")) if _agents.has(p_bare) and online else P.TEXT_DIM)
	v.add_child(st)
	row.set_meta("status", st)
	return row

# Ancho de la columna: acotado a COLUMN_MAX y con margen simétrico; si el panel
# es angosto (sidebar de escritorio), ocupa el ancho disponible.
func _column_width() -> float:
	var avail = _scroll.rect_size.x if _scroll != null else rect_size.x
	if avail <= 0.0:
		avail = rect_size.x
	if avail <= 0.0:
		return COLUMN_MAX
	return min(max(140.0, avail - 2.0 * COLUMN_MARGIN), COLUMN_MAX)

func _on_resized() -> void:
	var w = _column_width()
	for row in _box.get_children():
		var inner = row.get_meta("inner", null)
		if inner != null:
			inner.rect_min_size.x = w

func _on_scroll_started() -> void:
	_scrolling = true

func _on_scroll_ended() -> void:
	_scrolling = false

func _status_text(p_bare: String) -> String:
	var n = int(_unread.get(p_bare, 0))
	if n > 0:
		return "● %d nuevo%s" % [n, "" if n == 1 else "s"]
	if not _online.get(p_bare, false):
		return "desconectado"
	if not _agents.has(p_bare):
		return "en línea"
	var st = _agents[p_bare]
	if str(st.get("tool", "")) != "":
		return "usando " + str(st["tool"])
	var act = str(st.get("activity", ""))
	return {"processing": "pensando…", "busy": "ocupado", "pending": "esperando aprobación", "paused": "en pausa", "available": "disponible"}.get(act, "en línea")

# Anillo del avatar: actividad para agentes, verde en línea para personas.
func _ring(p_bare: String) -> Color:
	if not _online.get(p_bare, false):
		return Color(0, 0, 0, 0)
	if _agents.has(p_bare):
		return P.activity_color(str(_agents[p_bare].get("activity", "")))
	return P.OK

func _on_row(p_bare: String) -> void:
	if _scrolling:
		return # el toque fue parte de un arrastre para desplazar la lista
	select(p_bare)
	emit_signal("peer_selected", p_bare)

func _row_name(p_bare: String) -> String:
	return "row_" + p_bare.replace("@", "_").replace(".", "_")
