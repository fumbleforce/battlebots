shader_type fog;
// A short-lived local dust pocket. No global atmosphere or emissive smoke.
uniform float density = 0.0;
uniform float age = 0.0;
void fog() {
	vec3 p = (UVW - 0.5) * 2.0;
	float radial = length(p);
	float edge = 1.0 - smoothstep(0.25, 1.0, radial);
	vec3 q = WORLD_POSITION * 2.5;
	float curl = sin(q.x + sin(q.z * 0.8 + age)) * sin(q.y * 1.3 - age * 1.7) * sin(q.z + age * 0.6);
	DENSITY = density * edge * edge * (0.75 + 0.25 * curl);
	ALBEDO = vec3(0.49, 0.48, 0.46);
}
