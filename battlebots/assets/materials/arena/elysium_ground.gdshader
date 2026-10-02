shader_type spatial;
// Elysium (#115) island tops: sunlit lawns strewn with flowers, and white
// marble paving with gold inlay on the Sanctum, the bridges and the paths.
// COLOR.r = paving share (Sanctum and bridges), COLOR.g = closeness to the
// island edge (1 at the rim), COLOR.b = polar (Sanctum) paving instead of
// straight courses. The Halo's promenade, paths and well kerbs are drawn
// here from the layout, so their edges stay crisp.
render_mode cull_back;
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 lawn_tint = vec3(0.42, 0.78, 0.2);
uniform vec3 lawn_gold = vec3(1.0, 0.86, 0.45);
uniform vec3 marble = vec3(0.93, 0.91, 0.87);
uniform vec3 gold = vec3(1.0, 0.74, 0.32);
// Radii (m) of the gold rings inlaid in the Sanctum's paving.
uniform vec4 inlay_rings = vec4(6.0, 19.5, 34.0, 44.5);
uniform float spokes = 12.0;
// Promenade ring (radius, half width), half width of the paths along the
// bridge axes (data/elysium_arena.json bridges.angles: the x and z axes), and
// the well kerbs (x, z, radius).
uniform vec2 promenade = vec2(96.0, 5.5);
uniform float radial_path = 10.0;
uniform vec3 kerbs[4];

varying vec3 world_pos;
varying vec3 paint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	paint = COLOR.rgb;
}

