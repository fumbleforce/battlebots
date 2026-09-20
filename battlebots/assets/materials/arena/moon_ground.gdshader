shader_type spatial;
uniform sampler2D regolith : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fine_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D compact_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool playable = false;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment(){
 vec3 w=pow(abs(world_normal),vec3(4)); w/=max(w.x+w.y+w.z,.001);
 vec3 p=world_pos;
 vec3 stone=texture(rock_color,p.yz/2.6).rgb*w.x+texture(rock_color,p.xz/2.6).rgb*w.y+texture(rock_color,p.xy/2.6).rgb*w.z;
  vec3 grit=texture(regolith,p.yz/3.).rgb*w.x+texture(regolith,p.xz/3.).rgb*w.y+texture(regolith,p.xy/3.).rgb*w.z;
 stone=mix(stone,grit*.7,.48);
 vec3 dust=texture(regolith,p.xz/4.5).rgb;
 vec3 macro=texture(regolith,p.xz/29.+vec2(.31)).rgb;
 float deposit=smoothstep(.45,.88,world_normal.y);
 float compact=smoothstep(.15,.45,sin(p.x*.19+sin(p.z*.11))*cos(p.z*.14));
 vec3 packed=texture(compact_color,p.xz/3.3).rgb;
 vec3 soil=mix(dust,packed,compact*.3)*(0.8+macro*.55);
 ALBEDO=mix(stone,soil,deposit);
 ROUGHNESS=mix(.78,.97,deposit);
 vec3 micro=texture(fine_normal,p.xz/4.5).xyz*2.-1.;
  vec3 nx=texture(rock_normal,p.yz/2.6).xyz*2.-1.;
 vec3 ny=texture(rock_normal,p.xz/2.6).xyz*2.-1.;
 vec3 nz=texture(rock_normal,p.xy/2.6).xyz*2.-1.;
 vec3 bump=(vec3(0,nx.x,nx.y)*w.x+vec3(ny.x,0,ny.y)*w.y+vec3(nz.x,nz.y,0)*w.z)*.7;
 NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(bump,0)).xyz*(1.-deposit));
 NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(micro.x*.55,0,micro.y*.55,0)).xyz*deposit);
 AO=mix(1.,texture(relief,p.xz/4.5).r,.35);
 if(playable){
  float edge=max(max(abs(p.x),abs(p.z)),(abs(p.x)+abs(p.z))*.70710678);
  float strip=step(23.65,edge)*(1.-step(23.87,edge))*step(.45,fract((p.x+p.z)*.35));
  ALBEDO=mix(ALBEDO,vec3(.42,.24,.045),strip*.7);
 }
}
