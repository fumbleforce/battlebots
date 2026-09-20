shader_type spatial;
uniform sampler2D surface_atlas : source_color, filter_linear_mipmap;
uniform vec4 paint : source_color = vec4(0.66, 0.32, 0.018, 1.0);
uniform float metal = 0.5;
uniform float rough = 0.5;
void fragment() {
	ALBEDO = paint.rgb * (2.0 * texture(surface_atlas, UV).r);
	METALLIC = metal;
	ROUGHNESS = rough;
}
