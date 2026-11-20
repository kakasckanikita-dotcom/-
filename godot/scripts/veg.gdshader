// Трава и кусты: перекрещенные плоскости с вырезом по альфе, колышутся на
// ветру (верх сильнее низа), освещаются как поверхность земли — без тёмных
// изнанок. Вдали плавно исчезают.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float sway = 0.12;
uniform float fade_far = 80.0;

varying float fade;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float top = 1.0 - UV.y;
	float w = sin(TIME * 1.7 + wpos.x * 0.35 + wpos.z * 0.2) + 0.4 * sin(TIME * 3.1 + wpos.z * 0.9);
	VERTEX.x += w * sway * top * top;
	VERTEX.z += w * sway * 0.5 * top * top;
	NORMAL = vec3(0.0, 1.0, 0.0);
	fade = 1.0 - smoothstep(fade_far * 0.75, fade_far, length(wpos - CAMERA_POSITION_WORLD));
}

void fragment() {
	vec4 c = texture(tex, UV);
	// дизеринг при исчезновении вдали вместо резкого обрыва
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	if (c.a < 0.5 || fade < dither) {
		discard;
	}
	// обе стороны освещены как земля (иначе изнанка темнеет)
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = c.rgb * COLOR.rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.15;
}
