shader_type canvas_item;

// Halo interior suave junto al borde de un Control/Panel. Conserva el
// color/textura original y sólo suma brillo en la franja cercana al borde.
uniform vec4 glow_color : hint_color = vec4(0.31, 0.82, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.6;
uniform float width : hint_range(0.0, 0.5) = 0.12;
uniform float pulse_speed : hint_range(0.0, 8.0) = 0.0;

void fragment() {
	// Base: textura * color modulado (alpha original preservado).
	vec4 base = texture(TEXTURE, UV) * COLOR;
	// Distancia (en UV) al borde más próximo.
	vec2 d = min(UV, vec2(1.0) - UV);
	float edge = min(d.x, d.y);
	// 1 en el borde interior, 0 hacia el centro.
	float band = 1.0 - smoothstep(0.0, max(width, 0.0001), edge);
	// Pulso opcional (0 = estático).
	float pulse = 1.0;
	if (pulse_speed > 0.0) {
		pulse = 0.5 + 0.5 * sin(TIME * pulse_speed);
	}
	float add = band * strength * pulse;
	base.rgb += glow_color.rgb * add;
	// No bajamos el alpha original; sólo lo reforzamos con el halo.
	base.a = max(base.a, add * glow_color.a);
	COLOR = base;
}
