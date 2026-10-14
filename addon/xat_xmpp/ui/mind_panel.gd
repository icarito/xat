extends PanelContainer

# Panel "mente" del agente: orbe + telemetría real + chips de comandos.
# Sólo muestra lo que llegó por protocolo (ver docs/ui.md, "Honestidad").

signal command_requested(node)
signal back_requested() # vista de un panel (móvil): volver al chat

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const Orb = preload("res://addons/xat_xmpp/ui/agent_orb.gd")
const SmoothScroll = preload("res://addons/xat_xmpp/ui/smooth_scroll.gd")
# Chips en DOS filas con semántica: seguros (consulta, sin efectos) y de
# mantenimiento (mutan la sesión). Ver docs/ui.md. abort/new piden confirmación.
const CHIPS_SAFE := [["status", P.TEXT], ["context", P.TEXT], ["model", P.TEXT]]
const CHIPS_MAINT := [["compact", P.OK], ["new", P.TEXT], ["abort", P.ERROR]]
const CONFIRM_MS := 3000
const MAX_NOTES := 3
const MAX_EVENTS := 5

var _orb
var _back: Button
var _name: Label
var _model: Label
var _grid: GridContainer
var _badge: Label
var _notes: VBoxContainer
var _timeline: VBoxContainer
var _tl_title: Label
var _events := [] # últimos hooks con significado: {ts, event, label, color}
var _armed := {} # comando -> expira_ms para confirmaciones de doble toque
var _brain: Button
var _brain_url := ""
var _scroll: ScrollContainer
var _smooth = SmoothScroll.new()
var _tween: Tween

func _init():
	rect_min_size = Vector2(260, 0)
	add_stylebox_override("panel", _box(P.BG1, 0, 12))
	var root := VBoxContainer.new()
	root.add_constant_override("separation", 0)
	add_child(root)
	# La info (orbe + telemetría) scrollea con arrastre táctil; los chips quedan
	# fijos abajo para tenerlos siempre a mano. Los hijos no capturan el arrastre
	# (IGNORE) para que llegue al ScrollContainer; el orbe sólo lo propaga (PASS).
	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.mouse_filter = Control.MOUSE_FILTER_STOP
	sc.connect("gui_input", self, "_on_scroll_input")
	_scroll = sc
	_smooth.setup(sc)
	root.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_constant_override("separation", 8)
	sc.add_child(v)
	# Atrás: sólo cuando el panel ocupa toda la pantalla (vista de un panel).
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	_back = Button.new()
	_back.text = "←"
	_back.flat = true
	_back.visible = false
	_back.focus_mode = Control.FOCUS_NONE
	_back.rect_min_size = Vector2(44, 44)
	_back.connect("pressed", self, "emit_signal", ["back_requested"])
	bar.add_child(_back)
	# Cerebro (fleet-wiki) del agente, si la proyección declara un brain-url https.
	# Hook: main.gd debe llamar set_brain_url(FleetSnapshot.brain_url(...)).
	_brain = Button.new()
	_brain.text = "Brain"
	_brain.flat = true
	_brain.visible = false
	_brain.focus_mode = Control.FOCUS_NONE
	_brain.rect_min_size = Vector2(64, 44)
	_brain.connect("pressed", self, "_on_brain")
	bar.add_child(_brain)
	_orb = Orb.new()
	_orb.mouse_filter = Control.MOUSE_FILTER_PASS
	_orb.connect("clicked", self, "emit_signal", ["command_requested", "status"])
	v.add_child(_orb)
	_notes = VBoxContainer.new()
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notes.add_constant_override("separation", 4)
	v.add_child(_notes)
	_name = _label("", P.TEXT, P.FONT_BOLD, 15)
	_name.align = Label.ALIGN_CENTER
	_name.clip_text = true
	v.add_child(_name)
	_model = _label("", P.TEXT_DIM, P.FONT_MONO, 12)
	_model.align = Label.ALIGN_CENTER
	_model.clip_text = true
	v.add_child(_model)
	_badge = _label("", P.BG0, P.FONT_BOLD, 12)
	_badge.size_flags_horizontal = SIZE_SHRINK_CENTER
	_badge.add_stylebox_override("normal", _box(P.PENDING, 10, 3))
	_badge.visible = false
	v.add_child(_badge)
	_grid = GridContainer.new()
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.columns = 2
	_grid.add_constant_override("hseparation", 10)
	_grid.add_constant_override("vseparation", 4)
	v.add_child(_grid)
	# Línea de tiempo: últimos hooks con significado (activity/progress/error).
	_tl_title = _label("Actividad reciente", P.TEXT_DIM, P.FONT_REGULAR, 11)
	_tl_title.visible = false
	v.add_child(_tl_title)
	_timeline = VBoxContainer.new()
	_timeline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timeline.add_constant_override("separation", 2)
	_timeline.visible = false
	v.add_child(_timeline)
	# Chips de comandos en DOS filas: seguros (consulta) y mantenimiento
	# (mutan la sesión; new/abort piden confirmación por doble toque).
	var chips := VBoxContainer.new()
	chips.add_constant_override("separation", 6)
	root.add_child(chips)
	_add_chip_row(chips, CHIPS_SAFE, 0)
	_add_chip_row(chips, CHIPS_MAINT, CONFIRM_MS)
	_tween = Tween.new()
	add_child(_tween)
	set_state({})

