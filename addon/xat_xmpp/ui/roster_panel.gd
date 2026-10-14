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
signal update_requested()
signal font_scale_requested(dir) # -1 achicar, +1 agrandar letra
signal room_invite_accept(room)
signal room_invite_ignore(room)
signal fleet_requested() # X2.5: tocar la franja de flota abre la vista Flota
signal quick_question_requested(bare, text) # X2.3: chip de pregunta rápida

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const AgentOrb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const AvatarBadge = preload("res://addons/xat_xmpp/ui/avatar_badge.gd")
const XatXmpp = preload("res://addons/xat_xmpp/xat_xmpp.gd")
const IconButton = preload("res://addons/xat_xmpp/ui/icon_button.gd")
const QuickQuestions = preload("res://addons/xat_xmpp/ui/quick_questions.gd")

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
var _rooms_activity := {} # sala -> timestamp ISO del último mensaje (orden)
var _scroll: ScrollContainer
var _grid_scroll: ScrollContainer
var _grid: HBoxContainer
var _columns := 1 # 1 = lista simple; >1 = multicolumna (landscape) con scroll lateral
var _requests := {} # bare -> status (solicitudes de suscripción pendientes)
var _invites := {} # sala -> {from, reason} (invitaciones MUC pendientes)
var _deferred := {} # sala -> {from, reason} ("Ahora no": pendiente en Salas)
var _names := {} # bare -> nombre visible del roster (X2.4 humaniza la invitación)
var _last_msg := {} # bare -> {from, body, ts} último mensaje, para la tarjeta de agente (X2.2)
var _room_info := {} # sala -> {subject, last_from, last_body, last_ts, occupants} (X3.1)
var _fleet := {} # resumen del snapshot de flota (X2.5); {} = sin datos
var _fleet_strip: Button
var _fleet_bar
var _fleet_fresh: Label
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

# Pestañas Contactos | Salas (arrastrables con swipe en táctil).
var _tabbar_margin: MarginContainer
var _tabbar: HBoxContainer
var _tab_contacts: Button
var _tab_rooms: Button
var _rooms_scroll: ScrollContainer
var _rooms_empty: Label
var _tab := 0
var _touch_start := Vector2.ZERO
var _touch_active := false
var _swipe_consumed := false

# La lista es una columna de ancho fijo, centrada en el panel: los avatares
# quedan alineados entre filas (no pegados al borde izquierdo a pantalla completa).
const COLUMN_MAX := 320.0
const COLUMN_MARGIN := 18.0

func _init() -> void:
	name = "RosterPanel"
	rect_min_size = Vector2(240, 0)
	var root = VBoxContainer.new()
	add_child(root)
	root.add_child(_make_header())
	# X2.5: franja de flota (salud + frescura), justo bajo la identidad.
	root.add_child(_make_fleet_wrap())
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
	# Pestañas Contactos | Salas (cada panel con su título).
	_tabbar_margin = MarginContainer.new()
	_tabbar_margin.add_constant_override("margin_left", COLUMN_MARGIN)
	_tabbar_margin.add_constant_override("margin_right", COLUMN_MARGIN)
	_tabbar_margin.add_constant_override("margin_top", 8)
	root.add_child(_tabbar_margin)
	_tabbar = HBoxContainer.new()
	_tabbar.add_constant_override("separation", 4)
	_tabbar_margin.add_child(_tabbar)
	# Las pestañas van al tope del roster (mejor uso del espacio).
	root.move_child(_tabbar_margin, 0)
	_tab_contacts = _tab_button("Contactos", 0)
	_tabbar.add_child(_tab_contacts)
	_tab_rooms = _tab_button("Salas", 1)
	_tabbar.add_child(_tab_rooms)
	# Página Contactos.
	var sc = ScrollContainer.new()
	_scroll = sc
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.connect("scroll_started", self, "_on_scroll_started")
	sc.connect("scroll_ended", self, "_on_scroll_ended")
	root.add_child(sc)
	var top = MarginContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_constant_override("margin_left", COLUMN_MARGIN)
	top.add_constant_override("margin_right", COLUMN_MARGIN)
	top.add_constant_override("margin_top", 6)
	top.add_constant_override("margin_bottom", 6)
	sc.add_child(top)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE # deja pasar el arrastre táctil entre filas
	_box.add_constant_override("separation", 2)
	top.add_child(_box)
	# Página Salas (XEP-0045): sus propias salas guardadas, con título.
	_rooms_scroll = ScrollContainer.new()
	_rooms_scroll.scroll_horizontal_enabled = false
	_rooms_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rooms_scroll.visible = false
	root.add_child(_rooms_scroll)
	var rooms_top = MarginContainer.new()
	rooms_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_top.add_constant_override("margin_left", COLUMN_MARGIN)
	rooms_top.add_constant_override("margin_right", COLUMN_MARGIN)
	rooms_top.add_constant_override("margin_top", 6)
	rooms_top.add_constant_override("margin_bottom", 6)
	_rooms_scroll.add_child(rooms_top)
	var rooms_v = VBoxContainer.new()
	rooms_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rooms_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rooms_v.add_constant_override("separation", 8)
	rooms_top.add_child(rooms_v)
	_rooms_empty = Label.new()
	_rooms_empty.text = "No estás en ninguna sala todavía.\nUsá “Unirse a sala” o aceptá una invitación."
	_rooms_empty.autowrap = true
	_rooms_empty.align = Label.ALIGN_CENTER
	_rooms_empty.add_color_override("font_color", P.TEXT_DIM)
	_rooms_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rooms_v.add_child(_rooms_empty)
	_rooms_box = VBoxContainer.new()
	_rooms_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rooms_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rooms_box.add_constant_override("separation", 2)
	rooms_v.add_child(_rooms_box)
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
	var update_btn = _icon_button("download", "Buscar actualizaciones")
	update_btn.connect("pressed", self, "_on_update")
	foot.add_child(update_btn)
	# Tamaño de letra: accesible donde los atajos Ctrl/Cmd+± no llegan (macOS).
	var smaller = _icon_button("text_minus", "Achicar la letra")
	smaller.connect("pressed", self, "_on_font_smaller")
	foot.add_child(smaller)
	var bigger = _icon_button("text_plus", "Agrandar la letra")
	bigger.connect("pressed", self, "_on_font_bigger")
	foot.add_child(bigger)
	_set_tab(0)
	set_process_input(true)

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

