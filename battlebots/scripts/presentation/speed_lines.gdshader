shader_type canvas_item;
// Nitro speed streaks: radial dashes rushing past the screen edges, clear centre.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(0.94, 0.95, 0.96, 1.0);
// Neutral darkening only; the blue belongs to the exhaust, not the screen.
uniform vec4 edge_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(uv);
	float turn = atan(uv.y, uv.x) / 6.2831853 + 0.5;
	float lanes = 150.0;
	float lane = floor(turn * lanes);
	float seed = hash(lane);
	float across = abs(fract(turn * lanes) - 0.5);
	float thin = smoothstep(0.22, 0.0, across);
	// Each lane carries dashes at its own pace; only some lanes are live.
	float pace = 1.6 + seed * 2.6;
	float dash = fract(r * 1.6 - TIME * pace + seed * 9.0);
	float streak = smoothstep(0.0, 0.08, dash) * smoothstep(0.55, 0.2, dash);
	float live = step(0.52, seed);
	float mask = smoothstep(0.24, 0.62, r);
	float lines = thin * streak * live * mask;
	float vignette = smoothstep(0.4, 0.9, r) * 0.18;
	vec3 color = line_color.rgb * lines + edge_tint.rgb * vignette;
	COLOR = vec4(color, clamp((lines * 0.4 + vignette) * intensity, 0.0, 1.0));
}
