shader_type sky;
// Elysium (#115) heaven sky: a deep, clear zenith blending through soft
// lilac into a luminous gold horizon, a sun with a wide halo, high cirrus
// veils catching the light, and a glowing cloud floor below the horizon.
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform vec3 zenith = vec3(0.09, 0.24, 0.62);
uniform vec3 upper = vec3(0.34, 0.52, 0.88);
uniform vec3 horizon = vec3(1.0, 0.86, 0.66);
uniform vec3 below = vec3(1.0, 0.93, 0.84);
uniform vec3 sun_tint = vec3(1.0, 0.85, 0.6);
uniform float sun_size = 0.9994;
uniform float halo_power = 6.0;
uniform float cirrus = 0.55;

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sun = normalize(LIGHT0_DIRECTION);
	float facing = max(dot(d, sun), 0.0);
	float h = d.y;
	vec3 col = mix(horizon, upper, smoothstep(0.0, 0.28, h));
	col = mix(col, zenith, smoothstep(0.22, 0.95, h));
	// The horizon blushes toward the sun.
	col += sun_tint * pow(facing, 3.0) * 0.45 * (1.0 - smoothstep(0.0, 0.5, abs(h)));
	// Below the horizon: the luminous top of the endless cloud sea.
	col = mix(col, below * (0.92 + 0.25 * pow(facing, 4.0)), smoothstep(0.0, -0.06, h));
	if (!AT_CUBEMAP_PASS) {
		// High cirrus veils, projected on a dome and drifting slowly.
		if (h > 0.0) {
			vec2 uv = d.xz / (h + 0.18) * 1.6 + vec2(TIME * 0.0015, 0.0);
			float wisps = ely_fbm2(uv * vec2(1.0, 3.5) + ely_fbm2(uv * 0.7, 3) * 1.8, 5);
			float veil = smoothstep(0.48, 0.78, wisps) * smoothstep(0.02, 0.2, h) * (1.0 - smoothstep(0.55, 0.95, h));
			vec3 lit = mix(vec3(1.0, 0.97, 0.94), sun_tint * 1.35, pow(facing, 6.0));
			col = mix(col, lit, veil * cirrus);
		}
		// Sun disk and its soft glory.
		col += sun_tint * 18.0 * smoothstep(sun_size, sun_size + 0.0003, facing);
	}
	col += sun_tint * (pow(facing, 220.0) * 2.4 + pow(facing, halo_power) * 0.35);
	COLOR = col;
}
