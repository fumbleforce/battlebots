shader_type spatial;
uniform vec4 paint_color : source_color = vec4(0.23,0.26,0.28,1.0);
uniform bool hazard = false;
uniform bool banded = false;
uniform bool panelized = false;
uniform float base_metallic = 0.78;
uniform float base_roughness = 0.46;
uniform float texture_strength = 0.45;
uniform sampler2D steel_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying vec3 world_normal;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 float wear=noise(world_pos*12.0), grime=noise(world_pos*0.8);
 vec3 n=pow(abs(world_normal),vec3(4.0)); n/=n.x+n.y+n.z;
 vec3 scan=texture(steel_texture,world_pos.yz/3.0).rgb*n.x+
  texture(steel_texture,world_pos.xz/3.0).rgb*n.y+
  texture(steel_texture,world_pos.xy/3.0).rgb*n.z;
 float brightness=dot(scan,vec3(0.3333));
 vec3 color=paint_color.rgb*mix(1.0,0.65+brightness*2.2,texture_strength);
 bool painted = hazard && (!banded || (world_pos.y > 1.45 && world_pos.y < 2.8));
 float chip=0.0;
 if(painted) {
  vec2 tangent=normalize(vec2(world_normal.z,-world_normal.x)+vec2(0.0001));
  float stripe=step(0.5,fract((dot(world_pos.xz,tangent)+world_pos.y)*0.7));
  color=mix(vec3(0.018,0.022,0.025),vec3(0.85,0.48,0.07),stripe);
  chip=1.0-smoothstep(0.20,0.34,wear);
  color=mix(color,scan*0.8,chip);
 }
 float panel_height=0.0;
 if(panelized) {
  vec2 tangent=normalize(vec2(world_normal.z,-world_normal.x)+vec2(0.0001));
  vec2 at=vec2(dot(world_pos.xz,tangent),world_pos.y);
  vec2 panel=abs(fract(at/vec2(3.45,2.8))-0.5)*vec2(3.45,2.8);
  vec2 edge=vec2(1.725,1.4)-panel;
  float seam=1.0-smoothstep(0.009,0.024,min(edge.x,edge.y));
  float bolt_dist=length(panel-vec2(1.59,1.265));
  float washer=1.0-smoothstep(0.07,0.09,bolt_dist);
  float bolt=1.0-smoothstep(0.035,0.06,bolt_dist);
  color*=1.0-seam*0.85;
  color=mix(color,vec3(0.015),washer);
  color=mix(color,vec3(0.23,0.24,0.25),bolt);
  panel_height=-seam*0.009+bolt*0.008;
  AO=1.0-seam*0.5-washer*(1.0-bolt)*0.4;
 }
 ALBEDO=color*(0.84+grime*0.22);
 METALLIC=painted ? mix(0.10,0.86,chip) : base_metallic;
 ROUGHNESS=clamp(base_roughness+(0.5-brightness)*0.25+grime*0.08,0.22,0.95);
 float h=brightness*0.003*texture_strength+panel_height;
 vec3 px=dFdx(VERTEX), py=dFdy(VERTEX);
 vec3 rx=cross(py,NORMAL), ry=cross(NORMAL,px);
 float determinant=dot(px,rx);
 NORMAL=normalize(abs(determinant)*NORMAL-sign(determinant)*(dFdx(h)*rx+dFdy(h)*ry));
}
