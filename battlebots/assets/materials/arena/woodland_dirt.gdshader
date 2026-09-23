shader_type spatial;
// Packed forest-clearing dirt: circling ruts, gravel, damp hollows, standing
// puddles, grassy rises and silted water beds. Fine relief is shading only.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform float arena_half_extent = 50.0;
uniform vec4 clusters[8];
uniform float water_level = -10.0;
varying vec3 wnormal; // Undisplaced terrain normal: drives material masks.
varying vec3 wpos;
float octagon_distance(vec2 p) {
	return arena_half_extent - max(max(abs(p.x), abs(p.y)), (abs(p.x) + abs(p.y)) * 0.70710678);
}
// Twin tank tracks along elliptical loops, point-symmetric pairs and lanes.
// Returns groove depth 0..1; tread gets the cross-cleat pattern.
float loop_track(vec2 p, vec2 c, vec2 radii, float rot, float seed, out float tread) {
	vec2 q = p - c;
	q = mat2(vec2(cos(rot), sin(rot)), vec2(-sin(rot), cos(rot))) * q;
	float ang = atan(q.y, q.x);
	float wob = (wl_noise(vec2(ang * 2.0 + seed, seed)) - 0.5) * 0.18 + sin(ang * 3.0 + seed) * 0.05;
	float d = (length(q / radii) - 1.0 - wob) * min(radii.x, radii.y);
	float present = smoothstep(0.3, 0.45, wl_noise(vec2(ang * 1.6 + seed * 3.0, seed * 1.7)));
	float best = 0.0;
	for (int w = 0; w < 2; w++) {
		float g = abs(d - (float(w) * 4.6 - 2.3));
		best = max(best, 1.0 - smoothstep(0.2, 1.5, g));
	}
	tread = step(0.5, fract(ang * length(q) * 1.1)) * best * present;
	return best * present;
}
float lane_track(vec2 p, float phase, float amp, float seed, out float tread) {
	float x = p.x - sin(p.y * 0.045 + phase) * amp - sin(p.y * 0.11 + seed) * amp * 0.3;
	float best = 0.0;
	for (int w = 0; w < 2; w++) {
		float g = abs(x - (float(w) * 4.6 - 2.3));
		best = max(best, 1.0 - smoothstep(0.2, 1.5, g));
	}
	float present = smoothstep(0.35, 0.5, wl_noise(vec2(p.y * 0.03 + seed, seed)));
	tread = step(0.5, fract(p.y * 1.1)) * best * present;
	return best * present;
}
float ruts(vec2 p, out float tread) {
	float best = 0.0;
	tread = 0.0;
	float t;
	// Loops around the mesa, and around each major feature on both halves.
	vec4 loops[6] = vec4[](vec4(0.0, 0.0, 44.0, 39.0), vec4(0.0, 0.0, 55.0, 48.0), vec4(0.0, 0.0, 36.0, 33.0),
		vec4(-32.0, -48.0, 17.0, 13.0), vec4(-82.0, -2.0, 14.0, 12.0), vec4(-58.0, 30.0, 15.0, 11.0));
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		for (int s = 0; s < (i < 3 ? 1 : 2); s++) {
			float sg = s == 0 ? 1.0 : -1.0;
			float r = loop_track(p, loops[i].xy * sg, loops[i].zw, fi * 0.7, fi * 5.3, t);
			if (r > best) { best = r; tread = t; }
		}
	}
	// Serpentine lanes from each team end toward the middle.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float r = lane_track(p, fi * 2.1, 14.0 + fi * 6.0, fi * 3.7, t) * smoothstep(20.0, 45.0, abs(p.y));
		r = max(r, lane_track(-p, fi * 2.1, 14.0 + fi * 6.0, fi * 3.7, t) * smoothstep(20.0, 45.0, abs(p.y)));
		if (r > best) { best = r; tread = t; }
	}
	return best;
}
float track_depth(vec2 p) {
	float tread;
	float r = ruts(p, tread);
	// A groove with churned berms at its lips.
	return -r * r * (3.0 - 2.0 * r) * 0.16 + smoothstep(0.0, 0.3, r) * (1.0 - smoothstep(0.3, 0.6, r)) * 0.05;
}

