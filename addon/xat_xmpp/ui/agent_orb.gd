extends Control

# Orbe 3D del agente + anillo de contexto. Ver docs/ui.md ("Orbe").
# Viewport propio (esfera con orb.shader); en GLES3 bloom por WorldEnvironment,
# en GLES2 halo falso. Sólo anima por TIME del shader + unos uniforms.

signal clicked

const P = preload("res://addons/xat_xmpp/ui/palette.gd")
const ORB_SHADER = preload("res://addons/xat_xmpp/ui/fx/orb.shader")
const TRANS := 0.4

var _compact := false
var _connected := true
var _state := {}
var _focused := true
var _gles3 := OS.get_current_video_driver() != OS.VIDEO_DRIVER_GLES2

# Valores animados (los mueve el Tween; los setters empujan uniforms).
var col := P.ASLEEP setget _set_col
var energy := 0.3 setget _set_energy
var spin := 0.1 setget _set_spin
var crack := 0.0 setget _set_crack
var pulse := 0.15 setget _set_pulse
var frac := 0.0 setget _set_frac
var sat_k := 0.0 setget _set_sat_k
var ring_a := 1.0 setget _set_ring_a

var _vp: Viewport
var _tex: TextureRect
var _halo: ColorRect
var _mat: ShaderMaterial
var _sat: MeshInstance
var _sat_mat: ShaderMaterial
var _pivot: Spatial
var _label: Label
var _tween: Tween
var _timer: Timer
var _transition := false
var _rate := -1.0
var _last_ms := 0
var _pressing := false
var _press_pos := Vector2.ZERO

func _init():
	rect_min_size = Vector2(200, 224)
	_vp = Viewport.new()
	_vp.size = Vector2(256, 256)
	_vp.own_world = true
	_vp.transparent_bg = true
	_vp.render_target_v_flip = true
	_vp.render_target_update_mode = Viewport.UPDATE_DISABLED # lo dispara _tick (UPDATE_ONCE)
	if _gles3:
		_vp.msaa = Viewport.MSAA_4X
		_vp.hdr = true
	add_child(_vp)

	var cam := Camera.new()
	cam.projection = Camera.PROJECTION_ORTHOGONAL
	cam.size = 2.5
	cam.translation = Vector3(0, 0, 4)
	_vp.add_child(cam)

	if _gles3:
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.glow_enabled = true
		for l in [1, 3, 5]:
			env.set("glow_levels/%d" % l, true)
		env.glow_intensity = 0.5
		env.glow_bloom = 0.1
		env.glow_hdr_threshold = 1.1
		var we := WorldEnvironment.new()
		we.environment = env
		_vp.add_child(we)

	_mat = ShaderMaterial.new()
	_mat.shader = ORB_SHADER
	var sm := SphereMesh.new()
	sm.radial_segments = 32
	sm.rings = 16
	var core := MeshInstance.new()
	core.mesh = sm
	core.material_override = _mat
	_vp.add_child(core)

	# Satélite de tool: esfera chica emisiva en una órbita inclinada.
	_pivot = Spatial.new()
	_pivot.rotation_degrees = Vector3(70, 0, 0) # órbita casi de frente: nunca queda tras el núcleo
	_vp.add_child(_pivot)
	var ssm := SphereMesh.new()
	ssm.radius = 0.14
	ssm.height = 0.28
	ssm.radial_segments = 16
	ssm.rings = 8
	_sat_mat = ShaderMaterial.new()
	var ss := Shader.new()
	ss.code = "shader_type spatial;\nrender_mode unshaded;\nuniform vec4 c : hint_color;\nuniform float k = 0.0;\nvoid fragment(){ float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0); ALBEDO = c.rgb * (1.0 + 1.5 * f) + vec3(0.25) * f; ALPHA = k; }"
	_sat_mat.shader = ss
	_sat_mat.set_shader_param("c", P.TOOL)
	_sat = MeshInstance.new()
	_sat.mesh = ssm
	_sat.material_override = _sat_mat
	_sat.translation = Vector3(1.15, 0, 0)
	_sat.visible = false
	_pivot.add_child(_sat)

	if true:
		_halo = ColorRect.new()
		_halo.mouse_filter = MOUSE_FILTER_IGNORE
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform vec4 c : hint_color;\nvoid fragment(){ float d = length(UV - vec2(0.5)) * 2.0; COLOR = vec4(c.rgb, c.a * smoothstep(1.0, 0.45, d)); }"
		var hm := ShaderMaterial.new()
		hm.shader = sh
		_halo.material = hm
		add_child(_halo)

	_tex = TextureRect.new()
	_tex.mouse_filter = MOUSE_FILTER_IGNORE
	_tex.expand = true
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.texture = _vp.get_texture()
	add_child(_tex)

	_label = Label.new()
	_label.align = Label.ALIGN_CENTER
	_label.valign = Label.VALIGN_CENTER
	_label.add_color_override("font_color", P.TOOL)
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	_label.clip_text = true
	_label.modulate.a = 0.0
	add_child(_label)

	_tween = Tween.new()
	add_child(_tween)
	_tween.connect("tween_all_completed", self, "_on_tween_done")
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.connect("timeout", self, "_tick")
	add_child(_timer)

