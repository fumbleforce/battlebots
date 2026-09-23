shader_type spatial;
// Packed forest-clearing dirt: circling ruts, gravel, damp hollows, standing
// puddles, grassy rises and silted water beds. Fine relief is shading only.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform float arena_half_extent = 50.0;
uniform vec4 clusters[8];
uniform float water_level = -10.0;
varying vec3 wnormal; // Undisplaced terrain normal: drives material masks.
varying vec3 wpos;
// Photoscanned CC0 layers (assets/textures/woodland/CREDITS.md).
uniform sampler2D mud_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocky_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocky_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocky_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;

struct Layer {
	vec3 albedo;
	vec3 normal; // Tangent-space xy offsets in world x/z (y unused).
	vec3 arm;
	float height;
};

// Two differently rotated samples blended by noise hide tile repetition.
Layer sample_layer(sampler2D d, sampler2D n, sampler2D a, vec2 p, float tile) {
	vec2 uv1 = p / tile;
	vec2 uv2 = mat2(vec2(0.766, 0.643), vec2(-0.643, 0.766)) * (p / (tile * 1.37)) + vec2(0.31, 0.57);
	float m = smoothstep(0.3, 0.7, wl_noise(p / (tile * 2.3)));
	vec3 c = mix(texture(d, uv1).rgb, texture(d, uv2).rgb, m);
	vec3 t1 = texture(n, uv1).rgb * 2.0 - 1.0;
	vec3 t2 = texture(n, uv2).rgb * 2.0 - 1.0;
	t2.xy = mat2(vec2(0.766, -0.643), vec2(0.643, 0.766)) * t2.xy;
	vec3 t = mix(t1, t2, m);
	Layer l;
	l.albedo = c;
	l.normal = vec3(t.x, 0.0, -t.y);
	l.arm = mix(texture(a, uv1).rgb, texture(a, uv2).rgb, m);
	l.height = dot(c, vec3(0.333));
	return l;
}

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
	float edge = octagon_distance(p);
	float tread;
	float rut = ruts(p, tread);
	float hollow = big * 0.72 + mid * 0.28 + rut * 0.08;
	float wet = smoothstep(0.55, 0.67, hollow);
	float flat_ground = smoothstep(0.9, 0.985, wnormal.y);
	float puddle = smoothstep(0.75, 1.0, rut) * smoothstep(0.5, 0.7, wl_noise(p * 0.12 + 3.0)) * flat_ground * 0.85;
	// Grass survives along the walls, around outcrops and on raised, undriven ground.
	float grass = 1.0 - smoothstep(1.0, 4.0 + mid * 5.0, edge);
	for (int i = 0; i < 8; i++) {
		float d = distance(p, clusters[i].xy);
		grass = max(grass, 1.0 - smoothstep(clusters[i].z, clusters[i].z + 2.5 + mid * 4.0, d));
	}
	grass = max(grass, smoothstep(0.5, 1.4, wpos.y) * 0.9);
	grass = max(grass, smoothstep(0.55, 0.8, wl_fbm(p * 0.045 + 7.0, 4)) * 0.8);
	grass *= smoothstep(0.32, 0.55, mid + fine * 0.35) * (1.0 - rut) * (1.0 - wet * 0.6);
	float steep = 1.0 - smoothstep(0.55, 0.8, wnormal.y);
	grass *= 1.0 - steep;

	Layer mud = sample_layer(mud_diff, mud_nor, mud_arm, p, 3.2);
	// The scan is ochre clay; the reference mud is a dark, desaturated brown.
	float mud_lum = dot(mud.albedo, vec3(0.299, 0.587, 0.114));
	mud.albedo = mix(vec3(mud_lum), mud.albedo, 0.45) * vec3(0.92, 0.82, 0.72);
	Layer rocky = sample_layer(rocky_diff, rocky_nor, rocky_arm, p, 2.6);
	Layer ground = sample_layer(ground_diff, ground_nor, ground_arm, p, 3.0);
	Layer turf = sample_layer(grass_diff, grass_nor, grass_arm, p, 2.2);
	// Weights: worn rocky ground, lighter trodden dirt, churned mud, turf, rock.
	float w_rocky = 1.0;
	float w_ground = smoothstep(0.35, 0.7, big + (mid - 0.5) * 0.6) * 1.2;
	float w_mud = smoothstep(0.05, 0.6, rut) * 2.5 + wet * 1.5 + (1.0 - smoothstep(0.0, 2.5, edge)) * 0.8;
	float w_turf = grass * 3.0;
	// Height-aware blending: stones poke through mud, turf fills the hollows.
	vec4 w = vec4(w_rocky * (rocky.height + 0.3), w_ground * (ground.height + 0.3), w_mud * (1.1 - mud.height), w_turf * (turf.height + 0.4));
	w = pow(max(w, vec4(0.0001)), vec4(4.0));
	w /= w.x + w.y + w.z + w.w;
	vec3 col = rocky.albedo * w.x + ground.albedo * w.y + mud.albedo * w.z + turf.albedo * w.w;
	vec3 tn = rocky.normal * w.x + ground.normal * w.y + mud.normal * w.z + turf.normal * w.w;
	vec3 arm = rocky.arm * w.x + ground.arm * w.y + mud.arm * w.z + turf.arm * w.w;
	// Macro variation so the bowl never reads as one repeated swatch.
	col *= 0.82 + big * 0.3 + (mid - 0.5) * 0.18;
	// Cleat prints and churned lips in the ruts.
	col = mix(col, col * 0.6, tread * 0.35 * fade);
	col = mix(col, col * 1.12, smoothstep(0.0, 0.3, rut) * (1.0 - smoothstep(0.3, 0.6, rut)) * 0.5);
	col = mix(col, col * vec3(0.55, 0.5, 0.45), wet * 0.6);
	// Scorch marks from past fights.
	vec2 sc = wl_cells(p * 0.045 + 5.0);
	float scorch = (1.0 - smoothstep(0.05, 0.28, sc.x)) * step(0.72, sc.y);
	float rays = 0.6 + 0.4 * sin(atan(p.y, p.x) * 23.0 + sc.y * 40.0);
	col = mix(col, col * 0.18, scorch * rays * 0.8);
	// Standing water in the deepest ruts: dark, with a soft (never mirror) sheen.
	col = mix(col, col * 0.35 + vec3(0.02, 0.02, 0.018), puddle);
	// Steep faces are exposed granite, projected from the side.
	vec3 an = abs(wnormal);
	vec2 uvx = wpos.zy;
	vec2 uvz = wpos.xy;
	float bx = an.x / max(an.x + an.z, 0.001);
	vec3 rock_c = mix(texture(rock_diff, uvz / 5.0).rgb, texture(rock_diff, uvx / 5.0).rgb, bx);
	vec3 rock_arm_s = mix(texture(rock_arm, uvz / 5.0).rgb, texture(rock_arm, uvx / 5.0).rgb, bx);
	vec3 rock_t = mix(texture(rock_nor, uvz / 5.0).rgb, texture(rock_nor, uvx / 5.0).rgb, bx) * 2.0 - 1.0;
	col = mix(col, rock_c * 0.85, steep);
	arm = mix(arm, rock_arm_s, steep);
	col *= 1.0 - (1.0 - smoothstep(0.0, 1.2, edge)) * 0.25;
	ALBEDO = col;
	ROUGHNESS = mix(clamp(arm.g * (1.0 - wet * 0.25), 0.35, 1.0), 0.45, puddle);
	SPECULAR = 0.4;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.25;
	// World-space normal: terrain + rut tilt, plus scanned detail (flattened in puddles).
	vec3 base = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 detail = tn * (1.0 - puddle) * mix(0.6, 1.0, fade);
	vec3 side = vec3(0.0, rock_t.y, rock_t.x) * steep;
	vec3 nw = normalize(base + vec3(detail.x, 0.0, detail.z) + side * 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
