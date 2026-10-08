extends PanelContainer

# Card inline de una tool en curso/terminada: punto de estado + nombre (mono) +
# estado + duración (Timer 1 s, sin _process) y detalle plegable (clic).

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const Shimmer = preload("res://addons/xat_xmpp/ui/fx/shimmer.gd")

var tool_name := ""
var state := "running"  # running | ok | err
var _t0 := 0
var _elapsed := 0
var _icon: Control
var _name: Label
var _status: RichTextLabel
var _dur: Label
var _detail: Label
var _timer: Timer
var _anim: Timer  # fuerza redibujo del shimmer (low_processor_mode lo congela)

func _init() -> void:
	size_flags_horizontal = 0
	var s = XatTheme.box(Palette.BG1, Palette.RADIUS_SMALL + 4, 12, 8)
	s.border_color = Palette.TOOL
	s.border_width_left = 3
	add_stylebox_override("panel", s)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 4)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 8)
	_icon = Control.new()
	_icon.rect_min_size = Vector2(14, 14)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.connect("draw", self, "_draw_icon")
	h.add_child(_icon)
	_name = Label.new()
	_name.add_font_override("font", XatTheme.font(Palette.FONT_MONO, Palette.FONT_SIZE - 1))
	h.add_child(_name)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content_height = true
	_status.scroll_active = false
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.custom_effects = [Shimmer.new()]
	_status.rect_min_size.x = 84
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.add_color_override("default_color", Palette.TEXT_DIM)
	_status.add_font_override("normal_font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 2))
	h.add_child(_status)
	_dur = Label.new()
	_dur.add_color_override("font_color", Palette.TEXT_DIM)
	_dur.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 3))
	h.add_child(_dur)
	v.add_child(h)
	_detail = Label.new()
	_detail.autowrap = true
	_detail.visible = false
	_detail.rect_min_size.x = 220
	_detail.add_color_override("font_color", Palette.TEXT_DIM)
	_detail.add_font_override("font", XatTheme.font(Palette.FONT_MONO, Palette.FONT_SIZE - 3))
	v.add_child(_detail)
	add_child(v)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.connect("timeout", self, "_tick")
	add_child(_timer)
	_anim = Timer.new()
	_anim.wait_time = 0.05
	_anim.connect("timeout", _status, "update")
	add_child(_anim)
	connect("gui_input", self, "_on_input")

func start(p_name: String, p_detail: String = "") -> void:
	tool_name = p_name
	_name.text = p_name
	state = "running"
	_t0 = OS.get_ticks_msec()
	_elapsed = 0
	set_detail(p_detail)
	_show_state()
	_timer.autostart = true
	_anim.autostart = true
	if is_inside_tree():
		_timer.start()
		_anim.start()

func finish(p_ok: bool = true) -> void:
	if state != "running":
		return
	_elapsed = OS.get_ticks_msec() - _t0
	state = "ok" if p_ok else "err"
	_timer.stop()
	_anim.stop()
	_show_state()

func set_detail(p_text: String) -> void:
	_detail.text = p_text
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if p_text != "" else Control.CURSOR_ARROW
	if p_text == "":
		_detail.visible = false

func _show_state() -> void:
	match state:
		"running":
			_status.bbcode_text = "[shimmer color=#a78bff speed=2 width=3]ejecutando…[/shimmer]"
		"ok":
			_status.bbcode_text = "listo"
		_:
			_status.bbcode_text = "[color=#%s]error[/color]" % Palette.ERROR.to_html(false)
	_tick()
	_icon.update()

func _tick() -> void:
	if state == "running":
		_elapsed = OS.get_ticks_msec() - _t0
	_dur.text = "%ds" % (_elapsed / 1000) if _elapsed >= 1000 else ("<1s" if state != "running" else "")

func _on_input(p_ev: InputEvent) -> void:
	if p_ev is InputEventMouseButton and p_ev.pressed and p_ev.button_index == BUTTON_LEFT and _detail.text != "":
		_detail.visible = not _detail.visible

func _draw_icon() -> void:
	var c = Vector2(7, 7)
	match state:
		"running":
			_icon.draw_circle(c, 4, Palette.TOOL)
		"ok":
			_icon.draw_polyline(PoolVector2Array([Vector2(1, 8), Vector2(5, 12), Vector2(13, 2)]), Palette.OK, 2.0, true)
		_:
			_icon.draw_line(Vector2(2, 2), Vector2(12, 12), Palette.ERROR, 2.0, true)
			_icon.draw_line(Vector2(12, 2), Vector2(2, 12), Palette.ERROR, 2.0, true)