func _ready():
	connect("gui_input", self, "_on_gui_input")
	_layout()
	_apply(true)
	_retune(true)

func set_compact(p_compact: bool) -> void:
	_compact = p_compact
	rect_min_size = Vector2(48, 48) if p_compact else Vector2(200, 224)
	_vp.size = Vector2(96, 96) if p_compact else Vector2(256, 256)
	_retune(true)
	_label.visible = not p_compact
	_layout()
	update()

func set_connected(p_connected: bool) -> void:
	_connected = p_connected
	_apply()

func set_state(p_state: Dictionary) -> void:
	_state = p_state
	_apply()

# Estado -> valores objetivo; todo se interpola ~0.4 s, sin saltos.
func _apply(p_now := false) -> void:
	var act := str(_state.get("activity", ""))
	var tool_name := str(_state.get("tool", ""))
	var c: Color = P.activity_color(act)
	var e := 0.3
	var s := 0.1
	var pl := 0.15
	match act:
		"available":
			e = 0.8; s = 0.25; pl = 0.5
		"processing", "busy":
			e = 1.5; s = 1.2; pl = 0.3
		"pending":
			e = 1.1; s = 0.4; pl = 1.0
	if not _connected:
		c = Color.from_hsv(c.h, c.s * 0.15, c.v * 0.7)
		e = 0.3; s = 0.05; pl = 0.0
	var ctx: Dictionary = _state.get("context", {}) if _state.get("context") is Dictionary else {}
	var mx := float(ctx.get("max", 0))
	var f := clamp(float(ctx.get("used", 0)) / mx, 0.0, 1.0) if mx > 0.0 else 0.0
	var has_tool := tool_name != "" and _connected
	if tool_name != "":
		_label.text = tool_name
	_label.add_color_override("font_color", P.TOOL)
	# fuera del árbol no hay Tween que valga: aplica directo (y _ready reaplica)
	p_now = p_now or not is_inside_tree()
	if not p_now:
		_tween.stop_all()
		_transition = true
	var tg := {"col": c, "energy": e, "spin": s, "pulse": pl, "crack": 1.0 if not _connected else 0.0,
		"frac": f, "sat_k": 1.0 if has_tool else 0.0, "ring_a": 0.35 if not _connected else 1.0}
	for k in tg:
		if p_now:
			set(k, tg[k])
		else:
			_tween.interpolate_property(self, k, get(k), tg[k], TRANS, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	if p_now:
		_label.modulate.a = 1.0 if has_tool else 0.0
		_on_tween_done()
		return
	_tween.interpolate_property(_label, "modulate:a", _label.modulate.a, 1.0 if has_tool else 0.0, TRANS)
	_tween.start()
	_retune() # transición a tasa activa

func _asleep() -> bool:
	var act := str(_state.get("activity", ""))
	return act == "" or act == "paused"

# Presupuesto (low_processor_mode): cada UPDATE_ONCE cuesta ~2 frames dibujados
# (render + reset del modo), así que 15 ticks/s activos = ~30 fps de app. El viewport se renderiza por UPDATE_ONCE a
# una tasa según estado; dormido/desconectado = 1 frame y el timer se detiene.
func _target_rate() -> float:
	var act := str(_state.get("activity", ""))
	var busy: bool = act in ["processing", "busy", "pending"] or (sat_k > 0.01 and _connected)
	var r := 0.0
	if _transition:
		r = 15.0
	elif not _connected or _asleep():
		r = 0.0
	elif busy:
		r = 15.0
	else:
		r = 5.0
	if _compact:
		r *= 0.5
	if not _focused:
		r = 0.0 if r == 0.0 or (_asleep() and not _transition) else min(r, 3.0)
	return r

func _retune(p_force := false) -> void:
	if not is_inside_tree():
		return
	var r := _target_rate()
	if r == _rate and not p_force:
		return
	_rate = r
	_vp.render_target_update_mode = Viewport.UPDATE_ONCE # al menos un frame con el valor final
	_last_ms = OS.get_ticks_msec()
	if r <= 0.0:
		_timer.stop()
	else:
		_arm()

# Re-arma en la rejilla global de 1/15 s: todos los orbes disparan a la vez
# y comparten frame de pantalla (si no, N orbes = N veces los fps).
func _arm() -> void:
	var step := 66667.0 * max(1, int(round(15.0 / _rate)))
	var now := float(OS.get_ticks_usec())
	_timer.start(max(0.002, (ceil(now / step) * step - now) / 1000000.0))

func _tick() -> void:
	if _rate > 0.0:
		_arm()
	if not is_visible_in_tree():
		return
	var now := OS.get_ticks_msec()
	if sat_k > 0.01:
		_pivot.rotation.y += (now - _last_ms) * 0.001 * (1.6 + energy)
	_last_ms = now
	_vp.render_target_update_mode = Viewport.UPDATE_ONCE

func _on_tween_done() -> void:
	_transition = false
	_retune()
	_vp.render_target_update_mode = Viewport.UPDATE_ONCE

func _notification(what):
	match what:
		NOTIFICATION_WM_FOCUS_OUT:
			_focused = false
			_retune()
		NOTIFICATION_WM_FOCUS_IN:
			_focused = true
			_retune()
		NOTIFICATION_RESIZED:
			if _label:
				_layout()

func _square() -> Rect2:
	var lh := 0.0 if _compact else 22.0
	var side := min(rect_size.x, rect_size.y - lh)
	return Rect2(Vector2((rect_size.x - side) * 0.5, 0), Vector2(side, side))

func _layout() -> void:
	var r := _square()
	_tex.rect_position = r.position
	_tex.rect_size = r.size
	if _halo:
		var g := r.grow(-r.size.x * 0.02)
		_halo.rect_position = g.position
		_halo.rect_size = g.size
	_label.rect_position = Vector2(0, r.size.y)
	_label.rect_size = Vector2(rect_size.x, 22)
	update()

func _draw() -> void:
	var r := _square()
	var w := 2.0 if _compact else 4.0
	var rad := r.size.x * 0.5 - w
	var ctr := r.position + r.size * 0.5
	var bg := P.LINE
	draw_arc(ctr, rad, 0, TAU, 96, bg, w, true)
	if frac > 0.001:
		# desconectado: arco tenue gris, no semáforo
		var fg: Color = P.context_color(frac) if _connected else P.ASLEEP
		fg.a = ring_a
		draw_arc(ctr, rad, -PI * 0.5, -PI * 0.5 + TAU * frac, 96, fg, w, true)

# Emite "clicked" en el soltar y sólo si no fue un arrastre (así el orbe puede
# convivir con el scroll táctil del contenedor: PASS + umbral de movimiento).
func _on_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
		if ev.pressed:
			_pressing = true
			_press_pos = ev.position
		elif _pressing:
			_pressing = false
			if ev.position.distance_to(_press_pos) < 8.0:
				emit_signal("clicked")

# --- setters de valores animados ---
func _set_col(v: Color) -> void:
	col = v
	if _mat:
		_mat.set_shader_param("core_color", v)
		_mat.set_shader_param("rim_color", v.lightened(0.45))
	if _halo:
		var hc := v
		hc.a = 0.85 * clamp(energy, 0.25, 1.2)
		_halo.material.set_shader_param("c", hc)

func _set_energy(v: float) -> void:
	energy = v
	if _mat:
		_mat.set_shader_param("energy", v)
	if _halo:
		_set_col(col)

func _set_spin(v: float) -> void:
	spin = v
	if _mat:
		_mat.set_shader_param("spin", v)

func _set_crack(v: float) -> void:
	crack = v
	if _mat:
		_mat.set_shader_param("crack", v)

func _set_pulse(v: float) -> void:
	pulse = v
	if _mat:
		_mat.set_shader_param("pulse", v)

func _set_frac(v: float) -> void:
	frac = v
	update()

func _set_ring_a(v: float) -> void:
	ring_a = v
	update()

func _set_sat_k(v: float) -> void:
	sat_k = v
	if _sat:
		_sat.visible = v > 0.01
		_sat_mat.set_shader_param("k", v)
