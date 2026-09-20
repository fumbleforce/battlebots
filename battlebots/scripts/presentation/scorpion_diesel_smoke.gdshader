shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D smoke_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
varying float puff_seed;
varying float puff_age;

void vertex() {
	// Preserve particle roll and size while facing the camera. The simulation
	// retains world coordinates, so cards don't follow a departing robot.
	float angle = INSTANCE_CUSTOM.x;
	vec2 spin = vec2(cos(angle), sin(angle));
	vec3 right = INV_VIEW_MATRIX[0].xyz * spin.x + INV_VIEW_MATRIX[1].xyz * spin.y;
	vec3 up = -INV_VIEW_MATRIX[0].xyz * spin.y + INV_VIEW_MATRIX[1].xyz * spin.x;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	puff_seed = fract(sin(angle * 17.13) * 437.7);
	puff_age = INSTANCE_CUSTOM.y;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 drift = vec2(puff_seed * 3.7, puff_age * -0.13);
	float broad = texture(smoke_noise, UV * 0.72 + drift).r;
	float detail = texture(smoke_noise, UV * 1.8 + drift * 1.31).r;
	float billow = broad * 0.74 + detail * 0.26;
	float radius = length(p);
	float edge = 1.0 - smoothstep(0.28, 0.96, radius + (billow - 0.5) * 0.46);
	float density = edge * smoothstep(0.16, 0.70, billow) * 1.15;
	// Dark soot has a shaded, irregular body and soft diffuse highlights; it
	// still receives the real arena's lights rather than emitting black light.
	ALBEDO = mix(vec3(0.009, 0.010, 0.012), vec3(0.065, 0.072, 0.080), billow * 0.65 + puff_age * 0.35);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize(vec3(p.x * 0.43, -p.y * 0.43, 0.90 - radius * 0.25));
	float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, scene_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#endif
	vec4 scene_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene_position.xyz /= scene_position.w;
	float contact_fade = smoothstep(0.0, 0.36, VERTEX.z - scene_position.z);
	ALPHA = clamp(density, 0.0, 1.0) * COLOR.a * contact_fade;
}
