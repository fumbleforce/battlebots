shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float age = 0.0;
uniform bool smoke = false;
instance uniform float seed = 0.0;

float hash(vec2 p) {
	// Integer lattice hashing keeps shared corners identical on D3D12/Vulkan.
	uvec2 q = uvec2(ivec2(p));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float(h ^ (h >> 16u)) * (1.0 / 4294967295.0);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	// Face the active camera while retaining each puff's authored world scale.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz), 0.0),
		MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 drift = vec2(seed * 13.1, -age * 0.8);
	float n = noise(p * 3.5 + drift) * 0.55
		+ noise(p * 8.0 + drift * 1.7) * 0.3
		+ noise(p * 17.0 + drift * 2.1) * 0.15;
	float edge = 1.0 - smoothstep(0.38, 1.0, length(p) + (n - 0.5) * 0.42);
	edge *= 1.0 - smoothstep(0.8, 1.0, length(p));
	if (smoke) {
		float fade = smoothstep(0.12, 0.45, age) * (1.0 - smoothstep(2.0, 4.2, age));
		ALBEDO = mix(vec3(0.045, 0.052, 0.065), vec3(0.28, 0.29, 0.31), n);
		// Warm underside briefly catches the departing fireball.
		ALBEDO += vec3(0.28, 0.055, 0.005) * (1.0 - smoothstep(0.3, 1.3, age)) * (1.0 - UV.y);
		ALPHA = edge * fade * 0.78;
	} else {
		float heat = clamp(n * 1.3 + (1.0 - length(p)) * 0.4 - age * 0.55, 0.0, 1.0);
		vec3 fire = mix(vec3(0.28, 0.016, 0.002), vec3(1.0, 0.22, 0.008), smoothstep(0.08, 0.48, heat));
		fire = mix(fire, vec3(1.0, 0.84, 0.32), smoothstep(0.45, 0.85, heat));
		ALBEDO = fire;
		EMISSION = fire * (1.0 + heat * 4.0);
		ALPHA = edge * (1.0 - smoothstep(0.42, 1.05, age));
	}
}
