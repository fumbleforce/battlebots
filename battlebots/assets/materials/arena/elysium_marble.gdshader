shader_type spatial;
// Elysium (#115) architecture: veined white Carrara-style marble, or polished
// gold leaf for capitals, mouldings, the dome and obelisk tips. Weathering
// gathers in crevices (baked into COLOR.r as cavity, 1 = open surface).
render_mode cull_back;
#include "res://assets/materials/arena/elysium_common.gdshaderinc"

uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool gilded = false;
uniform vec3 marble = vec3(0.95, 0.93, 0.89);
uniform vec3 vein_color = vec3(0.72, 0.72, 0.77);
uniform vec3 gold = vec3(1.0, 0.68, 0.22);
uniform float gold_glow = 0.05;

varying vec3 world_pos;
varying vec3 world_normal;
varying float cavity;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	cavity = COLOR.r;
}

void fragment() {
	vec3 n = ely_safe_normalize(world_normal);
	if (gilded) {
		float wear = ely_fbm3(world_pos * 1.7, 4);
		ALBEDO = gold * (0.88 + 0.2 * wear);
		// Not a perfect mirror: the leaf keeps its own warm colour instead of
		// reflecting the green lawns.
		METALLIC = 0.82;
		ROUGHNESS = 0.3 + 0.15 * wear;
		EMISSION = gold * gold_glow;
	} else {
		float detail = dot(ely_triplanar(stone_tex, world_pos, n, 0.21).rgb, vec3(0.333));
		float veins = ely_marble(world_pos * 0.8);
		vec3 albedo = mix(vein_color, marble, veins) * (0.9 + 0.2 * detail);
		// Rain-streaked soft shading toward the base and in crevices.
		albedo *= mix(0.78, 1.0, cavity) * mix(0.93, 1.0, smoothstep(-2.0, 6.0, world_pos.y));
		ALBEDO = albedo;
		METALLIC = 0.0;
		ROUGHNESS = mix(0.45, 0.28, veins);
		SPECULAR = 0.55;
		NORMAL_MAP = mix(ely_triplanar(stone_nor, world_pos, n, 0.21).rgb, vec3(0.5, 0.5, 1.0), 0.55);
		// Marble glows where the sun shines through its edges.
		SSS_STRENGTH = 0.25;
	}
}
