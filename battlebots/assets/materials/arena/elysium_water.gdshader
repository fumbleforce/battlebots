shader_type spatial;
// Elysium (#115) waterfalls pouring off the islands into the clouds: bright
// streaking ribbons that break into white spray and dissolve as they fall.
// UV.x across the fall, UV.y metres down from the lip (scaled by fall_length).
render_mode cull_disabled, depth_draw_never, blend_mix;
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform vec3 water = vec3(0.66, 0.86, 0.95);
uniform vec3 foam = vec3(1.0, 0.99, 0.96);
uniform vec3 sunlit = vec3(1.0, 0.86, 0.6);
uniform float fall_length = 160.0;
uniform float speed = 9.0;

void fragment() {
	float down = UV.y * fall_length;
	float across = UV.x;
	vec2 flow = vec2(across * 18.0, down * 0.09 - TIME * speed * 0.09);
	float streaks = ely_fbm2(vec2(flow.x, flow.y * 0.35), 4);
	float fine = ely_noise2(vec2(across * 60.0, down * 0.4 - TIME * speed * 0.4));
	float spray = smoothstep(0.0, 0.6, UV.y);
	float white = clamp(streaks * 1.2 + fine * 0.3 + spray * 0.6 - 0.35, 0.0, 1.0);
	vec3 col = mix(water, foam, white);
	col += sunlit * 0.25 * white;
	ALBEDO = col;
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	EMISSION = col * 0.18;
	float sides = smoothstep(0.0, 0.18 + spray * 0.25, across) * smoothstep(1.0, 0.82 - spray * 0.25, across);
	float lip = smoothstep(0.0, 0.01, UV.y);
	float dissolve = 1.0 - smoothstep(0.55, 1.0, UV.y);
	ALPHA = clamp(sides * lip * dissolve * (0.55 + 0.45 * streaks + 0.2 * fine), 0.0, 1.0);
}