# X2.5: franja de flota. Barra de salud + frescura ("LIVE · hace 12 s"); toca
# toda la franja (>=44 px) y emite `fleet_requested`. Sin datos = "sin datos"
# en gris, nunca 0 ni verde (honestidad).
func _make_fleet_wrap() -> MarginContainer:
	var m = MarginContainer.new()
	m.add_constant_override("margin_left", COLUMN_MARGIN)
	m.add_constant_override("margin_right", COLUMN_MARGIN)
	m.add_constant_override("margin_top", 2)
	_fleet_strip = Button.new()
	_fleet_strip.rect_min_size = Vector2(0, 44)
	_fleet_strip.focus_mode = Control.FOCUS_NONE
	_fleet_strip.hint_tooltip = "Abrir la flota"
	_fleet_strip.add_stylebox_override("normal", XatTheme.box(P.BG2, 10, 10, 4))
	_fleet_strip.add_stylebox_override("focus", StyleBoxEmpty.new())
	_fleet_strip.add_stylebox_override("hover", XatTheme.box(P.BG2.lightened(0.12), 10, 10, 4))
	_fleet_strip.add_stylebox_override("pressed", XatTheme.box(P.BG2.darkened(0.15), 10, 10, 4))
	_fleet_strip.connect("pressed", self, "_on_fleet_pressed")
	var h = HBoxContainer.new()
	h.anchor_right = 1.0
	h.anchor_bottom = 1.0
	h.margin_left = 10
	h.margin_right = -10
	h.alignment = BoxContainer.ALIGN_CENTER
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_constant_override("separation", 8)
	_fleet_strip.add_child(h)
	var t = Label.new()
	t.text = "Flota"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE - 1))
	h.add_child(t)
	_fleet_bar = ProgressBar.new()
	_fleet_bar.percent_visible = false
	_fleet_bar.min_value = 0
	_fleet_bar.max_value = 100
	_fleet_bar.value = 0
	_fleet_bar.rect_min_size = Vector2(72, 8)
	_fleet_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fleet_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_fleet_bar)
	var sp = Label.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	_fleet_fresh = Label.new()
	_fleet_fresh.clip_text = true
	_fleet_fresh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fleet_fresh.add_color_override("font_color", P.TEXT_DIM)
	_fleet_fresh.add_font_override("font", XatTheme.font(P.FONT_MONO, P.FONT_SIZE - 4))
	h.add_child(_fleet_fresh)
	m.add_child(_fleet_strip)
	_rebuild_fleet()
	return m

