extends Button

# Botón de icono vectorial 2D de contorno (recoloreable). Evita sumar PNGs:
# cada glifo se dibuja con la misma pluma (trazo ~2 px, puntas redondeadas) y se
# tiñe con `icon_color` (TEXT / USER / ERROR / TEXT_DIM). Pensado para el
# composer (adjuntar, emoji, micrófono, enviar, papelera).

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")

var glyph := "mic"
# Glifo alterno para toggles apagados (p. ej. sonido → "sound_off"). Si está
# vacío, el toggle sólo cambia de color al apagarse.
var glyph_off := ""
var icon_color := Palette.TEXT

var _glyph_size := 22.0

func setup(p_glyph: String, p_size: int, p_color: Color, p_tip: String) -> void:
	glyph = p_glyph
	icon_color = p_color
	hint_tooltip = p_tip
	rect_min_size = Vector2(p_size, p_size)
	_glyph_size = float(p_size) * 0.56
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not is_connected("toggled", self, "_on_toggled"):
		connect("toggled", self, "_on_toggled")
	update()

func set_glyph(p_glyph: String) -> void:
	if glyph == p_glyph:
		return
	glyph = p_glyph
	update()

func set_off_glyph(p_glyph: String) -> void:
	glyph_off = p_glyph
	update()

func _on_toggled(_p_pressed: bool) -> void:
	update()

func set_icon_color(p_color: Color) -> void:
	icon_color = p_color
	update()

func _draw() -> void:
	_glyph(active_glyph(), rect_size * 0.5, _glyph_size * 0.5, icon_color)

# Glifo efectivo según el estado del toggle (apagado usa `glyph_off` si existe).
func active_glyph() -> String:
	if toggle_mode and not pressed and glyph_off != "":
		return glyph_off
	return glyph

# Cuerpo del altavoz (compartido por "sound" y "sound_off").
func _speaker(c: Vector2, r: float, col: Color, w: float) -> void:
	draw_polyline(PoolVector2Array([
		c + Vector2(-r * 0.62, -r * 0.28), c + Vector2(-r * 0.28, -r * 0.28),
		c + Vector2(r * 0.02, -r * 0.66), c + Vector2(r * 0.02, r * 0.66),
		c + Vector2(-r * 0.28, r * 0.28), c + Vector2(-r * 0.62, r * 0.28),
		c + Vector2(-r * 0.62, -r * 0.28)]), col, w, true)

# Letra "A" vectorial (dos patas + travesaño), para los botones de tamaño de letra.
func _letter_a(c: Vector2, r: float, col: Color, w: float) -> void:
	var apex = c + Vector2(0, -r * 0.7)
	var lf = c + Vector2(-r * 0.52, r * 0.42)
	var rt = c + Vector2(r * 0.52, r * 0.42)
	draw_line(apex, lf, col, w, true)
	draw_line(apex, rt, col, w, true)
	draw_line(c + Vector2(-r * 0.3, -r * 0.02), c + Vector2(r * 0.3, -r * 0.02), col, w, true)

