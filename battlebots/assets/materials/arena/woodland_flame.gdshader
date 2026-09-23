shader_type spatial;
// Brazier fire on crossed cards: rising turbulent tongues, hot core.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
varying float seed;
void vertex() { seed = wl_hash(MODEL_MATRIX[3].xz); }
void fragment() {
	vec2 uv = UV;
	float t = TIME * (1.6 + seed * 0.6);
	float n = wl_fbm(vec2(uv.x * 3.0 + seed * 9.0, uv.y * 2.0 + t), 4);
	float body = (1.0 - abs(uv.x - 0.5) * 2.0);
	float rise = 1.0 - uv.y;
	float shape = body * 1.3 - uv.y * 1.1 + (n - 0.5) * 1.1 + 0.15;
	float a = smoothstep(0.0, 0.35, shape) * smoothstep(0.0, 0.08, rise);
	// Warm orange tongues; only the base core runs yellow so distant
	// braziers read as fire, never as white sparkles.
	vec3 hot = vec3(1.0, 0.5, 0.1);
	vec3 cool = vec3(0.75, 0.14, 0.02);
	vec3 c = mix(cool, hot, smoothstep(0.4, 1.0, shape) * (1.0 - uv.y));
	float far = smoothstep(30.0, 120.0, length(VERTEX));
	// Alpha-blended, so a bright sky behind cannot wash the fire to white.
	ALBEDO = c * mix(1.6, 1.1, far);
	ALPHA = a * 0.92;
}