func _on_fleet_pressed() -> void:
	emit_signal("fleet_requested")

# Recalcula la franja a partir de `_fleet` (mismo formato que fleet_snapshot).
func _rebuild_fleet() -> void:
	if _fleet_strip == null:
		return
	var entities = _fleet.get("entities", [])
	var has = not entities.empty()
	if not has:
		_fleet_bar.visible = false
		_fleet_fresh.text = "sin datos"
		_fleet_fresh.add_color_override("font_color", P.TEXT_DIM)
		_fleet_strip.hint_tooltip = "Configurar la flota"
		return
	var ready := 0
	for e in entities:
		if _fleet_state_key(e) == "ready":
			ready += 1
	var frac = float(ready) / float(entities.size())
	_fleet_bar.visible = true
	_fleet_bar.value = int(round(frac * 100.0))
	var col = P.context_color(frac)
	_fleet_bar.add_stylebox_override("bg", XatTheme.box(P.LINE, 4, 0, 0))
	_fleet_bar.add_stylebox_override("fg", XatTheme.box(col, 4, 0, 0))
	var fresh = fleet_freshness(str(_fleet.get("generated_at", "")), OS.get_unix_time())
	var stale = bool(_fleet.get("stale", false)) or str(_fleet.get("generated_at", "")) == ""
	var head = "STALE" if stale else "LIVE"
	if fresh == "":
		_fleet_fresh.text = "sin hora"
		_fleet_fresh.add_color_override("font_color", P.TEXT_DIM)
	elif stale:
		_fleet_fresh.text = head + " · " + fresh
		_fleet_fresh.add_color_override("font_color", P.PENDING)
	else:
		_fleet_fresh.text = head + " · " + fresh
		_fleet_fresh.add_color_override("font_color", P.OK)

# Clasificación de salud de una instancia (misma semántica que fleet_monitor).
static func _fleet_state_key(p_entity: Dictionary) -> String:
	var lifecycle = str(p_entity.get("lifecycle", "")).to_lower()
	var health = str(p_entity.get("health", p_entity.get("status", ""))).to_lower()
	if lifecycle == "hibernated" or health == "hibernated":
		return "hibernated"
	if health in ["ready", "healthy", "up", "running", "online", "active", "ok"]:
		return "ready"
	if health in ["degraded", "unhealthy"]:
		return "degraded"
	if health in ["down", "failed", "error"]:
		return "down"
	return "unknown"

func _tab_button(p_text: String, p_index: int) -> Button:
	var b = Button.new()
	b.text = p_text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.rect_min_size = Vector2(0, 32)
	b.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE - 1))
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 8))
	b.connect("pressed", self, "_on_tab", [p_index])
	return b

func _on_tab(p_index: int) -> void:
	_set_tab(p_index)

# Cambia la pestaña activa (0 = Contactos, 1 = Salas) y muestra su página.
# La activa se resalta como control segmentado (fondo), no sólo el color de texto.
func _set_tab(p_index: int) -> void:
	_tab = int(clamp(p_index, 0, 1))
	var on = XatTheme.box(P.BG2, 8)
	var off = StyleBoxEmpty.new()
	if _tab_contacts != null:
		_tab_contacts.add_stylebox_override("normal", on if _tab == 0 else off)
		_tab_contacts.add_stylebox_override("pressed", on)
		_tab_contacts.add_color_override("font_color", P.TEXT if _tab == 0 else P.TEXT_DIM)
	if _tab_rooms != null:
		_tab_rooms.add_stylebox_override("normal", on if _tab == 1 else off)
		_tab_rooms.add_stylebox_override("pressed", on)
		_tab_rooms.add_color_override("font_color", P.TEXT if _tab == 1 else P.TEXT_DIM)
	if _columns > 1:
		_rebuild_grid()
		return
	if _scroll != null:
		_scroll.visible = _tab == 0
	if _rooms_scroll != null:
		_rooms_scroll.visible = _tab == 1

func _update_tab_labels() -> void:
	if _tab_contacts != null:
		_tab_contacts.text = ("Contactos (%d)" % _peers.size()) if not _peers.empty() else "Contactos"
	if _tab_rooms != null:
		_tab_rooms.text = ("Salas (%d)" % _rooms.size()) if not _rooms.empty() else "Salas"

# Swipe horizontal (táctil) para cambiar de pestaña: izquierda -> Salas,
# derecha -> Contactos. En la vista multicolumna (landscape) no aplica.
func _active_scroll() -> ScrollContainer:
	if _columns > 1:
		return _grid_scroll
	if _tab == 1:
		return _rooms_scroll
	return _scroll

