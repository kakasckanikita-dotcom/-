// Земля пустыни: песок с рябью от ветра, россыпь камешков, трещины сухой
// глины, кустистые участки, красные скалы на склонах с пластами породы.
// Всё в мировых координатах, без повторяющейся плитки.
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D noise_small : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_big : repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D cells : repeat_enable, filter_linear_mipmap;
uniform sampler2D pebbles : repeat_enable, filter_linear_mipmap;
uniform vec3 sand_a : source_color = vec3(0.56, 0.41, 0.27);
uniform vec3 sand_b : source_color = vec3(0.66, 0.51, 0.35);
uniform vec3 scrub : source_color = vec3(0.50, 0.47, 0.30);
uniform vec3 redrock : source_color = vec3(0.70, 0.42, 0.28);
uniform vec3 clay : source_color = vec3(0.62, 0.50, 0.38);
uniform vec3 cliff_a : source_color = vec3(0.58, 0.33, 0.22);
uniform vec3 cliff_b : source_color = vec3(0.76, 0.50, 0.34);

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float near = 1.0 - smoothstep(25.0, 70.0, dist); // мелкие детали только вблизи
	float s = texture(noise_small, wp.xz / 14.0).r;
	float d = texture(noise_small, wp.xz / 3.1).r;
	float b = texture(noise_big, wp.xz / 260.0).r;
	float m = texture(noise_big, wp.xz / 60.0).r;
	vec3 c = mix(sand_a, sand_b, s);
	c = mix(c, scrub, smoothstep(0.58, 0.78, b) * 0.7);
	c = mix(c, redrock, smoothstep(0.42, 0.22, b) * 0.5);
	// пятна сухой потрескавшейся глины
	float clay_k = smoothstep(0.6, 0.7, m) * (1.0 - smoothstep(0.55, 0.75, b));
	float crack = texture(cells, wp.xz / 2.2).r;
	c = mix(c, clay, clay_k * 0.8);
	c *= 1.0 - clay_k * smoothstep(0.08, 0.0, crack) * 0.45 * near;
	// рябь песка от ветра
	float rip = sin(wp.x * 2.6 + wp.z * 0.9 + s * 9.0) * 0.5 + 0.5;
	c *= 1.0 - rip * 0.06 * (1.0 - clay_k) * near;
	// камешки
	float pebble = texture(pebbles, wp.xz / 3.0).r;
	float pmask = smoothstep(0.45, 0.7, texture(noise_small, wp.xz / 7.0).r);
	float pk = smoothstep(0.16, 0.1, pebble) * pmask * near;
	c = mix(c, c * vec3(0.62, 0.58, 0.55), pk * 0.8);
	c *= 0.92 + d * 0.16;
	// крутые склоны — красный камень с полосами пластов, вершины гор светлее
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float strata = sin(wp.y * 1.6 + s * 2.0) * 0.5 + 0.5;
	vec3 cliff = mix(cliff_a, cliff_b, strata) * (0.85 + d * 0.3);
	float ck = smoothstep(0.1, 0.28, slope);
	c = mix(c, cliff, ck);
	c = mix(c, c * vec3(1.05, 0.95, 0.88), smoothstep(6.0, 20.0, wp.y) * 0.5);
	ALBEDO = c;
	// микрорельеф: два масштаба карты нормалей, на скалах — сильнее
	vec3 n1 = texture(noise_normal, wp.xz / 4.0).rgb;
	vec3 n2 = texture(noise_normal, wp.xz / 1.1 + 0.37).rgb;
	vec3 nm = mix(n1, n2, 0.5);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nm, (0.35 + ck * 0.5 + pk * 0.6) * (0.3 + near * 0.7));
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