func _ready() -> void:
	set_process(false) # el integrador de scroll se activa on-demand

func _process(p_delta: float) -> void:
	if not _smooth.process(p_delta):
		set_process(false)

# Rueda/trackpad sobre el panel: scroll suave (ver smooth_scroll.gd).
func _on_scroll_input(p_event) -> void:
	var dy = SmoothScroll.wheel_delta(p_event)
	if is_zero_approx(dy):
		return
	if _scroll == null:
		return
	get_tree().set_input_as_handled()
	_smooth.kick(dy)
	set_process(true)

func set_agent(p_bare: String) -> void:
	_name.text = p_bare.split("@")[0]
	_name.hint_tooltip = p_bare

func set_connected(p_connected: bool) -> void:
	_orb.set_connected(p_connected)

func set_back_visible(p_visible: bool) -> void:
	_back.visible = p_visible

func set_state(p_state: Dictionary) -> void:
	_orb.set_state(p_state)
	var model := str(p_state.get("model", ""))
	_model.text = model.split("/")[-1]
	_model.visible = model != ""
	var rows := []
	var ctx = p_state.get("context", {})
	if ctx is Dictionary and float(ctx.get("max", 0)) > 0:
		var u := float(ctx.get("used", 0))
		rows.append(["Contexto", "%s / %s (%d%%)" % [fmt_n(u), fmt_n(float(ctx["max"])), int(round(u / float(ctx["max"]) * 100.0))], P.TEXT])
	var tk = p_state.get("tokens", {})
	if tk is Dictionary and not tk.empty():
		rows.append(["Tokens", "in %s · out %s" % [fmt_n(float(tk.get("input", 0))), fmt_n(float(tk.get("output", 0)))], P.TEXT])
	var costs := []
	var pricing_known := p_state.has("model_pricing") or p_state.has("pricing")
	for k in [["session_cost", "sesión"], ["day_cost", "hoy"]]:
		var c = p_state.get(k[0], {})
		if c is Dictionary and (c.has("usd") or not c.empty()):
			costs.append("%s %s" % [fmt_cost(c.get("usd", null), pricing_known), k[1]])
	if not costs.empty():
		rows.append(["Costo", PoolStringArray(costs).join(" · "), P.TEXT])
	var ss := str(p_state.get("session_status", ""))
	if ss != "":
		rows.append(["Sesión", ss, P.TEXT])
	if not rows.empty() or model != "":
		var t := str(p_state.get("tool", ""))
		rows.append(["Tool", t if t != "" else "ninguna", P.TOOL if t != "" else P.TEXT_DIM])
	_fill(rows)
	var n := 0
	var now := OS.get_unix_time() * 1000
	var ap = p_state.get("approvals", {})
	if ap is Dictionary:
		for a in ap.values():
			var ex = a.get("expiresAtMs")
			if str(a.get("state", "")) == "pending" and not (ex != null and int(ex) > 0 and int(ex) <= now):
				n += 1
	_badge.visible = n > 0
	_badge.text = "%d aprobación%s pendiente%s" % [n, "" if n == 1 else "es", "" if n == 1 else "s"]

func _fill(p_rows: Array) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	if p_rows.empty():
		_grid.columns = 1
		_grid.add_child(_label("sin telemetría", P.TEXT_DIM, P.FONT_REGULAR, 13))
		_settle_scale()
		return
	_grid.columns = 2
	for r in p_rows:
		_grid.add_child(_label(r[0], P.TEXT_DIM, P.FONT_REGULAR, 12))
		var l := _label(r[1], r[2], P.FONT_REGULAR, 13)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		l.autowrap = true
		l.rect_min_size.x = 120
		_grid.add_child(l)
	_settle_scale()

