shader_type spatial;
// Woodland arena ground. A 0.25 m grid displaced on the GPU from the physical
// height field (so it matches collision) plus the baked rut mask (visual
// grooves with churned lips). Materials are CC0 photoscans blended by the baked
// masks (tools/bake_woodland_masks.gd) and hex-tile sampled to hide repetition.
#include "res://assets/materials/arena/woodland_common.gdshaderinc"
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D masks : filter_linear_mipmap, repeat_disable;
uniform sampler2D lump_tex : filter_linear, repeat_disable;
uniform float arena_half = 120.0;
uniform float grid = 241.0;
uniform float rut_depth = 0.16;
uniform sampler2D mud_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocky_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocky_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rocky_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ground_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_arm : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
varying vec3 wnormal;

vec2 height_uv(vec2 xz) { return ((xz + arena_half) / (2.0 * arena_half)) * (grid - 1.0) / grid + 0.5 / grid; }
vec2 mask_uv(vec2 xz) { return (xz + arena_half) / (2.0 * arena_half); }
// Groove with raised, churned lips; r is the baked rut coverage.
float rut_profile(float r) { return -smoothstep(0.15, 1.0, r) + smoothstep(0.0, 0.15, r) * (1.0 - smoothstep(0.15, 0.45, r)) * 0.35; }
float surface(vec2 xz) {
	float h = textureLod(height_tex, height_uv(xz), 0.0).r;
	vec4 m = textureLod(masks, mask_uv(xz), 0.0);
	// Visual-only lumps and churned hummocks (<= ~0.3 m) so open ground is
	// never a flat sheet; flattened inside ruts so tracks stay crisp.
	float lumps = textureLod(lump_tex, mask_uv(xz), 0.0).r * (1.0 - smoothstep(0.05, 0.5, m.r));
	return h + lumps + rut_profile(m.r) * rut_depth;
}

// Rock strata on steep faces: layered ledges pushed along the slope's
// horizontal normal (visual only, < 0.45 m from the collision surface).
// g is the terrain gradient at the vertex, reused for neighbours.
vec3 strata(vec2 xz, float h, vec2 g) {
	float slope = length(g);
	float steep = smoothstep(0.7, 1.4, slope);
	if (steep <= 0.0) { return vec3(xz.x, h, xz.y); }
	vec2 outward = -g / max(slope, 1e-4);
	float along = dot(xz, vec2(-outward.y, outward.x));
	// Uneven bed thickness, dipping beds and blocky joints between them.
	float band = h * 0.85 + wl_fbm(vec2(along * 0.05, h * 0.15), 3) * 3.0 + along * 0.04;
	float bed = floor(band);
	float step_profile = fract(band);
	float ledge = smoothstep(0.0, 0.12 + wl_hash(vec2(bed, 1.0)) * 0.2, step_profile) * (1.0 - smoothstep(0.6, 1.0, step_profile));
	float joint_cell = floor(along / (2.5 + wl_hash(vec2(bed, 5.0)) * 4.0) + wl_hash(vec2(bed, 9.0)));
	float blocks = wl_hash(vec2(joint_cell, bed * 3.1));
	float push = (ledge * 0.55 + blocks * 0.45 - 0.5) * 0.9 * steep;
	return vec3(xz.x + outward.x * push, h + steep * (blocks - 0.5) * 0.1, xz.y + outward.y * push);
}

varying vec2 macro; // Low-frequency tone noise, per vertex (x: 50 m, y: 8 m).

void vertex() {
	vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float e = 0.25;
	// One 5-tap height stencil serves the gradient, strata and normal.
	float h0 = surface(xz);
	float hxp = surface(xz + vec2(e, 0.0)), hxn = surface(xz - vec2(e, 0.0));
	float hzp = surface(xz + vec2(0.0, e)), hzn = surface(xz - vec2(0.0, e));
	vec2 g = vec2(hxp - hxn, hzp - hzn) / (2.0 * e);
	vec3 p = strata(xz, h0, g);
	vec3 dx = strata(xz + vec2(e, 0.0), hxp, g) - strata(xz - vec2(e, 0.0), hxn, g);
	vec3 dz = strata(xz + vec2(0.0, e), hzp, g) - strata(xz - vec2(0.0, e), hzn, g);
	VERTEX.xz += p.xz - xz;
	VERTEX.y = p.y;
	vec3 n = normalize(cross(dz, dx));
	if (n.y < 0.0) { n = -n; }
	NORMAL = n;
	TANGENT = normalize(cross(n, vec3(0.0, 0.0, 1.0)));
	BINORMAL = normalize(cross(TANGENT, n));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = n;
	macro = vec2(wl_fbm(wpos.xz * 0.02, 4), wl_fbm(wpos.xz * 0.13 + 3.1, 3));
}

