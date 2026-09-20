shader_type spatial;
render_mode blend_mix, depth_draw_never;
varying vec3 local_point;
float scorch_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9, 78.2, 39.4))) * 43758.54);
}
float scorch_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(scorch_hash(cell), scorch_hash(cell + vec3(1,0,0)), f.x),
		mix(scorch_hash(cell + vec3(0,1,0)), scorch_hash(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(scorch_hash(cell + vec3(0,0,1)), scorch_hash(cell + vec3(1,0,1)), f.x),
		mix(scorch_hash(cell + vec3(0,1,1)), scorch_hash(cell + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	local_point = VERTEX;
}
void fragment() {
	float soot = scorch_noise(local_point * 8.0) * 0.7 + scorch_noise(local_point * 43.0) * 0.3;
	ALBEDO = mix(vec3(0.02, 0.025, 0.03), vec3(0.09, 0.07, 0.045), soot);
	METALLIC = 0.55;
	ROUGHNESS = 0.78 + soot * 0.16;
	ALPHA = 0.68 + soot * 0.18;
}