# Escala la geometría de la telemetría recién creada al factor de zoom vigente.
func _settle_scale() -> void:
	var fz = _font_zoom()
	if fz != null:
		fz.settle(self)

# Nota diegética bajo el orbe: aparece, se mantiene ~4 s y se desvanece.
func show_note(p_text: String) -> void:
	while _notes.get_child_count() >= MAX_NOTES:
		var o = _notes.get_child(0)
		_notes.remove_child(o)
		o.queue_free()
	var l := _label(p_text, P.TEXT, P.FONT_REGULAR, 13)
	l.align = Label.ALIGN_CENTER
	l.autowrap = true
	l.add_stylebox_override("normal", _box(P.BG2, 10, 6, P.AGENT_EDGE))
	l.modulate.a = 0.0
	_notes.add_child(l)
	_tween.interpolate_property(l, "modulate:a", 0.0, 1.0, 0.25)
	_tween.interpolate_property(l, "modulate:a", 1.0, 0.0, 0.6, Tween.TRANS_LINEAR, Tween.EASE_IN, 4.0)
	_tween.start()
	get_tree().create_timer(4.7).connect("timeout", self, "_drop", [l])

func _drop(p_l) -> void:
	if is_instance_valid(p_l) and p_l.get_parent() == _notes:
		_notes.remove_child(p_l)
		p_l.queue_free()

# 12.0k / 131k / 1.2M
static func fmt_n(p_n: float) -> String:
	if p_n >= 1000000.0:
		return "%.1fM" % (p_n / 1000000.0)
	if p_n >= 100000.0:
		return "%dk" % int(round(p_n / 1000.0))
	if p_n >= 1000.0:
		return "%.1fk" % (p_n / 1000.0)
	return str(int(p_n))

# Costo honesto: nunca "$0.0000". Ausente o 0 -> "sin tarifa"; si el modelo no
# publica precio, la etiqueta lo aclara. Valor real -> formato USD.
static func fmt_cost(p_usd, p_pricing_known := true) -> String:
	var v = _cost_value(p_usd)
	if v == null or v <= 0.0:
		return "sin tarifa" if p_pricing_known else "sin tarifa (el modelo no publica precio)"
	if v < 0.00005:
		return "<$0.0001"
	return "$%.4f" % v

# float del valor si es numérico; null si ausente/no parseable.
static func _cost_value(p_usd):
	if p_usd == null:
		return null
	if p_usd is int or p_usd is float:
		return float(p_usd)
	if p_usd is String and p_usd.is_valid_float():
		return float(p_usd)
	return null

# Hooks con significado (activity/progress/error) para la línea de tiempo.
# Hook pendiente de cablear desde main.gd (ver AGENTS/follow-up).
func record_hook(p_hook: Dictionary) -> void:
	var ev := str(p_hook.get("event", ""))
	if not (ev in ["activity", "progress", "error"]):
		return
	_events.append(_event_row(p_hook))
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
	_render_timeline()

func _event_row(p_hook: Dictionary) -> Dictionary:
	var ev := str(p_hook.get("event", ""))
	var detail := str(p_hook.get("detail", p_hook.get("state", p_hook.get("message", ""))))
	var color := P.TEXT_DIM
	var text := ""
	match ev:
		"activity":
			color = P.activity_color(str(p_hook.get("state", "")))
			text = "actividad · %s" % (str(p_hook.get("state", "")) if detail == "" else detail)
		"progress":
			color = P.PROCESSING
			text = "progreso · %s" % (detail if detail != "" else str(p_hook.get("state", "")))
		"error":
			color = P.ERROR
			text = "error · %s" % (detail if detail != "" else "sin detalle")
	var ts := int(p_hook.get("at", p_hook.get("timestamp", p_hook.get("ts", 0))))
	if ts <= 0:
		ts = OS.get_unix_time() * 1000
	return {"ts": ts, "text": text, "color": color}

func _render_timeline() -> void:
	for c in _timeline.get_children():
		_timeline.remove_child(c)
		c.queue_free()
	var show := not _events.empty()
	_tl_title.visible = show
	_timeline.visible = show
	if not show:
		return
	for e in _events:
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_constant_override("separation", 6)
		h.add_child(_label(_clock(int(e["ts"])), P.TEXT_DIM, P.FONT_MONO, 11))
		var l := _label(str(e["text"]), e["color"], P.FONT_REGULAR, 12)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
		_timeline.add_child(h)
	_settle_scale()

