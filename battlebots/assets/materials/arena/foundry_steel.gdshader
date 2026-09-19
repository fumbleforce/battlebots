shader_type spatial;
uniform vec4 paint_color : source_color = vec4(0.23,0.26,0.28,1.0);
uniform bool hazard = false;
uniform bool banded = false;
uniform sampler2D steel_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_pos;
varying vec3 world_normal;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
 mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { local_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment() {
 float wear=noise(local_pos*9.0), grime=noise(local_pos*3.0);
 vec3 color=paint_color.rgb;
 bool painted = hazard && (!banded || (local_pos.y > 1.45 && local_pos.y < 2.8));
 vec2 tangent=normalize(vec2(world_normal.z,-world_normal.x)+vec2(0.0001));
 if(painted) { color=mix(vec3(0.045,0.05,0.047),vec3(0.78,0.48,0.095),step(0.5,fract((dot(local_pos.xz,tangent)+local_pos.y)*0.7))); }
 vec3 n=abs(world_normal); n/=n.x+n.y+n.z;
 vec3 scan=texture(steel_texture,local_pos.yz/4.0).rgb*n.x+
  texture(steel_texture,local_pos.xz/4.0).rgb*n.y+
  texture(steel_texture,local_pos.xy/4.0).rgb*n.z;
 color=mix(color,scan,0.17);
 if(painted) { color=mix(scan,color,smoothstep(0.18,0.34,wear)); }
 ALBEDO=color*(0.75+dot(scan,vec3(0.5)));
 METALLIC=0.35;
 ROUGHNESS=0.57+grime*0.3;
}
