extends PanelContainer

# Card de aprobación inline bajo la burbuja del agente: botones grandes (quick
# responses primero, comandos secundarios), anillo de cuenta regresiva si el
# hook trae expiresAtMs, y sello al decidir/expirar. Timer 1 s, sin _process.

signal decided(kind, value)  # kind: "quick" | "command"

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const GLOW = preload("res://addons/xat_xmpp/ui/fx/bubble_glow.shader")

var msg_id := ""
var sealed := false
var row: HBoxContainer  # botones (quick + comandos)
var _title: Label
var _cmd: Label
var _stamp: Label
var _ring: Control
var _timer: Timer
var _glow: Timer  # redibujo ~20 Hz del pulso mientras está pendiente
var _font: Font
var _expires_ms := 0.0
var _total_ms := 0.0
var _tw: Tween

func _init() -> void:
	size_flags_horizontal = 0
	_font = XatTheme.font(Palette.FONT_MEDIUM, Palette.FONT_SIZE - 5)
	var pend = Palette.PENDING
	add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(Palette.BG1, Palette.RADIUS, 14, 12), Color(pend.r, pend.g, pend.b, 0.5)))
	var m = ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_param("glow_color", Palette.PENDING)
	m.set_shader_param("strength", 0.22)
	m.set_shader_param("width", 0.05)
	m.set_shader_param("pulse_speed", 3.0)
	material = m
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 10)
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 10)
	_ring = Control.new()
	_ring.rect_min_size = Vector2(30, 30)
	_ring.visible = false
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.connect("draw", self, "_draw_ring")
	top.add_child(_ring)
	var t = VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Label.new()
	_title.text = "¿Aprobar?"
	_title.add_font_override("font", XatTheme.font(Palette.FONT_BOLD))
	t.add_child(_title)
	_cmd = Label.new()
	_cmd.visible = false
	_cmd.autowrap = true
	_cmd.rect_min_size.x = 200
	_cmd.add_color_override("font_color", Palette.TEXT_DIM)
	_cmd.add_font_override("font", XatTheme.font(Palette.FONT_MONO, Palette.FONT_SIZE - 3))
	t.add_child(_cmd)
	top.add_child(t)
	v.add_child(top)
	row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	v.add_child(row)
	_stamp = Label.new()
	_stamp.visible = false
	_stamp.add_font_override("font", XatTheme.font(Palette.FONT_BOLD))
	v.add_child(_stamp)
	add_child(v)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.connect("timeout", self, "_tick")
	add_child(_timer)
	_glow = Timer.new()
	_glow.wait_time = 0.05
	_glow.autostart = true
	_glow.connect("timeout", self, "update")
	add_child(_glow)
	_tw = Tween.new()
	add_child(_tw)

func set_actions(p_rec: Dictionary) -> void:
	msg_id = str(p_rec.get("id", ""))
	# El gateway puede anunciar la misma aprobación a la vez como quick responses
	# (XEP-0439) y como items de comando (disco#items): deduplicar por etiqueta
	# para no mostrar botones dobles ("permitir una vez / denegar" x2).
	var seen := {}
	for q in p_rec.get("quick_responses", []):
		var value = str(q.get("value", ""))
		var label = str(q.get("label", value))
		if seen.has(_key(label)):
			continue
		seen[_key(label)] = true
		var b = _button(label, true)
		b.connect("pressed", self, "_on_pressed", ["quick", value, b.text])
		row.add_child(b)
	for item in p_rec.get("commands", []):
		var name = str(item.get("name", item.get("node", "acción")))
		if seen.has(_key(name)):
			continue
		seen[_key(name)] = true
		var b = _button(name, false)
		b.hint_tooltip = str(item.get("node", ""))
		b.connect("pressed", self, "_on_pressed", ["command", item, name])
		row.add_child(b)

static func _key(p_text: String) -> String:
	return p_text.strip_edges().to_lower()

func _button(p_text: String, p_primary: bool) -> Button:
	var b = Button.new()
	b.text = p_text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.rect_min_size = Vector2(64, 40)
	var col = Palette.USER if p_primary else Palette.BG2
	var edge = Palette.USER.lightened(0.2) if p_primary else Palette.LINE
	b.add_stylebox_override("normal", XatTheme.with_border(XatTheme.box(col, 20, 14, 6), edge))
	b.add_stylebox_override("hover", XatTheme.with_border(XatTheme.box(col.lightened(0.15), 20, 14, 6), Palette.AGENT_EDGE))
	b.add_stylebox_override("pressed", XatTheme.with_border(XatTheme.box(col.darkened(0.2), 20, 14, 6), Palette.AGENT_EDGE))
	b.add_font_override("font", XatTheme.font(Palette.FONT_MEDIUM))
	return b

