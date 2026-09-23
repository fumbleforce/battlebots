shader_type spatial;
// Palisade timber on Blender-built modules (art_source/woodland/build_palisade.py).
// UVs are metres along (U) and across (V) the grain; the CC0 grain scan runs
// vertically, so it is sampled with swapped axes. Weathering greys the wood
// toward the top, mud and moss wick up from the ground, and the baked vertex
// ambient occlusion darkens contacts.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform sampler2D grain_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tone : source_color = vec3(1.0);
uniform float weathering : hint_range(0.0, 1.0) = 0.5;
uniform float tile = 4.4;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	// The weathered-plank scan holds ~8.7 boards across; map ~0.5 m of
	// board width to one scanned board so knots and nail rows keep scale.
	vec2 uv = vec2(UV.y * 0.23, UV.x / tile);
	vec3 scan = texture(grain_diff, uv).rgb;
	vec3 arm = texture(grain_arm, uv).rgb;
	float lum = dot(scan, vec3(0.3, 0.59, 0.11));
	// Per-board tone from the random UV offset each board was given.
	// Board-to-board tone from the random UV offset each timber was given.
	float board = wl_noise(UV * 0.37 + UV.yx * 0.11);
	float patchy = wl_fbm(wpos.xz * 0.2 + wpos.y * 0.15, 3);
	float grey = clamp(weathering + (patchy - 0.5) * 0.6 + (board - 0.5) * 0.4 + clamp(wnormal.y, 0.0, 1.0) * 0.3, 0.0, 1.0);
	vec3 aged = vec3(lum) * vec3(1.55, 1.48, 1.36) + 0.1;
	// Exaggerate the scan's grain so it survives gameplay distance.
	float mean = max(dot(textureLod(grain_diff, vec2(0.5), 12.0).rgb, vec3(0.333)), 0.02);
	float grain = clamp(lum / mean, 0.0, 3.0);
	vec3 c = mix(scan * 1.7, aged, grey) * mix(1.0, grain, 0.35) * tone * (0.85 + board * 0.3);
	float ground = 1.0 - smoothstep(0.0, 1.0 + wl_noise(wpos.xz * 1.3) * 0.9, wpos.y);
	c = mix(c, c * vec3(0.42, 0.35, 0.27), ground * 0.85);
	float moss = smoothstep(0.55, 0.75, wl_fbm(wpos.xz * 1.4 + wpos.y * 0.9, 4)) * clamp(ground + clamp(wnormal.y, 0.0, 1.0) * 0.6, 0.0, 1.0);
	c = mix(c, vec3(0.12, 0.16, 0.055), moss * 0.8);
	// Baked vertex AO is coarse on box timbers: normalise it and apply lightly.
	float vao = clamp(COLOR.r / 0.45, 0.0, 1.0);
	ALBEDO = c * mix(1.0, vao, 0.35);
	ROUGHNESS = clamp(arm.g + grey * 0.1, 0.5, 1.0);
	SPECULAR = 0.35;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	vec3 tn = texture(grain_nor, uv).rgb;
	NORMAL_MAP = vec3(tn.y, tn.x, tn.z);
	NORMAL_MAP_DEPTH = 1.4;
}
