// Небо Территории Мескаль: градиент с дымкой у горизонта, солнечный диск
// и ореол, плывущие кучевые и перистые облака, звёзды и луна ночью.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.24, 0.45, 0.77);
uniform vec3 horizon_color : source_color = vec3(0.85, 0.75, 0.61);
uniform vec3 ground_color : source_color = vec3(0.54, 0.42, 0.28);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.62, 0.7);
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float coverage = 0.42;
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.7);
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : repeat_enable, filter_linear_mipmap;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	// градиент: у горизонта — тёплая пыльная дымка
	float t = pow(clamp(h, 0.0, 1.0), 0.45);
	vec3 col = mix(horizon_color, top_color, t);
	col = mix(col, ground_color, smoothstep(0.0, -0.08, h));

	vec3 sd = normalize(LIGHT0_DIRECTION);
	float sun_dot = LIGHT0_ENABLED ? max(dot(d, sd), 0.0) : 0.0;
	// ореол вокруг солнца, на закате — широкий и оранжевый
	col += sun_tint * (pow(sun_dot, 8.0) * (0.25 + dusk * 0.5) + pow(sun_dot, 64.0) * 0.4) * (1.0 - night);
	// горизонт у солнца на закате
	col = mix(col, vec3(1.0, 0.5, 0.25), dusk * pow(sun_dot, 3.0) * (1.0 - t) * 0.55);

	// облака на плоскости над миром (в карту отражений — без них, дешевле)
	if (h > 0.0 && !AT_CUBEMAP_PASS) {
		vec2 uv = d.xz / (h + 0.12) * 0.22;
		vec2 wind = vec2(TIME * 0.0035, TIME * 0.0012);
		float n = texture(cloud_noise, uv * 0.6 + wind).r;
		n += texture(cloud_noise, uv * 1.4 - wind * 1.6).r * 0.5;
		n += texture(detail_noise, uv * 4.0 + wind * 3.0).r * 0.25;
		n /= 1.75;
		float c = smoothstep(1.0 - coverage, 1.0 - coverage + 0.22, n);
		// перистые тонкие полосы выше
		float cir = texture(detail_noise, vec2(uv.x * 0.35, uv.y * 1.8) + wind * 0.5).r;
		c = max(c, smoothstep(0.62, 0.85, cir) * 0.35);
		c *= smoothstep(0.0, 0.18, h); // у горизонта облака тают в дымке
		// подсветка: край, обращённый к солнцу, светлее
		float lit = clamp(0.55 + (n - 0.5) * 1.4 + pow(sun_dot, 4.0) * 0.6, 0.0, 1.2);
		vec3 cc = mix(cloud_shade, cloud_light, lit);
		cc = mix(cc, vec3(1.0, 0.55, 0.35), dusk * 0.6);
		cc = mix(cc, vec3(0.08, 0.09, 0.14), night * 0.9);
		col = mix(col, cc, c * 0.92);
		// звёзды и луна ночью
		if (night > 0.01) {
			vec3 cell = floor(d * 380.0);
			float st = hash(cell);
			float star = step(0.9965, st) * (0.6 + 0.4 * sin(TIME * 2.0 + st * 60.0));
			col += vec3(star) * night * (1.0 - c) * smoothstep(0.0, 0.25, h);
			float md = dot(d, normalize(moon_dir));
			float moon = smoothstep(0.99955, 0.9997, md);
			col += vec3(0.95, 0.93, 0.85) * moon * night * (1.0 - c * 0.8);
			col += vec3(0.25, 0.3, 0.45) * pow(max(md, 0.0), 200.0) * night * 0.6;
		}
	}
	// солнечный диск
	col += sun_tint * smoothstep(0.9993, 0.9997, sun_dot) * 6.0 * (1.0 - night) * smoothstep(-0.02, 0.02, h);
	COLOR = col;
}
