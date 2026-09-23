shader_type spatial;
// Scanned CC0 concrete (triplanar), graded to a weathered grey, with rain
// streaks running down the faces and mud/moss at the foot.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 concrete_color : source_color = vec3(0.42, 0.41, 0.39);
uniform sampler2D scan_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_arm : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 p = wpos;
	vec3 scan = wl_triplanar(scan_diff, p, wnormal, 3.0);
	float mean = max(dot(textureLod(scan_diff, vec2(0.5), 12.0).rgb, vec3(0.333)), 0.05);
	// Keep the scan's detail, but set the overall tone from concrete_color.
	vec3 c = concrete_color * (scan / mean);
	float broad = wl_fbm3(p * 0.18, 3);
	c *= 0.88 + broad * 0.24;
	// Rain streaks under ledges: long, thin, vertical.
	float streak = wl_noise(vec2((p.x + p.z) * 5.0, p.y * 0.18)) * (1.0 - abs(wnormal.y));
	c *= 1.0 - smoothstep(0.55, 0.9, streak) * 0.35;
	float foot = 1.0 - smoothstep(0.0, 0.9 + broad * 0.6, p.y - (MODEL_MATRIX[3].y));
	c = mix(c, c * vec3(0.5, 0.42, 0.33), foot * 0.75);
	float moss = smoothstep(0.62, 0.8, wl_fbm3(p * 0.9, 3)) * clamp(wnormal.y, 0.0, 1.0);
	c = mix(c, vec3(0.12, 0.15, 0.06), moss * 0.7);
	ALBEDO = c * COLOR.rgb;
	vec3 arm = wl_triplanar(scan_arm, p, wnormal, 3.0);
	ROUGHNESS = clamp(arm.g + 0.1, 0.6, 1.0);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.3;
	SPECULAR = 0.35;
	vec3 nw = wl_triplanar_normal(scan_nor, p, wnormal, 3.0, 0.9);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
