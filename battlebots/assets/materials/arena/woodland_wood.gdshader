shader_type spatial;
// Sawn and hewn timber. Grain follows each instance's longest axis, so the same
// material serves planks, posts, rails, braces and logs. COLOR tints a batch.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 fresh_color : source_color = vec3(0.45, 0.31, 0.19);
uniform vec3 aged_color : source_color = vec3(0.43, 0.40, 0.36);
uniform float weathering : hint_range(0.0, 1.0) = 0.5;
uniform float tar : hint_range(0.0, 1.0) = 0.0;
uniform float ring_density = 22.0;
uniform float pith_offset : hint_range(0.0, 1.0) = 1.0;
uniform float hewn : hint_range(0.0, 1.0) = 0.0;
uniform float moss : hint_range(0.0, 1.0) = 0.35;
uniform float mud_height = 1.1;
varying vec3 gp;
varying vec3 half_dims;
varying vec3 gnormal;
varying vec3 wpos;
varying vec3 wnormal;
varying float seed;

void vertex() {
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec3 b = VERTEX * s;
	if (s.y >= s.x && s.y >= s.z) { gp = b.yxz; half_dims = s.yxz * 0.5; gnormal = NORMAL.yxz; }
	else if (s.x >= s.z) { gp = b; half_dims = s * 0.5; gnormal = NORMAL; }
	else { gp = b.zyx; half_dims = s.zyx * 0.5; gnormal = NORMAL.zyx; }
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 origin = MODEL_MATRIX[3].xyz;
	seed = wl_hash(origin.xz * 0.731 + origin.y * 1.37);
}

void fragment() {
	float fade = 1.0 - smoothstep(12.0, 55.0, length(VERTEX));
	float along = gp.x;
	vec2 cr = gp.yz;
	// Flat-sawn boards place the pith outside the board; boxed-heart posts centre it.
	float side = fract(seed * 13.1) > 0.5 ? 1.0 : -1.0;
	vec2 pith = vec2((seed - 0.5) * half_dims.y, side * (half_dims.z + 0.06 + fract(seed * 3.7) * 0.3)) * pith_offset;
	vec2 q = cr - pith;
	float wob = wl_noise(vec2(along * 0.35, seed * 17.0)) * 0.05 + wl_noise(vec2(along * 1.9, seed * 5.0)) * 0.012;
	float knot_on = step(0.42, fract(seed * 21.7));
	float knot_along = (fract(seed * 9.1) - 0.5) * half_dims.x * 1.5;
	float kd = length(vec2((along - knot_along) * 1.5, cr.x - (fract(seed * 4.3) - 0.5) * half_dims.y));
	float r = length(q) * (1.0 + 0.06 * sin(atan(q.y, q.x) * 3.0 + seed * 6.0)) + wob + knot_on * 0.025 * exp(-kd * 16.0);
	float ring = fract(r * ring_density);
	float late = smoothstep(0.55, 0.92, ring) * (1.0 - smoothstep(0.92, 1.0, ring));
	float across = (cr.x + cr.y);
	float fiber = wl_noise(vec2(along * 1.4, across * 85.0 + seed * 40.0));
	float fiber2 = wl_noise(vec2(along * 5.5, across * 240.0 + seed * 13.0));
	float check = smoothstep(0.83, 0.9, wl_noise(vec2(along * 0.7 + seed * 9.0, across * 26.0)));
	check *= smoothstep(0.2, 0.6, weathering);
	float knot = knot_on * (1.0 - smoothstep(0.012, 0.045, kd));

	vec3 wood = fresh_color * (0.8 + 0.34 * fiber);
	wood = mix(wood, fresh_color * 0.52, late * 0.8);
	float up = clamp(wnormal.y, 0.0, 1.0);
	float patchy = wl_fbm(wpos.xz * 0.27 + wpos.y * 0.21, 3) - 0.5;
	float aged_mask = clamp(weathering + patchy * 0.7 + up * 0.25 + (seed - 0.5) * 0.35, 0.0, 1.0);
	vec3 aged = aged_color * (0.74 + 0.4 * fiber2) * (1.0 - late * 0.3);
	wood = mix(wood, aged, aged_mask);
	wood = mix(wood, wood * vec3(0.3, 0.25, 0.21), tar * (0.8 + patchy * 0.4));
	// End grain: annual rings and a darker absorbent cut.
	float end_grain = smoothstep(0.7, 0.95, abs(gnormal.x));
	wood = mix(wood, fresh_color * (0.55 + (1.0 - late) * 0.3) * mix(1.0, 0.75, aged_mask), end_grain);
	// Rain splash, mud and moisture wick up from the ground.
	float ground = 1.0 - smoothstep(0.0, mud_height + wl_noise(wpos.xz * 1.3) * 0.8, wpos.y);
	wood = mix(wood, wood * vec3(0.42, 0.35, 0.27), ground * 0.8);
	float moss_mask = smoothstep(0.52, 0.72, wl_fbm(wpos.xz * 1.6 + wpos.y * 1.1, 4)) * clamp(ground * 0.9 + up * 0.7, 0.0, 1.0) * moss;
	wood = mix(wood, vec3(0.13, 0.17, 0.055) * (0.7 + fiber * 0.6), clamp(moss_mask * 1.3, 0.0, 1.0));
	// Handling polishes and lightens arrises.
	vec3 ad = half_dims - abs(gp);
	float edge_d = max(min(ad.x, ad.y), min(max(ad.x, ad.y), ad.z));
	float arris = 1.0 - smoothstep(0.004, 0.028, edge_d);
	wood *= 1.0 + arris * 0.22 * (1.0 - moss_mask);
	wood *= 1.0 - check * 0.65;
	wood = mix(wood, vec3(0.1, 0.06, 0.035), knot * 0.85);
	ALBEDO = wood * COLOR.rgb;
	ROUGHNESS = clamp(mix(0.68, 0.9, aged_mask) - tar * 0.18 + moss_mask * 0.05, 0.3, 1.0);
	SPECULAR = 0.35;
	AO = 1.0 - check * 0.6 - knot * 0.2;
	AO_LIGHT_AFFECT = 0.4;
	float adze = hewn * (wl_noise(vec2(along * 2.6 + seed * 3.0, across * 5.0)) - 0.5) * 0.012;
	float h = (-late * 0.0012 * aged_mask - fiber2 * 0.0006 - check * 0.004 - knot * 0.002) * fade
		- arris * 0.006 + adze + moss_mask * 0.004 * fade;
	NORMAL = wl_bump(VERTEX, NORMAL, h, 1.0);
}
