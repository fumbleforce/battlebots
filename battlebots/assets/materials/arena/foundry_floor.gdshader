shader_type spatial;
// Meter-scaled steel plates. Wear changes reflections as well as base color.
varying vec3 world_pos;
uniform float arena_half_extent = 50.0;
uniform sampler2D steel_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);
}
vec2 plate_uv(vec2 p) {
 vec2 cell=floor(p/2.5), q=fract(p/2.5)-0.5;
 float seed=hash(cell);
 if(seed>0.5) { q=q.yx; }
 q.x*=seed>0.25 && seed<0.75 ? -1.0 : 1.0;
 q.y*=seed>0.5 ? -1.0 : 1.0;
 return q*0.85+vec2(hash(cell+21.0),hash(cell+53.0));
}
// Physical-height detail is shading only: neither plate joints nor bolts snag wheels.
float surface_height(vec2 p) {
 vec2 plate=abs(fract(p/2.5)-0.5)*2.5;
 float seam=1.25-max(plate.x,plate.y);
 float bolt=length(plate-vec2(1.10));
 float joint=-0.010*(1.0-smoothstep(0.007,0.024,seam));
 float washer=-0.004*(1.0-smoothstep(0.055,0.072,bolt));
 float head=0.006*(1.0-smoothstep(0.035,0.055,bolt));
 float scratch=dot(texture(steel_texture,plate_uv(p)).rgb,vec3(0.3333));
 return joint+washer+head+scratch*0.002+noise(p*2.3)*0.002;
}
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=world_pos.xz;
 vec3 scan=texture(steel_texture,plate_uv(p)).rgb;
 scan=mix(vec3(dot(scan,vec3(0.2126,0.7152,0.0722))),scan,0.5);
 float abrasion=smoothstep(0.11,0.40,dot(scan,vec3(0.3333)));
 float oil=smoothstep(0.48,0.83,noise(p*0.19+12.0));
 vec2 panel=abs(fract(p/2.5)-0.5)*2.5;
 float seam=1.25-max(panel.x,panel.y);
 float joint=1.0-smoothstep(0.007,0.024,seam);
 float polished_edge=(1.0-smoothstep(0.03,0.065,seam))*(1.0-joint);
 float bolt_distance=length(panel-vec2(1.10));
 float washer=1.0-smoothstep(0.055,0.075,bolt_distance);
 float bolt=1.0-smoothstep(0.036,0.055,bolt_distance);
 float socket=1.0-smoothstep(0.012,0.019,bolt_distance);
 float plate_tone=mix(0.83,1.12,hash(floor(p/2.5)));
 vec3 steel=scan*plate_tone*0.95;
 steel=mix(steel,vec3(0.060,0.047,0.032),oil*0.4);
 steel=mix(steel,vec3(0.31,0.32,0.33),polished_edge*0.25);
 steel*=1.0-joint*0.86;
 steel=mix(steel,vec3(0.026),washer*0.85);
 steel=mix(steel,vec3(0.26,0.28,0.29),bolt*0.85);
 steel*=1.0-socket*0.85;
 // Double center ring and chipped perimeter paint.
 float radius=length(p);
 float ring=(1.0-smoothstep(0.075,0.13,abs(radius-15.6)))+
  (1.0-smoothstep(0.025,0.07,abs(radius-16.0)));
 float edge=max(max(abs(p.x),abs(p.y)),(abs(p.x)+abs(p.y))*0.70710678);
 float band=step(arena_half_extent-1.6,edge)*(1.0-step(arena_half_extent-1.0,edge));
 float stripe=step(0.48,fract((p.x+p.y)*0.68));
 float paint=clamp(max(ring,band*stripe)*smoothstep(0.24,0.46,noise(p*7.0)),0.0,1.0);
 steel=mix(steel,vec3(0.78,0.46,0.075),paint);
 float tracks=0.0;
 for(int i=0;i<4;i++) {
  vec2 q=p-vec2(float(i)*6.1-9.0,sin(float(i)*4.0)*8.0);
  float r=length(q); float arc=step(-0.25,sin(atan(q.y,q.x)*2.0+float(i)));
  tracks+=((1.0-smoothstep(0.10,0.18,abs(r-4.2)))+
    (1.0-smoothstep(0.10,0.18,abs(r-5.4))))*arc;
 }
 ALBEDO=steel*(1.0-clamp(tracks,0.0,1.0)*0.24);
 METALLIC=mix(0.87,0.12,paint);
 ROUGHNESS=clamp(mix(0.58,0.34,abrasion)+oil*0.11+joint*0.25+paint*0.16,0.24,0.85);
 SPECULAR=0.5;
 AO=1.0-joint*0.65-washer*(1.0-bolt)*0.30;
 // Derivative bump uses real view-space surface directions, independent of box UVs.
 float h=surface_height(p);
 vec3 px=dFdx(VERTEX), py=dFdy(VERTEX);
 vec3 rx=cross(py,NORMAL), ry=cross(NORMAL,px);
 float determinant=dot(px,rx);
 vec3 gradient=sign(determinant)*(dFdx(h)*rx+dFdy(h)*ry);
 NORMAL=normalize(abs(determinant)*NORMAL-gradient);
}
