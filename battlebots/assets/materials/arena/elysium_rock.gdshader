shader_type spatial;
// Elysium (#115) island undersides: pale honey limestone hanging in tapering
// roots under each island, laced with faintly glowing gold veins, mossy and
// grass-draped at the lip. COLOR.r = share of the way down (0 at the lip),
// COLOR.g = moss drape.
render_mode cull_back;
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 stone_light = vec3(0.95, 0.86, 0.72);
uniform vec3 stone_deep = vec3(0.44, 0.45, 0.6);
uniform vec3 moss = vec3(0.45, 0.66, 0.26);
uniform vec3 vein_glow = vec3(1.0, 0.72, 0.3);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 drape;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	drape = COLOR.rg;
}

void fragment() {
	vec3 n = ely_safe_normalize(world_normal);
	vec4 scan = ely_triplanar(rock_tex, world_pos, n, 0.06);
	vec4 scan_fine = ely_triplanar(rock_tex, world_pos, n, 0.23);
	float lum = dot(mix(scan.rgb, scan_fine.rgb, 0.35), vec3(0.3, 0.55, 0.15));
	// Sedimentary banding, uneven and dipping.
	float bands = ely_fbm2(vec2(world_pos.y * 0.35 + ely_noise2(world_pos.xz * 0.03) * 3.0, 0.5), 3);
	vec3 stone = mix(stone_deep, stone_light, clamp(1.0 - drape.x * 0.8 + (bands - 0.5) * 0.4, 0.0, 1.0));
	vec3 albedo = stone * (0.78 + lum * 0.55);
	// Moss and grass hanging over the lip.
	float hang = drape.y * smoothstep(0.35, 0.6, ely_fbm2(world_pos.xz * 0.4 + world_pos.y * 0.25, 3) + drape.y * 0.35);
	albedo = mix(albedo, moss * (0.7 + lum * 0.6), clamp(hang, 0.0, 1.0));
	// Gold veins: thin warped ridges of noise, glowing softly in the shade.
	float v = abs(ely_fbm3(world_pos * 0.045, 4) - 0.5);
	float vein = (1.0 - smoothstep(0.0015, 0.005, v)) * (1.0 - hang) * smoothstep(0.15, 0.45, drape.x) * smoothstep(0.45, 0.6, ely_noise3(world_pos * 0.02));
	ALBEDO = mix(albedo, vein_glow, vein * 0.6);
	METALLIC = vein * 0.9;
	ROUGHNESS = mix(0.88, 0.3, vein);
	NORMAL_MAP = ely_triplanar(rock_nor, world_pos, n, 0.06).rgb;
	NORMAL_MAP_DEPTH = 1.2;
	EMISSION = vein_glow * vein * 0.7;
}
