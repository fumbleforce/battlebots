shader_type spatial;
// Valley ground: needle litter under the pines, meadow grass, granite on steep
// crags, wet sand and silt at the waterline, graded dirt roads.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform float water_level = -5.0;
varying vec3 wpos;
varying vec3 wnormal;
float road(vec2 p) {
	float d = abs(p.x) > 118.0 ? abs(p.y + sin(p.x * 0.01) * 6.0) : 1e5;
	if (p.y > 118.0) { d = min(d, abs(p.x - sin(p.y * 0.012) * 10.0)); }
	return 1.0 - smoothstep(4.5, 7.0, d);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(20.0, 120.0, dist);
	float big = wl_fbm(p * 0.006, 4);
	float mid = wl_fbm(p * 0.05, 4);
	float fine = wl_noise(p * 2.0);
	vec3 litter = mix(vec3(0.13, 0.1, 0.07), vec3(0.2, 0.15, 0.09), mid);
	vec3 meadow = mix(vec3(0.16, 0.2, 0.08), vec3(0.34, 0.33, 0.16), smoothstep(0.3, 0.8, mid + fine * 0.2));
	vec3 col = mix(litter, meadow, smoothstep(0.45, 0.62, big));
	// Far ground reads as unbroken canopy where individual trees end.
	col = mix(col, vec3(0.06, 0.1, 0.07), smoothstep(700.0, 1200.0, length(p)) * 0.8);
	float steep = 1.0 - smoothstep(0.45, 0.7, wnormal.y);
	float strata = wl_noise(vec2(wpos.y * 0.9 + mid * 3.0, (p.x - p.y) * 0.05));
	vec3 granite = vec3(0.3, 0.29, 0.275) * (0.65 + strata * 0.5);
	col = mix(col, granite, steep);
	float shore = 1.0 - smoothstep(water_level + 0.3, water_level + 2.5, wpos.y);
	col = mix(col, vec3(0.27, 0.23, 0.17), shore);
	col = mix(col, vec3(0.1, 0.085, 0.06), 1.0 - smoothstep(water_level - 1.5, water_level + 0.2, wpos.y));
	float r = road(p);
	col = mix(col, vec3(0.26, 0.2, 0.14) * (0.85 + fine * 0.3), r);
	col *= 0.85 + fine * 0.2 * fade + 0.1;
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.7, shore);
	SPECULAR = 0.35;
	float h = (mid * 0.3 + fine * 0.04 * fade) * (1.0 - r) + steep * strata * 0.4;
	NORMAL = wl_bump(VERTEX, NORMAL, h, 1.0);
}
