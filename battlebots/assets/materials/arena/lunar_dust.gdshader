shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
void vertex(){
 vec3 s=vec3(length(MODEL_MATRIX[0].xyz),length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz));
 MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0]*s.x,INV_VIEW_MATRIX[1]*s.y,INV_VIEW_MATRIX[2]*s.z,MODEL_MATRIX[3]);
 MODELVIEW_NORMAL_MATRIX=mat3(MODELVIEW_MATRIX);
}
void fragment(){
 float r=length(UV-.5)*2.;
 float lobes=.8+.2*sin(UV.x*19.+sin(UV.y*13.))*cos(UV.y*17.);
 float alpha=(1.-smoothstep(.05,lobes,r));
 ALBEDO=vec3(.43,.44,.45)*COLOR.rgb;
 ROUGHNESS=1.;
 ALPHA=alpha*alpha*COLOR.a*.22;
}
