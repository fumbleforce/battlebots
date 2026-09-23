shader_type spatial;
// Instanced spectators. Every part of a person shares the phase in COLOR.a,
// so each person bobs and occasionally stands to cheer as a unit.
uniform float excitement = 0.6;
varying float shade;
float h1(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float id = COLOR.a;
	float t = TIME * (1.4 + id * 1.3) + id * 30.0;
	float bob = max(0.0, sin(t)) * 0.05;
	float cheer = smoothstep(0.75, 1.0, sin(TIME * 0.21 + id * 17.0 + origin.x * 0.02)) * excitement;
	bob += cheer * (0.18 + max(0.0, sin(t * 2.3)) * 0.12);
	VERTEX.y += bob / max(length(MODEL_MATRIX[1].xyz), 0.001);
	shade = 0.75 + id * 0.5;
}
void fragment() {
	ALBEDO = COLOR.rgb * shade;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
}
