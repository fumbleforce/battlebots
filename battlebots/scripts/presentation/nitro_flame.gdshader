shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Nitro jet: a white-hot nozzle core fading through blue to a violet tip, with
// travelling shock diamonds. Local +Y is the nozzle and -Y the tip of a unit cone.

instance uniform float intensity = 1.0;
instance uniform float seed = 0.0;
uniform vec3 core_color : source_color = vec3(0.62, 0.86, 1.0);
uniform vec3 body_color : source_color = vec3(0.08, 0.36, 1.0);
uniform vec3 tip_color : source_color = vec3(0.2, 0.14, 0.95);
varying float along;

void vertex() {
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Keep a floor so the jet still reads when viewed straight down its axis.
	float body = mix(0.45, 1.0, pow(facing, 1.4));
	float flicker = 0.78 + 0.22 * sin(TIME * 57.0 + seed * 6.1 + along * 9.0) * sin(TIME * 31.0 + seed * 2.3);
	float diamonds = 0.82 + 0.18 * sin(along * 28.0 - TIME * 34.0 + seed);
	float fade = pow(1.0 - along, 0.85);
	vec3 color = mix(core_color, body_color, smoothstep(0.0, 0.22, along));
	color = mix(color, tip_color, smoothstep(0.5, 1.0, along));
	ALBEDO = color * 2.6 * flicker * diamonds;
	ALPHA = clamp(body * fade * intensity, 0.0, 1.0);
}
