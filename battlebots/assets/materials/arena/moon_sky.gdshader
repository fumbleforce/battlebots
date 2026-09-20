shader_type sky;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
void sky() {
 vec3 d=normalize(EYEDIR);
 vec3 grid=d*650.0;
 float h=hash(floor(grid));
 vec3 f=fract(grid)-0.5;
 float star=pow(max(0.0,1.0-length(f)*2.0),10.0)*step(0.989,h);
 COLOR=vec3(0.00025,0.00035,0.0006)+vec3(star)*0.5;
}