uniform bool displaced = true;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Ruts are visual only: shallow enough that treads sit in them naturally.
	if (displaced) {
		float flat_ground = smoothstep(0.85, 0.97, wnormal.y);
		vec2 q = wpos.xz;
		float d0 = track_depth(q);
		float dx = track_depth(q + vec2(0.25, 0.0)) - track_depth(q - vec2(0.25, 0.0));
		float dz = track_depth(q + vec2(0.0, 0.25)) - track_depth(q - vec2(0.0, 0.25));
		VERTEX.y += d0 * flat_ground;
		// Tilt the normal by the rut slope so shading follows the displaced surface.
		NORMAL = normalize(NORMAL + vec3(-dx, 0.0, -dz) * 2.0 * flat_ground);
		wpos.y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	}
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	float fade = 1.0 - smoothstep(14.0, 60.0, dist);
	float big = wl_fbm(p * 0.018, 4);
	float mid = wl_fbm(p * 0.21 + 3.1, 4);
	float fine = wl_fbm(p * 2.4, 3);
	float grain = wl_noise(p * 31.0);
	float edge = octagon_distance(p);
	float tread;
	float rut = ruts(p, tread);
	// Gravel stones pressed into the surface.
	vec2 cell = wl_cells(p * 7.0);
	float stone = (1.0 - smoothstep(0.16, 0.3, cell.x)) * step(0.62, cell.y) * (1.0 - rut * 0.7);
	vec2 cell2 = wl_cells(p * 2.1 + 9.0);
	float cobble = (1.0 - smoothstep(0.1, 0.22, cell2.x)) * step(0.9, cell2.y);
	// Hollows collect water; puddles sit in the deepest parts and in the ruts.
	float hollow = big * 0.72 + mid * 0.28 + rut * 0.08;
	float wet = smoothstep(0.55, 0.67, hollow);
	// Rain pools in the deepest stretches of the ruts and in flat hollows.
	float flat_ground = smoothstep(0.9, 0.985, wnormal.y);
	float puddle = smoothstep(0.75, 1.0, rut) * smoothstep(0.5, 0.7, wl_noise(p * 0.12 + 3.0)) * flat_ground * 0.85;
	puddle = clamp(puddle, 0.0, 1.0);
	// Grass survives along the walls and around the outcrops.
	float grass = 1.0 - smoothstep(1.0, 4.0 + mid * 5.0, edge);
	for (int i = 0; i < 8; i++) {
		float d = distance(p, clusters[i].xy);
		grass = max(grass, 1.0 - smoothstep(clusters[i].z, clusters[i].z + 2.5 + mid * 4.0, d));
	}
	// Raised, undriven ground grows grass; banks and water edges stay green.
	grass = max(grass, smoothstep(0.5, 1.4, wpos.y) * 0.9);
	float bank = (1.0 - smoothstep(0.4, 1.2, wpos.y - water_level)) * step(water_level - 0.3, wpos.y);
	grass = max(grass, bank * 0.7);
	grass = max(grass, smoothstep(0.55, 0.8, wl_fbm(p * 0.045 + 7.0, 4)) * 0.8);
	grass *= smoothstep(0.32, 0.55, mid + fine * 0.35) * (1.0 - rut) * (1.0 - wet * 0.6);
	vec3 packed = vec3(0.15, 0.108, 0.072);
	vec3 dusty = vec3(0.23, 0.175, 0.125);
	vec3 loam = vec3(0.11, 0.08, 0.055);
	vec3 col = mix(packed, dusty, smoothstep(0.3, 0.75, big + fine * 0.35 - wet * 0.3));
	col = mix(col, loam, smoothstep(0.5, 0.8, mid) * 0.6);
	col *= 0.84 + grain * 0.2 + (fine - 0.5) * 0.3;
	// Churned mud in the ruts, with wet dark cleat prints.
	col = mix(col, vec3(0.16, 0.115, 0.08), smoothstep(0.0, 0.6, rut) * 0.55);
	col = mix(col, vec3(0.1, 0.075, 0.05), tread * 0.3 * fade);
	col = mix(col, col * 1.25, smoothstep(0.0, 0.3, rut) * (1.0 - smoothstep(0.3, 0.6, rut)) * 0.5);
	// Scorch marks from past fights.
	vec2 sc = wl_cells(p * 0.045 + 5.0);
	float scorch = (1.0 - smoothstep(0.05, 0.28, sc.x)) * step(0.72, sc.y);
	float rays = 0.6 + 0.4 * sin(atan(p.y, p.x) * 23.0 + sc.y * 40.0);
	col = mix(col, vec3(0.04, 0.035, 0.03), scorch * rays * 0.75);
	col = mix(col, vec3(0.34, 0.32, 0.29) * (0.7 + grain * 0.5), stone * 0.75);
	col = mix(col, vec3(0.3, 0.29, 0.27) * (0.8 + fine * 0.4), cobble);
	col = mix(col, vec3(0.08, 0.06, 0.04), wet * 0.8);
	vec3 green = mix(vec3(0.1, 0.13, 0.045), vec3(0.3, 0.27, 0.12), smoothstep(0.35, 0.75, fine + grain * 0.2));
	col = mix(col, green * (0.8 + grain * 0.3), grass * 0.92);
	vec3 water = vec3(0.03, 0.028, 0.022);
	col = mix(col, water, puddle);
	// Submerged beds are dark silt; steep banks show wet clay.
	float under = 1.0 - smoothstep(water_level - 0.05, water_level + 0.35, wpos.y);
	col = mix(col, vec3(0.09, 0.075, 0.05), under);
	// Steep faces are exposed bedrock: layered, cracked granite.
	float steep = 1.0 - smoothstep(0.55, 0.8, wnormal.y);
	float strata = wl_noise(vec2(wpos.y * 3.5 + wl_noise(p * 0.4) * 2.0, (p.x + p.y) * 0.25));
	float crack = pow(1.0 - abs(wl_noise(p * 1.3 + wpos.y) * 2.0 - 1.0), 8.0);
	vec3 bedrock = vec3(0.36, 0.35, 0.33) * (0.7 + strata * 0.45) * (1.0 - crack * 0.6);
	col = mix(col, bedrock, steep);
	grass *= 1.0 - steep;
	puddle *= 1.0 - under;
	// Water at the wall foot darkens the soil.
	col *= 1.0 - (1.0 - smoothstep(0.0, 1.2, edge)) * 0.3;
	ALBEDO = col;
	float rough = mix(0.94, 0.72, wet);
	rough = mix(rough, 0.8, stone * 0.5);
	// Muddy water, not a mirror: broad soft sheen instead of sun sparkles.
	ROUGHNESS = mix(rough, 0.3, puddle);
	SPECULAR = mix(0.36, 0.4, puddle);
	float ripple = (sin(dot(p, vec2(3.0, 2.3)) + TIME * 1.2) + sin(dot(p, vec2(-2.0, 3.7)) + TIME * 1.6)) * 0.0003;
	float h = tread * 0.006 * fade + (fine - 0.5) * 0.02 + stone * 0.012 * fade + cobble * 0.03
		+ (grain - 0.5) * 0.003 * fade + grass * (wl_noise(p * 45.0) - 0.5) * 0.01 * fade;
	h = mix(h, ripple * fade, puddle);
	NORMAL = wl_bump(VERTEX, NORMAL, h, 1.0);
	AO = 1.0 - rut * 0.25 - stone * 0.1;
}
