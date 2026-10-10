extends Control

# Onda estática para el reproductor de audio embebido: dibuja una onda (o un
# riel si no hay datos), la parte reproducida en color de acento y el resto
# atenuado, con el marcador de posición. No anima por sí sola: la burbuja le
# empuja el progreso desde el player global (low_processor_mode friendly).

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")

const BARS := 28

var color := Palette.AGENT_EDGE
var base_color := Palette.LINE

var _frac := 0.0
# Amplitudes 0..1 deterministas por posición (barra estática, no datos reales:
# es un riel decorativo honesto, no pretende representar el audio).
var _amps := []

func _init() -> void:
	for i in range(BARS):
		# Perfil suave y reproducible (seno + variación por índice) para que
		# todas las burbujas de audio se vean parejas.
		var t = float(i) / float(BARS - 1)
		_amps.append(0.35 + 0.5 * abs(sin(t * PI * 3.0)) * (0.6 + 0.4 * cos(t * PI)))

func set_progress(p_frac: float) -> void:
	_frac = clamp(p_frac, 0.0, 1.0)
	update()

func _draw() -> void:
	var w = rect_size.x
	var h = rect_size.y
	if w <= 0.0 or h <= 0.0:
		return
	var cy = h * 0.5
	var step = w / float(BARS)
	var bw = max(1.5, step * 0.5)
	var played_x = w * _frac
	for i in range(BARS):
		var a = _amps[i]
		var bh = max(2.0, a * (h - 4.0))
		var x = i * step + step * 0.5
		var col = color if x <= played_x else base_color
		draw_line(Vector2(x, cy - bh * 0.5), Vector2(x, cy + bh * 0.5), col, bw, true)