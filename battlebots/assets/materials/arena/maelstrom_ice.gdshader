shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// The frozen maelstrom's ice sheet (#102). Mostly wind-packed snow, scoured
// into ripples; where the wind has stripped it, grey-blue glacier ice shows,
// scarred by the whirlpool's frozen flow and split by dark fractures. The rim
// and eye cliffs are sheer, striated ice sinking into shadow.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
uniform float twist = 0.3;
uniform vec3 dark_ice : source_color = vec3(0.07, 0.1, 0.13);
uniform vec3 grey_ice : source_color = vec3(0.26, 0.34, 0.41);
uniform vec3 snow_color : source_color = vec3(0.6, 0.66, 0.72);
uniform vec3 crack_color : source_color = vec3(0.03, 0.045, 0.06);
varying vec3 world;
varying vec3 normal_world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float r = max(length(world.xz), 1.0);
	float ang = atan(world.z, world.x);
	float spiral = ang - log(r / maelstrom_eye) / twist;
	vec2 bent = world.xz + vec2(mael_fbm(world.xz * 0.05), mael_fbm(world.xz * 0.05 + 9.0)) * 18.0;
	float warp = mael_fbm(world.xz * 0.025) * 2.5;
	// Exposed ice: stripped along the spiral flow and in broad scoured patches.
	float scour = mael_fbm(bent * 0.03) + sin(spiral * 2.0 + warp) * 0.18 - smoothstep(maelstrom_eye + 30.0, maelstrom_eye + 4.0, r) * 0.3;
	float exposed = smoothstep(0.52, 0.53, scour);
	float band = pow(1.0 - abs(sin(spiral * 29.0 + warp)), 5.0) * smoothstep(0.3, 0.7, mael_noise(world.xz * 0.09));
	vec3 ice = mix(grey_ice, dark_ice, smoothstep(0.45, 0.8, mael_fbm(world.xz * 0.06 + 3.0)));
	ice = mix(ice, grey_ice * 1.35, band * 0.35);
	// Fractures: thin, dark, wandering.
	vec2 site;
	vec2 split = mael_cells_id(bent * 0.045, site);
	float crack = (1.0 - smoothstep(0.0, 0.012, split.y)) * smoothstep(0.3, 0.55, mael_noise(bent * 0.07));
	vec2 fine_site;
	vec2 fine = mael_cells_id(bent * 0.3, fine_site);
	float hair = (1.0 - smoothstep(0.0, 0.02, fine.y)) * smoothstep(0.55, 0.8, mael_noise(bent * 0.12 + 4.0));
	// Snow: packed, rippled by the wind across the flow, grimy where thin.
	float ripple = sin(spiral * 150.0 + mael_fbm(world.xz * 0.4) * 6.0);
	float grain = mael_noise(world.xz * 2.3) * 0.5 + mael_noise(world.xz * 7.1) * 0.5;
	vec3 snow = snow_color * (0.86 + 0.08 * ripple + 0.1 * grain);
	float flatness = smoothstep(0.55, 0.9, normal_world.y);
	float thin = smoothstep(0.47, 0.515, scour);
	vec3 albedo = mix(snow, mix(snow * 0.8, ice, 0.5), thin);
	albedo = mix(albedo, ice, exposed);
	albedo = mix(albedo, crack_color, crack * max(exposed, 0.35));
	albedo = mix(albedo, crack_color * 2.0, hair * exposed * 0.5);
	// Cliffs: sheer, vertically striated ice, darkening as it drops.
	float cliff = 1.0 - flatness;
	float striae = 0.55 + 0.45 * mael_noise(vec2(world.x * 0.9, world.y * 0.08)) * mael_noise(vec2(world.z * 0.9, world.y * 0.08 + 5.0)) * 2.0;
	vec3 wall = mix(dark_ice * 0.4, grey_ice, clamp((world.y + 16.0) / 16.0, 0.0, 1.0)) * striae;
	albedo = mix(albedo, wall, cliff);
	ALBEDO = albedo * mix(0.4, 1.0, mael_playable(world));
	ROUGHNESS = mix(0.82, 0.32, exposed) * (1.0 - cliff * 0.3);
	SPECULAR = mix(0.35, 0.55, exposed);
	// Wind ripples and grain in the snow, plate tilts in the ice.
	float fleck = mael_noise(world.xz * 19.0) - 0.5;
	vec2 tilt = mix(vec2(ripple * 0.1 + fleck * 0.08, (grain - 0.5) * 0.14), (fine_site - 0.5) * 0.14, exposed);
	NORMAL_MAP = normalize(vec3(0.5 + tilt.x, 0.5 + tilt.y, 1.0));
}
