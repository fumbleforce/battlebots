shader_type spatial;
// Grass tuft cards: alpha-cut blades that sway, base in shadow, dry tips.
render_mode cull_disabled;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 base_color : source_color = vec3(0.13, 0.17, 0.06);
uniform vec3 tip_color : source_color = vec3(0.45, 0.45, 0.22);
varying float seed;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seed = wl_hash(origin.xz * 1.7);
	float bend = UV.y * UV.y;
	float wind = sin(TIME * 1.6 + origin.x * 0.35 + origin.z * 0.21) * 0.7 + sin(TIME * 3.7 + seed * 20.0) * 0.3;
	VERTEX.x += wind * bend * 0.08;
	VERTEX.z += wind * bend * 0.04;
}
void fragment() {
	// UV.y is 0 at the ground and 1 at the tips.
	float h = 1.0 - UV.y;
	float blades = 14.0;
	float cell = floor(UV.x * blades);
	float r = wl_hash(vec2(cell, seed * 31.0));
	float len = 0.45 + r * 0.55;
	float x = fract(UV.x * blades) - 0.5 + (h - 0.0) * 0.0 + (r - 0.5) * 0.3 * UV.y;
	float width = 0.3 * (1.0 - UV.y / len);
	if (abs(x) > width || UV.y > len) { discard; }
	float t = UV.y / len;
	vec3 c = mix(base_color, tip_color * (0.8 + r * 0.4), smoothstep(0.1, 0.95, t));
	c = mix(c, vec3(0.2, 0.26, 0.08), step(0.6, r) * 0.5 * (1.0 - t));
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.5;
	AO = mix(0.65, 1.0, t);
	AO_LIGHT_AFFECT = 0.5;
}
