// Shared Woodland procedural helpers. Heights are metres; wl_bump turns a
// procedural height into a physically scaled shading normal (surface gradient).
float wl_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float wl_hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
vec2 wl_hash22(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}
float wl_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wl_hash(i), wl_hash(i + vec2(1, 0)), f.x), mix(wl_hash(i + vec2(0, 1)), wl_hash(i + 1.0), f.x), f.y);
}
float wl_noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(wl_hash3(i), wl_hash3(i + vec3(1, 0, 0)), f.x), mix(wl_hash3(i + vec3(0, 1, 0)), wl_hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(wl_hash3(i + vec3(0, 0, 1)), wl_hash3(i + vec3(1, 0, 1)), f.x), mix(wl_hash3(i + vec3(0, 1, 1)), wl_hash3(i + 1.0), f.x), f.y), f.z);
}
float wl_fbm(vec2 p, int octaves) {
	float sum = 0.0, amp = 0.5, norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += wl_noise(p) * amp;
		norm += amp;
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + 17.3;
		amp *= 0.5;
	}
	return sum / norm;
}
float wl_fbm3(vec3 p, int octaves) {
	float sum = 0.0, amp = 0.5, norm = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += wl_noise3(p) * amp;
		norm += amp;
		p = p * 2.03 + vec3(11.7, 5.3, 23.1);
		amp *= 0.5;
	}
	return sum / norm;
}
// Ridged noise for cracks and fractured stone edges (1 at the crack line).
float wl_ridge3(vec3 p) { return 1.0 - abs(wl_noise3(p) * 2.0 - 1.0); }
// Voronoi distance to the nearest feature point; returns (distance, cell id).
vec2 wl_cells(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float best = 8.0, id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = wl_hash22(i + g);
			float d = length(g + o - f);
			if (d < best) { best = d; id = wl_hash(i + g); }
		}
	}
	return vec2(best, id);
}
// View-space surface-gradient bump. vertex/normal are fragment VERTEX/NORMAL.
vec3 wl_bump(vec3 vertex, vec3 normal, float height, float strength) {
	vec3 dpdx = dFdx(vertex), dpdy = dFdy(vertex);
	float dhx = dFdx(height), dhy = dFdy(height);
	vec3 r1 = cross(dpdy, normal), r2 = cross(normal, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	vec3 bumped = abs(det) * normal - grad * strength;
	// Degenerate derivatives (grazing angles, helper lanes, tiny triangles)
	// would normalize a zero vector into NaN, which bloom and TAA smear into
	// flickering white blobs. Fall back to the unperturbed normal instead.
	float len2 = dot(bumped, bumped);
	return len2 > 1e-20 && !isnan(len2) && !isinf(len2) ? bumped * inversesqrt(len2) : normal;
}
// World-space triplanar sampling for scanned maps. Returns the blended colour.
vec3 wl_triplanar(sampler2D t, vec3 p, vec3 n, float tile) {
	vec3 w = pow(abs(n), vec3(4.0)) + 1e-5;
	w /= w.x + w.y + w.z;
	return texture(t, p.zy / tile).rgb * w.x + texture(t, p.xz / tile).rgb * w.y + texture(t, p.xy / tile).rgb * w.z;
}
// Triplanar tangent-space normal map, returned as a world-space normal (UDN blend).
vec3 wl_triplanar_normal(sampler2D t, vec3 p, vec3 n, float tile, float strength) {
	vec3 w = pow(abs(n), vec3(4.0)) + 1e-5;
	w /= w.x + w.y + w.z;
	vec3 tx = (texture(t, p.zy / tile).rgb * 2.0 - 1.0) * strength;
	vec3 ty = (texture(t, p.xz / tile).rgb * 2.0 - 1.0) * strength;
	vec3 tz = (texture(t, p.xy / tile).rgb * 2.0 - 1.0) * strength;
	vec3 nx = vec3(0.0, tx.y, tx.x) * sign(n.x);
	vec3 ny = vec3(ty.x, 0.0, -ty.y);
	vec3 nz = vec3(tz.x, tz.y, 0.0) * sign(n.z);
	vec3 r = n + nx * w.x + ny * w.y + nz * w.z;
	float len2 = dot(r, r);
	return len2 > 1e-12 ? r * inversesqrt(len2) : n;
}
