shader_type spatial;
uniform vec4 paint : source_color=vec4(.5,.5,.5,1);
uniform float metalness=.5;
uniform float rough=.5;
uniform sampler2D grain : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 p;
varying vec3 n;
void vertex(){p=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;n=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
void fragment(){
 vec3 w=pow(abs(n),vec3(4));w/=max(dot(w,vec3(1)),.001);
 float fleck=texture(grain,p.yz*2.).b*w.x+texture(grain,p.xz*2.).b*w.y+texture(grain,p.xy*2.).b*w.z;
 float deposits=smoothstep(.48,.8,n.y)*.2;
 ALBEDO=mix(paint.rgb*(.8+fleck*.4),vec3(.27,.26,.24),deposits);
 METALLIC=metalness*(1.-deposits);
 ROUGHNESS=clamp(rough+(fleck-.5)*.3+deposits,.15,1.);
}
