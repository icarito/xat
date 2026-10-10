extends Reference

# Integrador de scroll suave con inercia para un ScrollContainer.
#
# Godot 3 mueve page/8 por muesca (saltos bruscos en pantallas grandes). Acá la
# rueda/pan empuja una velocidad y un _process externo la integra con fricción
# exponencial hasta detenerse: sensación "full smooth".
#
# El dueño (un Control) debe llamar `process(delta)` desde su _process y
# `kick(dy)` desde su manejo de input. Es puro respecto al árbol: sólo toca el
# ScrollContainer que se le pasa.

const WHEEL_STEP := 72.0          # px de impulso por muesca
const FRICTION := 14.0           # amortiguación por segundo (mayor = frena antes)
const MAX_SPEED := 4200.0
const DEFAULT_GAIN := 12.0       # impulso -> velocidad

var _scroll: ScrollContainer
var _vel := 0.0
var _active := false

func setup(p_scroll: ScrollContainer) -> void:
	_scroll = p_scroll

func is_active() -> bool:
	return _active

# Empuja velocidad a partir de un desplazamiento de rueda/pan (dy en px).
func kick(p_dy: float, p_gain: float = DEFAULT_GAIN) -> void:
	if _scroll == null or not is_instance_valid(_scroll):
		return
	_vel = clamp(_vel + p_dy * p_gain, -MAX_SPEED, MAX_SPEED)
	_active = true

# Detiene la inercia (p. ej. al empezar un arrastre táctil).
func cancel() -> void:
	_vel = 0.0
	_active = false

# Avanza el scroll. Devuelve true si sigue activo (el dueño debe seguir
# procesando); false cuando ya se detuvo.
func process(p_delta: float) -> bool:
	if not _active or _scroll == null or not is_instance_valid(_scroll):
		_active = false
		return false
	var sb = _scroll.get_v_scrollbar()
	var lo := 0.0
	var hi := float(max(0.0, sb.max_value - sb.page))
	var v = clamp(_scroll.scroll_vertical + _vel * p_delta, lo, hi)
	_scroll.scroll_vertical = int(round(v))
	if (v <= lo and _vel < 0.0) or (v >= hi and _vel > 0.0):
		_vel = 0.0
	else:
		_vel = lerp(0.0, _vel, exp(-FRICTION * p_delta))
	if abs(_vel) < 1.0:
		_vel = 0.0
		_active = false
		return false
	return true

# Interpreta un evento de rueda/pan y devuelve el impulso (0 si no aplica).
static func wheel_delta(p_event) -> float:
	if p_event is InputEventMouseButton:
		if not p_event.pressed:
			return 0.0
		if p_event.button_index == BUTTON_WHEEL_UP:
			return -WHEEL_STEP * p_event.factor
		if p_event.button_index == BUTTON_WHEEL_DOWN:
			return WHEEL_STEP * p_event.factor
		return 0.0
	if p_event is InputEventPanGesture:
		return p_event.delta.y * WHEEL_STEP * 6.0
	return 0.0