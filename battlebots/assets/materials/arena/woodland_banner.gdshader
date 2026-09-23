shader_type spatial;
// Hanging team pennant. UV.y is 0 at the top bar; wind swings the free hem.
// Instance COLOR carries the team dye.
render_mode cull_disabled;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 trim_color : source_color = vec3(0.09, 0.08, 0.07);
uniform vec3 emblem_color : source_color = vec3(0.9, 0.84, 0.7);
uniform float wind = 1.0;
varying float phase;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	phase = wl_hash(origin.xz * 0.37) * 6.2831;
	float hang = UV.y * UV.y;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + phase);
	float wave = sin(TIME * 1.9 + UV.y * 4.0 + phase) * 0.6 + sin(TIME * 3.1 + UV.x * 5.0 + UV.y * 7.0 + phase) * 0.25;
	VERTEX.y += wave * hang * 0.06 * wind * gust / max(length(MODEL_MATRIX[1].xyz), 0.001);
	NORMAL = normalize(NORMAL + vec3(0.0, -cos(TIME * 1.9 + UV.y * 4.0 + phase) * hang * 0.25 * wind * gust, 0.0));
}
float diamond(vec2 p, float r) { return abs(p.x) + abs(p.y) - r; }
void fragment() {
	vec2 uv = UV;
	vec3 dye = COLOR.rgb;
	float fold = wl_noise(vec2(uv.x * 7.0, uv.y * 1.5 + phase)) - 0.5;
	vec3 c = dye * (0.9 + fold * 0.22);
	// Dark trim bands and a woven edge.
	float border = step(uv.x, 0.06) + step(0.94, uv.x) + step(uv.y, 0.05);
	float band = step(0.1, uv.y) * step(uv.y, 0.125) + step(0.8, uv.y) * step(uv.y, 0.82);
	c = mix(c, trim_color, clamp(border + band, 0.0, 1.0));
	// Emblem: a diamond frame around crossed hammers of the arena crest.
	vec2 e = (uv - vec2(0.5, 0.46)) * vec2(1.0, 2.6);
	float frame = smoothstep(0.03, 0.0, abs(diamond(e, 0.34)) - 0.03);
	float inner = smoothstep(0.02, 0.0, diamond(e, 0.2));
	float cut = smoothstep(0.02, 0.0, abs(e.x - e.y) - 0.035) + smoothstep(0.02, 0.0, abs(e.x + e.y) - 0.035);
	c = mix(c, emblem_color, clamp(frame + inner * (1.0 - clamp(cut, 0.0, 1.0)), 0.0, 1.0));
	// Swallowtail hem cut out of the bottom.
	float tail = uv.y - (0.93 + abs(uv.x - 0.5) * 0.14);
	if (tail > 0.0) { discard; }
	float grime = smoothstep(0.55, 0.9, wl_fbm(uv * vec2(4.0, 12.0) + phase, 3)) * smoothstep(0.4, 0.95, uv.y);
	c *= 1.0 - grime * 0.35;
	ALBEDO = c;
	ROUGHNESS = 0.88;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.55;
}
