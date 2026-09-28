shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Frozen Maelstrom wrecks and rock (#102). One shader, one material per kit
// slot (and per fleet for fleet colours). Vertex colour: r = per-piece tint.
// Everything carries rime and wind-packed snow; hull interiors (back faces)
// fall into shadow.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
// 0 wood, 1 deck, 2 paint, 3 gilt/silver trim, 4 iron, 5 rope, 6 frozen skin,
// 7 tabard cloth, 8 basalt, 9 black glass, 10 lantern.
uniform int kind = 0;
uniform vec3 base_color : source_color = vec3(0.2, 0.13, 0.08);
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.5;
uniform float frost = 1.0;
varying vec3 world;
varying vec3 normal_world;
varying float tint;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.r;
}

vec3 unpack(vec4 s) { return s.xyz * 2.0 - 1.0; }

// Triplanar scanned normals (whiteout blend) for rock, returned in world space.
vec3 rock_normal(vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(dot(w, vec3(1.0)), 0.0001);
	vec3 nx = unpack(texture(detail_normal, world.zy * scale));
	vec3 ny = unpack(texture(detail_normal, world.xz * scale));
	vec3 nz = unpack(texture(detail_normal, world.xy * scale));
	nx = vec3(nx.xy + n.zy, abs(nx.z) * n.x);
	ny = vec3(ny.xy + n.xz, abs(ny.z) * n.y);
	nz = vec3(nz.xy + n.xy, abs(nz.z) * n.z);
	return normalize(nx.zyx * w.x + ny.xzy * w.y + nz.xyz * w.z);
}

void fragment() {
	vec3 n = FRONT_FACING ? normal_world : -normal_world;
	if (kind == 8) {
		n = rock_normal(n, detail_scale);
		NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	}
	vec3 scan = kind == 8 ? mael_triplanar(detail, world, n, detail_scale) : texture(detail, UV * detail_scale).rgb;
	float lum = dot(scan, vec3(0.3, 0.55, 0.15));
	vec3 albedo = base_color * (0.55 + lum * 0.9) * (0.85 + 0.3 * tint);
	float rough = 0.85;
	float metal = 0.0;
	vec3 emit = vec3(0.0);
	if (kind == 2) {
		// Fleet paint, chipped and flaking back to the tarred planks.
		float chip = mael_fbm(UV * 2.3 + tint * 17.0);
		vec3 wood = vec3(0.12, 0.08, 0.05) * (0.6 + lum);
		albedo = mix(base_color * (0.75 + lum * 0.5), wood, smoothstep(0.62, 0.7, chip));
		rough = 0.7;
	} else if (kind == 3) {
		albedo = base_color * (0.7 + lum * 0.5);
		metal = 1.0;
		rough = 0.5 + 0.25 * mael_noise(UV * 4.0);
	} else if (kind == 4) {
		float rust = smoothstep(0.55, 0.8, mael_fbm(UV * 1.7 + world.y * 0.3));
		albedo = mix(base_color * (0.6 + lum), vec3(0.24, 0.08, 0.03), rust * 0.7);
		metal = 1.0 - rust;
		rough = mix(0.45, 0.9, rust);
	} else if (kind == 6) {
		albedo = base_color * (0.9 + 0.2 * tint);
		rough = 0.45;
	} else if (kind == 7) {
		albedo = base_color * (0.75 + 0.35 * mael_noise(UV * 9.0));
		rough = 0.95;
	} else if (kind == 8) {
		// Basalt: near-black with blue-grey mineral banding and an ice glaze.
		float band = 0.8 + 0.2 * abs(sin(world.y * 0.9 + mael_noise(world.xz * 0.2) * 3.0));
		albedo = base_color * (0.45 + lum * 1.1) * band;
		rough = 0.55;
	} else if (kind == 9) {
		albedo = vec3(0.005, 0.008, 0.012);
		rough = 0.08;
	} else if (kind == 10) {
		albedo = vec3(0.35, 0.18, 0.05);
		// A last guttering ember: the only warmth left on the ice.
		emit = vec3(1.0, 0.42, 0.12) * (0.5 + 0.35 * sin(TIME * 2.3 + tint * 20.0) * sin(TIME * 0.7));
		rough = 0.2;
	}
	// Rime: a pale blue-white bloom, heaviest low down where the spray froze.
	float rime = frost * clamp(0.3 + 0.4 * mael_fbm(world.xz * 0.7 + world.y) + 0.35 * smoothstep(3.0, 0.0, world.y), 0.0, 0.9);
	if (kind == 9 || kind == 10) rime *= 0.15;
	if (kind <= 2) rime *= 0.55; // timber stays brown under the frost
	albedo = mix(albedo, vec3(0.5, 0.57, 0.63) * (albedo * 0.6 + 0.5), rime * 0.6);
	float snow = mael_snow(world, n, frost);
	albedo = mix(albedo, vec3(0.62, 0.68, 0.74), snow);
	rough = mix(rough, 0.7, snow);
	metal *= 1.0 - snow;
	if (!FRONT_FACING) {
		albedo *= 0.22; // hull interiors
	}
	ALBEDO = albedo * mix(0.35, 1.0, mael_playable(world));
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = kind == 8 ? vec3(0.5, 0.5, 1.0) : mix(texture(detail_normal, UV * detail_scale).rgb, vec3(0.5, 0.5, 1.0), snow > 0.5 ? 0.6 : 0.0);
	NORMAL_MAP_DEPTH = 0.8;
	EMISSION = emit;
}
