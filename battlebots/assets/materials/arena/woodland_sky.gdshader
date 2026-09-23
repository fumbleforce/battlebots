shader_type sky;
// Late-afternoon mountain sky. Distant snow-capped ranges and a cloud deck are
// painted in the sky so no camera far plane can clip them.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 zenith : source_color = vec3(0.19, 0.36, 0.64);
uniform vec3 horizon : source_color = vec3(0.8, 0.76, 0.68);
uniform vec3 haze : source_color = vec3(0.62, 0.66, 0.7);
uniform vec3 rock : source_color = vec3(0.22, 0.25, 0.3);
uniform vec3 snow : source_color = vec3(0.9, 0.92, 0.96);
uniform vec3 far_forest : source_color = vec3(0.12, 0.17, 0.15);

float ridge(float a, float scale, float seed) {
	float h = 0.0, amp = 1.0, f = scale;
	for (int i = 0; i < 6; i++) {
		float n = wl_noise(vec2(a * f, seed + float(i) * 7.1));
		h += (1.0 - abs(n * 2.0 - 1.0)) * amp;
		amp *= 0.5;
		f *= 2.1;
	}
	return h / 1.97;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.5));
	vec3 sun_dir = LIGHT0_DIRECTION;
	float sd = max(dot(d, sun_dir), 0.0);
	col += vec3(1.0, 0.8, 0.55) * pow(sd, 6.0) * 0.35 * LIGHT0_ENERGY * 0.4;
	// Cloud deck with lit tops and grey bellies.
	if (up > 0.0) {
		vec2 uv = d.xz / (up + 0.12);
		float c = wl_fbm(uv * 0.9 + vec2(TIME * 0.004, 0.0), 5);
		float cover = smoothstep(0.56, 0.76, c) * smoothstep(0.0, 0.25, up);
		vec3 cloud = mix(vec3(0.66, 0.66, 0.7), vec3(1.0, 0.95, 0.86), smoothstep(0.55, 0.85, c) * 0.8 + pow(sd, 3.0) * 0.4);
		col = mix(col, cloud, cover * 0.7);
	}
	// Mountain ranges: a far snowy range, then nearer forested ridges.
	float a = atan(d.x, d.z);
	float far_h = 0.02 + ridge(a, 2.2, 3.0) * 0.085;
	float mid_h = 0.004 + ridge(a + 1.7, 3.5, 11.0) * 0.035;
	if (up < far_h) {
		float t = up / far_h;
		float streak = wl_noise(vec2(a * 180.0, up * 60.0));
		vec3 m = mix(rock, snow, smoothstep(0.55, 0.8, t + (streak - 0.5) * 0.35));
		float lit = 0.75 + 0.35 * dot(normalize(vec2(sun_dir.x, sun_dir.z)), vec2(sin(a * 7.0), cos(a * 7.0)));
		m *= lit;
		col = mix(m, haze, 0.55 - t * 0.15);
	}
	if (up < mid_h) {
		col = mix(far_forest, haze, 0.35 + (up / mid_h) * 0.1);
	}
	if (up < 0.0) {
		col = mix(far_forest, haze, 0.45);
	}
	COLOR = col;
}
