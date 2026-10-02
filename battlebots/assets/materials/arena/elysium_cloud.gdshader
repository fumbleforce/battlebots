shader_type spatial;
// Elysium (#115) cloud banks: billowing puffs hugging the islands, filling the
// chasm and the wells, and towering cumulus on the horizon. Vertices swell
// along their normals with 3D noise; edges erode into wisps; light is painted
// from the sun direction with a bright silver lining against the sun.
render_mode unshaded, cull_back, depth_draw_never, blend_mix;
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform vec3 sun_dir = vec3(0.5, 0.45, -0.7);
uniform vec3 bright = vec3(1.0, 0.98, 0.95);
uniform vec3 sunlit = vec3(1.0, 0.93, 0.8);
uniform vec3 shade = vec3(0.84, 0.84, 0.94);
uniform float swell = 0.32;
uniform float softness = 1.0;
uniform float opacity = 0.96;
uniform float proximity = 6.0;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_pos;
varying vec3 world_normal;
varying float lumps;

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length((MODEL_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 n = normalize(NORMAL);
	vec3 seed = n * 2.2 + centre * 0.013 + vec3(TIME * 0.02, 0.0, TIME * 0.013);
	lumps = ely_fbm3(seed, 4);
	// Flatter undersides, rounded cauliflower tops.
	float flatten = mix(0.55, 1.0, smoothstep(-0.6, 0.2, n.y));
	VERTEX = VERTEX * vec3(1.0, flatten, 1.0) + n * (lumps - 0.5) * 2.0 * swell;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = ely_safe_normalize(world_normal);
	vec3 sun = normalize(sun_dir);
	vec3 view = ely_safe_normalize(CAMERA_POSITION_WORLD - world_pos);
	float wrap = clamp(dot(n, sun) * 0.55 + 0.5, 0.0, 1.0);
	float up = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(shade, bright, smoothstep(0.1, 0.95, wrap * 0.75 + up * 0.35));
	col = mix(col, sunlit * 1.08, smoothstep(0.6, 1.0, wrap) * 0.6);
	// Silver lining: thin edges seen against the sun glow.
	float rim = pow(1.0 - clamp(dot(n, view), 0.0, 1.0), 3.0);
	float against = pow(max(dot(-view, sun), 0.0), 4.0);
	col += sunlit * rim * (0.35 + against * 1.6);
	// Forward scattering: seen against the sun, the whole bank glows gold.
	col = mix(col, (bright + sunlit) * 0.62, against * 0.55);
	col *= 0.9 + 0.2 * lumps;
	ALBEDO = col;
	// Wispy, eroded silhouettes.
	float edge = clamp(dot(n, view), 0.0, 1.0);
	float erode = ely_fbm3(world_pos * 0.09 + vec3(0.0, TIME * 0.05, 0.0), 4);
	float alpha = smoothstep(0.05, 0.75 * softness, edge - (erode - 0.5) * 0.6);
	// Melt softly into the islands and other geometry.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	alpha *= clamp((VERTEX.z - behind.z) / proximity, 0.0, 1.0);
	ALPHA = alpha * opacity;
}
