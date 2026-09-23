shader_type spatial;
// Distant mountain ranges: forested lower slopes, bare granite above the tree
// line, snow on high, gentle faces. Distance haze is applied by the world fog.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform float snow_line = 1050.0;
uniform float tree_line = 650.0;
varying vec3 wpos;
varying vec3 wnormal;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec2 p = wpos.xz;
	float n = wl_fbm(p * 0.004, 5);
	float fine = wl_fbm(p * 0.03, 3);
	float up = clamp(wnormal.y, 0.0, 1.0);
	vec3 forest = mix(vec3(0.05, 0.075, 0.05), vec3(0.09, 0.11, 0.07), fine);
	vec3 rock = mix(vec3(0.13, 0.135, 0.145), vec3(0.22, 0.22, 0.225), n) * (0.8 + fine * 0.4);
	vec3 snow = vec3(0.86, 0.88, 0.92);
	float h = wpos.y + (n - 0.5) * 160.0;
	float trees = (1.0 - smoothstep(tree_line - 30.0, tree_line + 30.0, h)) * smoothstep(0.45, 0.7, up);
	vec3 c = mix(rock, forest, trees);
	// Snow settles on gentle faces above the snow line and streaks down gullies.
	float gully = smoothstep(0.55, 0.8, wl_fbm(vec2(p.x * 0.01, wpos.y * 0.02) + n, 3));
	float s = smoothstep(snow_line - 40.0, snow_line + 40.0, h + gully * 220.0) * smoothstep(0.35, 0.65, up + gully * 0.2);
	c = mix(c, snow, s);
	ALBEDO = c;
	ROUGHNESS = mix(0.95, 0.7, s);
	SPECULAR = 0.3;
}
