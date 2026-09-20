shader_type spatial;
render_mode unshaded, fog_disabled;
uniform sampler2D earth_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 sphere;
void vertex() { sphere=normalize(VERTEX); }
void fragment() {
 vec3 n=normalize(sphere);
 vec3 earth=texture(earth_texture,UV+vec2(0.2,0)).rgb;
 float daylight=smoothstep(-0.12,0.7,dot(n,normalize(vec3(-0.7,0.35,1))));
 float rim=pow(1.0-max(dot(NORMAL,VIEW),0.0),3.0);
 ALBEDO=earth*(0.015+daylight*0.85)+vec3(0.045,0.17,0.42)*rim*daylight*0.7;
}
