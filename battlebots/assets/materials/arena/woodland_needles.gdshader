shader_type spatial;
// Conifer spray cards. UV.x crosses a spray, UV.y runs from twig base to tip.
// Distance solidifies the silhouette so far trees do not shimmer.
render_mode cull_disabled;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 deep_color : source_color = vec3(0.05, 0.09, 0.05);
uniform vec3 tip_color : source_color = vec3(0.19, 0.28, 0.1);
uniform float density = 1.0;
varying float seed;
varying float dist;
void vertex() {
	seed = wl_hash(MODEL_MATRIX[3].xz * 0.29);
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
	vec2 uv = UV;
	float across = abs(uv.x - 0.5) * 2.0;
	float taper = mix(0.95, 0.35, smoothstep(0.55, 1.0, uv.y)) * smoothstep(0.0, 0.12, uv.y);
	float lump = wl_noise(uv * vec2(5.0, 9.0) + seed * 13.0);
	float needles = wl_noise(uv * vec2(38.0, 70.0) + seed * 7.0);
	float solid = smoothstep(18.0, 70.0, dist);
	float shape = taper - across * 0.85 + (lump - 0.5) * 0.55 * (1.0 - solid * 0.6) + (needles - 0.5) * 0.35 * (1.0 - solid) + 0.08;
	shape += solid * 0.18 + density * 0.12 - 0.12;
	ALPHA = step(0.0, shape);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float depth = smoothstep(0.0, 0.9, uv.y) * (1.0 - across * 0.4);
	vec3 c = mix(deep_color, tip_color, depth * (0.6 + lump * 0.6));
	c *= 0.8 + needles * 0.35 + (seed - 0.5) * 0.25;
	ALBEDO = c;
	ROUGHNESS = 0.78;
	SPECULAR = 0.28;
	BACKLIGHT = c * 0.6;
	AO = mix(0.55, 1.0, depth);
	AO_LIGHT_AFFECT = 0.3;
}
