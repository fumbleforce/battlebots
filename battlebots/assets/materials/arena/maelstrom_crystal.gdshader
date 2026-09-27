shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
// Glacier ice (#102): seracs, icicles, floes, the eye's frozen vortex and the
// far ice walls. Dense, old, bubble-clouded ice: grey-blue and frosted, dark
// in its cracks, faintly translucent where the light comes through, heavy with
// snow on every ledge. Deep in the eye it sinks into black.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
uniform vec3 core : source_color = vec3(0.05, 0.08, 0.11);
uniform vec3 surface : source_color = vec3(0.3, 0.39, 0.47);
uniform vec3 translucent : source_color = vec3(0.08, 0.16, 0.22);
uniform float snow_amount = 1.0;
uniform float abyss_top = -3.0;
uniform float abyss_bottom = -30.0;
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
	vec3 w = abs(n);
	vec2 plane = w.y > max(w.x, w.z) ? world.xz : (w.x > w.z ? world.zy : world.xy);
	// Vertical melt streaks and bubble clouds.
	float streak = mael_noise(vec2(plane.x * 1.4, world.y * 0.15));
	float cloudy = mael_fbm(plane * 0.7 + tint * 7.0);
	vec2 cells = mael_cells(plane * 0.45 + tint * 9.0);
	float crack = (1.0 - smoothstep(0.0, 0.02, cells.y)) * smoothstep(0.4, 0.7, mael_noise(plane * 0.3));
	vec3 albedo = mix(core, surface, 0.35 + 0.35 * cloudy + 0.2 * streak + 0.15 * tint);
	albedo = mix(albedo, core * 0.5, crack * 0.8);
	// Hoarfrost bloom and snow on ledges.
	albedo = mix(albedo, vec3(0.55, 0.62, 0.68), smoothstep(0.55, 0.85, mael_fbm(plane * 2.5)) * 0.35);
	float snow = mael_snow(world, n, snow_amount);
	albedo = mix(albedo, vec3(0.62, 0.68, 0.74) * (0.9 + 0.1 * mael_noise(world.xz * 3.0)), snow);
	float abyss = smoothstep(abyss_top, abyss_bottom, world.y);
	albedo *= 1.0 - abyss * 0.95;
	ALBEDO = albedo * mix(0.45, 1.0, mael_playable(world));
	ROUGHNESS = mix(0.38 + 0.2 * cloudy, 0.85, snow);
	SPECULAR = 0.5;
	BACKLIGHT = translucent * (1.0 - snow) * (1.0 - abyss);
	NORMAL_MAP = normalize(vec3(0.5 + (streak - 0.5) * 0.25, 0.5 + (cloudy - 0.5) * 0.2, 1.0));
}
