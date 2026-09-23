shader_type fog;
uniform float density = 0.0;
uniform float age = 0.0;
void fog() {
 vec3 p=(UVW-.5)*2.0;
 float edge=1.0-smoothstep(.1,1.0,length(p));
 vec3 q=WORLD_POSITION*4.0;
 float curl=sin(q.x+sin(q.z-age))*sin(q.y-age*2.0)*sin(q.z+age);
 DENSITY=density*edge*edge*(.7+.3*curl);
 ALBEDO=vec3(.075,.08,.085);
}
