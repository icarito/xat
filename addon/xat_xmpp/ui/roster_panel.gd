extends PanelContainer

# Roster: filas con avatar XEP-0084 (o mini-orbe para agentes sin avatar, o
# inicial), nombre y línea de estado, ordenadas por última actividad (como
# gtk-llm-chat). Un clic selecciona. Emite peer_selected.

signal peer_selected(bare)
signal add_contact_requested()
signal join_room_requested()
signal subscription_accept(bare)
signal subscription_deny(bare)
signal avatar_requested()
signal room_invite_accept(room)
signal room_invite_ignore(room)

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const AgentOrb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")
const XatXmpp = preload("res://addons/xat_xmpp/xat_xmpp.gd")
const IconButton = preload("res://addons/xat_xmpp/ui/icon_button.gd")

var _peers := []
var _agents := {} # bare -> último state de agente
var _online := {} # bare -> disponible
var _unread := {} # bare -> mensajes sin leer
var _avatars := {} # bare -> textura de avatar
var _activity := {} # bare -> timestamp ISO del último mensaje (orden)
var _selected := ""
var _box: VBoxContainer
var _rooms := [] # salas (bare) persistidas
var _rooms_box: VBoxContainer
var _rooms_header: Label
var _rooms_activity := {} # sala -> timestamp ISO del último mensaje (orden)
var _scroll: ScrollContainer
var _grid_scroll: ScrollContainer
var _grid: HBoxContainer
var _columns := 1 # 1 = lista simple; >1 = multicolumna (landscape) con scroll lateral
var _requests := {} # bare -> status (solicitudes de suscripción pendientes)
var _invites := {} # sala -> {from, reason} (invitaciones MUC pendientes)
var _req_box: VBoxContainer
var _scrolling := false
var _juice = null
var _sound_btn: Button
var _haptic_btn: Button
var _add_btn: Button
var _room_btn: Button
var _foot: HBoxContainer
var _id_btn: Button
var _id_avatar
var _id_name: Label

# La lista es una columna de ancho fijo, centrada en el panel: los avatares
# quedan alineados entre filas (no pegados al borde izquierdo a pantalla completa).
const COLUMN_MAX := 360.0
const COLUMN_MARGIN := 16.0

func _init() -> void:
	name = "RosterPanel"
	rect_min_size = Vector2(240, 0)
	var root = VBoxContainer.new()
	add_child(root)
	root.add_child(_make_header())
	# Solicitudes de suscripción pendientes: banda arriba de la lista, oculta
	# mientras no haya ninguna.
	_req_box = VBoxContainer.new()
	_req_box.visible = false
	_req_box.add_constant_override("separation", 4)
	var req_margin = MarginContainer.new()
	req_margin.add_constant_override("margin_left", COLUMN_MARGIN)
	req_margin.add_constant_override("margin_right", COLUMN_MARGIN)
	req_margin.add_child(_req_box)
	root.add_child(req_margin)
	var sc = ScrollContainer.new()
	_scroll = sc
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.connect("scroll_started", self, "_on_scroll_started")
	sc.connect("scroll_ended", self, "_on_scroll_ended")
	root.add_child(sc)
	# Vista multicolumna (landscape): columnas en un HBox con scroll lateral.
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.scroll_horizontal_enabled = true
	_grid_scroll.scroll_vertical_enabled = true
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.visible = false
	root.add_child(_grid_scroll)
	_grid = HBoxContainer.new()
	_grid.add_constant_override("separation", 4)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_scroll.add_child(_grid)
	# Recoloca la columna cuando cambia el ancho (móvil portrait/landscape).
	connect("resized", self, "_on_resized")
	# Pie: ajustes (sonido / vibración / avatar / acerca) con los mismos iconos
	# vectoriales que el sidebar de landscape, para no mezclar estilos.
	var foot = HBoxContainer.new()
	_foot = foot
	foot.alignment = BoxContainer.ALIGN_CENTER
	foot.add_constant_override("separation", 4)
	root.add_child(foot)
	_sound_btn = _icon_toggle("sound", "sound_enabled", "Sonido")
	foot.add_child(_sound_btn)
	var avatar_btn = _icon_button("person", "Cambiar foto de perfil")
	avatar_btn.connect("pressed", self, "_on_avatar")
	foot.add_child(avatar_btn)
	_haptic_btn = _icon_toggle("vibrate", "haptics_enabled", "Vibración (móvil / gamepad)")
	foot.add_child(_haptic_btn)
	var about_btn = _icon_button("info", "Privacidad y soporte")
	about_btn.connect("pressed", self, "_on_about")
	foot.add_child(about_btn)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE # deja pasar el arrastre táctil entre filas
	_box.add_constant_override("separation", 2)
	# Sección "Salas" (XEP-0045), bajo Contactos. Oculta mientras no haya salas.
	_rooms_header = Label.new()
	_rooms_header.text = "Salas"
	_rooms_header.visible = false
	_rooms_header.add_color_override("font_color", P.TEXT_DIM)
	_rooms_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_box.add_constant_override("separation", 2)
	_rooms_box.visible = false
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_constant_override("separation", 2)
	content.add_child(_box)
	content.add_child(_rooms_header)
	content.add_child(_rooms_box)
	var top = MarginContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_constant_override("margin_top", 12)
	top.add_constant_override("margin_bottom", 6)
	sc.add_child(top)
	top.add_child(content)

