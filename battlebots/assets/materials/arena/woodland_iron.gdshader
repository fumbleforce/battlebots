shader_type spatial;
// Forged straps, bands and bolts: dark mill scale with rust blooms and streaks.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 iron_color : source_color = vec3(0.11, 0.105, 0.1);
uniform vec3 rust_color : source_color = vec3(0.36, 0.16, 0.07);
uniform float rust_amount : hint_range(0.0, 1.0) = 0.45;
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.56;
uniform sampler2D plate_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plate_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rust_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float fade = 1.0 - smoothstep(8.0, 40.0, length(VERTEX));
	float scale = wl_fbm3(wpos * 7.0, 3);
	float bloom = wl_fbm3(wpos * 2.2 + 4.0, 4);
	float streak = wl_noise(vec2((wpos.x + wpos.z) * 9.0, wpos.y * 0.9));
	float rust = clamp(smoothstep(0.62 - rust_amount * 0.3, 0.78 - rust_amount * 0.3, bloom) + streak * rust_amount * 0.35, 0.0, 1.0);
	vec3 iron = iron_color * (0.75 + scale * 0.5);
	vec3 oxide = rust_color * (0.6 + wl_noise3(wpos * 40.0) * 0.6);
	vec3 plate = wl_triplanar(plate_diff, wpos, wnormal, 1.8);
	vec3 rust_scan = wl_triplanar(rust_diff, wpos, wnormal, 1.4);
	// The rusty scan's orange blooms become the rust mask; the plate scan the steel.
	float scan_rust = smoothstep(0.08, 0.3, rust_scan.r - rust_scan.b);
	rust = clamp(max(rust * 0.6, scan_rust * rust_amount), 0.0, 1.0);
	iron = plate * (iron_color / 0.35) * (0.85 + scale * 0.3);
	float rl = dot(rust_scan, vec3(0.3, 0.59, 0.11));
	oxide = mix(oxide, mix(vec3(rl), rust_scan, 0.55) * 0.7, 0.6);
	ALBEDO = mix(iron, oxide, rust);
	METALLIC = mix(0.7, 0.12, rust);
	ROUGHNESS = mix(roughness_floor + scale * 0.16, 0.86, rust);
	float pit = wl_noise3(wpos * 90.0) * rust * 0.0006 * fade;
	vec3 base = wl_bump(VERTEX, NORMAL, scale * 0.0005 * fade + pit, 1.0);
	vec3 nw = wl_triplanar_normal(plate_nor, wpos, wnormal, 1.8, 0.7);
	NORMAL = normalize(base + (VIEW_MATRIX * vec4(nw - wnormal, 0.0)).xyz);
}