// --- Hex-tile sampling (after Mikkelsen, "Practical Real-Time Hex-Tiling").
struct Hex { vec2 uv1; vec2 uv2; vec2 uv3; vec3 w; mat2 r1; mat2 r2; mat2 r3; };
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(vec2(c, s), vec2(-s, c)); }
Hex hex(vec2 uv) {
	vec2 st = uv * 3.4641016;
	vec2 skewed = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054)) * st;
	vec2 base = floor(skewed);
	vec3 t = vec3(fract(skewed), 0.0);
	t.z = 1.0 - t.x - t.y;
	float s = step(0.0, -t.z);
	float s2 = 2.0 * s - 1.0;
	Hex h;
	h.w = vec3(-t.z * s2, s - t.y * s2, s - t.x * s2);
	vec2 v1 = base + vec2(s, s);
	vec2 v2 = base + vec2(s, 1.0 - s);
	vec2 v3 = base + vec2(1.0 - s, s);
	h.r1 = rot(wl_hash(v1) * 6.2831853);
	h.r2 = rot(wl_hash(v2) * 6.2831853);
	h.r3 = rot(wl_hash(v3) * 6.2831853);
	h.uv1 = h.r1 * uv + wl_hash22(v1 + 17.0);
	h.uv2 = h.r2 * uv + wl_hash22(v2 + 17.0);
	h.uv3 = h.r3 * uv + wl_hash22(v3 + 17.0);
	return h;
}
struct Layer { vec3 albedo; vec2 nxz; vec3 arm; float height; };
vec3 grad_sample(sampler2D t, vec2 uv, mat2 r, vec2 dx, vec2 dy) { return textureGrad(t, uv, r * dx, r * dy).rgb; }
Layer layer(sampler2D d, sampler2D n, sampler2D a, Hex h, vec2 uv, vec2 dx, vec2 dy) {
	vec3 c1 = grad_sample(d, h.uv1, h.r1, dx, dy);
	vec3 c2 = grad_sample(d, h.uv2, h.r2, dx, dy);
	vec3 c3 = grad_sample(d, h.uv3, h.r3, dx, dy);
	// Luminance-weighted blend keeps contrast where tiles meet.
	vec3 w = h.w * pow(vec3(dot(c1, vec3(0.3)), dot(c2, vec3(0.3)), dot(c3, vec3(0.3))) + 0.05, vec3(2.0));
	w = pow(w, vec3(3.0));
	w /= w.x + w.y + w.z;
	Layer l;
	l.albedo = c1 * w.x + c2 * w.y + c3 * w.z;
	vec2 n1 = transpose(h.r1) * (grad_sample(n, h.uv1, h.r1, dx, dy).xy * 2.0 - 1.0);
	vec2 n2 = transpose(h.r2) * (grad_sample(n, h.uv2, h.r2, dx, dy).xy * 2.0 - 1.0);
	vec2 n3 = transpose(h.r3) * (grad_sample(n, h.uv3, h.r3, dx, dy).xy * 2.0 - 1.0);
	vec2 tn = n1 * w.x + n2 * w.y + n3 * w.z;
	l.nxz = vec2(tn.x, -tn.y);
	// Roughness/AO vary slowly: one tap, no hex blend.
	l.arm = textureGrad(a, uv, dx, dy).rgb;
	l.height = dot(l.albedo, vec3(0.333));
	return l;
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	vec4 m = texture(masks, mask_uv(p));
	float rut = m.r, grass = m.g, wet = m.b, scorch = m.a;
	float big = macro.x;
	float mid = macro.y;
	float steep = 1.0 - smoothstep(0.55, 0.8, wnormal.y);
	grass *= 1.0 - steep;
	// Pre-weights decide which scanned layers are sampled at all.
	float w_mud = smoothstep(0.02, 0.5, rut) * 2.5 + wet * 1.2 + (1.0 - smoothstep(0.0, 2.5, arena_half - max(max(abs(p.x), abs(p.y)), (abs(p.x) + abs(p.y)) * 0.70710678))) * 0.6;
	float w_ground = smoothstep(0.35, 0.72, big + (mid - 0.5) * 0.5) * 1.1;
	float w_rocky = 0.9;
	float w_turf = grass * 3.0;
	vec3 col = vec3(0.0);
	vec2 tn = vec2(0.0);
	vec3 arm = vec3(0.0);
	vec4 w = vec4(w_rocky, w_ground, w_mud, w_turf);
	Layer L[4];
	// Only layers within reach of the strongest pre-weight are sampled at all.
	float cut = max(max(w.x, w.y), max(w.z, w.w)) * 0.3;
	vec4 hw = vec4(0.0);
	if (w.x > cut) { L[0] = layer(rocky_diff, rocky_nor, rocky_arm, hex(p / 3.0), p / 3.0, dFdx(p / 3.0), dFdy(p / 3.0)); hw.x = L[0].height + 0.3; }
	if (w.y > cut) { L[1] = layer(ground_diff, ground_nor, ground_arm, hex(p / 3.4 + 0.37), p / 3.4, dFdx(p / 3.4), dFdy(p / 3.4)); hw.y = L[1].height + 0.3; }
	if (w.z > cut) { L[2] = layer(mud_diff, mud_nor, mud_arm, hex(p / 5.5 + 0.71), p / 5.5, dFdx(p / 5.5), dFdy(p / 5.5)); hw.z = 1.1 - L[2].height; }
	if (w.w > cut) { L[3] = layer(grass_diff, grass_nor, grass_arm, hex(p / 2.2 + 0.13), p / 2.2, dFdx(p / 2.2), dFdy(p / 2.2)); hw.w = L[3].height + 0.4; }
	vec4 bw = pow(max(w * hw, vec4(0.0001)), vec4(4.0));
	bw /= bw.x + bw.y + bw.z + bw.w;
	// The scanned mud is ochre clay; the reference mud is a dark brown.
	if (hw.z > 0.0) {
		float lum = dot(L[2].albedo, vec3(0.299, 0.587, 0.114));
		L[2].albedo = mix(vec3(lum), L[2].albedo, 0.35) * vec3(0.62, 0.55, 0.48);
	}
	for (int i = 0; i < 4; i++) {
		if (hw[i] > 0.0 && bw[i] > 0.0005) {
			col += L[i].albedo * bw[i];
			tn += L[i].nxz * bw[i];
			arm += L[i].arm * bw[i];
		}
	}
	col *= 0.82 + big * 0.3 + (mid - 0.5) * 0.2;
	// Churned, lighter lips and darker wet groove floors.
	float lip = smoothstep(0.0, 0.25, rut) * (1.0 - smoothstep(0.25, 0.5, rut));
	col *= 1.0 + lip * 0.12 - smoothstep(0.5, 1.0, rut) * 0.18;
	col = mix(col, col * vec3(0.45, 0.41, 0.37), wet * 0.7);
	// Scorch: soot mottled by fine noise, strongest at the blast centre.
	float soot = scorch > 0.1 ? smoothstep(0.1, 0.7, scorch) * (0.6 + 0.4 * wl_fbm(p * 1.3, 3)) : 0.0;
	col = mix(col, col * 0.16, soot * 0.85);
	// Standing water in wet grooves: a flat, dark, reflective surface.
	float puddle = smoothstep(0.3, 0.7, rut) * smoothstep(0.35, 0.7, wet) * smoothstep(0.97, 0.995, wnormal.y);
	col = mix(col, col * 0.4 + vec3(0.015, 0.014, 0.012), puddle);
	// Steep faces are scanned granite projected from the side.
	vec3 an = abs(wnormal);
	float bx = an.x / max(an.x + an.z, 0.001);
	if (steep > 0.01) {
		vec3 rc = mix(texture(rock_diff, wpos.xy / 5.0).rgb, texture(rock_diff, wpos.zy / 5.0).rgb, bx);
		vec3 ra = mix(texture(rock_arm, wpos.xy / 5.0).rgb, texture(rock_arm, wpos.zy / 5.0).rgb, bx);
		// Weathered strata: darker seams under each ledge, lighter tops.
		float band = fract(wpos.y * 0.85 + wl_fbm(vec2((wpos.x + wpos.z) * 0.05, wpos.y * 0.15), 3) * 3.0 + (wpos.x + wpos.z) * 0.03);
		rc *= mix(0.6, 1.08, smoothstep(0.0, 0.18, band)) * (1.0 - smoothstep(0.88, 1.0, band) * 0.25);
		// Lichen and water streaks down the face.
		float streak = wl_noise(vec2((wpos.x - wpos.z) * 1.7, wpos.y * 0.12));
		rc = mix(rc, rc * vec3(0.55, 0.52, 0.46), smoothstep(0.55, 0.85, streak) * 0.6);
		col = mix(col, rc * 0.85, steep);
		arm = mix(arm, ra, steep);
	}
	ALBEDO = col;
	ROUGHNESS = mix(clamp(arm.g * (1.0 - wet * 0.3), 0.3, 1.0), 0.42, puddle);
	SPECULAR = mix(0.4, 0.35, puddle);
	AO = mix(arm.r, 1.0, puddle);
	AO_LIGHT_AFFECT = 0.3;
	float fade = mix(1.0, 0.8, smoothstep(60.0, 200.0, dist));
	vec3 nw = normalize(wnormal + vec3(tn.x, 0.0, tn.y) * fade * (1.0 - puddle));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
