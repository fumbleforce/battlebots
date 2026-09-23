shader_type spatial;
// Scots/red pine bark: grey-brown furrowed plates low, thin orange bark high.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform float height = 14.0;
varying vec3 lpos;
varying vec3 wpos;
varying float seed;
void vertex() {
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	seed = wl_hash(MODEL_MATRIX[3].xz * 0.37);
}
void fragment() {
	float fade = 1.0 - smoothstep(10.0, 45.0, length(VERTEX));
	float ang = atan(lpos.x, lpos.z);
	vec2 bp = vec2(ang * 3.0 + seed * 20.0, lpos.y * 1.6);
	float plates = wl_noise(bp * vec2(1.0, 0.45) + wl_noise(bp * 2.0) * 0.6);
	float furrow = smoothstep(0.35, 0.6, abs(wl_noise(vec2(ang * 5.0 + seed * 9.0, lpos.y * 0.7)) * 2.0 - 1.0));
	float upper = smoothstep(0.35, 0.7, lpos.y / height + (wl_noise(bp) - 0.5) * 0.2);
	vec3 low = vec3(0.23, 0.18, 0.14) * (0.7 + plates * 0.6);
	vec3 high = vec3(0.62, 0.34, 0.17) * (0.75 + plates * 0.4);
	vec3 c = mix(low, high, upper);
	c *= 1.0 - (1.0 - furrow) * 0.6 * (1.0 - upper * 0.7);
	float lichen = smoothstep(0.62, 0.7, wl_noise(bp * 3.0 + 4.0)) * (1.0 - upper);
	c = mix(c, vec3(0.45, 0.47, 0.36), lichen * 0.5);
	float mud = 1.0 - smoothstep(0.0, 0.6, wpos.y);
	c = mix(c, c * 0.55, mud);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
	AO = mix(0.55, 1.0, furrow);
	float h = (furrow * 0.02 + plates * 0.006) * (1.0 - upper * 0.8);
	NORMAL = wl_bump(VERTEX, NORMAL, h * mix(0.4, 1.0, fade), 1.0);
}