func _input(p_event) -> void:
	if not visible:
		return
	if p_event is InputEventScreenTouch:
		if p_event.pressed:
			_touch_start = p_event.position
			_touch_active = true
			_swipe_consumed = false
		else:
			_touch_active = false
	elif p_event is InputEventScreenDrag and _touch_active and not _swipe_consumed:
		var dx = p_event.position.x - _touch_start.x
		var dy = p_event.position.y - _touch_start.y
		# Swipe horizontal: cambia de pestaña (sólo con pestañas, no en grid).
		if _columns <= 1 and abs(dx) > 60.0 and abs(dx) > abs(dy) * 1.5:
			_swipe_consumed = true
			_set_tab(1 if dx < 0.0 else 0)
			get_tree().set_input_as_handled()
			return
		# Arrastre vertical: scrollea la lista. Las filas son Buttons y consumen
		# el press, así que el ScrollContainer no recibe el gesto de touch acá.
		var sc = _active_scroll()
		if sc != null and abs(p_event.relative.y) > 0.01:
			sc.scroll_vertical = max(0, sc.scroll_vertical - int(p_event.relative.y))
			get_tree().set_input_as_handled()

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
	_deferred.erase(p_room)
	_invites[p_room] = {"from": p_from, "reason": p_reason}
	_rebuild_requests()
	_rebuild_rooms()

func remove_invite(p_room: String) -> void:
	var had = _invites.has(p_room) or _deferred.has(p_room)
	_invites.erase(p_room)
	_deferred.erase(p_room)
	if had:
		_rebuild_requests()
		_rebuild_rooms()

func _rebuild_requests() -> void:
	for c in _req_box.get_children():
		_req_box.remove_child(c)
		c.queue_free()
	_req_box.visible = not _requests.empty() or not _invites.empty()
	for bare in _requests.keys():
		_req_box.add_child(_make_request_row(str(bare)))
	for room in _invites.keys():
		_req_box.add_child(_make_invite_row(str(room)))

# X2.4: "{nombre} te invita a #{sala}", con el nombre visible del roster y el
# localpart de la sala. Nunca se muestra el JID crudo (ni el recurso).
func _make_invite_row(p_room: String) -> PanelContainer:
	var info = _invites.get(p_room, {})
	var from = str(info.get("from", ""))
	var reason = str(info.get("reason", ""))
	var card = PanelContainer.new()
	card.add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.AGENT_EDGE))
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 4)
	card.add_child(v)
	var l = Label.new()
	l.text = humanize_invite(from, p_room, str(_names.get(jid_bare(from), "")))
	l.clip_text = true
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
	accept.text = "Unirme"
	accept.focus_mode = Control.FOCUS_NONE
	accept.rect_min_size = Vector2(0, 44)
	accept.connect("pressed", self, "_on_invite_accept", [p_room])
	actions.add_child(accept)
	var defer = Button.new()
	defer.text = "Ahora no"
	defer.focus_mode = Control.FOCUS_NONE
	defer.rect_min_size = Vector2(0, 44)
	defer.connect("pressed", self, "_on_invite_defer", [p_room])
	actions.add_child(defer)
	return card

func _on_invite_accept(p_room: String) -> void:
	remove_invite(p_room)
	emit_signal("room_invite_accept", p_room)

# "Ahora no" deja la invitación pendiente en Salas (no la descarta): sale de la
# banda de solicitudes y se ofrece como tarjeta en la pestaña Salas. No emite
# `room_invite_ignore` para que main no borre la invitación pendiente.
func _on_invite_defer(p_room: String) -> void:
	var info = _invites.get(p_room, {})
	_invites.erase(p_room)
	_deferred[p_room] = info
	_rebuild_requests()
	_rebuild_rooms()

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
	b.setup(p_glyph, 44, P.TEXT_DIM, p_tip)
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
	b.setup(p_glyph, 44, P.TEXT_DIM, p_tip)
	b.toggle_mode = true
	if p_glyph == "sound":
		b.set_off_glyph("sound_off")
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
	if _juice != null:
		var n = {"sound_enabled": "Sonido", "haptics_enabled": "Vibración"}.get(p_key, "")
		if n != "":
			_juice.toast("%s %s" % [n, "activado" if p_on else "desactivado"])

func _on_about() -> void:
	OS.shell_open(XatXmpp.PRIVACY_URL)

