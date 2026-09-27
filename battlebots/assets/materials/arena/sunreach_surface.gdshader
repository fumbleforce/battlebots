shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform int kind = 0;
uniform sampler2D paint_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.18;
varying vec3 world;
varying vec3 paint;
varying vec3 normal_world;
float hash(vec2 p) { uvec2 q=uvec2(ivec2(floor(p))); uint n=q.x*1597334677u+q.y*3812015801u; n=(n^(n>>16u))*2246822519u; return float(n^(n>>13u))/4294967295.0; }
float noise(vec2 p) {vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex() {
 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 paint=COLOR.rgb;
 normal_world=normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
 if(kind==3 || kind==4) {
  float flex=kind==4 ? clamp(VERTEX.y-floor(VERTEX.y),0.0,1.0)*0.16 : 0.06;
  VERTEX.x+=sin(world.x*.33+world.z*.24+TIME*1.45)*flex;
 }
}
void fragment() {
 vec3 weights=pow(abs(normal_world),vec3(4.0));
 weights/=max(dot(weights,vec3(1.0)),.001);
 vec3 tex=texture(paint_texture,world.yz*.28).rgb*weights.x+texture(paint_texture,world.xz*.28).rgb*weights.y+texture(paint_texture,world.xy*.28).rgb*weights.z;
 if(kind==2) tex=texture(paint_texture,UV*detail_scale).rgb;
 float luminance=dot(tex,vec3(.25,.6,.15));
 float brush=floor(luminance*7.0)/7.0;
 float cloud=noise(world.xz*.32+world.y*.12);
 float pigment=0.76+brush*.48+(cloud-.5)*.17;
 ALBEDO=paint*pigment*mix(vec3(1.0),tex/(luminance+.001),.22);
 ROUGHNESS=.93;
 if(kind==0) ALBEDO*=.86+.23*floor(noise(world.xz*2.7)*5.0)/5.0;
 if(kind==1) { // Limestone: mineral seams and broad ochre weathering, no glitter.
  float stratum=noise(vec2(world.x*.15+world.z*.13,world.y*1.7));
  ALBEDO*=.93+.12*smoothstep(.24,.66,stratum);
 }
 if(kind==2) { // Timber: long grain follows each plank's authored UVs.
  float grain=noise(UV*vec2(.8,39.0));
  ALBEDO*=.83+.26*smoothstep(.18,.8,grain);
 }
 if(kind==3 || kind==4) {
  float leaves=noise(world.xz*3.7+world.y*vec2(2.8,3.2));
  ALBEDO*=.76+.36*smoothstep(.25,.72,leaves);
  BACKLIGHT=paint*.25;
  ROUGHNESS=1.0;
 }
}
