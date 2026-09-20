shader_type spatial;
render_mode blend_mix, depth_draw_never;
varying vec3 local_point;
void vertex() {
	local_point = VERTEX;
}
void fragment() {
	float soot = fract(sin(dot(floor(local_point * 17.0), vec3(12.9, 78.2, 39.4))) * 43758.54);
	ALBEDO = mix(vec3(0.025, 0.029, 0.034), vec3(0.1, 0.085, 0.07), soot);
	METALLIC = 0.7;
	ROUGHNESS = 0.88;
	ALPHA = 0.88;
}