func _on_avatar() -> void:
	emit_signal("avatar_requested")

func _on_update() -> void:
	emit_signal("update_requested")

func _on_font_smaller() -> void:
	emit_signal("font_scale_requested", -1)

func _on_font_bigger() -> void:
	emit_signal("font_scale_requested", 1)

func set_peers(p_bares: Array) -> void:
	_peers = p_bares
	_update_tab_labels()
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
	# X2.2: los contactos con caps de agente se fijan arriba.
	var aa = _agents.has(a)
	var ab = _agents.has(b)
	if aa != ab:
		return aa
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
	for b in _room_info.keys():
		if not kept.has(b):
			_room_info.erase(b)
	_rebuild_rooms()

# X3.1: metadatos de una sala (sujeto, último mensaje, ocupantes). `info`:
# {subject, last_from, last_body, last_ts, occupants:[{nick, jid, ...}]}.
func set_room_info(p_room: String, p_info: Dictionary) -> void:
	_room_info[p_room] = p_info
	if _rooms.has(p_room) or _deferred.has(p_room):
		_rebuild_rooms()

# X2.4: nombre visible del contacto (roster); humaniza las invitaciones.
func set_display_name(p_bare: String, p_name: String) -> void:
	_names[p_bare] = p_name

# X2.2: último mensaje de un contacto, para la tarjeta de agente.
func set_last_message(p_bare: String, p_from: String, p_body: String, p_ts: String = "") -> void:
	_last_msg[p_bare] = {"from": p_from, "body": p_body, "ts": p_ts}
	if _agents.has(p_bare):
		_rebuild()

# X2.5: resumen del snapshot de flota (mismo formato que fleet_snapshot.parse).
func set_fleet_state(p_fleet: Dictionary) -> void:
	_fleet = p_fleet
	_rebuild_fleet()

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
	var has = not _rooms.empty() or not _deferred.empty()
	_rooms_empty.visible = not has
	_rooms_box.visible = has
	_update_tab_labels()
	if not has:
		return
	# Invitaciones diferidas con "Ahora no": quedan pendientes acá (X2.4).
	for room in _deferred.keys():
		if not _rooms.has(str(room)):
			_rooms_box.add_child(_make_deferred_row(str(room)))
	for b in _sorted_rooms():
		_rooms_box.add_child(_make_room_row(str(b)))

# Tarjeta de invitación pendiente en Salas ("Ahora no"): Unirme o descartar.
func _make_deferred_row(p_room: String) -> PanelContainer:
	var info = _deferred.get(p_room, {})
	var from = str(info.get("from", ""))
	var card = PanelContainer.new()
	card.add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.PENDING))
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 4)
	card.add_child(v)
	var l = Label.new()
	l.text = humanize_invite(from, p_room, str(_names.get(jid_bare(from), "")))
	l.clip_text = true
	v.add_child(l)
	var tag = Label.new()
	tag.text = "invitación pendiente"
	tag.add_color_override("font_color", P.TEXT_DIM)
	tag.add_font_override("font", XatTheme.font(P.FONT_REGULAR, P.FONT_SIZE - 3))
	v.add_child(tag)
	var actions = HBoxContainer.new()
	actions.add_constant_override("separation", 6)
	v.add_child(actions)
	var accept = Button.new()
	accept.text = "Unirme"
	accept.focus_mode = Control.FOCUS_NONE
	accept.rect_min_size = Vector2(0, 44)
	accept.connect("pressed", self, "_on_invite_accept", [p_room])
	actions.add_child(accept)
	var dismiss = Button.new()
	dismiss.text = "Descartar"
	dismiss.focus_mode = Control.FOCUS_NONE
	dismiss.rect_min_size = Vector2(0, 44)
	dismiss.connect("pressed", self, "_on_deferred_dismiss", [p_room])
	actions.add_child(dismiss)
	return card

func _on_deferred_dismiss(p_room: String) -> void:
	_deferred.erase(p_room)
	_rebuild_rooms()

# Alterna entre lista simple (portrait) y multicolumna con scroll lateral
# (landscape). El número de columnas lo decide main según el ancho.
func set_columns(p_n: int) -> void:
	p_n = max(1, p_n)
	if p_n == _columns:
		return
	_columns = p_n
	var grid = _columns > 1
	# Las pestañas siguen visibles también en multicolumna (filtra Contactos/Salas).
	if _tabbar_margin != null:
		_tabbar_margin.visible = true
	if _scroll != null:
		_scroll.visible = (not grid) and _tab == 0
	if _rooms_scroll != null:
		_rooms_scroll.visible = (not grid) and _tab == 1
	if _grid_scroll != null:
		_grid_scroll.visible = grid
	if grid:
		_rebuild_grid()
	else:
		_rebuild()
		_rebuild_rooms()

