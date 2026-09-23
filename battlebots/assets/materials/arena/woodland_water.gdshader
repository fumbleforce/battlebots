shader_type spatial;
// Peaty pond and creek water. One plane at the water level; opaque terrain
// hides it everywhere except the carved beds. Depth tints and clears the edge.
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 shallow_color : source_color = vec3(0.22, 0.24, 0.16);
uniform vec3 deep_color : source_color = vec3(0.03, 0.055, 0.05);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float h = (wl_noise(p * 0.9 + vec2(t * 0.25, t * 0.13)) + wl_noise(p * 2.3 - vec2(t * 0.31, -t * 0.2)) * 0.5
	) * 0.01 * (1.0 - smoothstep(20.0, 120.0, length(VERTEX)));
	vec3 n = wl_bump(VERTEX, NORMAL, h, 1.0);
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	behind.xyz /= behind.w;
	float thickness = max(VERTEX.z - behind.z, 0.0);
	float depth = 1.0 - exp(-thickness * 0.9);
	vec2 offset = (n.xy - NORMAL.xy) * 0.05 * depth;
	vec3 refracted = textureLod(screen_tex, SCREEN_UV + offset, 1.5).rgb;
	vec3 water = mix(shallow_color, deep_color, smoothstep(0.0, 1.0, depth));
	vec3 c = mix(refracted * shallow_color * 2.2, water, smoothstep(0.05, 0.75, depth));
	float foam = (1.0 - smoothstep(0.0, 0.25, thickness)) * smoothstep(0.45, 0.7, wl_noise(p * 3.0 + t * 0.3));
	c = mix(c, vec3(0.62, 0.6, 0.52), foam * 0.5);
	ALBEDO = c;
	ALPHA = clamp(0.55 + depth * 0.45, 0.0, 1.0);
	ROUGHNESS = 0.1 + foam * 0.5;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	NORMAL = n;
}
