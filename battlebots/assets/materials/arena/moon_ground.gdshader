shader_type spatial;
uniform sampler2D regolith : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool playable = false;
varying vec3 world_pos;
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=world_pos.xz;
 vec3 fine=texture(regolith,p/5.0).rgb;
 vec3 broad=texture(regolith,p/23.0+vec2(0.37)).rgb;
 vec3 ground=mix(fine,broad,0.3)*0.8;
 if(playable) {
  float edge=max(max(abs(p.x),abs(p.y)),(abs(p.x)+abs(p.y))*0.70710678);
  float strip=step(23.65,edge)*(1.0-step(23.87,edge));
  float dash=step(0.45,fract((p.x+p.y)*0.35));
  ground=mix(ground,vec3(0.68,0.47,0.12),strip*dash*0.6);
  float rut=(1.0-smoothstep(0.12,0.22,abs(length(p-vec2(-4,2))-7.0)))+
   (1.0-smoothstep(0.12,0.22,abs(length(p-vec2(-4,2))-8.2)));
  ground*=1.0-rut*0.10;
 }
 ALBEDO=ground;
 ROUGHNESS=0.94;
 float h=dot(fine,vec3(0.333));
 float hx=dot(texture(regolith,p/5.0+vec2(0.001,0)).rgb,vec3(0.333));
 float hy=dot(texture(regolith,p/5.0+vec2(0,0.001)).rgb,vec3(0.333));
 // World-projected microrelief also works on terrain meshes without UV tangents.
 NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4((h-hx)*2.0,0.0,(h-hy)*2.0,0.0)).xyz);
}