func _glyph(g: String, c: Vector2, r: float, col: Color) -> void:
	var w = max(1.5, r * 0.2)
	match g:
		"mic":
			var bw = r * 0.4
			draw_circle(c + Vector2(0, -r * 0.35), bw, col)
			draw_circle(c + Vector2(0, r * 0.05), bw, col)
			draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, r * 0.05), col, bw * 2.0, true)
			draw_arc(c + Vector2(0, r * 0.05), r * 0.62, 0.0, PI, 20, col, w, true)
			draw_line(c + Vector2(0, r * 0.67), c + Vector2(0, r * 0.98), col, w, true)
			draw_line(c + Vector2(-r * 0.38, r * 0.98), c + Vector2(r * 0.38, r * 0.98), col, w, true)
		"send":
			draw_polyline(PoolVector2Array([c + Vector2(-r * 0.62, r * 0.15), c + Vector2(0, -r * 0.62), c + Vector2(r * 0.62, r * 0.15)]), col, w, true)
			draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.78), col, w, true)
		"paperclip":
			# Clip diagonal estilizado: cuerpo (dos trazos paralelos) + gancho.
			var a = c + Vector2(-r * 0.5, r * 0.5)
			var b = c + Vector2(r * 0.42, -r * 0.42)
			draw_line(a, b, col, w, true)
			draw_line(a + Vector2(r * 0.34, r * 0.34), b + Vector2(-r * 0.34, r * 0.34), col, w, true)
			draw_arc(c + Vector2(r * 0.5, -r * 0.5), r * 0.34, PI * 0.5, PI * 1.5, 16, col, w, true)
			draw_arc(c + Vector2(-r * 0.5, r * 0.5), r * 0.34, -PI * 0.5, PI * 0.5, 16, col, w, true)
		"plus":
			# Cruz gruesa: la señal universal de "agregar/adjuntar".
			draw_line(c + Vector2(0, -r * 0.62), c + Vector2(0, r * 0.62), col, w * 1.5, true)
			draw_line(c + Vector2(-r * 0.62, 0), c + Vector2(r * 0.62, 0), col, w * 1.5, true)
		"emoji":
			draw_arc(c, r * 0.72, 0.0, TAU, 30, col, w, true)
			draw_circle(c + Vector2(-r * 0.26, -r * 0.18), w * 0.7, col)
			draw_circle(c + Vector2(r * 0.26, -r * 0.18), w * 0.7, col)
			draw_arc(c + Vector2(0, r * 0.05), r * 0.4, 0.15 * PI, 0.85 * PI, 20, col, w, true)
		"trash":
			draw_line(c + Vector2(-r * 0.6, -r * 0.5), c + Vector2(r * 0.6, -r * 0.5), col, w, true)
			draw_line(c + Vector2(-r * 0.25, -r * 0.75), c + Vector2(r * 0.25, -r * 0.75), col, w, true)
			draw_polyline(PoolVector2Array([c + Vector2(-r * 0.45, -r * 0.5), c + Vector2(-r * 0.32, r * 0.75), c + Vector2(r * 0.32, r * 0.75), c + Vector2(r * 0.45, -r * 0.5)]), col, w, true)
			draw_line(c + Vector2(-r * 0.1, -r * 0.25), c + Vector2(-r * 0.1, r * 0.5), col, w * 0.8, true)
			draw_line(c + Vector2(r * 0.1, -r * 0.25), c + Vector2(r * 0.1, r * 0.5), col, w * 0.8, true)
		"lock":
			draw_arc(c + Vector2(0, -r * 0.15), r * 0.4, PI, TAU, 20, col, w, true)
			draw_rect(Rect2(c + Vector2(-r * 0.5, -r * 0.05), Vector2(r, r * 0.8)), col, false, w, true)
		"close":
			draw_line(c + Vector2(-r * 0.5, -r * 0.5), c + Vector2(r * 0.5, r * 0.5), col, w, true)
			draw_line(c + Vector2(-r * 0.5, r * 0.5), c + Vector2(r * 0.5, -r * 0.5), col, w, true)
		"sound":
			_speaker(c, r, col, w)
			draw_arc(c + Vector2(r * 0.08, 0), r * 0.4, -PI * 0.32, PI * 0.32, 14, col, w, true)
			draw_arc(c + Vector2(r * 0.08, 0), r * 0.68, -PI * 0.32, PI * 0.32, 16, col, w, true)
		"sound_off":
			_speaker(c, r, col, w)
			draw_line(c + Vector2(-r * 0.62, -r * 0.62), c + Vector2(r * 0.62, r * 0.62), col, w, true)
		"fleet":
			# Red de nodos: flota de agentes monitoreada por pubsub.
			var n0 = c + Vector2(0, -r * 0.66)
			var n1 = c + Vector2(-r * 0.62, r * 0.5)
			var n2 = c + Vector2(r * 0.62, r * 0.5)
			draw_line(n0, c, col, w * 0.8, true)
			draw_line(n1, c, col, w * 0.8, true)
			draw_line(n2, c, col, w * 0.8, true)
			draw_circle(n0, r * 0.2, col)
			draw_circle(n1, r * 0.2, col)
			draw_circle(n2, r * 0.2, col)
			draw_circle(c, r * 0.24, col)
		"brain":
			# Dos hemisferios con surco central y circunvoluciones.
			draw_arc(c + Vector2(-r * 0.32, 0), r * 0.5, 0.0, TAU, 26, col, w, true)
			draw_arc(c + Vector2(r * 0.32, 0), r * 0.5, 0.0, TAU, 26, col, w, true)
			draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), col, w * 0.8, true)
			draw_arc(c + Vector2(-r * 0.32, 0), r * 0.22, PI * 0.2, PI * 1.5, 12, col, w * 0.7, true)
			draw_arc(c + Vector2(r * 0.32, 0), r * 0.22, -PI * 0.5, PI * 0.8, 12, col, w * 0.7, true)
		"vibrate":
			draw_rect(Rect2(c + Vector2(-r * 0.32, -r * 0.68), Vector2(r * 0.64, r * 1.36)), col, false, w, true)
			draw_line(c + Vector2(-r * 0.55, -r * 0.42), c + Vector2(-r * 0.74, -r * 0.18), col, w, true)
			draw_line(c + Vector2(-r * 0.55, r * 0.42), c + Vector2(-r * 0.74, r * 0.18), col, w, true)
			draw_line(c + Vector2(r * 0.55, -r * 0.42), c + Vector2(r * 0.74, -r * 0.18), col, w, true)
			draw_line(c + Vector2(r * 0.55, r * 0.42), c + Vector2(r * 0.74, r * 0.18), col, w, true)
		"info":
			draw_arc(c, r * 0.76, 0.0, TAU, 32, col, w, true)
			draw_circle(c + Vector2(0, -r * 0.34), w * 0.75, col)
			draw_line(c + Vector2(0, -r * 0.02), c + Vector2(0, r * 0.42), col, w, true)
		"person":
			draw_arc(c + Vector2(0, -r * 0.32), r * 0.34, 0.0, TAU, 24, col, w, true)
			draw_arc(c + Vector2(0, r * 0.92), r * 0.82, PI + 0.4, TAU - 0.4, 24, col, w, true)
		"download":
			draw_line(c + Vector2(0, -r * 0.72), c + Vector2(0, r * 0.2), col, w, true)
			draw_polyline(PoolVector2Array([c + Vector2(-r * 0.36, -r * 0.12), c + Vector2(0, r * 0.26), c + Vector2(r * 0.36, -r * 0.12)]), col, w, true)
			draw_line(c + Vector2(-r * 0.5, r * 0.62), c + Vector2(r * 0.5, r * 0.62), col, w, true)
		"text_plus":
			# Letra "A" + signo +: agrandar la letra.
			_letter_a(c + Vector2(-r * 0.18, 0), r, col, w)
			draw_line(c + Vector2(r * 0.5, -r * 0.62), c + Vector2(r * 0.5, -r * 0.06), col, w, true)
			draw_line(c + Vector2(r * 0.22, -r * 0.34), c + Vector2(r * 0.78, -r * 0.34), col, w, true)
		"text_minus":
			# Letra "A" + signo −: achicar la letra.
			_letter_a(c + Vector2(-r * 0.18, 0), r, col, w)
			draw_line(c + Vector2(r * 0.22, -r * 0.34), c + Vector2(r * 0.78, -r * 0.34), col, w, true)
		"play":
			draw_polyline(PoolVector2Array([
				c + Vector2(-r * 0.45, -r * 0.6), c + Vector2(r * 0.62, 0),
				c + Vector2(-r * 0.45, r * 0.6), c + Vector2(-r * 0.45, -r * 0.6)]), col, w, true)
		"pause":
			draw_line(c + Vector2(-r * 0.28, -r * 0.55), c + Vector2(-r * 0.28, r * 0.55), col, w * 1.6, true)
			draw_line(c + Vector2(r * 0.28, -r * 0.55), c + Vector2(r * 0.28, r * 0.55), col, w * 1.6, true)
		"person_add":
			draw_arc(c + Vector2(-r * 0.22, -r * 0.32), r * 0.32, 0.0, TAU, 22, col, w, true)
			draw_arc(c + Vector2(-r * 0.22, r * 0.95), r * 0.78, PI + 0.42, TAU - 0.42, 22, col, w, true)
			draw_line(c + Vector2(r * 0.64, -r * 0.62), c + Vector2(r * 0.64, r * 0.02), col, w, true)
			draw_line(c + Vector2(r * 0.32, -r * 0.3), c + Vector2(r * 0.96, -r * 0.3), col, w, true)
		"hash":
			draw_line(c + Vector2(-r * 0.34, -r * 0.72), c + Vector2(-r * 0.14, r * 0.72), col, w, true)
			draw_line(c + Vector2(r * 0.14, -r * 0.72), c + Vector2(r * 0.34, r * 0.72), col, w, true)
			draw_line(c + Vector2(-r * 0.7, -r * 0.18), c + Vector2(r * 0.7, -r * 0.32), col, w, true)
			draw_line(c + Vector2(-r * 0.7, r * 0.32), c + Vector2(r * 0.7, r * 0.18), col, w, true)
