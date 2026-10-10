extends Control

# Forma de onda en vivo de la grabación de voz: buffer circular de amplitudes
# (0..1) que dibuja barras verticales con la misma pluma que el resto de la UI.
# NO inventa datos: si no se le empuja ningún sample queda vacío (regla de
# honestidad de docs/ui.md). Sólo se redibuja cuando se le empuja una muestra o
# cambia el progreso del gesto; nunca por frame (low_processor_mode).

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")

const CAP := 36

var color := Palette.AGENT_EDGE
var cancel_color := Palette.ERROR

var _samples := []
var _lock := 0.0
var _cancel := 0.0

func push(p_sample: float) -> void:
	_samples.append(clamp(p_sample, 0.0, 1.0))
	while _samples.size() > CAP:
		_samples.pop_front()
	update()

func clear() -> void:
	_samples.clear()
	_lock = 0.0
	_cancel = 0.0
	update()

func set_progress(p_lock: float, p_cancel: float) -> void:
	_lock = clamp(p_lock, 0.0, 1.0)
	_cancel = clamp(p_cancel, 0.0, 1.0)
	update()

func _draw() -> void:
	var w = rect_size.x
	var h = rect_size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cy = h * 0.5
	var col = color.linear_interpolate(cancel_color, _cancel)
	# Riel base: señala "acá va la onda" incluso sin muestras.
	draw_line(Vector2(1.0, cy), Vector2(w - 1.0, cy), Color(col.r, col.g, col.b, 0.25), 1.0, true)
	if _samples.empty():
		return
	var step = w / float(CAP)
	var bw = max(2.0, step * 0.55)
	var n = _samples.size()
	# Las muestras se anclan a la derecha (lo más nuevo al lado del temporizador).
	for i in range(n):
		var s = _samples[i]
		var bh = max(2.0, s * (h - 4.0))
		var x = w - (n - i) * step + step * 0.5
		draw_line(Vector2(x, cy - bh * 0.5), Vector2(x, cy + bh * 0.5), col, bw, true)
