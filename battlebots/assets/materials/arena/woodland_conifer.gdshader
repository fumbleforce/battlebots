shader_type spatial;
// Conifer foliage cards textured from Blender renders of a CC0 fir scan
// (art_source/woodland/build_conifer_atlas.py). Alpha-cut needles; normals are
// authored to point out of the crown; light scatters through thin sprays.
render_mode cull_disabled;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float cutoff = 0.42;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
varying float seed;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	seed = wl_hash(origin.xz * 0.29);
	// Crown sway grows with height; the base stays planted.
	float sway = sin(TIME * 0.7 + origin.x * 0.05 + origin.z * 0.03) * 0.5 + sin(TIME * 1.9 + seed * 20.0) * 0.15;
	VERTEX.x += sway * VERTEX.y * VERTEX.y * 0.0006;
	VERTEX.z += sway * VERTEX.y * VERTEX.y * 0.0004;
}
void fragment() {
	vec4 c = texture(atlas, UV);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = cutoff;
	vec3 col = c.rgb * tint * (0.9 + seed * 0.2);
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = col * 0.5;
}
