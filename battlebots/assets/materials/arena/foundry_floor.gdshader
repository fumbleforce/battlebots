shader_type spatial;
// Meter-scaled, deterministic wear: no texture downloads or runtime image work.
varying vec3 world_pos;
uniform sampler2D steel_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.0),f.x),f.y);
}
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=world_pos.xz;
 float broad=noise(p*0.45), grain=noise(p*14.0);
 float stains=smoothstep(0.42,0.75,noise(p*0.19+12.0));
 vec3 scan=texture(steel_texture,p/6.0).rgb;
 vec3 steel=scan*1.3;
 steel=mix(steel,vec3(0.075,0.068,0.058),stains*0.55);
 vec2 seam=abs(fract((p+25.0)/2.5)-0.5)*2.5;
 float joint=1.0-smoothstep(0.012,0.027,min(seam.x,seam.y));
 steel*=1.0-joint*0.67;
 float scratches=pow(noise(p*vec2(1.8,45.0)),14.0)*0.5;
 steel+=grain*0.007;
 // Double center ring and broken perimeter safety band, all paint, no obstacles.
 float radius=length(p);
 float ring=(1.0-smoothstep(0.07,0.12,abs(radius-7.6))) +
   (1.0-smoothstep(0.025,0.06,abs(radius-8.0)));
 float edge=max(max(abs(p.x),abs(p.y)),(abs(p.x)+abs(p.y))*0.70710678);
 float band=step(23.4,edge)*(1.0-step(24.0,edge));
 float stripe=step(0.48,fract((p.x+p.y)*0.68));
 float paint=max(ring,band*stripe)*smoothstep(0.23,0.55,noise(p*7.0));
 steel=mix(steel,vec3(0.67,0.39,0.075),clamp(paint,0.0,0.85));
 // Overlapping skid arcs: understated so combat silhouettes remain readable.
 float tracks=0.0;
 for(int i=0;i<4;i++) {
  vec2 q=p-vec2(float(i)*6.1-9.0,sin(float(i)*4.0)*8.0);
  float r=length(q); float arc=step(-0.25,sin(atan(q.y,q.x)*2.0+float(i)));
  tracks+=((1.0-smoothstep(0.10,0.18,abs(r-4.2)))+
    (1.0-smoothstep(0.10,0.18,abs(r-5.4))))*arc;
 }
 ALBEDO=steel*(1.0-clamp(tracks,0.0,1.0)*0.30);
 METALLIC=0.3;
 ROUGHNESS=clamp(0.55+broad*0.25-stains*0.22+joint*0.2,0.3,0.95);
 float height=dot(scan,vec3(0.333));
 float hx=dot(texture(steel_texture,p/6.0+vec2(0.001,0)).rgb,vec3(0.333));
 float hy=dot(texture(steel_texture,p/6.0+vec2(0,0.001)).rgb,vec3(0.333));
 NORMAL_MAP=normalize(vec3((height-hx)*2.0,(height-hy)*2.0,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH=0.35;
}
