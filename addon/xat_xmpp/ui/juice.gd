extends Node

# Juice: sonido, partículas, pop/shake y háptica, con ajustes persistentes.
# Una sola instancia bajo main (sin autoload). Ver docs/ui.md: animar sólo
# ante eventos con significado.

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")
const XatTheme = preload("res://addons/xat_xmpp/ui/xat_theme.gd")
const POOL := 4
const THROTTLE_MS := 80

var settings_path := "user://xat_settings.json"
var settings := {"sound_enabled": true, "motion_enabled": true, "haptics_enabled": true, "volume_db": -8.0, "font_scale": 1.0, "roster_hidden": false, "mind_hidden": false}

var _streams := {}
var _last := {}
var _players := []
var _next := 0
var _layer: CanvasLayer
var _tex: ImageTexture
var _silent_cached = null

# Detecta corridas sin salida de audio (tests headless): --no-window, o
# XAT_SILENT. Sin esto los SFX del juice suenan durante tools/run_tests.sh
# (el binario del fork usa SDL2 y no respeta AUDIODRIVER=Dummy).
func _silent() -> bool:
	if _silent_cached == null:
		var args = OS.get_cmdline_args()
		_silent_cached = args.has("--no-window") or args.has("--headless") or OS.get_environment("XAT_SILENT") == "1"
	return bool(_silent_cached)

func _ready():
	load_settings()
	for i in range(POOL):
		var p = AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_layer = CanvasLayer.new()
	_layer.layer = 10
	add_child(_layer)

# --- ajustes ---

func load_settings():
	var f = File.new()
	if f.open(settings_path, File.READ) != OK:
		return
	var d = parse_json(f.get_as_text())
	f.close()
	if typeof(d) == TYPE_DICTIONARY:
		for k in settings:
			if d.has(k) and typeof(d[k]) == typeof(settings[k]):
				settings[k] = d[k]

func set_setting(key: String, value):
	if not settings.has(key):
		return
	settings[key] = value
	var f = File.new()
	if f.open(settings_path, File.WRITE) == OK:
		f.store_string(to_json(settings))
		f.close()

# --- sonido ---

# Sin editor no hay import: se parsea el WAV a mano (chunks "fmt " y "data").
static func load_wav(path: String) -> AudioStreamSample:
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return null
	var b = f.get_buffer(f.get_len())
	f.close()
	if b.size() < 12 or b.subarray(0, 3).get_string_from_ascii() != "RIFF":
		return null
	var s = AudioStreamSample.new()
	s.format = AudioStreamSample.FORMAT_16_BITS
	var pos = 12
	var got_fmt = false
	while pos + 8 <= b.size():
		var id = b.subarray(pos, pos + 3).get_string_from_ascii()
		var n = b[pos + 4] | (b[pos + 5] << 8) | (b[pos + 6] << 16) | (b[pos + 7] << 24)
		var body = pos + 8
		if id == "fmt ":
			s.stereo = (b[body + 2] | (b[body + 3] << 8)) == 2
			s.mix_rate = b[body + 4] | (b[body + 5] << 8) | (b[body + 6] << 16) | (b[body + 7] << 24)
			got_fmt = true
		elif id == "data" and got_fmt:
			s.data = b.subarray(body, min(body + n, b.size()) - 1)
			return s
		pos = body + n + (n & 1)
	return null

func play(sfx: String):
	if _silent() or not settings["sound_enabled"] or _players.empty():
		return
	var now = OS.get_ticks_msec()
	if now - _last.get(sfx, -THROTTLE_MS) < THROTTLE_MS:
		return
	if not _streams.has(sfx):
		_streams[sfx] = load_wav("res://sfx/%s.wav" % sfx)
	if _streams[sfx] == null:
		return
	_last[sfx] = now
	var p = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sfx]
	p.volume_db = settings["volume_db"]
	p.play()

# Aviso transitorio arriba de la ventana (errores de media, cámara, etc.).
func toast(p_text: String, p_color: Color = Palette.TEXT) -> void:
	if _layer == null or p_text == "":
		return
	var pc = PanelContainer.new()
	pc.anchor_left = 0.0
	pc.anchor_right = 1.0
	pc.margin_left = 48
	pc.margin_right = -48
	pc.margin_top = 16
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.82)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(p_color.r, p_color.g, p_color.b, 0.5)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	pc.add_stylebox_override("panel", sb)
	var l = Label.new()
	l.text = p_text
	l.align = Label.ALIGN_CENTER
	l.autowrap = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_color_override("font_color", p_color)
	l.add_font_override("font", XatTheme.font(Palette.FONT_REGULAR, Palette.FONT_SIZE - 1))
	pc.add_child(l)
	_layer.add_child(pc)
	var t = Tween.new()
	_layer.add_child(t)
	t.interpolate_property(pc, "modulate:a", 1.0, 0.0, 0.6, Tween.TRANS_SINE, Tween.EASE_IN, 2.4)
	t.connect("tween_all_completed", pc, "queue_free")
	t.connect("tween_all_completed", t, "queue_free")
	t.start()

