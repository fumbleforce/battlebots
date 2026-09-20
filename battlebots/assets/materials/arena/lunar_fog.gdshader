shader_type fog;
uniform float pulse = 0.5;
void fog(){
 vec3 p=WORLD_POSITION;
 float waves=sin(p.x*1.1+TIME*.15)*sin(p.z*.85-TIME*.2)*sin(p.y*1.7-TIME*.28);
 float edge=1.-smoothstep(.2,.5,length(UVW-.5));
 DENSITY=(.065+.035*waves)*pulse*edge;
 ALBEDO=vec3(.53,.58,.63);
 EMISSION=vec3(.003,.005,.008);
}


