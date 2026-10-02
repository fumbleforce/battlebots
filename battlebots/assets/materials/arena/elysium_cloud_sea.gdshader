shader_type spatial;
// Elysium (#115): the endless sea of clouds far below the islands. Rolling
// billows rise in the vertex stage; the surface is lit by hand from the sun
// direction (sunlit crowns, lilac hollows, a silver lining toward the sun)
// and melts into the sky's glowing horizon with distance.
render_mode unshaded, cull_disabled, fog_disabled;
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform vec3 sun_dir = vec3(0.5, 0.45, -0.7);
uniform vec3 crown = vec3(1.0, 0.97, 0.92);
uniform vec3 sunlit = vec3(1.0, 0.92, 0.78);
uniform vec3 hollow = vec3(0.76, 0.76, 0.9);
uniform vec3 far_color = vec3(1.0, 0.92, 0.82);
uniform float billow_height = 34.0;
uniform float scale = 0.0021;
uniform float far_fade = 5200.0;

varying vec3 world_pos;
varying float billow;

float density(vec2 p) {
	vec2 q = p * scale + vec2(TIME * 0.0025, TIME * 0.001);
	vec2 warp = vec2(ely_fbm2(q * 0.8 + 3.1, 3), ely_fbm2(q * 0.8 + 9.7, 3));
	return ely_fbm2(q + warp * 1.6, 5);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	billow = density(world_pos.xz);
	float puff = smoothstep(0.3, 0.75, billow);
	world_pos.y += puff * puff * billow_height;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec3 sun = normalize(sun_dir);
	// Fine detail fades out with distance so the far sea does not shimmer.
	float detail_mix = 1.0 - smoothstep(600.0, 2400.0, dist);
	float d = billow + detail_mix * (ely_fbm2(p * 0.03 + TIME * 0.01, 4) - 0.5) * 0.18;
	// Light from the slope toward the sun: compare density a step sunward.
	vec2 toward = normalize(sun.xz + vec2(1e-4)) * 34.0;
	float ahead = density(p + toward);
	float lit = clamp(0.55 + (d - ahead) * 5.5 + sun.y * 0.4, 0.0, 1.0);
	float top = smoothstep(0.32, 0.72, d);
	vec3 col = mix(hollow, crown, top);
	col = mix(col * 0.82, col * mix(vec3(1.0), sunlit, 0.35) * 1.12, lit);
	// Silver lining on the crowns facing the sun.
	vec3 view = normalize(world_pos - CAMERA_POSITION_WORLD);
	float toward_sun = pow(max(dot(view, sun), 0.0), 8.0);
	col += sunlit * toward_sun * top * 0.6;
	float fade = smoothstep(far_fade * 0.25, far_fade, dist);
	ALBEDO = mix(col, far_color, fade);
}