# Encabezado del roster: tu identidad (foto + nombre) y las acciones.
func _make_header() -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 6)
	# Identidad propia: foto de perfil (XEP-0084) con un botón superpuesto para
	# cambiarla, y tu nombre debajo. Va primero para saber de quién es la cuenta.
	var id_m = MarginContainer.new()
	id_m.add_constant_override("margin_left", COLUMN_MARGIN)
	id_m.add_constant_override("margin_top", 8)
	id_m.add_constant_override("margin_bottom", 4)
	var id_v = VBoxContainer.new()
	id_v.alignment = BoxContainer.ALIGN_CENTER
	id_v.add_constant_override("separation", 2)
	# La foto y el botón de cambio comparten celda: el botón va superpuesto en la
	# esquina inferior derecha, sobre la foto misma (no como control aparte).
	var pic = Control.new()
	pic.rect_min_size = Vector2(48, 48)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_id_avatar = AvatarBadge.new(48.0)
	pic.add_child(_id_avatar)
	_id_btn = Button.new()
	_id_btn.flat = true
	_id_btn.focus_mode = Control.FOCUS_NONE
	_id_btn.hint_tooltip = "Cambiar foto de perfil"
	_id_btn.rect_min_size = Vector2(22, 22)
	_id_btn.anchor_left = 1.0
	_id_btn.anchor_top = 1.0
	_id_btn.anchor_right = 1.0
	_id_btn.anchor_bottom = 1.0
	_id_btn.margin_left = -22
	_id_btn.margin_top = -22
	_id_btn.add_stylebox_override("normal", _circle_box(P.BG2, P.LINE))
	_id_btn.add_stylebox_override("hover", _circle_box(P.LINE, P.AGENT_EDGE))
	_id_btn.add_stylebox_override("pressed", _circle_box(P.BG0, P.AGENT_EDGE))
	_id_btn.connect("pressed", self, "_on_avatar")
	pic.add_child(_id_btn)
	id_v.add_child(pic)
	_id_name = Label.new()
	_id_name.align = Label.ALIGN_CENTER
	_id_name.clip_text = true
	_id_name.rect_min_size = Vector2(64, 14)
	_id_name.add_color_override("font_color", P.TEXT)
	_id_name.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE - 3))
	id_v.add_child(_id_name)
	id_m.add_child(id_v)
	h.add_child(id_m)
	# Sin título "Contactos": es la única lista del panel, el nombre sobra.
	var m = MarginContainer.new()
	m.add_constant_override("margin_left", 0)
	m.add_constant_override("margin_right", 8)
	m.add_constant_override("margin_top", 12)
	m.add_constant_override("margin_bottom", 4)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(m)
	var add = _icon_button("person_add", "Añadir contacto por JID")
	add.connect("pressed", self, "_on_add_contact")
	_add_btn = add
	h.add_child(add)
	var room = _icon_button("hash", "Unirse a una sala (MUC)")
	room.connect("pressed", self, "_on_join_room")
	_room_btn = room
	h.add_child(room)
	return h

