shader_type spatial;
render_mode blend_mix, depth_draw_never;
uniform float damage_stage = 0.0;
varying vec3 local_point;
void vertex() {
	local_point = VERTEX;
}
void fragment() {
	// Broad irregular cracks stay legible at follow distance; intact paint remains below.
	vec3 p = local_point * 3.0;
	float wave = sin(p.x * 3.1 + sin(p.y * 2.7)) + sin(p.z * 4.3 + p.y);
	float crack = 1.0 - smoothstep(0.10, 0.25, abs(wave));
	float scorch = damage_stage > 1.5 ? 0.88 : 0.38;
	ALBEDO = vec3(0.07, 0.055, 0.035);
	ROUGHNESS = 1.0;
	METALLIC = 0.05;
	ALPHA = damage_stage > 0.5 ? max(scorch, crack * 0.9) : 0.0;
}
