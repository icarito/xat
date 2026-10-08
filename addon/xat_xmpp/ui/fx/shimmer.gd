extends RichTextEffect

# Banda de luz que barre los caracteres. Para el indicador "pensando…"/"escribiendo…".
# Uso: [shimmer speed=2 width=4 color=#4fd1ff]texto[/shimmer]

var bbcode = "shimmer"

const Palette = preload("res://addons/xat_xmpp/ui/palette.gd")

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var speed = float(char_fx.env.get("speed", 2.0))
	var width = max(float(char_fx.env.get("width", 4.0)), 0.05)
	var col = char_fx.env.get("color", Palette.AGENT_EDGE)
	if typeof(col) == TYPE_STRING:
		col = Color(col)
	# Cabeza de la banda: avanza en el tiempo y cicla cada `width * 8` chars.
	var span = width * 8.0
	var head = fposmod(float(char_fx.elapsed_time) * speed * width, span)
	# Distancia circular del carácter a la cabeza de la banda.
	var d = fposmod(float(char_fx.relative_index) - head + span * 0.5, span) - span * 0.5
	var band = 1.0 - clamp(abs(d) / width, 0.0, 1.0)
	band = band * band
	char_fx.color = char_fx.color.linear_interpolate(col, band)
	return true
