// Грунтовая дорога: утоптанная земля, две колеи от колёс, следы копыт
// посередине, края плавно переходят в песок.
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_small : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec3 dirt : source_color = vec3(0.55, 0.42, 0.29);
uniform vec3 dirt_dark : source_color = vec3(0.45, 0.34, 0.24);
uniform vec3 edge : source_color = vec3(0.62, 0.48, 0.33);
uniform float ruts = 1.0; // 0 — городская улица без колей

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float s = texture(noise_small, wp.xz / 9.0).r;
	float d = texture(noise_small, wp.xz / 1.7).r;
	vec3 c = mix(dirt, dirt_dark, s * 0.7);
	// колеи
	float wob = (s - 0.5) * 0.06;
	float r1 = smoothstep(0.07, 0.0, abs(u - 0.32 - wob));
	float r2 = smoothstep(0.07, 0.0, abs(u - 0.68 - wob));
	float rut = max(r1, r2) * ruts;
	c *= 1.0 - rut * 0.2;
	// следы копыт по центру
	float hoof = texture(noise_small, vec2(u * 6.0, UV.y * 1.3)).r;
	c *= 1.0 - smoothstep(0.66, 0.72, hoof) * smoothstep(0.25, 0.0, abs(u - 0.5)) * 0.18;
	c *= 0.93 + d * 0.14;
	// края — в цвет песка
	float e = smoothstep(0.0, 0.18, u) * smoothstep(1.0, 0.82, u);
	c = mix(edge, c, e);
	ALBEDO = c;
	vec3 nm = texture(noise_normal, wp.xz / 2.5).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, 0.35 + rut * 0.3);
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
