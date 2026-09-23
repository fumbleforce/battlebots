shader_type spatial;
// Arena video board: team halves, a centre divider and a slow sweep.
render_mode unshaded;
uniform vec3 left_color : source_color = vec3(0.12, 0.62, 0.85);
uniform vec3 right_color : source_color = vec3(0.95, 0.42, 0.1);
uniform float energy = 1.8;
void fragment() {
	vec2 uv = UV;
	vec3 team = uv.x < 0.5 ? left_color : right_color;
	float side = uv.x < 0.5 ? uv.x * 2.0 : (1.0 - uv.x) * 2.0;
	vec3 c = mix(vec3(0.02, 0.025, 0.035), team * 0.55, smoothstep(0.0, 0.9, side) * 0.8);
	c += team * smoothstep(0.45, 0.0, abs(uv.y - 0.55)) * 0.25 * side;
	float divider = smoothstep(0.012, 0.0, abs(uv.x - 0.5) - 0.06);
	c = mix(c, vec3(0.03, 0.035, 0.045), divider);
	float frame = step(uv.x, 0.012) + step(0.988, uv.x) + step(uv.y, 0.02) + step(0.98, uv.y);
	c = mix(c, team * 1.4, clamp(frame, 0.0, 1.0));
	float scan = 0.9 + 0.1 * sin(uv.y * 900.0);
	float sweep = smoothstep(0.08, 0.0, abs(fract(TIME * 0.08) - uv.x)) * 0.25;
	ALBEDO = c * scan * energy + sweep;
}
