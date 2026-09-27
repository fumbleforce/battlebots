shader_type sky;
float hash(vec2 p){uvec2 q=uvec2(ivec2(floor(p)));uint n=q.x*1597334677u+q.y*3812015801u;n=(n^(n>>16u))*2246822519u;return float(n^(n>>13u))/4294967295.0;}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void sky(){
 float up=max(EYEDIR.y,0.0);
 vec3 blue=mix(vec3(.47,.68,.77),vec3(.10,.36,.66),pow(up,.45));
 vec2 p=EYEDIR.xz/max(.12,EYEDIR.y+.08)*1.1;
 float cloud=noise(p*.6)*.55+noise(p*1.4)*.30+noise(p*3.3)*.15;
 float cover=smoothstep(.56,.72,cloud)*smoothstep(.01,.12,up);
 vec3 cotton=mix(vec3(.60,.72,.77),vec3(.89,.92,.86),smoothstep(.54,.76,cloud));
 COLOR=mix(blue,cotton,cover);
 if(EYEDIR.y<0.0) COLOR=mix(vec3(.47,.68,.77),vec3(.16,.24,.14),smoothstep(0.0,.2,-EYEDIR.y));
}
