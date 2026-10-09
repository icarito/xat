extends Control

# Visor de imágenes a pantalla completa.
#
# Cómo cerrar (antes era imposible en Android porque el ColorRect de fondo
# consumía el toque): botón ✕, botón atrás del sistema, Esc, o un toque/click
# en el fondo. Tocar sin arrastrar cierra; doble toque alterna 1x/2.5x.
#
# Zoom: pinza (InputEventMagnifyGesture en Android), rueda (escritorio) y doble
# toque. Con zoom > 1 el arrastre de un dedo desplaza la imagen.

signal closed

const MediaUtil = preload("res://addons/xat_xmpp/ui/media_util.gd")

const MARGIN := 24.0
const MIN_ZOOM := 1.0
const MAX_ZOOM := 6.0
const DOUBLE_MS := 260

var _tex: TextureRect
var _bg: ColorRect
var _hint: Label
var _close: Button
var _tap_timer: Timer

var _tex_w := 0.0
var _tex_h := 0.0
var _zoom := 1.0
var _pan := Vector2.ZERO
var _gesturing := false
var _touches := 0

func _init() -> void:
	visible = false
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0.92)
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_tex = TextureRect.new()
	_tex.expand = true
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tex)

	_hint = Label.new()
	_hint.text = "Tocá para cerrar · pinza para zoom"
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.anchor_right = 1.0
	_hint.margin_top = -34.0
	_hint.margin_bottom = -8.0
	_hint.align = Label.ALIGN_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_color_override("font_color", Color(1, 1, 1, 0.7))
	add_child(_hint)

	_close = Button.new()
	_close.text = "✕"
	_close.focus_mode = Control.FOCUS_NONE
	_close.anchor_left = 1.0
	_close.anchor_right = 1.0
	_close.margin_left = -58.0
	_close.margin_right = -12.0
	_close.margin_top = 12.0
	_close.margin_bottom = 58.0
	_close.mouse_filter = Control.MOUSE_FILTER_STOP
	_close.connect("pressed", self, "close")
	add_child(_close)

	_tap_timer = Timer.new()
	_tap_timer.one_shot = true
	_tap_timer.wait_time = float(DOUBLE_MS) / 1000.0
	_tap_timer.connect("timeout", self, "_close_now")
	add_child(_tap_timer)

	connect("resized", self, "_apply")
	set_process_input(false)

func is_open() -> bool:
	return visible

func open(p_path: String) -> void:
	var tex = MediaUtil.load_texture(p_path)
	if tex == null:
		return
	_tex.texture = tex
	_tex_w = float(tex.get_width())
	_tex_h = float(tex.get_height())
	_zoom = 1.0
	_pan = Vector2.ZERO
	_gesturing = false
	_touches = 0
	visible = true
	set_process_input(true)
	_apply()

func close() -> void:
	if not visible:
		return
	_tap_timer.stop()
	visible = false
	set_process_input(false)
	_tex.texture = null
	_tex.rect_size = Vector2.ZERO
	_tex.rect_position = Vector2.ZERO
	emit_signal("closed")

func _close_now() -> void:
	if not _gesturing:
		close()

# Recoloca la imagen centrada, aplicando zoom y desplazamiento.
func _apply() -> void:
	if _tex_w <= 0.0 or _tex_h <= 0.0:
		return
	var avail = rect_size - Vector2(MARGIN * 2.0, MARGIN * 2.0)
	if avail.x <= 1.0 or avail.y <= 1.0:
		return
	var fit = min(avail.x / _tex_w, avail.y / _tex_h)
	var disp = Vector2(_tex_w, _tex_h) * fit * _zoom
	var max_pan = Vector2(max(0.0, (disp.x - avail.x) * 0.5), max(0.0, (disp.y - avail.y) * 0.5))
	_pan.x = clamp(_pan.x, -max_pan.x, max_pan.x)
	_pan.y = clamp(_pan.y, -max_pan.y, max_pan.y)
	_tex.rect_size = disp
	_tex.rect_position = (rect_size - disp) * 0.5 + _pan

# Cambia el zoom manteniendo el punto p_focus bajo el cursor/dedo.
func _zoom_to(p_zoom: float, p_focus: Vector2) -> void:
	var old = _zoom
	_zoom = clamp(p_zoom, MIN_ZOOM, MAX_ZOOM)
	if _zoom <= MIN_ZOOM + 0.001:
		_zoom = MIN_ZOOM
		_pan = Vector2.ZERO
	else:
		var focus = p_focus - rect_size * 0.5
		_pan = focus - (focus - _pan) * (_zoom / old)
	_apply()

func _input(event) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()
		return
	if event is InputEventMagnifyGesture:
		_gesturing = true
		_zoom_to(_zoom * event.factor, event.position)
		get_tree().set_input_as_handled()
		return
	if event is InputEventPanGesture:
		_gesturing = true
		_pan += event.delta * 12.0
		_apply()
		get_tree().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == BUTTON_WHEEL_UP:
			_zoom_to(_zoom * 1.12, event.position)
			get_tree().set_input_as_handled()
			return
		if event.pressed and event.button_index == BUTTON_WHEEL_DOWN:
			_zoom_to(_zoom / 1.12, event.position)
			get_tree().set_input_as_handled()
			return
		if event.button_index == BUTTON_LEFT and not OS.has_touchscreen_ui_hint():
			# Escritorio: click fuera del botón ✕ cierra.
			if event.pressed and not _close.get_global_rect().has_point(event.position):
				_on_tap()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches += 1
			if _touches == 1:
				_gesturing = false
		else:
			_touches = max(0, _touches - 1)
			if _touches == 0 and not _gesturing:
				_on_tap()
		return
	if event is InputEventScreenDrag:
		if _touches >= 2:
			_gesturing = true
			return
		if _zoom > MIN_ZOOM + 0.001:
			_gesturing = true
			_pan += event.relative
			_apply()
		return

func _on_tap() -> void:
	if not _tap_timer.is_stopped():
		# Segundo toque dentro de la ventana: doble toque = alternar zoom.
		_tap_timer.stop()
		if _zoom > MIN_ZOOM + 0.001:
			_zoom = MIN_ZOOM
			_pan = Vector2.ZERO
			_apply()
		else:
			_zoom_to(2.5, rect_size * 0.5)
	else:
		_tap_timer.start()
