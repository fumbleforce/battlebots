shader_type spatial;
// Elysium (#115) heavenly light shafts: additive, soft at the silhouette
// (facing ratio) and fading along their length (UV.y).
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;

uniform vec3 tint = vec3(1.0, 0.86, 0.58);
uniform float strength = 0.12;

varying vec3 world_normal;
varying vec3 world_pos;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 view = normalize(CAMERA_POSITION_WORLD - world_pos);
	float facing = abs(dot(normalize(world_normal), view));
	float along = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float near = smoothstep(20.0, 120.0, length(CAMERA_POSITION_WORLD - world_pos));
	ALBEDO = tint * strength * pow(facing, 2.0) * along * near;
}