# Fija tu identidad en la cabecera (foto de perfil y nombre de la cuenta).
func set_identity(p_bare: String, p_tex) -> void:
	if _id_avatar != null:
		_id_avatar.bare = p_bare
		_id_avatar.set_texture(p_tex)
	if _id_name != null:
		_id_name.text = p_bare.split("@")[0] if p_bare != "" else ""
	if _id_btn != null:
		_id_btn.hint_tooltip = p_bare if p_bare != "" else "Cambiar foto de perfil"

# Oculta los botones propios del roster (añadir/sala y pie de ajustes) cuando la
# navegación vive en el sidebar (landscape).
func set_chrome_visible(p_visible: bool) -> void:
	if _add_btn != null:
		_add_btn.visible = p_visible
	if _room_btn != null:
		_room_btn.visible = p_visible
	if _foot != null:
		_foot.visible = p_visible

func _on_add_contact() -> void:
	emit_signal("add_contact_requested")

func _on_join_room() -> void:
	emit_signal("join_room_requested")

# --- Solicitudes de suscripción pendientes ---

func add_request(p_bare: String, p_status: String = "") -> void:
	if _requests.has(p_bare):
		return
	_requests[p_bare] = p_status
	_rebuild_requests()

func remove_request(p_bare: String) -> void:
	if _requests.has(p_bare):
		_requests.erase(p_bare)
		_rebuild_requests()

func has_request(p_bare: String) -> bool:
	return _requests.has(p_bare)

# --- Invitaciones a salas (MUC) ---

func add_invite(p_room: String, p_from: String, p_reason: String = "") -> void:
	_invites[p_room] = {"from": p_from, "reason": p_reason}
	_rebuild_requests()

func remove_invite(p_room: String) -> void:
	if _invites.has(p_room):
		_invites.erase(p_room)
		_rebuild_requests()

func _rebuild_requests() -> void:
	for c in _req_box.get_children():
		_req_box.remove_child(c)
		c.queue_free()
	_req_box.visible = not _requests.empty() or not _invites.empty()
	for bare in _requests.keys():
		_req_box.add_child(_make_request_row(str(bare)))
	for room in _invites.keys():
		_req_box.add_child(_make_invite_row(str(room)))

func _make_invite_row(p_room: String) -> PanelContainer:
	var info = _invites.get(p_room, {})
	var who = str(info.get("from", ""))
	var reason = str(info.get("reason", ""))
	var card = PanelContainer.new()
	card.add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.AGENT_EDGE))
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 4)
	card.add_child(v)
	var l = Label.new()
	l.text = "%s te invita a %s" % [who if who != "" else "Alguien", p_room]
	l.clip_text = true
	l.hint_tooltip = p_room
	v.add_child(l)
	if reason != "":
		var note = Label.new()
		note.text = reason
		note.clip_text = true
		note.add_color_override("font_color", P.TEXT_DIM)
		v.add_child(note)
	var actions = HBoxContainer.new()
	actions.add_constant_override("separation", 6)
	v.add_child(actions)
	var accept = Button.new()
	accept.text = "Unirse"
	accept.focus_mode = Control.FOCUS_NONE
	accept.connect("pressed", self, "_on_invite_accept", [p_room])
	actions.add_child(accept)
	var ignore = Button.new()
	ignore.text = "Ignorar"
	ignore.focus_mode = Control.FOCUS_NONE
	ignore.connect("pressed", self, "_on_invite_ignore", [p_room])
	actions.add_child(ignore)
	return card

func _on_invite_accept(p_room: String) -> void:
	remove_invite(p_room)
	emit_signal("room_invite_accept", p_room)

