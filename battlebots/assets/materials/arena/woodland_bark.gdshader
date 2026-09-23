shader_type spatial;
// Scanned CC0 pine bark wrapped around the trunk (UV.x around, UV.y metres up),
// darkened and mud-splashed at the root flare.
uniform sampler2D bark_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wraps = 2.0;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = vec2(UV.x * wraps, UV.y / 1.4);
	vec3 arm = texture(bark_arm, uv).rgb;
	vec3 c = texture(bark_diff, uv).rgb;
	float foot = 1.0 - smoothstep(0.0, 0.8, UV.y);
	c = mix(c, c * vec3(0.5, 0.42, 0.34), foot * 0.7);
	ALBEDO = c;
	NORMAL_MAP = texture(bark_nor, uv).rgb;
	ROUGHNESS = arm.g;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.4;
	SPECULAR = 0.3;
}
