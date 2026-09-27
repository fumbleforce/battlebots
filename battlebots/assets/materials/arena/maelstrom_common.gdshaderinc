// Shared Frozen Maelstrom helpers (#102). Integer (PCG) hashing only: the sin
// hash shards between noise cells on the GPU (docs/art/ARENA_ENVIRONMENTS.md).
uniform float maelstrom_rim = 126.0;
uniform float maelstrom_eye = 16.0;

uint mael_pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}
float mael_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	return float(mael_pcg(q.x + mael_pcg(q.y))) / 4294967295.0;
}
vec2 mael_hash2(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	uint h = mael_pcg(q.x + mael_pcg(q.y));
	return vec2(float(h & 65535u), float(h >> 16u)) / 65535.0;
}
float mael_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mael_hash(i), mael_hash(i + vec2(1, 0)), f.x), mix(mael_hash(i + vec2(0, 1)), mael_hash(i + vec2(1, 1)), f.x), f.y);
}
// Each octave is rotated so the value-noise lattice never lines up into squares.
float mael_fbm(vec2 p) {
	const mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 q = turn * p;
	float v = mael_noise(q) * 0.5;
	q = turn * q * 2.07 + 13.1;
	v += mael_noise(q) * 0.3;
	q = turn * q * 2.08 - 7.7;
	return v + mael_noise(q) * 0.2;
}
// Smooth single-scale noise without lattice squares (two rotated samples).
float mael_soft(vec2 p) {
	return 0.5 * (mael_noise(p) + mael_noise(mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * p + 5.3));
}
// Voronoi: x = distance to the nearest site, y = gap to the second (cracks at y ~ 0).
vec2 mael_cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = mael_hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return vec2(d1, d2 - d1);
}
// Like mael_cells, also returning the nearest site's hash (a facet id).
vec2 mael_cells_id(vec2 p, out vec2 site) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	site = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = mael_hash2(i + g);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; site = mael_hash2(i + g + vec2(71.0, 19.0)); } else if (d < d2) { d2 = d; }
		}
	}
	return vec2(d1, d2 - d1);
}
// Outside the ice ring (the open sea and the eye) everything is shaded darker.
float mael_playable(vec3 world) {
	float r = length(world.xz);
	return (1.0 - smoothstep(maelstrom_rim + 1.0, maelstrom_rim + 14.0, r)) * smoothstep(maelstrom_eye - 8.0, maelstrom_eye - 1.0, r);
}
// Wind-packed snow on up-facing surfaces.
float mael_snow(vec3 world, vec3 normal_world, float amount) {
	float n = mael_fbm(world.xz * 0.9 + world.y * 0.4);
	return smoothstep(0.55, 0.8, normal_world.y + (n - 0.5) * 0.5) * amount;
}
vec3 mael_triplanar(sampler2D tex, vec3 world, vec3 normal_world, float scale) {
	vec3 w = pow(abs(normal_world), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.0001);
	return texture(tex, world.zy * scale).rgb * w.x + texture(tex, world.xz * scale).rgb * w.y + texture(tex, world.xy * scale).rgb * w.z;
}