func _on_invite_ignore(p_room: String) -> void:
	remove_invite(p_room)
	emit_signal("room_invite_ignore", p_room)

func _make_request_row(p_bare: String) -> PanelContainer:
	var card = PanelContainer.new()
	card.add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.PENDING))
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 4)
	card.add_child(v)
	var who = Label.new()
	who.text = "%s quiere agregarte" % p_bare
	who.clip_text = true
	who.hint_tooltip = p_bare
	v.add_child(who)
	var status = str(_requests.get(p_bare, ""))
	if status != "":
		var note = Label.new()
		note.text = status
		note.clip_text = true
		note.add_color_override("font_color", P.TEXT_DIM)
		v.add_child(note)
	var actions = HBoxContainer.new()
	actions.add_constant_override("separation", 6)
	v.add_child(actions)
	var accept = Button.new()
	accept.text = "Aceptar"
	accept.focus_mode = Control.FOCUS_NONE
	accept.connect("pressed", self, "_on_request_accept", [p_bare])
	actions.add_child(accept)
	var deny = Button.new()
	deny.text = "Rechazar"
	deny.focus_mode = Control.FOCUS_NONE
	deny.connect("pressed", self, "_on_request_deny", [p_bare])
	actions.add_child(deny)
	return card

func _on_request_accept(p_bare: String) -> void:
	remove_request(p_bare)
	emit_signal("subscription_accept", p_bare)

func _on_request_deny(p_bare: String) -> void:
	remove_request(p_bare)
	emit_signal("subscription_deny", p_bare)

func set_juice(p_juice) -> void:
	_juice = p_juice
	for pair in [[_sound_btn, "sound_enabled"], [_haptic_btn, "haptics_enabled"]]:
		var on = bool(_juice.settings.get(pair[1], true))
		pair[0].pressed = on
		pair[0].set_icon_color(P.USER if on else P.TEXT_DIM)

# Iconos vectoriales compartidos con el sidebar de landscape (mismo estilo).
func _icon_button(p_glyph: String, p_tip: String) -> IconButton:
	var b = IconButton.new()
	b.setup(p_glyph, 40, P.TEXT_DIM, p_tip)
	for st in ["normal", "focus"]:
		b.add_stylebox_override(st, XatTheme.box(P.BG2, 10, 4, 4))
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 4, 4))
	b.add_stylebox_override("pressed", XatTheme.box(P.BG2.darkened(0.15), 10, 4, 4))
	b.connect("mouse_entered", self, "_on_icon_hover", [b, true])
	b.connect("mouse_exited", self, "_on_icon_hover", [b, false])
	return b

# Caja circular pequeña para el botón overlay de la foto.
func _circle_box(p_bg: Color, p_border: Color) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = p_bg
	s.set_corner_radius_all(11)
	s.set_border_width_all(1)
	s.border_color = p_border
	return s

func _icon_toggle(p_glyph: String, p_key: String, p_tip: String) -> IconButton:
	var b = IconButton.new()
	b.setup(p_glyph, 40, P.TEXT_DIM, p_tip)
	b.toggle_mode = true
	b.add_stylebox_override("normal", XatTheme.box(P.BG2, 10, 4, 4))
	b.add_stylebox_override("focus", XatTheme.box(P.BG2, 10, 4, 4))
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 4, 4))
	b.add_stylebox_override("pressed", XatTheme.box(P.USER.darkened(0.55), 10, 4, 4))
	var on = _juice == null or bool(_juice.settings.get(p_key, true))
	b.pressed = on
	b.set_icon_color(P.USER if on else P.TEXT_DIM)
	b.connect("toggled", self, "_on_icon_toggle", [b, p_key])
	return b

func _on_icon_hover(p_b, p_enter: bool) -> void:
	if p_b.toggle_mode and p_b.pressed:
		return
	p_b.set_icon_color(P.TEXT if p_enter else P.TEXT_DIM)