func _clock(p_ms: int) -> String:
	var t = OS.get_time()
	# La hora del hook no viene con zona; usamos la hora local del equipo.
	if p_ms > 0:
		var secs := int(p_ms / 1000)
		if secs > 0:
			var d = OS.get_datetime_from_unix_time(secs)
			return "%02d:%02d" % [int(d.hour), int(d.minute)]
	return "%02d:%02d" % [int(t.hour), int(t.minute)]

func set_brain_url(p_url: String) -> void:
	var ok := p_url.begins_with("https://")
	_brain_url = p_url if ok else ""
	_brain.visible = ok
	_brain.hint_tooltip = p_url if ok else ""

func _on_brain() -> void:
	if _brain_url != "":
		OS.shell_open(_brain_url)

func _add_chip_row(p_parent: Node, p_chips: Array, p_confirm_ms: int) -> void:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 6)
	p_parent.add_child(h)
	for c in p_chips:
		h.add_child(_chip(c[0], c[1], p_confirm_ms))

func _chip(p_node: String, p_tint: Color, p_confirm_ms := 0) -> Button:
	var b := Button.new()
	b.text = p_node
	b.focus_mode = Control.FOCUS_NONE
	b.rect_min_size = Vector2(0, 44)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_color_override("font_color", p_tint)
	b.add_color_override("font_color_hover", p_tint.lightened(0.3))
	b.add_stylebox_override("normal", _box(P.BG2, 12, 5, p_tint.linear_interpolate(P.LINE, 0.7)))
	b.add_stylebox_override("hover", _box(P.LINE, 12, 5, p_tint))
	b.add_stylebox_override("pressed", _box(P.BG0, 12, 5, p_tint))
	if p_confirm_ms > 0:
		b.connect("pressed", self, "_on_chip_press", [p_node, p_confirm_ms])
	else:
		b.connect("pressed", self, "emit_signal", ["command_requested", p_node])
	return b

# Comandos destructivos: primer toque arma y avisa; segundo dentro de la ventana
# (p_confirm_ms) ejecuta. Nada se emite sin confirmación real del usuario.
func _on_chip_press(p_node: String, p_confirm_ms: int) -> void:
	var now := OS.get_unix_time() * 1000
	var until := int(_armed.get(p_node, 0))
	if now < until:
		_armed.erase(p_node)
		emit_signal("command_requested", p_node)
		return
	_armed[p_node] = now + p_confirm_ms
	show_note(_confirm_note(p_node))

func _confirm_note(p_node: String) -> String:
	match p_node:
		"abort":
			return "Toca de nuevo para abortar"
		"new":
			return "Toca de nuevo para iniciar una sesión nueva"
	return "Toca de nuevo para confirmar"

func _label(p_text: String, p_color: Color, p_font: String, p_size: int) -> Label:
	var l := Label.new()
	l.text = p_text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE # deja pasar el arrastre al ScrollContainer
	l.add_color_override("font_color", p_color)
	if ResourceLoader.exists(p_font):
		var f := DynamicFont.new()
		f.font_data = load(p_font)
		f.size = p_size
		# Registro en el zoom global: sin esto las etiquetas de la vista mente
		# no se reescalaban al cambiar el zoom (a diferencia de XatTheme.font).
		var fz = _font_zoom()
		if fz != null:
			fz.register(f, p_size)
		l.add_font_override("font", f)
	return l

static func _font_zoom():
	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		var root = loop.get_root()
		if root != null:
			return root.get_node_or_null("FontZoom")
	return null

func _box(p_bg: Color, p_radius: int, p_pad: int, p_border = null) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = p_bg
	s.set_corner_radius_all(p_radius)
	s.set_default_margin(MARGIN_LEFT, p_pad + 4 if p_radius > 0 else p_pad)
	s.set_default_margin(MARGIN_RIGHT, p_pad + 4 if p_radius > 0 else p_pad)
	s.set_default_margin(MARGIN_TOP, p_pad if p_radius > 0 else p_pad)
	s.set_default_margin(MARGIN_BOTTOM, p_pad)
	if p_border != null:
		s.set_border_width_all(1)
		s.border_color = p_border
	return s
