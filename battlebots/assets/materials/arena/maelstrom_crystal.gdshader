shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Glacier ice (#102): seracs, icicles, floes, icebergs and the far ice walls.
// The same ice as the sheet's scoured windows: grey-blue with a slow tonal
// drift, dark melt streaks running down the faces and fine scratches; faintly
// translucent, snow lying on every ledge. No cracked-cell pattern.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
uniform vec3 core : source_color = vec3(0.1, 0.14, 0.18);
uniform vec3 surface : source_color = vec3(0.26, 0.34, 0.41);
uniform vec3 translucent : source_color = vec3(0.07, 0.14, 0.2);
uniform float snow_amount = 1.0;
uniform float abyss_top = -6.0;
uniform float abyss_bottom = -40.0;
varying vec3 world;
varying vec3 normal_world;
varying float tint;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.r;
}

void fragment() {
	vec3 n = FRONT_FACING ? normal_world : -normal_world;
	vec2 across = vec2(world.x + world.z, world.y);
	// Slow tonal drift through the ice, per piece.
	float drift = mael_fbm(world.xz * 0.04 + world.y * 0.03 + tint * 7.0);
	vec3 albedo = mix(surface, core, drift * 0.8);
	// Melt streaks running down the faces, and fine scratches.
	float streaks = pow(abs(sin(across.x * 1.7 + mael_fbm(across * vec2(0.3, 0.05)) * 5.0)), 10.0);
	albedo *= 1.0 - streaks * 0.2;
	albedo = mix(albedo, surface * 1.2, mael_fbm(across * vec2(1.4, 0.25)) * 0.25);
	float snow = mael_snow(world, n, snow_amount);
	albedo = mix(albedo, vec3(0.6, 0.66, 0.72) * (0.92 + 0.08 * mael_soft(world.xz * 3.0)), snow);
	float abyss = smoothstep(abyss_top, abyss_bottom, world.y);
	albedo *= 1.0 - abyss * 0.95;
	ALBEDO = albedo * mix(0.62, 1.0, mael_playable(world));
	ROUGHNESS = mix(0.32 + 0.12 * drift, 0.6, snow);
	SPECULAR = 0.55;
	BACKLIGHT = translucent * (1.0 - snow) * (1.0 - abyss);
	NORMAL_MAP = normalize(vec3(0.5 + (streaks - 0.5) * 0.12, 0.5 + (drift - 0.5) * 0.15, 1.0));
}
