extends Control

# Avatar circular (XEP-0084) con anillo de estado; sin imagen, un círculo con
# la inicial y color estable por JID. Anillo: presencia (personas) o actividad
# (agentes); apagado si offline.

const P = preload("res://addons/xat_xmpp/ui/palette.gd")

# Recorte circular. Ojo: smoothstep con los bordes invertidos es comportamiento
# indefinido en GLSL y en GPUs móviles (GLES2) da alfa 0 -> avatar invisible.
# Usar los bordes en orden y restar de 1.
const MASK := """
shader_type canvas_item;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.a *= 1.0 - smoothstep(0.46, 0.5, length(UV - vec2(0.5)));
	COLOR = c;
}
"""

var bare := ""
var ring := Color(0, 0, 0, 0)
var _pic: TextureRect

func _init(p_size: float = 48.0) -> void:
	rect_min_size = Vector2(p_size, p_size)
	size_flags_vertical = SIZE_SHRINK_CENTER
	mouse_filter = MOUSE_FILTER_IGNORE
	_pic = TextureRect.new()
	_pic.expand = true
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.anchor_right = 1.0
	_pic.anchor_bottom = 1.0
	var inset = max(3.0, p_size * 0.08)
	_pic.margin_left = inset
	_pic.margin_top = inset
	_pic.margin_right = -inset
	_pic.margin_bottom = -inset
	_pic.mouse_filter = MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = MASK
	var mat = ShaderMaterial.new()
	mat.shader = sh
	_pic.material = mat
	add_child(_pic)

func set_texture(p_tex) -> void:
	_pic.texture = p_tex
	update()

func set_ring(p_color: Color) -> void:
	ring = p_color
	update()

func _draw() -> void:
	var ctr = rect_size / 2.0
	var r = rect_size.y / 2.0
	if _pic.texture == null:
		var col = Color.from_hsv(float(bare.hash() % 360) / 360.0, 0.45, 0.75)
		draw_circle(ctr, r * 0.84, col)
		var font = get_font("font", "Label")
		var ch = bare.substr(0, 1).to_upper()
		var sz = font.get_string_size(ch)
		draw_string(font, ctr - Vector2(sz.x / 2.0, -font.get_ascent() / 2.0 + 2), ch, P.BG0)
	if ring.a > 0.0:
		draw_arc(ctr, r - 1.5, 0, TAU, 48, ring, 2.5, true)
