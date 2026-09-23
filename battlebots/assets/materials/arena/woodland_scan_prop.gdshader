shader_type spatial;
// Scanned scatter props (grass, ferns, pebbles, rocks). Foliage uses an alpha
// cut-out, shades both faces with an up-biased normal so thin blades light
// like a canopy instead of flickering black/white, and sways gently.
render_mode cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D arm_tex : filter_linear_mipmap_anisotropic;
uniform bool foliage = false;
uniform bool has_normal = true;
uniform bool has_arm = true;
uniform float saturation = 1.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float cutoff = 0.45;
void vertex() {
	if (foliage) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float h = max(VERTEX.y, 0.0);
		float sway = sin(TIME * 1.7 + origin.x * 0.4 + origin.z * 0.3) * 0.6 + sin(TIME * 3.3 + origin.x) * 0.25;
		VERTEX.xz += vec2(sway, sway * 0.5) * h * h * 0.6;
	}
}
void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (foliage) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = cutoff;
	}
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(lum), c.rgb, saturation) * tint;
	ALBEDO = col;
	vec3 arm = has_arm ? texture(arm_tex, UV).rgb : vec3(1.0, 0.8, 0.0);
	ROUGHNESS = arm.g;
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.5;
	SPECULAR = foliage ? 0.25 : 0.4;
	if (foliage) {
		vec3 n = FRONT_FACING ? NORMAL : -NORMAL;
		vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		NORMAL = normalize(mix(n, up, 0.65));
		BACKLIGHT = col * 0.6;
	} else if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
