shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
varying float age;
varying float seed;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() {
 float angle=INSTANCE_CUSTOM.x;
 vec2 spin=vec2(cos(angle),sin(angle));
 vec3 right=INV_VIEW_MATRIX[0].xyz*spin.x+INV_VIEW_MATRIX[1].xyz*spin.y;
 vec3 up=-INV_VIEW_MATRIX[0].xyz*spin.y+INV_VIEW_MATRIX[1].xyz*spin.x;
 vec3 s=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(vec4(right*s.x,0),vec4(up*s.y,0),vec4(INV_VIEW_MATRIX[2].xyz*s.z,0),MODEL_MATRIX[3]);
 MODELVIEW_NORMAL_MATRIX=mat3(MODELVIEW_MATRIX);
 seed=fract(sin(angle*17.13)*437.7);
 age=INSTANCE_CUSTOM.y;
}
void fragment() {
 vec2 p=UV*2.0-1.0;
 vec2 drift=vec2(seed*11.0,age*.7);
 float billow=noise(UV*3.5+drift)*.7+noise(UV*8.0+drift)*.3;
 float edge=1.0-smoothstep(.2,1.0,length(p)+(billow-.5)*.4);
 ALBEDO=mix(vec3(.32,.31,.29),vec3(.57,.55,.51),billow)*COLOR.rgb;
 ROUGHNESS=1.0; SPECULAR=0.0;
 NORMAL=normalize(vec3(p.x*.4,-p.y*.4,.9));
 float depth=textureLod(depth_texture,SCREEN_UV,0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 vec3 ndc=vec3(SCREEN_UV,depth)*2.0-1.0;
#else
 vec3 ndc=vec3(SCREEN_UV*2.0-1.0,depth);
#endif
 vec4 scene=INV_PROJECTION_MATRIX*vec4(ndc,1.0);
 scene.xyz/=scene.w;
 float contact=smoothstep(0.0,.3,VERTEX.z-scene.z);
 ALPHA=edge*edge*mix(.45,1.0,billow)*COLOR.a*.38*contact;
}
