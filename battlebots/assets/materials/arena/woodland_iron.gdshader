shader_type spatial;
// Forged straps, bands and bolts: dark mill scale with rust blooms and streaks.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 iron_color : source_color = vec3(0.11, 0.105, 0.1);
uniform vec3 rust_color : source_color = vec3(0.36, 0.16, 0.07);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.56;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fade = 1.0 - smoothstep(8.0, 40.0, length(VERTEX));
	float scale = wl_fbm3(wpos * 7.0, 3);
	float bloom = wl_fbm3(wpos * 2.2 + 4.0, 4);
	float streak = wl_noise(vec2((wpos.x + wpos.z) * 9.0, wpos.y * 0.9));
	float rust = clamp(smoothstep(0.62 - rust_amount * 0.3, 0.78 - rust_amount * 0.3, bloom) + streak * rust_amount * 0.35, 0.0, 1.0);
	vec3 iron = iron_color * (0.75 + scale * 0.5);
	vec3 oxide = rust_color * (0.6 + wl_noise3(wpos * 40.0) * 0.6);
	ALBEDO = mix(iron, oxide, rust);
	METALLIC = mix(0.7, 0.12, rust);
	ROUGHNESS = mix(roughness_floor + scale * 0.16, 0.86, rust);
	float pit = wl_noise3(wpos * 90.0) * rust * 0.0006 * fade;
	NORMAL = wl_bump(VERTEX, NORMAL, scale * 0.0005 * fade + pit, 1.0);
}