func _make_room_row(p_room: String) -> Button:
	var info = _room_info.get(p_room, {})
	var rich = not info.empty()
	var row = Button.new()
	row.name = _room_row_name(p_room)
	row.toggle_mode = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	# X3.1: cada sala es una tarjeta.
	row.add_stylebox_override("normal", XatTheme.with_border(XatTheme.box(P.BG2, 10, 8, 6), P.LINE))
	row.add_stylebox_override("focus", StyleBoxEmpty.new())
	row.add_stylebox_override("hover", XatTheme.with_border(XatTheme.box(P.BG2.lightened(0.1), 10, 8, 6), P.LINE))
	row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10, 8, 6), P.AGENT_EDGE))
	row.pressed = p_room == _selected
	row.rect_min_size = Vector2(0, 66 if rich else 54)
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
	# X3.2: el "#" vive en un contenedor de 44 px y queda centrado siempre.
	inner.add_child(_hash_box())
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
	if rich:
		var subj = str(info.get("subject", "")).strip_edges()
		if subj != "":
			var subj_l = Label.new()
			subj_l.text = subj
			subj_l.clip_text = true
			subj_l.add_color_override("font_color", P.TEXT_DIM)
			subj_l.add_font_override("font", XatTheme.font(P.FONT_REGULAR, P.FONT_SIZE - 2))
			v.add_child(subj_l)
		var last = _room_last_line(info)
		if last != "":
			var last_l = Label.new()
			last_l.text = last
			last_l.clip_text = true
			last_l.autowrap = true
			last_l.rect_min_size = Vector2(0, 32) # ~2 líneas
			last_l.add_color_override("font_color", P.TEXT_DIM)
			last_l.add_font_override("font", XatTheme.font(P.FONT_REGULAR, P.FONT_SIZE - 2))
			v.add_child(last_l)
	var st = Label.new()
	st.text = _status_text(p_room)
	st.clip_text = true
	st.add_color_override("font_color", P.TEXT_DIM)
	v.add_child(st)
	row.set_meta("status", st)
	if rich:
		var right = VBoxContainer.new()
		right.alignment = BoxContainer.ALIGN_CENTER
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_constant_override("separation", 2)
		inner.add_child(right)
		var ts = str(info.get("last_ts", ""))
		if ts != "":
			var time_l = Label.new()
			time_l.text = clock_time(ts)
			time_l.align = Label.ALIGN_RIGHT
			time_l.add_color_override("font_color", P.TEXT_DIM)
			time_l.add_font_override("font", XatTheme.font(P.FONT_MONO, P.FONT_SIZE - 4))
			time_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			right.add_child(time_l)
		right.add_child(_occupant_stack(info.get("occupants", [])))
	return row

