// Elysium (#115) shared helpers. Exact integer hashing (PCG) of float bits:
// the sin() hash differs between neighbouring cells on the GPU (see
// docs/art/ARENA_ENVIRONMENTS.md, "Triangle shards").

uint ely_pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float ely_hash2(vec2 p) {
	ivec2 i = ivec2(floor(p));
	return float(ely_pcg(uint(i.x) + ely_pcg(uint(i.y)))) / 4294967295.0;
}

float ely_hash3(vec3 p) {
	ivec3 i = ivec3(floor(p));
	return float(ely_pcg(uint(i.x) + ely_pcg(uint(i.y) + ely_pcg(uint(i.z))))) / 4294967295.0;
}

float ely_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = ely_hash2(i);
	float b = ely_hash2(i + vec2(1.0, 0.0));
	float c = ely_hash2(i + vec2(0.0, 1.0));
	float d = ely_hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float ely_noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = ely_hash3(i);
	float n100 = ely_hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = ely_hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = ely_hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = ely_hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = ely_hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = ely_hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = ely_hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float ely_fbm2(vec2 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * ely_noise2(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return sum;
}

float ely_fbm3(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * ely_noise3(p);
		p = p * 2.03 + vec3(11.7, 3.1, 7.9);
		amp *= 0.5;
	}
	return sum;
}

// Veined white marble: warped sine bands through fbm, value 0 (vein) .. 1 (stone).
float ely_marble(vec3 p) {
	float warp = ely_fbm3(p * 0.35, 5);
	float bands = sin((p.x * 0.6 + p.y * 0.25 + p.z * 0.45) + warp * 9.0);
	float vein = pow(1.0 - abs(bands), 14.0);
	float fine = pow(1.0 - abs(sin(p.z * 1.7 - p.x * 0.9 + ely_fbm3(p * 1.3 + 4.0, 4) * 7.0)), 30.0);
	return clamp(1.0 - vein * 0.75 - fine * 0.35, 0.0, 1.0);
}

// Triplanar sample of a scan, blended by the surface normal.
vec4 ely_triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	return texture(tex, p.zy * scale) * w.x + texture(tex, p.xz * scale) * w.y + texture(tex, p.xy * scale) * w.z;
}

vec3 ely_safe_normalize(vec3 v) {
	float len = length(v);
	return len > 1e-6 ? v / len : vec3(0.0, 1.0, 0.0);
}
