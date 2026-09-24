shader_type spatial;
render_mode cull_disabled;
// Cut-capable stand-in for the bot surface materials (#72). WreckPieces copies
// the source parameters in: source_mode 0 mirrors StandardMaterial3D and
// atlas_paint.gdshader (same uniform names), 1 mirrors the Sawblade atlas
// paint (sawblade_runtime/paint.gdshader).
#include "res://scripts/presentation/destruction_cut.gdshaderinc"

uniform int source_mode = 0;
uniform sampler2D surface_albedo : source_color, filter_linear_mipmap;
uniform sampler2D surface_orm : filter_linear_mipmap;
uniform sampler2D surface_coverage : hint_default_black, filter_linear_mipmap;
uniform sampler2D surface_ao : hint_default_white, filter_linear_mipmap;
uniform sampler2D surface_normal : hint_normal, filter_linear_mipmap;
uniform sampler2D surface_emission : source_color, hint_default_black, filter_linear_mipmap;
uniform bool coverage_enabled = false;
uniform bool vertex_color_enabled = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 paint : source_color = vec4(1.0);
uniform vec4 authored_paint : source_color = vec4(1.0);
uniform float roughness_factor = 1.0;
uniform float metallic_factor = 1.0;
uniform bool ao_enabled = false;
uniform float ao_light_affect = 0.0;
uniform float normal_strength = 0.0;
uniform bool emission_enabled = false;
uniform bool emission_texture_enabled = false;
uniform vec4 emission_color : source_color;
uniform float emission_energy = 1.0;
uniform bool emission_add = true;
// Sawblade atlas mode.
uniform sampler2D surface_atlas : source_color, filter_linear_mipmap;
uniform float metal = 0.5;
uniform float rough = 0.5;

void vertex() {
	cut_point = VERTEX;
}

void fragment() {
	vec3 albedo;
	float metallic;
	float roughness;
	vec3 emission = vec3(0.0);
	float normal_depth = normal_strength;
	if (source_mode == 1) {
		albedo = paint.rgb * (2.0 * texture(surface_atlas, UV).r);
		metallic = metal;
		roughness = rough;
		normal_depth = 0.0;
	} else {
		vec3 base = texture(surface_albedo, UV).rgb * albedo_tint.rgb;
		if (vertex_color_enabled) base *= COLOR.rgb;
		vec3 orm = texture(surface_orm, UV).rgb;
		float coverage = coverage_enabled ? texture(surface_coverage, UV).r : 1.0;
		vec3 enamel = base * paint.rgb / max(authored_paint.rgb, vec3(0.001));
		albedo = mix(base, enamel, coverage);
		AO = ao_enabled ? texture(surface_ao, UV).r : 1.0;
		AO_LIGHT_AFFECT = ao_light_affect;
		roughness = orm.g * roughness_factor;
		metallic = orm.b * metallic_factor;
		NORMAL_MAP = texture(surface_normal, UV).rgb;
		if (emission_enabled) {
			vec3 glow = emission_texture_enabled ? texture(surface_emission, UV).rgb : (emission_add ? vec3(0.0) : vec3(1.0));
			emission = (emission_add ? emission_color.rgb + glow : emission_color.rgb * glow) * emission_energy;
		}
	}
	cut_fragment(cut_point, FRONT_FACING, albedo, metallic, roughness, emission, normal_depth);
	ALBEDO = albedo;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	EMISSION = emission;
	NORMAL_MAP_DEPTH = normal_depth;
}