func _on_icon_toggle(p_on: bool, p_b, p_key: String) -> void:
	if _juice != null:
		_juice.set_setting(p_key, p_on)
	p_b.set_icon_color(P.USER if p_on else P.TEXT_DIM)

func _on_about() -> void:
	OS.shell_open(XatXmpp.PRIVACY_URL)

func _on_avatar() -> void:
	emit_signal("avatar_requested")

func set_peers(p_bares: Array) -> void:
	_peers = p_bares
	_rebuild()

# Rehace las filas descartando la fuente cacheada (p. ej. tras cambiar el zoom).
func refresh() -> void:
	_rebuild()
	_rebuild_rooms()

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

# Último mensaje con el peer/sala: si cambia el orden, se reordena.
func touch(p_bare: String, p_ts: String) -> void:
	if _rooms.has(p_bare):
		if p_ts <= str(_rooms_activity.get(p_bare, "")):
			return
		_rooms_activity[p_bare] = p_ts
		_rebuild_rooms()
		return
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
	var row = _find_row(p_bare)
	if row != null:
		var st = row.get_meta("status")
		st.text = _status_text(p_bare)
		if p_n > 0:
			st.add_color_override("font_color", P.PENDING)

func select(p_bare: String) -> void:
	_selected = p_bare
	for row in _box.get_children():
		row.pressed = row.get_meta("bare") == p_bare
	for row in _rooms_box.get_children():
		row.pressed = row.get_meta("bare") == p_bare

func _find_row(p_bare: String):
	var row = _box.get_node_or_null(_row_name(p_bare))
	if row == null:
		row = _rooms_box.get_node_or_null(_room_row_name(p_bare))
	return row

# --- Salas (XEP-0045) ---

# Reemplaza la lista de salas persistidas (bares) y reconstruye la sección.
func set_rooms(p_rooms: Array) -> void:
	_rooms = p_rooms
	var kept := {}
	for r in _rooms:
		kept[str(r)] = true
	for b in _rooms_activity.keys():
		if not kept.has(b):
			_rooms_activity.erase(b)
	_rebuild_rooms()

func _sorted_rooms() -> Array:
	var out = _rooms.duplicate()
	out.sort_custom(self, "_before_room")
	return out

func _before_room(a, b) -> bool:
	var ta = str(_rooms_activity.get(a, ""))
	var tb = str(_rooms_activity.get(b, ""))
	if ta != tb:
		return ta > tb
	return str(a) < str(b)

func _rebuild_rooms() -> void:
	if _rooms_box == null:
		return
	if _columns > 1:
		_rebuild() # la vista grid incluye contactos + salas
		return
	for c in _rooms_box.get_children():
		_rooms_box.remove_child(c)
		c.queue_free()
	var has = not _rooms.empty()
	_rooms_header.visible = has
	_rooms_box.visible = has
	if not has:
		return
	for b in _sorted_rooms():
		_rooms_box.add_child(_make_room_row(str(b)))

# Alterna entre lista simple (portrait) y multicolumna con scroll lateral
# (landscape). El número de columnas lo decide main según el ancho.
func set_columns(p_n: int) -> void:
	p_n = max(1, p_n)
	if p_n == _columns:
		return
	_columns = p_n
	var grid = _columns > 1
	if _scroll != null:
		_scroll.visible = not grid
	if _grid_scroll != null:
		_grid_scroll.visible = grid
	_rebuild()
	if not grid:
		_rebuild_rooms()

func _make_room_row(p_room: String) -> Button:
	var row = Button.new()
	row.name = _room_row_name(p_room)
	row.toggle_mode = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_stylebox_override("normal", StyleBoxEmpty.new())
	row.add_stylebox_override("focus", StyleBoxEmpty.new())
	row.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 10))
	row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.LINE))
	row.pressed = p_room == _selected
	row.rect_min_size = Vector2(0, 54)
	row.set_meta("bare", p_room)
	row.set_meta("room", true)
	row.connect("pressed", self, "_on_row", [p_room])
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
	var hash_l = Label.new()
	hash_l.text = "#"
	hash_l.rect_min_size = Vector2(48, 0)
	hash_l.align = Label.ALIGN_CENTER
	hash_l.valign = Label.VALIGN_CENTER
	hash_l.add_color_override("font_color", P.LINE)
	hash_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(hash_l)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGN_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_constant_override("separation", 0)
	inner.add_child(v)
	var name_l = Label.new()
	name_l.text = p_room.split("@")[0]
	name_l.clip_text = true
	name_l.hint_tooltip = p_room
	v.add_child(name_l)
	var st = Label.new()
	st.text = _status_text(p_room)
	st.clip_text = true
	st.add_color_override("font_color", P.TEXT_DIM)
	v.add_child(st)
	row.set_meta("status", st)
	return row

