shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// The frozen maelstrom's ice sheet (#102), aiming for photographic snow rather
// than drawn detail: wind-packed snow with sastrugi ripples and grain, subtle
// value shifts where drifts deepen or thin, and a few wind-scoured windows of
// grey-blue glacier ice, dusted over and ragged at the edges. No outlines.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
uniform float twist = 0.3;
uniform vec3 snow_color : source_color = vec3(0.6, 0.66, 0.72);
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.63);
uniform vec3 grey_ice : source_color = vec3(0.24, 0.32, 0.39);
uniform vec3 dark_ice : source_color = vec3(0.1, 0.14, 0.18);
varying vec3 world;
varying vec3 normal_world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float r = max(length(world.xz), 1.0);
	float spiral = atan(world.z, world.x) - log(r / maelstrom_eye) / twist;
	vec2 bent = world.xz + vec2(mael_fbm(world.xz * 0.04), mael_fbm(world.xz * 0.04 + 9.0)) * 14.0;
	// Drift depth: broad, soft value changes (deep drifts brighter, packed crust duller).
	float drift = mael_fbm(bent * 0.018) * 0.65 + mael_fbm(bent * 0.07) * 0.35;
	vec3 snow = mix(packed_color, snow_color, smoothstep(0.3, 0.7, drift));
	// Wind-scoured windows onto the ice, their edges broken up by grain.
	float grain = mael_noise(world.xz * 3.1) * 0.5 + mael_noise(world.xz * 9.7) * 0.3 + mael_noise(world.xz * 23.0) * 0.2;
	float scour = mael_fbm(bent * 0.022 + 5.0) + sin(spiral * 2.0) * 0.08 + (grain - 0.5) * 0.08;
	float bare = smoothstep(0.6, 0.66, scour);
	vec3 ice = mix(grey_ice, dark_ice, smoothstep(0.4, 0.8, mael_fbm(world.xz * 0.05 + 3.0)));
	// Snow dust lying in the ice's hollows.
	ice = mix(ice, packed_color * 0.9, smoothstep(0.45, 0.75, mael_noise(world.xz * 0.9)) * 0.45);
	vec3 albedo = mix(snow, ice, bare);
	// Sastrugi: wind ribs across the spin (70 per turn: seamless in angle).
	float rib = fract(spiral * 70.0 / TAU + mael_fbm(world.xz * 0.3) * 3.0);
	float ribs = smoothstep(0.0, 0.08, rib) * (1.0 - smoothstep(0.08, 1.0, rib));
	albedo *= 0.94 + 0.08 * grain + 0.04 * ribs * (1.0 - bare);
	// Cliffs: sheer, vertically striated ice, darkening as it drops.
	float flatness = smoothstep(0.55, 0.9, normal_world.y);
	float striae = 0.55 + 0.45 * mael_noise(vec2(world.x * 0.9, world.y * 0.08)) * mael_noise(vec2(world.z * 0.9, world.y * 0.08 + 5.0)) * 2.0;
	vec3 wall = mix(dark_ice * 0.5, grey_ice, clamp((world.y + 8.0) / 16.0, 0.0, 1.0)) * striae;
	albedo = mix(albedo, wall, 1.0 - flatness);
	ALBEDO = albedo * mix(0.45, 1.0, mael_playable(world));
	ROUGHNESS = mix(0.85, 0.35, bare);
	SPECULAR = mix(0.35, 0.55, bare);
	// Snow grain and wind ribs in the normals; ice is smoother.
	vec2 tilt = vec2((grain - 0.5) * 0.22 + ribs * 0.12, (mael_noise(world.zx * 5.3) - 0.5) * 0.2) * (1.0 - bare * 0.6);
	NORMAL_MAP = normalize(vec3(0.5 + tilt.x, 0.5 + tilt.y, 1.0));
}
