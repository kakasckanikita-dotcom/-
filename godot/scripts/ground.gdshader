// Песок пустыни: два слоя шума в мировых координатах, без повторяющейся плитки.
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_small : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_big : repeat_enable, filter_linear_mipmap;
uniform vec3 sand_a : source_color = vec3(0.58, 0.43, 0.29);
uniform vec3 sand_b : source_color = vec3(0.69, 0.55, 0.38);
uniform vec3 scrub : source_color = vec3(0.58, 0.54, 0.34);
uniform vec3 redrock : source_color = vec3(0.74, 0.46, 0.31);

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float s = texture(noise_small, wp.xz / 14.0).r;
	float d = texture(noise_small, wp.xz / 3.1).r;
	float b = texture(noise_big, wp.xz / 260.0).r;
	vec3 c = mix(sand_a, sand_b, s);
	c = mix(c, scrub, smoothstep(0.58, 0.78, b) * 0.7);
	c = mix(c, redrock, smoothstep(0.42, 0.22, b) * 0.5);
	c *= 0.92 + d * 0.16;
	ALBEDO = c;
	ROUGHNESS = 0.97;
	SPECULAR = 0.15;
}
