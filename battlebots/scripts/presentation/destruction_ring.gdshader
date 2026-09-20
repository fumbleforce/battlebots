shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float age = 0.0;
void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	float ring = smoothstep(0.68, 0.88, radius) * (1.0 - smoothstep(0.88, 1.0, radius));
	vec3 tint = mix(vec3(1.0, 0.67, 0.23), vec3(0.32, 0.24, 0.18), clamp(age * 3.0, 0.0, 1.0));
	ALBEDO = tint;
	EMISSION = tint * max(0.0, 2.0 - age * 8.0);
	ALPHA = ring * (1.0 - smoothstep(0.0, 0.55, age)) * 0.65;
}
