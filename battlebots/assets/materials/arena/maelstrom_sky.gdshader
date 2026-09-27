shader_type sky;
// Frozen Maelstrom sky (#102): a low, heavy overcast in cold slate, rolling
// slowly with the whirlpool below; the moon is only a pale smear behind it and
// the horizon drowns in freezing haze. No colour to speak of.
#include "res://assets/materials/arena/maelstrom_common.gdshaderinc"
uniform vec3 zenith : source_color = vec3(0.09, 0.11, 0.14);
uniform vec3 horizon : source_color = vec3(0.36, 0.43, 0.5);
uniform vec3 cloud_dark : source_color = vec3(0.14, 0.17, 0.21);
uniform vec3 cloud_light : source_color = vec3(0.3, 0.36, 0.42);
uniform vec3 moon_glow : source_color = vec3(0.55, 0.64, 0.76);

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col = mix(horizon, zenith, smoothstep(-0.02, 0.6, up));
	// Cloud deck: projected onto a low ceiling so it streams toward the horizon.
	vec2 p = d.xz / max(up + 0.08, 0.04) * 0.7;
	float t = TIME * 0.004;
	float big = mael_fbm(p * 0.35 + vec2(t, t * 0.4));
	float torn = mael_fbm(p * 1.3 - vec2(t * 2.0, 0.0));
	float mass = smoothstep(0.3, 0.75, big * 0.75 + torn * 0.35);
	vec3 cloud = mix(cloud_dark, cloud_light, smoothstep(0.35, 0.8, torn) * 0.6);
	// The moon behind the overcast: a diffuse pale bloom, brightest in thin cloud.
	vec3 moon = LIGHT0_DIRECTION;
	float toward = max(dot(d, moon), 0.0);
	float halo = pow(toward, 18.0) * 0.5 + pow(toward, 160.0) * 1.2;
	cloud += moon_glow * halo * (1.2 - mass);
	col = mix(col + moon_glow * halo * 0.4, cloud, smoothstep(-0.02, 0.08, up) * (0.55 + 0.45 * mass));
	// Freezing haze swallowing the horizon.
	col = mix(col, horizon, 1.0 - smoothstep(0.0, 0.14, abs(up)));
	if (up < 0.0) {
		col = mix(horizon, vec3(0.05, 0.065, 0.08), smoothstep(0.0, 0.2, -up));
	}
	COLOR = col;
}
