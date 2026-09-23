shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// Expanding hammer shockwave: a glowing, refracting pressure ring with a
// white-hot leading edge and a darker scorched wake. Driven per instance, so
// every pooled ring shares one material.

instance uniform float progress = 0.0;
instance uniform float strength = 1.0;
uniform vec3 hot_color : source_color = vec3(1.0, 0.8, 0.52);
uniform vec3 ring_color : source_color = vec3(0.95, 0.88, 0.78);
uniform vec3 wake_color : source_color = vec3(0.16, 0.13, 0.11);
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap, repeat_disable;
varying vec3 center_view;

void vertex() {
	center_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Ease-out travel: the front bursts out and decelerates like a pressure wave.
	float eased = 1.0 - pow(1.0 - progress, 3.0);
	float front = mix(0.05, 0.95, eased);
	float width = mix(0.05, 0.12, progress);
	float edge = r - front;
	// Sharp outer edge, softer trailing band behind the front.
	float ring = edge > 0.0 ? smoothstep(width * 0.5, 0.0, edge) : smoothstep(width * 1.8, 0.0, -edge);
	float wake = smoothstep(front, front * 0.25, r) * step(r, front);
	float fade = 1.0 - progress;
	float hot = smoothstep(width * 0.6, 0.0, abs(edge)) * (1.0 - smoothstep(0.0, 0.5, progress));
	float mask = step(r, 1.0) * strength;
	vec2 radial = center_view.xy - VERTEX.xy;
	radial = length(radial) > 0.0001 ? normalize(radial) : vec2(0.0);
	vec2 offset = vec2(-radial.x, radial.y) * ring * fade * 0.045 * strength;
	vec3 behind = textureLod(screen_texture, SCREEN_UV + offset, 0.0).rgb;
	vec3 glow = ring_color * ring * 0.9 + hot_color * hot * 2.6;
	float scorch = wake * 0.35 * fade * fade;
	ALBEDO = mix(behind, wake_color, scorch) + glow * fade * mask;
	ALPHA = clamp((ring * 0.95 + hot + scorch) * fade * mask, 0.0, 1.0);
}