// Distance (m) to the nearest grout line, the tile id and whether it is gold.
vec3 tiles(vec2 p, float polar, out float gold_line) {
	gold_line = 0.0;
	if (polar > 0.5) {
		float r = length(p);
		float ring_w = 2.4;
		float ring = floor(r / ring_w);
		float along = atan(p.y, p.x) * max(r, 1.0);
		float seg_len = 2.8;
		float shift = ely_hash2(vec2(ring, 3.0)) * seg_len;
		float seg = floor((along + shift) / seg_len);
		float dr = min(fract(r / ring_w), 1.0 - fract(r / ring_w)) * ring_w;
		float da = min(fract((along + shift) / seg_len), 1.0 - fract((along + shift) / seg_len)) * seg_len;
		// Gold rings and the radiant spokes on the dais.
		vec4 dist = abs(vec4(r) - inlay_rings);
		float ring_gold = min(min(dist.x, dist.y), min(dist.z, dist.w));
		float sector = atan(p.y, p.x) / (6.2831853 / spokes);
		float spoke = abs(fract(sector + 0.5) - 0.5) * (6.2831853 / spokes) * r;
		float spoke_gold = r > inlay_rings.x && r < inlay_rings.y ? spoke : 1e3;
		gold_line = 1.0 - smoothstep(0.08, 0.2, min(ring_gold, spoke_gold));
		return vec3(min(dr, da), ring, seg);
	}
	vec2 size = vec2(3.0, 1.6);
	float row = floor(p.y / size.y);
	float x = p.x / size.x + ely_hash2(vec2(row, 7.0));
	float col = floor(x);
	float dx = min(fract(x), 1.0 - fract(x)) * size.x;
	float dy = min(fract(p.y / size.y), 1.0 - fract(p.y / size.y)) * size.y;
	return vec3(min(dx, dy), row, col);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	// Lawn: the grass scan at two scales (no visible repeat), graded to a lush,
	// sunlit heavenly green with golden drifts.
	vec3 g1 = texture(grass_tex, p * 0.21).rgb;
	vec3 g2 = texture(grass_tex, p * 0.047 + vec2(0.31, 0.77)).rgb;
	vec3 grass = mix(g1, g2, 0.45);
	float lum = dot(grass, vec3(0.3, 0.55, 0.15));
	float drift = ely_fbm2(p * 0.025, 4);
	// Meadow patches at several scales so the lawn reads from afar: deep and
	// sunny greens, golden drifts and pale swathes of flowers.
	float meadow = ely_fbm2(p * 0.012 + 7.0, 4);
	float swathe = ely_fbm2(p * 0.045 + 3.0, 4);
	vec3 base_green = mix(vec3(0.26, 0.55, 0.14), vec3(0.55, 0.8, 0.24), smoothstep(0.3, 0.7, meadow));
	vec3 lawn = (0.4 + lum * 1.25) * mix(base_green, lawn_gold, smoothstep(0.5, 0.78, drift) * 0.45);
	lawn = mix(lawn, vec3(0.95, 0.93, 0.8) * (0.75 + lum * 0.4), smoothstep(0.6, 0.75, swathe) * 0.45);
	lawn *= 0.9 + 0.2 * ely_noise2(p * 0.18);
	// Flowers: tiny white, pale gold and blush blooms, faded with distance
	// before they would shimmer.
	vec2 cell = p * 1.6;
	float h = ely_hash2(cell);
	vec2 centre = floor(cell) + 0.25 + 0.5 * vec2(ely_hash2(cell + 19.0), ely_hash2(cell + 41.0));
	float bloom = 1.0 - smoothstep(0.05, 0.11, length(cell - centre));
	bloom *= step(0.8 - 0.25 * smoothstep(0.35, 0.65, drift), h) * (1.0 - smoothstep(25.0, 70.0, dist));
	vec3 petal = h > 0.95 ? vec3(1.0, 0.82, 0.86) : (h > 0.89 ? vec3(1.0, 0.88, 0.45) : vec3(1.0, 0.99, 0.95));
	lawn = mix(lawn, petal, bloom);
	// The Halo's paved ways: crisp, anti-aliased edges.
	float r = length(p);
	float aa = max(fwidth(r), 0.02);
	float ring = 1.0 - smoothstep(promenade.y - aa, promenade.y + aa, abs(r - promenade.x));
	float path = 1.0 - smoothstep(radial_path - aa, radial_path + aa, min(abs(p.x), abs(p.y)));
	float kerb = 0.0;
	for (int i = 0; i < 4; i++) {
		kerb = max(kerb, 1.0 - smoothstep(kerbs[i].z + 3.0 - aa, kerbs[i].z + 3.0 + aa, distance(p, kerbs[i].xy)));
	}
	float pave = max(smoothstep(0.35, 0.65, paint.r), max(max(ring, path), kerb));
	// Marble paving with gold inlay.
	float gold_line;
	vec3 t = tiles(p, max(paint.b, ring * (1.0 - path)), gold_line);
	float stone_detail = dot(texture(stone_tex, p * 0.17).rgb, vec3(0.333));
	float veins = ely_marble(vec3(p.x, 0.0, p.y) * 0.6 + vec3(t.y * 3.1, 0.0, t.z * 1.7));
	float tile_tone = 0.94 + 0.08 * ely_hash2(t.yz + 5.0);
	vec3 paving = marble * tile_tone * mix(0.82, 1.0, veins) * (0.86 + 0.28 * stone_detail);
	float grout = 1.0 - smoothstep(0.03, 0.07, t.x);
	paving = mix(paving, paving * 0.62, grout * (1.0 - gold_line));

	vec3 albedo = mix(lawn, paving, pave);
	float is_gold = gold_line * pave;
	albedo = mix(albedo, gold, is_gold);
	ALBEDO = albedo;
	METALLIC = is_gold;
	ROUGHNESS = mix(mix(0.92, 0.5, pave), 0.25, is_gold);
	SPECULAR = mix(0.35, 0.42, pave);
	vec3 n_grass = texture(grass_nor, p * 0.21).rgb;
	vec3 n_stone = mix(texture(stone_nor, p * 0.17).rgb, vec3(0.5, 0.5, 1.0), 0.6);
	NORMAL_MAP = mix(n_grass, n_stone, pave);
	NORMAL_MAP_DEPTH = mix(1.0, 0.6, pave);
	// A whisper of glow from the gold so it catches the sun.
	EMISSION = gold * is_gold * 0.08;
}