# "#" centrado dentro de un contenedor de 44 px (X3.2).
func _hash_box() -> Control:
	var c = Control.new()
	c.rect_min_size = Vector2(44, 44)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = Label.new()
	l.text = "#"
	l.anchor_right = 1.0
	l.anchor_bottom = 1.0
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	l.add_color_override("font_color", P.LINE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(l)
	return c

# Remitente + cuerpo del último mensaje de la sala (una línea; el Label envuelve).
func _room_last_line(p_info: Dictionary) -> String:
	var body = str(p_info.get("last_body", "")).strip_edges()
	if body == "":
		return ""
	var from = str(p_info.get("last_from", "")).strip_edges()
	if from == "":
		return body
	return "%s: %s" % [from, body]

# Avatares apilados de ocupantes (máx. 3 + "+N"); orbe para agentes (X3.1).
func _occupant_stack(p_occupants: Array) -> Control:
	var c = Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n = p_occupants.size()
	if n == 0:
		c.rect_min_size = Vector2(0, 0)
		return c
	var shown = int(min(n, 3))
	var step := 16.0
	var side := 26.0
	c.rect_min_size = Vector2(step * float(shown - 1) + side, side)
	for i in range(shown):
		var occ = p_occupants[i]
		var bare = jid_bare(str(occ.get("jid", "")))
		var node
		if bare != "" and _agents.has(bare):
			var orb = AgentOrb.new()
			orb.set_compact(true)
			orb.rect_size = Vector2(48, 48)
			orb.rect_scale = Vector2(side / 48.0, side / 48.0)
			orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			node = orb
		else:
			var badge = AvatarBadge.new(side)
			badge.bare = bare if bare != "" else str(occ.get("nick", ""))
			badge.set_texture(_avatars.get(bare))
			badge.rect_size = Vector2(side, side)
			node = badge
		node.rect_position = Vector2(step * float(i), 0)
		c.add_child(node)
	if n > shown:
		var more = Label.new()
		more.text = "+%d" % (n - shown)
		more.add_color_override("font_color", P.TEXT_DIM)
		more.add_font_override("font", XatTheme.font(P.FONT_REGULAR, P.FONT_SIZE - 4))
		more.rect_position = Vector2(step * float(shown) - 8.0, side * 0.5 - 9.0)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(more)
	return c

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
# Encabezado de sección en la vista multicolumna (Salas / Contactos).
func _grid_header(p_text: String) -> Label:
	var h = Label.new()
	h.text = p_text
	h.add_color_override("font_color", P.TEXT_DIM)
	h.add_font_override("font", XatTheme.font(P.FONT_MEDIUM, P.FONT_SIZE - 2))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.rect_min_size = Vector2(0, 24)
	h.valign = Label.VALIGN_CENTER
	return h

# llenando de izquierda a derecha (orden de lectura) y con scroll lateral.
func _rebuild_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if _rooms_box != null:
		_rooms_box.visible = false
	var items := []
	if _tab == 1:
		for room in _deferred.keys():
			if not _rooms.has(str(room)):
				items.append(_make_deferred_row(str(room)))
		for b in _sorted_rooms():
			items.append(_make_room_row(str(b)))
	else:
		for b in _sorted():
			items.append(_make_row(str(b)))
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
	var is_agent = _agents.has(p_bare)
	var last_body = str(_last_msg.get(p_bare, {}).get("body", "")) if _last_msg.has(p_bare) else ""
	var row = Button.new()
	row.name = _row_name(p_bare)
	row.toggle_mode = true
	row.mouse_filter = Control.MOUSE_FILTER_PASS # el arrastre debe llegar al ScrollContainer
	# X2.2: el contacto con caps de agente es una tarjeta (borde AGENT_EDGE).
	if is_agent:
		row.add_stylebox_override("normal", XatTheme.with_border(XatTheme.box(P.BG2, 10, 8, 6), P.AGENT_EDGE))
		row.add_stylebox_override("hover", XatTheme.with_border(XatTheme.box(P.BG2.lightened(0.1), 10, 8, 6), P.AGENT_EDGE))
		row.add_stylebox_override("focus", StyleBoxEmpty.new())
		row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10, 8, 6), P.LINE))
	else:
		row.add_stylebox_override("normal", StyleBoxEmpty.new())
		row.add_stylebox_override("hover", XatTheme.box(P.BG2.darkened(0.15), 10))
		row.add_stylebox_override("focus", StyleBoxEmpty.new())
		row.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2, 10), P.LINE))
	row.pressed = p_bare == _selected
	row.rect_min_size = Vector2(0, 74 if (is_agent and last_body != "") else 60)
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
	name_l.text = str(_names.get(p_bare, p_bare.split("@")[0]))
	name_l.clip_text = true
	name_l.hint_tooltip = p_bare
	v.add_child(name_l)
	var st = Label.new()
	st.text = _status_text(p_bare)
	st.clip_text = true
	st.add_color_override("font_color", P.activity_color(_agents[p_bare].get("activity", "")) if _agents.has(p_bare) and online else P.TEXT_DIM)
	v.add_child(st)
	row.set_meta("status", st)
	# X2.2: último mensaje en la tarjeta del agente.
	if is_agent and last_body != "":
		var lm = Label.new()
		lm.text = last_body
		lm.clip_text = true
		lm.add_color_override("font_color", P.TEXT_DIM)
		lm.add_font_override("font", XatTheme.font(P.FONT_REGULAR, P.FONT_SIZE - 3))
		v.add_child(lm)
	# X2.3: chips de preguntas rápidas en la tarjeta del agente (hasta 4).
	if is_agent:
		var chips = _agent_chips()
		if not chips.empty():
			v.add_child(_agent_chips_row(p_bare, chips))
			# El Button no crece con sus hijos: reservar alto para los chips.
			row.rect_min_size = Vector2(0, row.rect_min_size.y + chips.size() * 46)
	return row

