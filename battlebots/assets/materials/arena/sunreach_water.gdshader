shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform bool waterfall = false;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform float water_level = -0.8;
uniform float arena_half = 120.0;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=waterfall ? vec2(world.x,world.y+TIME*5.0) : world.xz+vec2(TIME*.6,TIME*.2);
 float ribbons=sin(p.y*2.6+sin(p.x*.68)*1.4);
 float streak=smoothstep(.965,1.0,ribbons)*smoothstep(.3,.8,sin(p.x*.55+p.y*.15));
 float depth=water_level-texture(height_tex,(world.xz+arena_half+.5)/(arena_half*2.0+1.0)).r;
 if(!waterfall && depth<.015) discard;
 vec3 deep=vec3(.025,.25,.32); vec3 shallow=vec3(.12,.47,.43);
 float shore=1.0-smoothstep(.04,.32,depth);
 ALBEDO=mix(mix(shallow,deep,smoothstep(.1,1.9,depth)),vec3(.59,.80,.72),max(streak*.35,shore*.72));
 if(waterfall) {
  float flow=.5+.5*sin(p.x*6.0+sin(p.y*.75)+sin(p.y*.17)*2.0);
  ALBEDO=mix(vec3(.18,.52,.57),vec3(.72,.86,.83),smoothstep(.18,.85,flow));
 }
 ROUGHNESS=.32; SPECULAR=.45;
 EMISSION=ALBEDO*.025;
}