func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if _columns > 1:
		_rebuild_grid()
		return
	for b in _sorted():
		var row = _make_row(str(b))
		_box.add_child(row)
		# El orbe anima con Tween: aplicar estado ya dentro del árbol.
		if row.has_meta("orb"):
			row.get_meta("orb").set_state(_agents[str(b)])
			row.get_meta("orb").set_connected(_online.get(str(b), false))
	_settle_scale()

# Escala la geometría de las filas recién creadas al factor de zoom vigente.
func _settle_scale() -> void:
	var fz = get_node_or_null("/root/FontZoom")
	if fz != null:
		fz.settle(self)

# Multicolumna (landscape): reparte contactos y salas en `_columns` columnas,
# llenando de izquierda a derecha (orden de lectura) y con scroll lateral.
func _rebuild_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if _rooms_header != null:
		_rooms_header.visible = false
	if _rooms_box != null:
		_rooms_box.visible = false
	var items := []
	for b in _sorted():
		items.append(_make_row(str(b)))
	if not _rooms.empty():
		var hdr = Label.new()
		hdr.text = "Salas"
		hdr.add_color_override("font_color", P.TEXT_DIM)
		hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		items.append(hdr)
		for b in _sorted_rooms():
			items.append(_make_room_row(str(b)))
	var n = max(1, _columns)
	var cols := []
	for i in range(n):
		var v = VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.append(v)
		_grid.add_child(v)
	for i in range(items.size()):
		var it = items[i]
		cols[i % n].add_child(it)
		if it.has_meta("bare") and it.has_meta("orb"):
			var b = str(it.get_meta("bare"))
			if _agents.has(b):
				it.get_meta("orb").set_state(_agents[b])
			it.get_meta("orb").set_connected(_online.get(b, false))

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
	var avail := 0.0
	if _columns > 1:
		avail = rect_size.x
	elif _scroll != null:
		avail = _scroll.rect_size.x
	if avail <= 0.0:
		avail = rect_size.x
	if avail <= 0.0:
		return COLUMN_MAX
	if _columns > 1:
		# Ancho de celda: reparte el ancho entre las columnas.
		return max(160.0, (avail - 2.0 * COLUMN_MARGIN) / float(_columns))
	return min(max(140.0, avail - 2.0 * COLUMN_MARGIN), COLUMN_MAX)

func _on_resized() -> void:
	var w = _column_width()
	for row in _box.get_children():
		if row.has_meta("inner"):
			row.get_meta("inner").rect_min_size.x = w
	if _rooms_box != null:
		for row in _rooms_box.get_children():
			if row.has_meta("inner"):
				row.get_meta("inner").rect_min_size.x = w
	if _columns > 1 and _grid != null:
		for col in _grid.get_children():
			for row in col.get_children():
				if row.has_meta("inner"):
					row.get_meta("inner").rect_min_size.x = w

func _on_scroll_started() -> void:
	_scrolling = true

func _on_scroll_ended() -> void:
	_scrolling = false

func _status_text(p_bare: String) -> String:
	var n = int(_unread.get(p_bare, 0))
	if n > 0:
		return "● %d nuevo%s" % [n, "" if n == 1 else "s"]
	if _rooms.has(p_bare):
		return "sala"
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

func _room_row_name(p_room: String) -> String:
	return "room_" + p_room.replace("@", "_").replace(".", "_")
