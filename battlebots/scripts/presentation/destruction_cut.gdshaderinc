// #72 generic cuts, shared by every destructible surface (bot wreck pieces,
// broken arena props). All geometry is in the mesh's own object space, so a
// piece keeps its cut however it tumbles. WreckPieces sets the instance values.
//
// A piece keeps the region inside all of its planes (dot(n, p) <= w) and
// outside the tunnel. Up to four planes make a saw half or a Voronoi shard;
// the tunnel is a railgun bore. cut_tear roughens each plane's seam with the
// same noise on both sides, so neighbouring pieces still meet exactly.
instance uniform vec4 cut_plane_0 = vec4(0.0);
instance uniform vec4 cut_plane_1 = vec4(0.0);
instance uniform vec4 cut_plane_2 = vec4(0.0);
instance uniform vec4 cut_plane_3 = vec4(0.0);
// Signed tear amplitude per plane (object units).
instance uniform vec4 cut_tear = vec4(0.0);
// Tunnel: xyz start and w radius (0 = none); xyz end and w tear amplitude.
instance uniform vec4 cut_tunnel_a = vec4(0.0);
instance uniform vec4 cut_tunnel_b = vec4(0.0);
// x heat 0..1, y glow band (object units), z tear frequency (per object unit), w soot 0..1.
instance uniform vec4 cut_state = vec4(0.0, 0.05, 8.0, 0.0);
uniform vec3 cut_interior : source_color = vec3(0.045, 0.04, 0.036);
uniform vec3 cut_heat_color : source_color = vec3(1.0, 0.36, 0.05);
uniform float cut_heat_energy = 7.0;
uniform vec3 cut_soot_dark : source_color = vec3(0.02, 0.025, 0.03);
uniform vec3 cut_soot_light : source_color = vec3(0.09, 0.07, 0.045);

// Object-space position; the including shader's vertex() writes it:
// cut_point = VERTEX; (varyings cannot be written from helper functions).
varying vec3 cut_point;

float cut_hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 39.425))) * 43758.5453);
}

float cut_value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(cut_hash(cell), cut_hash(cell + vec3(1, 0, 0)), f.x),
		mix(cut_hash(cell + vec3(0, 1, 0)), cut_hash(cell + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(cut_hash(cell + vec3(0, 0, 1)), cut_hash(cell + vec3(1, 0, 1)), f.x),
		mix(cut_hash(cell + vec3(0, 1, 1)), cut_hash(cell + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Two octaves in -1..1: jagged metal tearing rather than smooth waves.
float cut_noise(vec3 p) {
	return (cut_value_noise(p) * 0.65 + cut_value_noise(p * 3.1 + 7.0) * 0.35) * 2.0 - 1.0;
}

float cut_plane_distance(vec4 plane, float tear, vec3 p, float n) {
	return dot(plane.xyz, p) - plane.w + tear * n;
}

// x: how far p lies inside a cut-away region (> 0 = discard).
// y: distance to the nearest cut surface, for the glowing edge.
vec2 cut_evaluate(vec3 p) {
	float outside = -1e6;
	float edge = 1e6;
	float n = cut_noise(p * cut_state.z);
	vec4 planes[4] = vec4[](cut_plane_0, cut_plane_1, cut_plane_2, cut_plane_3);
	for (int i = 0; i < 4; i++) {
		if (dot(planes[i].xyz, planes[i].xyz) < 0.25) continue;
		float s = cut_plane_distance(planes[i], cut_tear[i], p, n);
		outside = max(outside, s);
		edge = min(edge, abs(s));
	}
	if (cut_tunnel_a.w > 0.0) {
		vec3 a = cut_tunnel_a.xyz;
		vec3 ab = cut_tunnel_b.xyz - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		float s = cut_tunnel_a.w + cut_tunnel_b.w * n - length(p - a - ab * t);
		outside = max(outside, s);
		edge = min(edge, abs(s));
	}
	return vec2(outside, edge);
}

// Call at the end of fragment() with cut_point, after the surface is shaded. Back faces are
// the hollow inside seen through a cut: dark, rough, hot near the seam.
void cut_fragment(vec3 p, bool front_facing, inout vec3 albedo, inout float metallic, inout float roughness, inout vec3 emission, inout float normal_depth) {
	vec2 cut = cut_evaluate(p);
	if (cut.x > 0.0) discard;
	float soot = cut_value_noise(p * 8.0) * 0.7 + cut_value_noise(p * 43.0) * 0.3;
	albedo = mix(albedo, mix(cut_soot_dark, cut_soot_light, soot), cut_state.w * 0.85);
	roughness = mix(roughness, 0.8 + soot * 0.15, cut_state.w);
	if (!front_facing) {
		albedo = cut_interior * (0.7 + soot * 0.6);
		metallic = 0.35;
		roughness = 0.85;
		normal_depth = 0.0;
	}
	float band = max(cut_state.y, 1e-4);
	float glow = cut_state.x * exp(-cut.y / band);
	emission += cut_heat_color * cut_heat_energy * glow * glow;
	albedo = mix(albedo, cut_heat_color * 0.4, clamp(glow, 0.0, 1.0) * 0.5);
}
