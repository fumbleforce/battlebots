shader_type spatial;
render_mode cull_disabled;
uniform sampler2D surface_albedo : source_color, filter_linear_mipmap;
uniform sampler2D surface_orm : filter_linear_mipmap;
uniform sampler2D surface_coverage : hint_default_black, filter_linear_mipmap;
uniform sampler2D surface_ao : hint_default_white, filter_linear_mipmap;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D surface_emission : source_color, hint_default_black, filter_linear_mipmap;
uniform bool coverage_enabled = true;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 paint : source_color;
uniform vec4 authored_paint : source_color;
uniform float roughness_factor = 1.0;
uniform float metallic_factor = 1.0;
uniform bool ao_enabled = false;
uniform float ao_light_affect = 0.0;
uniform float normal_strength = 0.22;
uniform bool emission_enabled = false;
uniform bool emission_texture_enabled = false;
uniform vec4 emission_color : source_color;
uniform float emission_energy = 1.0;
uniform bool emission_add = true;

void fragment() {
	vec3 base = texture(surface_albedo, UV).rgb * albedo_tint.rgb;
	vec3 orm = texture(surface_orm, UV).rgb;
	// Coverage is authored separately: primer is nonmetallic but must stay intact.
	float coverage = coverage_enabled ? texture(surface_coverage, UV).r : 1.0;
	vec3 enamel = base * paint.rgb / max(authored_paint.rgb, vec3(0.001));
	ALBEDO = mix(base, enamel, coverage);
	AO = ao_enabled ? texture(surface_ao, UV).r : 1.0;
	AO_LIGHT_AFFECT = ao_light_affect;
	ROUGHNESS = orm.g * roughness_factor;
	METALLIC = orm.b * metallic_factor;
	NORMAL_MAP = texture(surface_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	if (emission_enabled) {
		vec3 glow = emission_texture_enabled ? texture(surface_emission, UV).rgb : (emission_add ? vec3(0.0) : vec3(1.0));
		EMISSION = (emission_add ? emission_color.rgb + glow : emission_color.rgb * glow) * emission_energy;
	}
}
