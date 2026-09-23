shader_type spatial;
// Lichen-spotted granite outcrops. World-space 3D noise avoids UV seams.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 stone_color : source_color = vec3(0.44, 0.42, 0.39);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float fade = 1.0 - smoothstep(15.0, 70.0, length(VERTEX));
	vec3 p = wpos;
	float broad = wl_fbm3(p * 0.45, 4);
	float mid = wl_fbm3(p * 1.8, 4);
	float crack = pow(wl_ridge3(p * vec3(0.9, 2.2, 0.9) + broad * 2.0), 10.0);
	float crack2 = pow(wl_ridge3(p * 3.1 + 7.0), 14.0);
	float speck = wl_noise3(p * 55.0);
	vec3 c = stone_color * (0.7 + broad * 0.55 + (mid - 0.5) * 0.25) * mix(vec3(1.0), vec3(1.06, 1.0, 0.92), wl_noise3(p * 0.2));
	c = mix(c, vec3(0.2, 0.19, 0.18), step(0.82, speck) * 0.35 * fade);
	c = mix(c, vec3(0.5, 0.49, 0.46), smoothstep(0.08, 0.03, speck) * 0.25 * fade);
	// Iron staining runs down from cracks.
	float stain = wl_noise(vec2((p.x + p.z) * 3.0, p.y * 0.5)) * smoothstep(0.3, 0.7, broad);
	c = mix(c, vec3(0.38, 0.27, 0.18), stain * 0.25);
	c *= 1.0 - (crack * 0.65 + crack2 * 0.4);
	float up = clamp(wnormal.y, 0.0, 1.0);
	float lichen = smoothstep(0.62, 0.7, wl_fbm3(p * 1.3 + 3.0, 3)) * (0.3 + up * 0.7);
	c = mix(c, vec3(0.62, 0.62, 0.45), lichen * 0.6);
	float moss = smoothstep(0.5, 0.7, mid + up * 0.3 - 0.1) * smoothstep(0.5, 0.85, up) * moss_amount;
	c = mix(c, vec3(0.12, 0.16, 0.05) * (0.7 + speck * 0.6), moss);
	// Damp, mud-splashed foot.
	float foot = 1.0 - smoothstep(0.0, 0.5 + broad * 0.6, p.y);
	c = mix(c, c * vec3(0.45, 0.38, 0.3), foot * 0.85);
	ALBEDO = c;
	ROUGHNESS = mix(0.82, 0.95, moss) - foot * 0.12;
	SPECULAR = 0.4;
	AO = 1.0 - crack * 0.5;
	float h = broad * 0.08 + mid * 0.035 - crack * 0.03 - crack2 * 0.01 * fade + (speck - 0.5) * 0.002 * fade + moss * 0.01;
	NORMAL = wl_bump(VERTEX, NORMAL, h, 1.0);
}
