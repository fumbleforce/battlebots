shader_type spatial;
// Board-formed concrete: pour lines, rain streaks, chipped arrises showing
// aggregate, soot high up and moss at the foot.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 concrete_color : source_color = vec3(0.47, 0.46, 0.43);
uniform sampler2D scan_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D scan_arm : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
varying vec3 wnormal;
varying vec3 lpos;
varying vec3 half_dims;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	lpos = VERTEX * s;
	half_dims = s * 0.5;
}
void fragment() {
	float fade = 1.0 - smoothstep(12.0, 60.0, length(VERTEX));
	vec3 p = wpos;
	float broad = wl_fbm3(p * 0.35, 4);
	float fine = wl_noise3(p * 18.0);
	float board = 1.0 - smoothstep(0.0, 0.02, abs(fract(p.y / 0.3) - 0.5) - 0.47);
	float streak = wl_noise(vec2((p.x + p.z) * 4.0, p.y * 0.25)) * smoothstep(0.3, 0.8, wl_noise(vec2((p.x + p.z) * 0.7, 3.0)));
	vec3 ad = half_dims - abs(lpos);
	float edge_d = max(min(ad.x, ad.y), min(max(ad.x, ad.y), ad.z));
	float chip = (1.0 - smoothstep(0.02, 0.09, edge_d)) * smoothstep(0.45, 0.6, wl_noise3(p * 3.0));
	vec3 scan = wl_triplanar(scan_diff, p, wnormal, 2.5);
	vec3 c = scan * (concrete_color / 0.46) * (0.85 + broad * 0.3);
	c *= 1.0 - board * 0.12;
	c = mix(c, c * vec3(0.55, 0.52, 0.48), streak * 0.55);
	c = mix(c, vec3(0.56, 0.54, 0.5) * (0.7 + fine * 0.6), chip);
	float soot = smoothstep(0.55, 0.85, wl_fbm3(p * 0.6 + 4.0, 3)) * smoothstep(1.0, 3.0, p.y);
	c = mix(c, vec3(0.08, 0.075, 0.07), soot * 0.45);
	float foot = 1.0 - smoothstep(0.0, 0.9 + broad, p.y - 0.0);
	c = mix(c, vec3(0.2, 0.16, 0.11), foot * 0.6);
	float moss = smoothstep(0.55, 0.75, wl_fbm3(p * 1.4, 3)) * (foot * 0.8 + clamp(wnormal.y, 0.0, 1.0) * 0.5);
	c = mix(c, vec3(0.12, 0.16, 0.06), clamp(moss, 0.0, 1.0));
	ALBEDO = c * COLOR.rgb;
	SPECULAR = 0.35;
	AO = 1.0 - board * 0.3;
	float h = (broad * 0.01 + (fine - 0.5) * 0.002 - board * 0.004 - chip * 0.02) * fade;
	vec3 nw = wl_triplanar_normal(scan_nor, p, wnormal, 2.5, 0.8);
	vec3 base = wl_bump(VERTEX, NORMAL, h, 1.0);
	NORMAL = normalize(base + (VIEW_MATRIX * vec4(nw - wnormal, 0.0)).xyz);
	ROUGHNESS = clamp(wl_triplanar(scan_arm, p, wnormal, 2.5).g, 0.6, 1.0);
}
