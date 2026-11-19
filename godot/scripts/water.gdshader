// Река: лёгкая рябь и светлые края.
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform vec4 deep : source_color = vec4(0.16, 0.38, 0.50, 0.94);
uniform vec4 shallow : source_color = vec4(0.42, 0.66, 0.72, 0.9);

void fragment() {
	float w = sin(UV.y * 4.0 - TIME * 2.2 + sin(UV.x * 9.0 + TIME) * 1.5) * 0.5 + 0.5;
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	vec4 c = mix(shallow, deep, edge);
	c.rgb += w * 0.05;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
}