# Hook de aprobación (OpenClaw): sólo aporta expiración, comando y estado.
func set_hook(p_hook: Dictionary) -> void:
	var st = str(p_hook.get("state", ""))
	if st != "" and st != "pending":
		seal_from_hook(p_hook)
		return
	if sealed:
		return
	var cmd = p_hook.get("command", null)
	if cmd != null and str(cmd) != "":
		_cmd.text = str(cmd)
		_cmd.visible = true
	var expiry = p_hook.get("expiresAtMs", null)
	if expiry != null and float(expiry) > 0.0:
		_expires_ms = float(expiry)
		if _total_ms <= 0.0:
			_total_ms = max(_expires_ms - _now_ms(), 1000.0)
		_ring.visible = true
		_timer.autostart = true
		if is_inside_tree():
			_timer.start()
		_ring.update()

func seal_from_hook(p_hook: Dictionary) -> void:
	var st = str(p_hook.get("state", ""))
	var dec = str(p_hook.get("decision", "")).to_lower()
	match st:
		"resolved":
			if dec.begins_with("allow") or dec.begins_with("approve"):
				seal("Aprobado", Palette.OK)
			elif dec.begins_with("deny") or dec.begins_with("reject"):
				seal("Rechazado", Palette.ERROR)
			else:
				seal("Resuelto", Palette.TEXT_DIM)
		"expired":
			seal("Expirado", Palette.TEXT_DIM)
		"canceled":
			seal("Cancelado", Palette.TEXT_DIM)
		"failed":
			seal("Falló", Palette.ERROR)

# Cierra la card: sin botones ni glow, con sello y pop de escala.
func seal(p_text: String, p_color: Color) -> void:
	if sealed:
		return
	sealed = true
	_timer.stop()
	_glow.stop()
	material = null
	_ring.visible = false
	row.queue_free()
	_title.visible = false
	_stamp.text = p_text
	_stamp.add_color_override("font_color", p_color)
	_stamp.visible = true
	_stamp.rect_pivot_offset = Vector2(0, 10)
	_tw.interpolate_property(_stamp, "rect_scale", Vector2(1.5, 1.5), Vector2(1, 1), 0.2, Tween.TRANS_BACK, Tween.EASE_OUT)
	_tw.start()
	var c = Palette.LINE
	add_stylebox_override("panel", XatTheme.with_border(XatTheme.box(Palette.BG1, Palette.RADIUS, 14, 8), c))

func _on_pressed(p_kind: String, p_value, p_label: String) -> void:
	if sealed:
		return
	var lv = str(p_value).to_lower()
	if p_kind == "quick" and lv in ["si", "sí", "yes", "ok", "allow", "approve", "aprobar"]:
		seal("Aprobado", Palette.OK)
	elif p_kind == "quick" and lv in ["no", "deny", "reject", "rechazar"]:
		seal("Rechazado", Palette.ERROR)
	else:
		seal(p_label, Palette.TEXT)
	emit_signal("decided", p_kind, p_value)

static func _now_ms() -> float:
	return float(OS.get_unix_time()) * 1000.0

func _tick() -> void:
	if _expires_ms - _now_ms() <= 0.0 and not sealed:
		seal("Expirado", Palette.TEXT_DIM)
		return
	_ring.update()

func _draw_ring() -> void:
	var left = max(_expires_ms - _now_ms(), 0.0)
	var frac = clamp(left / max(_total_ms, 1.0), 0.0, 1.0)
	var col = Palette.ERROR if left < 10000.0 else Palette.PENDING
	var c = _ring.rect_size / 2
	_ring.draw_arc(c, 13, 0, TAU, 32, Palette.LINE, 3.0, true)
	if frac > 0.0:
		_ring.draw_arc(c, 13, -PI / 2, -PI / 2 + TAU * frac, 32, col, 3.0, true)
	var s = str(int(ceil(left / 1000.0)))
	_ring.draw_string(_font, c + Vector2(-_font.get_string_size(s).x / 2, _font.get_ascent() / 2 - 1), s, col)