# X2.3: chips de la tarjeta de agente. Sólo datos del helper puro (defaults +
# settings); se acota a `MAX_QUESTIONS`, conservando el chip `/status`.
func _agent_chips() -> Array:
	var out = QuickQuestions.load_chips()
	if out.size() <= QuickQuestions.MAX_QUESTIONS:
		return out
	var keep := []
	for q in out:
		if str(q) == QuickQuestions.STATUS_VALUE:
			continue
		if keep.size() >= QuickQuestions.MAX_QUESTIONS - 1:
			break
		keep.append(q)
	if QuickQuestions.STATUS_VALUE in out:
		keep.append(QuickQuestions.STATUS_VALUE)
	return keep

func _agent_chips_row(p_bare: String, p_chips: Array) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for q in p_chips:
		var text = str(q)
		if text == "":
			continue
		var b = Button.new()
		b.text = text
		b.clip_text = true
		b.hint_tooltip = text
		b.focus_mode = Control.FOCUS_NONE
		b.rect_min_size = Vector2(0, 44) # toque >= 44 px
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_color_override("font_color", P.TEXT_DIM)
		b.add_color_override("font_color_hover", P.AGENT_EDGE)
		b.add_font_override("font", XatTheme.font(P.FONT_REGULAR, P.FONT_SIZE - 4))
		b.add_stylebox_override("normal", XatTheme.with_border(XatTheme.box(P.BG1, 10, 6, 4), P.LINE))
		b.add_stylebox_override("hover", XatTheme.with_border(XatTheme.box(P.BG2, 10, 6, 4), P.AGENT_EDGE))
		b.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(P.BG2.darkened(0.15), 10, 6, 4), P.AGENT_EDGE))
		b.connect("pressed", self, "_on_quick_chip", [p_bare, text])
		box.add_child(b)
	return box

func _on_quick_chip(p_bare: String, p_text: String) -> void:
	if p_bare == "" or p_text == "":
		return
	emit_signal("quick_question_requested", p_bare, p_text)

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

# --- Helpers puros (X2.4/X2.5) ---
# Se extraen acá para poder testearlos sin instanciar el panel (tests/invite_label_test.gd).

# JID sin recurso ("ana@h/x" -> "ana@h"); "" queda "".
static func jid_bare(p_jid: String) -> String:
	var s = p_jid.strip_edges()
	var slash = s.find("/")
	return s.substr(0, slash) if slash >= 0 else s

# Nick (parte local) del JID, sin recurso ni dominio ("ana@h/x" -> "ana").
static func jid_nick(p_jid: String) -> String:
	var bare = jid_bare(p_jid)
	var at = bare.find("@")
	return bare.substr(0, at) if at >= 0 else bare

# Localpart de la sala ("sala@conference.h" -> "sala"); nunca expone el dominio.
static func room_localpart(p_room: String) -> String:
	return jid_nick(p_room)

# X2.4: texto humano de la invitación. Usa el nombre del roster si lo hay, si no
# el nick del JID; jamás el JID crudo (ni el recurso). Sala = su localpart.
static func humanize_invite(p_from_jid: String, p_room_bare: String, p_roster_name: String = "") -> String:
	var name = p_roster_name.strip_edges()
	if name == "":
		name = jid_nick(p_from_jid)
	if name == "":
		name = "Alguien"
	var room = room_localpart(p_room_bare)
	return "%s te invita a #%s" % [name, room]

# X2.5: antigüedad en lenguaje natural. Negativo -> "hace 0 s" (no inventa).
static func ago_label(p_seconds: int) -> String:
	var s = max(0, p_seconds)
	if s < 60:
		return "hace %d s" % s
	if s < 3600:
		return "hace %d min" % int(s / 60)
	if s < 86400:
		return "hace %d h" % int(s / 3600)
	return "hace %d d" % int(s / 86400)

# X2.5: frescura de un snapshot ("hace 12 s"). "" si no hay hora válida.
static func fleet_freshness(p_generated_at: String, p_now_unix: int) -> String:
	var iso = p_generated_at.strip_edges()
	if iso == "":
		return ""
	var t = Time.get_unix_time_from_datetime_string(iso)
	if t <= 0:
		return ""
	return ago_label(p_now_unix - int(t))

# Hora corta "HH:MM" de un timestamp ISO ("" si no alcanza).
static func clock_time(p_iso: String) -> String:
	return p_iso.substr(11, 5) if p_iso.length() >= 16 else ""