# --- movimiento ---

func burst(at_global_pos: Vector2, color: Color = Palette.AGENT_EDGE, amount := 14):
	if not settings["motion_enabled"] or _layer == null:
		return
	var c = CPUParticles2D.new()
	c.texture = _soft_tex()
	c.one_shot = true
	c.explosiveness = 1.0
	c.amount = amount
	c.lifetime = 0.5
	c.spread = 180.0
	c.initial_velocity = 120.0
	c.initial_velocity_random = 0.5
	c.gravity = Vector2(0, 160)
	c.scale_amount = 0.5
	c.scale_amount_random = 0.4
	c.color = color
	var g = Gradient.new()
	g.colors = PoolColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PoolRealArray([0.3, 1.0])
	c.color_ramp = g
	c.position = at_global_pos
	_layer.add_child(c)
	c.emitting = true
	get_tree().create_timer(c.lifetime + 0.2).connect("timeout", c, "queue_free")

func pop(control: Control, scale := 1.08):
	if not settings["motion_enabled"] or not is_instance_valid(control):
		return
	control.rect_pivot_offset = control.rect_size / 2
	var t = _tween()
	t.interpolate_property(control, "rect_scale", Vector2.ONE, Vector2(scale, scale), 0.08, Tween.TRANS_QUAD, Tween.EASE_OUT)
	t.interpolate_property(control, "rect_scale", Vector2(scale, scale), Vector2.ONE, 0.18, Tween.TRANS_BACK, Tween.EASE_OUT, 0.08)
	t.start()

func shake(control: Control, px := 4.0):
	if not settings["motion_enabled"] or not is_instance_valid(control):
		return
	var x0 = control.rect_position.x
	var t = _tween()
	var step = 0.25 / 6.0
	for i in range(6):
		var to = x0 + (px if i % 2 == 0 else -px) * (1.0 - i / 6.0)
		t.interpolate_property(control, "rect_position:x", null, to, step, Tween.TRANS_SINE, Tween.EASE_IN_OUT, i * step)
	t.interpolate_property(control, "rect_position:x", null, x0, step, Tween.TRANS_SINE, Tween.EASE_OUT, 6 * step)
	t.start()

# Patrones hápticos: pulsos [débil, fuerte, ms] separados por HAPTIC_GAP ms.
# Móvil: vibrador (sólo duración). Escritorio: rumble de los gamepads conectados.
const HAPTIC_GAP := 70
const HAPTICS := {
	"tick": [[0.3, 0.0, 18]],                      # enviar, tool
	"receive": [[0.5, 0.0, 30]],                   # llega un mensaje
	"alert": [[0.2, 0.7, 60], [0.2, 0.7, 60]],     # aprobación pendiente
	"success": [[0.3, 0.0, 30], [0.6, 0.4, 60]],   # aprobado / compact
	"error": [[0.0, 1.0, 90], [0.0, 1.0, 90]],     # fallo de auth
}

func haptic(kind := "tick") -> void:
	if not settings.get("haptics_enabled", true) or not HAPTICS.has(kind):
		return
	var mobile = OS.get_name() in ["Android", "iOS"]
	var pads = Input.get_connected_joypads()
	if not mobile and pads.empty():
		return
	for pulse in HAPTICS[kind]:
		if mobile:
			# En Godot 3 la vibración está en Input, no en OS.
			Input.vibrate_handheld(int(pulse[2]))
		for dev in pads:
			Input.start_joy_vibration(dev, pulse[0], pulse[1], pulse[2] / 1000.0)
		yield(get_tree().create_timer((pulse[2] + HAPTIC_GAP) / 1000.0), "timeout")

func _tween() -> Tween:
	var t = Tween.new()
	add_child(t)
	t.connect("tween_all_completed", t, "queue_free")
	return t

# Disco suave con caída radial de alfa (no hay GradientTexture2D en Godot 3).
func _soft_tex() -> ImageTexture:
	if _tex == null:
		var n = 16
		var img = Image.new()
		img.create(n, n, false, Image.FORMAT_RGBA8)
		img.lock()
		for y in range(n):
			for x in range(n):
				var d = Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
				img.set_pixel(x, y, Color(1, 1, 1, clamp(1.0 - d, 0.0, 1.0)))
		img.unlock()
		_tex = ImageTexture.new()
		_tex.create_from_image(img)
	return _tex
