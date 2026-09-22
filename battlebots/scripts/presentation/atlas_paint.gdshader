shader_type spatial;
uniform sampler2D surface_albedo : source_color, filter_linear_mipmap;
uniform sampler2D surface_orm : filter_linear_mipmap;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap;
uniform vec4 paint : source_color;
uniform vec4 authored_paint : source_color;
uniform float normal_strength = 0.22;

void fragment() {
	vec3 base = texture(surface_albedo, UV).rgb;
	vec3 orm = texture(surface_orm, UV).rgb;
	// The metal-rich chips remain exposed steel when the enamel is repainted.
	float exposed = smoothstep(0.78, 0.90, orm.b);
	vec3 enamel = base * paint.rgb / max(authored_paint.rgb, vec3(0.001));
	ALBEDO = mix(enamel, base, exposed);
	AO = orm.r;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = texture(surface_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
