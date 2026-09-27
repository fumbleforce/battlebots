shader_type spatial;
render_mode diffuse_burley, cull_disabled;
// Fleet banners, crests, shields and sails, frozen stiff (#102). UV is in
// metres from the top-left corner; vertex colour rg = cloth size / 10 m, so
// emblems keep their proportions on any banner. Emblem 0: the Ember Crown's
// gold sunburst. Emblem 1: the Jade Covenant's trident over the waves.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
uniform int emblem = 0;
uniform bool sail = false;
uniform vec3 field : source_color = vec3(0.6, 0.04, 0.05);
uniform vec3 charge : source_color = vec3(1.0, 0.74, 0.18);
uniform vec3 border : source_color = vec3(0.08, 0.03, 0.02);
uniform vec3 canvas : source_color = vec3(0.34, 0.33, 0.31);
varying vec3 world;
varying vec3 normal_world;
varying vec2 cloth_size;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cloth_size = max(COLOR.rg * 10.0, vec2(0.05));
}

float tri(float x) { return abs(fract(x) * 2.0 - 1.0); }

// Signed coverage of the emblem at q (emblem units, y down, radius ~1).
float sunburst(vec2 q) {
	float r = length(q);
	float a = atan(q.y, q.x);
	float star = 0.5 + 0.48 * (1.0 - tri(a / TAU * 12.0));
	float rays = step(r, star) * step(0.46, r);
	float disc = step(r, 0.36);
	float ring = step(0.25, r) * step(r, 0.3);
	return max(rays, disc - ring);
}

float trident(vec2 q) {
	float shaft = step(abs(q.x), 0.07) * step(-0.35, q.y) * step(q.y, 0.95);
	float bar = step(abs(q.x), 0.55) * step(abs(q.y + 0.3), 0.07);
	float prongs = 0.0;
	for (int i = -1; i <= 1; i++) {
		float x = float(i) * 0.48;
		float tip = -0.95 + abs(q.x - x) * 3.2;
		prongs = max(prongs, step(abs(q.x - x), 0.07) * step(q.y, -0.3) * step(tip, q.y));
		// Barbed, dagger-sharp heads.
		prongs = max(prongs, step(abs(q.x - x), 0.18 - (q.y + 0.95) * 0.7) * step(-0.95, q.y) * step(q.y, -0.72));
	}
	float wave = 0.0;
	for (int k = 0; k < 2; k++) {
		float y = 0.62 + float(k) * 0.22;
		float zig = y + (tri(q.x * 2.2) - 0.5) * 0.18;
		wave = max(wave, step(abs(q.y - zig), 0.045) * step(abs(q.x), 0.8));
	}
	return max(max(shaft, bar), max(prongs, wave));
}

void fragment() {
	vec2 p = UV;
	vec2 size = cloth_size;
	float edge = min(min(p.x, size.x - p.x), min(p.y, size.y - p.y));
	vec3 base = sail ? canvas : field;
	vec2 centre = size * vec2(0.5, sail ? 0.45 : 0.4);
	float scale = min(size.x, size.y) * (sail ? 0.34 : 0.4);
	vec2 q = (p - centre) / scale;
	float mark = emblem == 0 ? sunburst(q) : trident(q);
	vec3 albedo = base;
	if (sail) {
		// Two broad fleet stripes and the emblem in fleet colours.
		float stripe = step(abs(p.y / size.y - 0.14), 0.05) + step(abs(p.y / size.y - 0.86), 0.05);
		albedo = mix(albedo, field, clamp(stripe, 0.0, 1.0));
		albedo = mix(albedo, field, mark);
	} else {
		albedo = mix(albedo, charge, mark);
		albedo = mix(albedo, border, step(edge, min(size.x, size.y) * 0.06));
	}
	// Weathered weave, soot and frost creeping up from the frayed edge.
	float weave = 0.85 + 0.15 * mael_noise(p * vec2(40.0, 3.0));
	albedo *= weave * (0.8 + 0.2 * mael_fbm(p * 0.8));
	float rime = smoothstep(size.y * 0.5, size.y, p.y) * 0.45 + mael_fbm(p * 1.3 + world.xz * 0.1) * 0.2;
	albedo = mix(albedo, vec3(0.48, 0.54, 0.6), rime * 0.7);
	float snow = mael_snow(world, FRONT_FACING ? normal_world : -normal_world, 0.8);
	albedo = mix(albedo, vec3(0.62, 0.68, 0.74), snow);
	ALBEDO = albedo * mix(0.35, 1.0, mael_playable(world));
	ROUGHNESS = 0.9;
	BACKLIGHT = albedo * 0.2;
}
