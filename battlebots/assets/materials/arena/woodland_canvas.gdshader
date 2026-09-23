shader_type spatial;
// Weathered canvas for stand canopies. Thin cloth transmits sunlight.
render_mode cull_disabled;
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform vec3 cloth_color : source_color = vec3(0.78, 0.74, 0.65);
uniform float seam_spacing = 1.4;
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fade = 1.0 - smoothstep(10.0, 45.0, length(VERTEX));
	float stain = wl_fbm(wpos.xz * 0.35 + wpos.y, 4);
	float drip = wl_noise(vec2((wpos.x + wpos.z) * 3.0, wpos.y * 0.6));
	float seam = 1.0 - smoothstep(0.0, 0.035, abs(fract((wpos.x - wpos.z) / seam_spacing) - 0.5) - 0.46);
	vec3 c = cloth_color * (0.85 + stain * 0.3);
	c = mix(c, c * vec3(0.72, 0.66, 0.55), smoothstep(0.55, 0.8, stain) * 0.7 + drip * 0.15);
	c *= 1.0 - seam * 0.18;
	ALBEDO = c * COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.45;
	float weave = (wl_noise(wpos.xz * 260.0) - 0.5) * 0.0004 * fade;
	NORMAL = wl_bump(VERTEX, NORMAL, weave - seam * 0.002 * fade, 1.0);
}
