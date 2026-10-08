shader_type spatial;
render_mode unshaded;

// Orbe del agente: núcleo de plasma (ruido de valor barato) + rim fresnel.
uniform vec4 core_color : hint_color = vec4(0.31, 0.55, 1.0, 1.0);
uniform vec4 rim_color : hint_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float energy = 1.0;  // 0..2: brillo y velocidad
uniform float spin = 0.5;    // velocidad de giro
uniform float crack = 0.0;   // 0..1: grietas / desaturado (desconectado)
uniform float pulse = 0.5;   // 0..1: amplitud de respiración

varying vec3 p;

float h3(vec3 x) {
	return fract(sin(dot(x, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vn(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	p = VERTEX;
	VERTEX *= 1.0 + pulse * 0.05 * sin(TIME * (1.5 + energy * 2.0));
}

void fragment() {
	float a = TIME * spin;
	vec3 q = vec3(cos(a) * p.x + sin(a) * p.z, p.y, -sin(a) * p.x + cos(a) * p.z);
	float n = vn(q * 2.2 + vec3(0.0, TIME * 0.2 * energy, 0.0)) * 0.65 + vn(q * 4.7 - vec3(TIME * 0.25 * energy)) * 0.35;
	float vein = pow(1.0 - abs(vn(q * 3.3 + vec3(TIME * 0.1 * energy)) * 2.0 - 1.0), 5.0);
	float fr = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 4.0);
	float br = 0.45 + 0.35 * energy;
	vec3 col = core_color.rgb * (0.2 + 0.8 * n) * br + rim_color.rgb * vein * 0.35 * energy;
	// grietas oscuras y desaturado
	col *= 1.0 - crack * smoothstep(0.1, 0.0, abs(n - 0.5)) * 0.9;
	float g = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(g), crack * 0.85);
	col *= 1.0 + pulse * 0.25 * sin(TIME * (1.5 + energy * 2.0));
	col += rim_color.rgb * fr * (0.5 + 0.4 * energy) * 1.1 * (1.0 - crack * 0.6);
	col += vec3(0.12) * fr * (1.0 - crack);
	ALBEDO = col;
}
