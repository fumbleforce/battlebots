shader_type fog;
// Lit volumetric core of a muzzle blast; the particle cards carry the detail.
uniform float density = 0.0;
uniform float age = 0.0;
uniform vec3 albedo : source_color = vec3(0.55, 0.53, 0.5);
void fog() {
	vec3 p = (UVW - 0.5) * 2.0;
	float edge = 1.0 - smoothstep(0.1, 1.0, length(p));
	vec3 q = WORLD_POSITION * 1.6;
	float curl = sin(q.x + sin(q.z - age)) * sin(q.y - age * 1.5) * sin(q.z + age);
	DENSITY = density * edge * edge * (0.7 + 0.3 * curl);
	ALBEDO = albedo;
}
