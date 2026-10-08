extends Node

# Zoom tipográfico global (Ctrl+scroll / Ctrl++ / Ctrl+- como un navegador).
# Los DynamicFont que crea XatTheme.font() se registran aquí para poder
# redimensionarlos en caliente; el factor se persiste en xat_settings.json.

signal scale_changed(scale)

const DEFAULT := 1.0
const MIN := 0.7
const MAX := 2.4
const STEP := 0.1

var scale := DEFAULT

var _fonts := [] # [[WeakRef(DynamicFont), tamaño_base]]

# Registra una fuente y la ajusta al factor actual. Guarda el tamaño base para
# poder reescalarla después sin perder el diseño original.
func register(p_font: DynamicFont, p_base: int) -> void:
	_prune()
	p_font.size = _size(p_base)
	_fonts.append([weakref(p_font), p_base])

func zoom_in() -> void:
	set_scale(scale + STEP)

func zoom_out() -> void:
	set_scale(scale - STEP)

func reset() -> void:
	set_scale(DEFAULT)

func set_scale(p_scale: float) -> void:
	var s = clamp(p_scale, MIN, MAX)
	if is_equal_approx(s, scale):
		return
	scale = s
	_prune()
	for e in _fonts:
		var f = e[0].get_ref()
		if f != null:
			f.size = _size(e[1])
	emit_signal("scale_changed", scale)

func _size(p_base: int) -> int:
	return int(max(1, int(round(p_base * scale))))

func _prune() -> void:
	var keep := []
	for e in _fonts:
		if e[0].get_ref() != null:
			keep.append(e)
	_fonts = keep
