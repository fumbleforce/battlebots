shader_type spatial;
// Instanced spectators (art_source/woodland/build_stands.py figures). One
// material per body part; COLOR carries the shirt colour and the person's
// phase in alpha, INSTANCE_CUSTOM the trousers colour and skin tone in alpha.
// Every part reads the same phase, so each person moves as a unit.
uniform int part = 0; // 0 shirt, 1 trousers, 2 skin, 3 hair/shoes
uniform float excitement = 0.6;
varying vec3 tint;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float id = COLOR.a;
	float t = TIME * (1.4 + id * 1.3) + id * 30.0;
	float bob = max(0.0, sin(t)) * 0.03;
	float cheer = smoothstep(0.75, 1.0, sin(TIME * 0.21 + id * 17.0 + origin.x * 0.02)) * excitement;
	bob += cheer * (0.12 + max(0.0, sin(t * 2.3)) * 0.1);
	VERTEX.y += bob;
	VERTEX.x += sin(t * 0.7) * 0.02 * VERTEX.y;
	vec3 skins[4] = vec3[](vec3(0.62, 0.45, 0.34), vec3(0.45, 0.31, 0.22), vec3(0.28, 0.19, 0.13), vec3(0.7, 0.54, 0.43));
	vec3 hairs[4] = vec3[](vec3(0.05, 0.04, 0.03), vec3(0.18, 0.12, 0.07), vec3(0.4, 0.3, 0.18), vec3(0.3, 0.3, 0.3));
	if (part == 0) { tint = COLOR.rgb; }
	else if (part == 1) { tint = INSTANCE_CUSTOM.rgb; }
	else if (part == 2) { tint = skins[int(INSTANCE_CUSTOM.a * 3.99)]; }
	else { tint = hairs[int(fract(id * 7.31) * 3.99)]; }
}
void fragment() {
	ALBEDO = tint;
	ROUGHNESS = part == 2 ? 0.6 : 0.85;
	SPECULAR = 0.3;
	BACKLIGHT = part == 2 ? tint * 0.2 : vec3(0.0);
}
