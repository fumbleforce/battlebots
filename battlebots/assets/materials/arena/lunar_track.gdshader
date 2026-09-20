shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform float opacity=1.0;
void fragment(){
 float edge=smoothstep(0.,.08,UV.x)*(1.-smoothstep(.92,1.,UV.x));
 float tread=smoothstep(.2,.35,fract(UV.y*6.+abs(UV.x-.5)*1.8));
 ALBEDO=vec3(.12,.13,.14); ROUGHNESS=1.; ALPHA=edge*tread*opacity*.32;
}
