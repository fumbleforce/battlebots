"""Reproducible authored Sunreach kit and scene. Run: blender -b --python art_source/sunreach/build_arena.py
Godot metres/Y-up below; convert only at export. Collision hulls and height samples
are exported from the very vertices used for art, without loading art on servers.
"""
import bpy, math, random, json, struct
from pathlib import Path
from mathutils import Vector
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'battlebots/assets/models/sunreach'
DATA=ROOT/'battlebots/data/sunreach'
C=json.loads((DATA/'layout.json').read_text())
R=random.Random(C['seed']); H=C['half']; STEP=C['grid_step']; N=int(H*2/STEP)+1
SP=json.loads((ROOT/'battlebots/data/arena_spawns.json').read_text())['arenas']['sunreach']
pads=[(x*s,z*s) for s in (1,-1) for x,z in SP['team']]
pads += [(math.sin(i*math.tau/8)*SP['ffa_radius'],math.cos(i*math.tau/8)*SP['ffa_radius']) for i in range(8)]
pads += [(0,0),(0,10),(-13,-2),(12,-11)]
duel=json.loads((ROOT/"battlebots/data/arena_spawns.json").read_text())["duel"]["monowheels"]["side_fraction_by_arena"]["sunreach"]*H
travel=json.loads((ROOT/"battlebots/data/arena_spawns.json").read_text())["duel"]["shuttle"]["travel"]
pads += [(-duel,0),(duel,0),(0,-duel),(duel,-travel),(duel,travel)]
def smooth(a,b,v):
 t=max(0,min(1,(v-a)/(b-a))); return t*t*(3-2*t)
def distseg(x,z,a,b):
 dx=b[0]-a[0]; dz=b[1]-a[1]; t=max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)))
 return math.hypot(x-a[0]-t*dx,z-a[1]-t*dz)
def pathdist(x,z,paths): return min(distseg(x,z,a,b) for p in paths for a,b in zip(p,p[1:]))
def road(x,z): return pathdist(x,z,C['roads'])
def river(x,z): return pathdist(x,z,C['streams'])
def rawheight(x,z):
 h=0.8+0.5*math.sin(x*.034)*math.cos(z*.045)+.28*math.cos((x+z)*.063)
 d=river(x,z); h=h*(smooth(5,12,d)) - C['stream_depth']*(1-smooth(2,11,d))
 for mx,mz,radius,peak in C['mounds']:
  h+=peak*(1-smooth(radius*.25,radius,math.hypot(x-mx,z-mz)))*smooth(7,14,d)
 for b in C['bridges']:
  # Level abutments. The riverbed stays below the deck.
  dx=abs(x-b['x']); dz=abs(z-b['z'])
  if dz>8:
   w=(1-smooth(9,16,dx))*(1-smooth(20,32,dz))*smooth(8,11,dz)
   h=h*(1-w)+b['deck_height']*w
 for px,pz in pads:
  w=1-smooth(C['spawn_pad_radius'],C['spawn_pad_radius']+C['spawn_pad_blend'], math.hypot(x-px,z-pz))
  h=h*(1-w)
 for b in C["bridges"]:
  dx=abs(x-b["x"]);dz=abs(z-b["z"])
  grade=(1-smooth(8,11,dx))*(1-smooth(18,30,dz))*smooth(10,13,dz)
  h=h*(1-grade)+b["deck_height"]*grade
  if abs(x-b["x"])<b["width"]*.5+1 and abs(z-b["z"])<=b["length"]*.5: h=min(h,b["deck_height"]-.15)
 return h
heights=[rawheight(-H+x*STEP,-H+z*STEP) for z in range(N) for x in range(N)]
def height(x,z):
 fx=max(0,min(N-1.000001,(x+H)/STEP)); fz=max(0,min(N-1.000001,(z+H)/STEP)); ix=int(fx); iz=int(fz); tx=fx-ix; tz=fz-iz
 a=heights[iz*N+ix]; b=heights[iz*N+ix+1]; c=heights[(iz+1)*N+ix]; d=heights[(iz+1)*N+ix+1]
 return a+(b-a)*tx+(c-a)*tz if tx+tz<1 else d+(c-d)*(1-tx)+(b-d)*(1-tz)
(DATA/'heights.bin').write_bytes(struct.pack('<%df'%len(heights),*heights))
# Mesh batches: 30 m cells keep culling local, surfaces retain material roles.
batches={}; colliders=[]
COL={'stone':(.43,.47,.46),'cliff':(.43,.49,.50),'wood':(.40,.29,.15),'iron':(.19,.22,.21),'bark':(.29,.27,.14),'leaf':(.43,.57,.12),'pine':(.15,.34,.21),'grass':(.49,.59,.15),'flower':(.93,.88,.57),'water':(.15,.66,.71),'foam':(.80,.91,.83),'terrain':(.5,.6,.2),'gravel':(.5,.5,.4)}
def add(kind,vs,fs,cols=None,cell=None):
 if not vs:return
 if cell is None: cell=(int(sum(v[0] for v in vs)/len(vs)//30),int(sum(v[2] for v in vs)/len(vs)//30))
 key=(kind,*cell)
 if key not in batches:batches[key]=[[],[],[]]
 vv,ff,cc=batches[key]; off=len(vv); vv.extend(vs); ff.extend([tuple(off+i for i in f) for f in fs]); cc.extend(cols or [(*COL[kind],1)]*len(vs))
def tint(kind,f): return tuple(min(1,c*f) for c in COL[kind])+(1,)
def hull(name,vs):colliders.append({'name':name,'points':[[round(c,4) for c in v] for v in vs]})
# Reuse the project's licensed granite silhouettes, recoloured for this map.
rock_templates=[]
for name in ['granite_boulder_a','granite_boulder_b','granite_boulder_c']:
 before=set(bpy.data.objects)
 bpy.ops.import_scene.gltf(filepath=str(ROOT/'battlebots/assets/models/woodland'/f'{name}.gltf'))
 obs=[o for o in bpy.data.objects if o not in before]
 for ob in obs:
  if ob.type!='MESH':continue
  bpy.context.view_layer.objects.active=ob
  mod=ob.modifiers.new('Sunreach silhouette LOD','DECIMATE');mod.ratio=.32
  bpy.ops.object.modifier_apply(modifier=mod.name)
  v=[ob.matrix_world@p.co for p in ob.data.vertices]
  lo=[min(p[k] for p in v) for k in range(3)];hi=[max(p[k] for p in v) for k in range(3)]
  verts=[((p.x-(lo[0]+hi[0])/2)/((hi[0]-lo[0])/2), (p.z-lo[2])/(hi[2]-lo[2]), -(p.y-(lo[1]+hi[1])/2)/((hi[1]-lo[1])/2)) for p in v]
  directions=[(math.sin(i*2.39996)*math.sqrt(1-(1-2*(i+.5)/96)**2),1-2*(i+.5)/96,math.cos(i*2.39996)*math.sqrt(1-(1-2*(i+.5)/96)**2)) for i in range(96)]
  hull_vertices=list(set(max(verts,key=lambda v:sum(v[k]*d[k] for k in range(3))) for d in directions))
  rock_templates.append((verts,[tuple(poly.vertices) for poly in ob.data.polygons],hull_vertices))
 for ob in obs:bpy.data.objects.remove(ob,do_unlink=True)
def rock(x,y,z,sx,sy,sz,kind='cliff',collision=False):
 if kind in ('cliff','stone'):
  template,fs,hull_template=R.choice(rock_templates);a=R.random()*math.tau;co=math.cos(a);si=math.sin(a)
  vs=[(x+(px*co+pz*si)*sx,y+py*sy,z+(-px*si+pz*co)*sz) for px,py,pz in template]
  colors=[]
  for px,py,pz in template:
   factor=.87+.16*py+.07*math.sin(px*4+pz*3+py*5)
   c=tint(kind,factor)
   if py>.86 and R.random()<.6:c=(.29,.38,.13,1)
   colors.append(c)
  add(kind,vs,fs,colors)
  if collision:
   # Convex hull from all authored vertices, Jolt simplifies coplanar points.
   hull('Rock',[(x+(px*co+pz*si)*sx,y+py*sy,z+(-px*si+pz*co)*sz) for px,py,pz in hull_template])
  return vs
 # Soft, overlapping canopy lobes; clipped tips keep a leafy silhouette.
 vs=[];sides=12;rings=7;phase=R.random()*6.28
 for k in range(rings):
  theta=.06+(math.pi-.12)*k/(rings-1)
  for j in range(sides):
   a=phase+j*math.tau/sides;r=math.sin(theta)*(1+.08*math.sin(a*5+k))
   vs.append((x+math.cos(a)*sx*r,y+sy*(.5-.5*math.cos(theta)),z+math.sin(a)*sz*r))
 fs=[tuple(reversed(range(sides))),tuple((rings-1)*sides+j for j in range(sides))]
 for k in range(rings-1):
  for j in range(sides):fs.append((k*sides+j,k*sides+(j+1)%sides,(k+1)*sides+(j+1)%sides,(k+1)*sides+j))
 colors=[tint(kind,.77+.38*(v[1]-y)/sy+R.uniform(-.035,.035)) for v in vs]
 add(kind,vs,fs,colors)
 return vs
# Hand chipped/chamfered masonry/timber: three octagonal cross sections.
def block(kind,pos,size,yaw=0,collision=False):
 x,y,z=pos; w,h,d=size; cut=min(w,h,d)*(.09 if kind=="stone" else .10); vs=[]
 ring=[(-w/2+cut,-d/2),(w/2-cut,-d/2),(w/2,-d/2+cut),(w/2,d/2-cut),(w/2-cut,d/2),(-w/2+cut,d/2),(-w/2,d/2-cut),(-w/2,-d/2+cut)]
 for k in range(4):
  yy=[-h/2,-h/2+cut,h/2-cut,h/2][k]
  for xx,zz in ring:
   noise=R.uniform(-.045,.045)*min(w,d) if kind=='stone' else 0
   q=.95 if k in (0,3) else 1
   a=xx*q+noise; b=zz*q+noise
   vs.append((x+math.cos(yaw)*a+math.sin(yaw)*b,y+yy,z-math.sin(yaw)*a+math.cos(yaw)*b))
 fs=[tuple(reversed(range(8))),tuple(range(24,32))]
 for k in range(3):
  for i in range(8):fs.append((k*8+i,k*8+(i+1)%8,(k+1)*8+(i+1)%8,(k+1)*8+i))
 f=R.uniform(.86,1.12);add(kind,vs,fs,[tint(kind,f*(.83 if i<8 else 1)) for i in range(32)])
 if collision:hull(kind,vs)

def branch(a,b,r1,r2,kind='bark',collision=False):
 a=Vector(a); b=Vector(b); direction=(b-a).normalized(); side=direction.cross(Vector((0,1,0)))
 if side.length<.01:side=Vector((1,0,0))
 side.normalize(); other=direction.cross(side).normalized(); vs=[]
 for t,r in [(0,r1),(.2,r1*.92),(.75,r2*1.35),(1,r2)]:
  for j in range(7):
   ang=j*math.tau/7; p=a.lerp(b,t)+(side*math.cos(ang)+other*math.sin(ang))*r*(1+.1*math.sin(j*6.3))
   vs.append(tuple(p))
 fs=[tuple(reversed(range(7))),tuple(range(21,28))]
 for k in range(3):
  for j in range(7):fs.append((k*7+j,k*7+(j+1)%7,(k+1)*7+(j+1)%7,(k+1)*7+j))
 add(kind,vs,fs,[tint(kind,R.uniform(.85,1.12)) for _ in vs])
 if collision:hull('Trunk',vs)
# Terrain: actual heightmap grid, painterly colour masks in vertices.
for cz in range(8):
 for cx in range(8):
  vs=[]; fs=[]; cols=[]
  for j in range(31):
   for i in range(31):
    x=-120+cx*30+i; z=-120+cz*30+j; y=height(x,z); vs.append((x,y,z))
    noise=.6*math.sin(x*.17+math.sin(z*.19))+.4*math.sin(z*.37+x*.24)
    lane=1-smooth(3.5+noise*2.8,10.0+noise*2,road(x,z))
    grass=(.39+.04*noise,.49+.055*noise,.14+.015*noise); dirt=(.63+.04*noise,.51+.045*noise,.30+.03*noise)
    cols.append(tuple(grass[k]*(1-lane)+dirt[k]*lane for k in range(3))+(1,))
  for j in range(30):
   for i in range(30):
    a=j*31+i;fs.extend([(a,a+31,a+1),(a+1,a+31,a+32)])
  add('terrain',vs,fs,cols,(cx-4,cz-4))
print('Terrain built',flush=True)
# Cliffs: irregular stepped crags aligned outside physical containment planes.
def rim_radius(dx,dz):return H/max(abs(dx),abs(dz),(abs(dx)+abs(dz))*.70710678)
def plateau(x,z):
 return 29+6*math.sin(x*.027)*math.cos(z*.032)+3*math.sin((x-z)*.049)
# An unbroken surrounding highland, so the arena belongs to a landscape.
for cz in range(-8,8):
 for cx in range(-8,8):
  vs=[];cols=[];fs=[]
  for j in range(11):
   for i in range(11):
    x=cx*50+i*5;z=cz*50+j*5;dist=max(abs(x),abs(z),(abs(x)+abs(z))*.70710678)
    y=plateau(x,z)*smooth(124,144,dist)
    if dist<128:y=-5
    y+=max(0,dist-170)*.09
    vs.append((x,y,z));cols.append((.32+.025*math.sin(x*.05),.43+.025*math.cos(z*.04),.16,1))
  for j in range(10):
   for i in range(10):
    a=j*11+i
    if max(abs(vs[a][0]),abs(vs[a][2]),(abs(vs[a][0])+abs(vs[a][2]))*.7071)<123:continue
    fs.extend([(a,a+11,a+1),(a+1,a+11,a+12)])
  add('terrain',vs,fs,cols,(cx+20,cz+20))
for i in range(C['art']['cliff_segments']):
 a=i*math.tau/C['art']['cliff_segments'];dx=math.sin(a);dz=math.cos(a);radius=rim_radius(dx,dz)
 for tier in range(3):
  rr=radius+5+tier*5+R.uniform(0,3);x=dx*rr;z=dz*rr; top=plateau(x,z)
  rock(x,-3+tier*top*.29,z,R.uniform(5,8),top*.46,R.uniform(5,8),collision=tier==0)
 if i%2==0:rock(dx*(radius+1),-.6,dz*(radius+1),2.8,R.uniform(2,5),2.4,collision=True)
# Far ridges are low and hazy, never huge floating boulders around the bowl.
for i in range(40):
 a=i*math.tau/40;r=R.uniform(550,800)
 rock(math.sin(a)*r,10,math.cos(a)*r,R.uniform(95,145),R.uniform(75,145),R.uniform(90,145))
# Separate rocks / boulders with construction-matched convex hulls.
for cx,cz in C['rock_clusters']:
 for j in range(6):
  x=cx+R.uniform(-6,6); z=cz+R.uniform(-4,4)
  rock(x,height(x,z)-.35,z,R.uniform(1.1,3.2),R.uniform(1.2,5),R.uniform(1,3),'stone',True)
# Uneven ruin courses with stepped broken ends, pilasters and fallen stones.
def ruin(x,z,yaw,length,rows,base=None):
 y=height(x,z) if base is None else base
 columns=int(length/2.25)
 for col in range(columns):
  courses=max(1,rows-int(abs(col-columns*.5)*.65)+R.choice([-1,0,1]))
  for row in range(courses):
   if row>1 and R.random()<.12:continue
   dx=(col-(columns-1)*.5)*2.28+(row%2)*.20; dz=R.uniform(-.05,.05)
   block('stone',(x+math.cos(yaw)*dx+math.sin(yaw)*dz,y+.60+row*1.18,z-math.sin(yaw)*dx+math.cos(yaw)*dz),(2.2,1.14,1.6),yaw,base is None)
 for sign in [-1,1]:
  dx=sign*length*.5
  for row in range(rows+2):block('stone',(x+math.cos(yaw)*dx,y+.62+row*1.2,z-math.sin(yaw)*dx),(2.1 if row%3 else 2.4,1.15,2.15),yaw,base is None)
 for j in range(7):
  dx=R.uniform(-length*.6,length*.6);dz=R.choice([-1,1])*R.uniform(2,4)
  xx=x+math.cos(yaw)*dx+math.sin(yaw)*dz;zz=z-math.sin(yaw)*dx+math.cos(yaw)*dz
  block('stone',(xx,(height(xx,zz) if base is None else base)+.45,zz),(R.uniform(.7,1.6),.9,R.uniform(.7,1.3)),R.random()*6,base is None)
for x,z,a,length,rows in C['ruins']:ruin(x,z,a,length,rows)
ruin(-17,-49,math.pi*.5-.22,13,4)
# Landmark arch beyond north-east battlefield, built as individually cut voussoirs.
x,z=94,-121;y=23
for side in [-1,1]:
 for i in range(7):block('stone',(x+side*8,y+i*1.5,z),(3,1.44,4),0)
for i in range(13):
 a=i*math.pi/12; cx=x+math.cos(a)*8; cy=y+9+math.sin(a)*8
 # wedge uses inner and outer arcs for a true opening
 vs=[]
 for zz in [z-2,z+2]:
  for rr,aa in [(6.8,a-.13),(9.4,a-.13),(9.4,a+.13),(6.8,a+.13)]:vs.append((x+math.cos(aa)*rr,y+9+math.sin(aa)*rr,zz))
 add('stone',vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
ruin(-57,-128,.2,24,6,25)
print('Stonework built',flush=True)
# Bridges: full-width continuous collider, individual warped boards, long
# stringers, pegged trestles, scarf braces, bolted rails and stone abutments.
for b in C['bridges']:
 x=b['x'];z=b['z'];w=b['width'];l=b['length'];y=b['deck_height']
 vs=[(x+dx,y+dy,z+dz) for dx in [-w/2,w/2] for dy in [-.65,0] for dz in [-l/2,l/2]];hull('BridgeDeck',vs)
 for i in range(30):
  zz=z-l/2+(i+.5)*l/30
  block('wood',(x,y-.13,zz),(w+R.uniform(0,.3),.26,l/30-.025))
  for xx in [x-w*.38,x+w*.38]:
   block('iron',(xx,y+.015,zz),(.14,.04,.20))
 for side in [-1,1]:
  xx=x+side*(w/2+.3)
  block('wood',(xx,y-.62,z),(.65,.80,l+1))
  for j in range(5):
   zz=z-l/2+j*l/4
   branch((xx,y-2.7,zz),(xx,y+1.65,zz),.3,.22,'wood',True)
   block('wood',(xx,y+1.54,zz),(.68,.24,.68))
  for j in range(4):
   zz=z-l/2+(j+.5)*l/4
   branch((xx,y+.82,zz-l/8),(xx,y+1.38,zz+l/8),.13,.13,'wood',True)
   branch((xx,y+1.38,zz-l/8),(xx,y+.82,zz+l/8),.11,.11,'wood')
  branch((xx,y+1.45,z-l/2-.35),(xx,y+1.45,z+l/2+.35),.21,.21,'wood',True)
 for sign in [-1,1]:
  for xx in [x-w*.35,x+w*.35]:block('stone',(xx,y-.8,z+sign*l*.46),(3,1.5,2.2),0,True)
# Water ribbons follow actual river bed; opaque stylized shader avoids sorting.
for path in C['streams']:
 for a,b in zip(path,path[1:]):
  dx=b[0]-a[0];dz=b[1]-a[1];length=math.hypot(dx,dz); nx=-dz/length; nz=dx/length
  steps=int(length/2)+1
  for i in range(steps):
   vs=[]
   for t in [i/steps,(i+1)/steps]:
    x=a[0]+dx*t;z=a[1]+dz*t
    for side in [-1,1]:vs.append((x+nx*side*8.5,C['water_level'],z+nz*side*8.5))
   pass # The continuous plane below fills bends without triangular ribbon holes.
  for j in range(int(length/5)):
   t=R.random();side=R.choice([-1,1]);x=a[0]+dx*t+nx*side*R.uniform(4.4,6);z=a[1]+dz*t+nz*side*R.uniform(4.4,6)
   if any(abs(x-bb['x'])<bb['width']*.5+3 and abs(z-bb['z'])<bb['length']*.5+16 for bb in C['bridges']):continue

   if min(math.hypot(x-px,z-pz) for px,pz in pads)<13:continue
   rock(x,height(x,z)-.2,z,R.uniform(.6,1.9),R.uniform(.7,2),R.uniform(.5,1.8),'stone',True)
add('water',[(-140,C['water_level'],-140),(140,C['water_level'],-140),(140,C['water_level'],140),(-140,C['water_level'],140)],[(0,2,1),(0,3,2)])
# NW falling water: four irregular translucent-looking bright ribbons, lip and splash.
for j in range(7):
 x=-98+j*1.0;z=-84
 vs=[(x,28,z-3),(x+1.1,28,z-3),(x+6.3,-.65,z+10),(x+4.8,-.65,z+10)]
 add('foam',vs,[(0,2,1),(0,3,2)])

# Trees: flared trunk, branch forks, layered canopy clusters, fine leaf silhouettes.
def tree(x,z,scale=1,pine=False,y=None,physical=True):
 y=height(x,z) if y is None else y
 tall=(12 if pine else 9)*scale
 branch((x,y-.15,z),(x+.25*scale,y+tall,z-.2*scale),.55*scale,.10*scale,'bark',physical)
 for a in [0,2.1,4.2]:branch((x+math.sin(a)*1.2*scale,y+.03,z+math.cos(a)*1.2*scale),(x,y+1.6*scale,z),.18*scale,.3*scale)
 if pine:
  for tier in range(7):
   yy=y+(3+tier*1.28)*scale; radius=(3.4-tier*.4)*scale
   # Jagged, curved drooping whorls with a raised central tuft.
   vs=[(x,yy+2.1*scale,z)]
   for ring in range(3):
    for j in range(15):
     a=j*math.tau/15+tier*.4; r=radius*[.35,1,.83][ring]*(1+R.uniform(-.16,.16))
     vs.append((x+math.sin(a)*r,yy+[1.2,.1,-.3][ring]*scale+R.uniform(-.25,.25)*scale,z+math.cos(a)*r))
   fs=[]
   for j in range(15):
    fs.append((0,1+j,1+(j+1)%15))
    for k in range(2):fs.append((1+k*15+j,1+(k+1)*15+j,1+(k+1)*15+(j+1)%15,1+k*15+(j+1)%15))
   add('pine',vs,fs,[tint('pine',R.uniform(.85,1.2)*(1.2 if i<16 else .9)) for i in range(len(vs))])
 else:
  for j in range(8):
   a=j*2.4; rr=R.uniform(1.5,3.2)*scale;xx=x+math.sin(a)*rr;zz=z+math.cos(a)*rr;yy=y+(6.3+(j%3)*1.2)*scale
   branch((x,y+3.8*scale,z),(xx,yy,zz),.22*scale,.08*scale)
   rock(xx,yy-1.5*scale,zz,2.5*scale,3.1*scale,2.4*scale,'leaf')
   # Scalloped fine leaf edge cards, clustered on the broad painted canopy.
   for k in range(20):
    aa=R.random()*math.tau; bb=R.uniform(-.8,.8);vx=xx+math.sin(aa)*2.35*scale;vz=zz+math.cos(aa)*2.25*scale;vy=yy+bb*scale
    s=R.uniform(.12,.25)*scale
    add('leaf',[(vx-s,vy,vz),(vx,vy+s*.55,vz-s),(vx+s,vy,vz),(vx,vy-.1,vz+s)],[(0,1,2),(0,2,3)],[tint('leaf',R.uniform(.95,1.28))]*4)
for gx,gz in C['groves']:
 for j in range(3):
  x=gx+R.uniform(-5,5);z=gz+R.uniform(-5,5)
  if min(math.hypot(x-px,z-pz) for px,pz in pads)<13 or river(x,z)<9:continue
  tree(x,z,R.uniform(.8,1.2),R.random()<.28)
for i in range(95):
 a=R.random()*math.tau;dx=math.sin(a);dz=math.cos(a); rr=H/max(abs(dx),abs(dz),(abs(dx)+abs(dz))*.7071)+R.uniform(19,40)
 xx=dx*rr;zz=dz*rr;dist=max(abs(xx),abs(zz),(abs(xx)+abs(zz))*.70710678)
 tree(xx,zz,R.uniform(.8,1.7),R.random()<.4,y=plateau(xx,zz)*smooth(124,144,dist)+max(0,dist-170)*.09,physical=False)
print('Bridges and trees built',flush=True)
# Close grass: bent tapered blades, seed heads and little five petal flowers.
for i in range(C['art']['grass_count']):
 x=R.uniform(-119,119);z=R.uniform(-119,119)
 if max(abs(x),abs(z),(abs(x)+abs(z))*.7071)>118:continue
 if river(x,z)<8 or road(x,z)<5+R.uniform(-2.6,2.6):continue
 y=height(x,z);vs=[];fs=[];cc=[];a=R.random()*6.28
 for k in range(5):
  xx=x+R.uniform(-.35,.35);zz=z+R.uniform(-.35,.35);h=R.uniform(.25,.65);w=R.uniform(.018,.045);dx=math.cos(a+k)*w;dz=math.sin(a+k)*w;bend=R.uniform(.05,.20)
  idx=len(vs);vs.extend([(xx-dx,y,zz-dz),(xx+dx,y,zz+dz),(xx+dx+bend,y+h*.58,zz+dz),(xx-dx+bend,y+h*.58,zz-dz),(xx+bend*1.8,y+h,zz)])
  fs.extend([(idx,idx+1,idx+2,idx+3),(idx+3,idx+2,idx+4)])
  f=R.uniform(.83,1.16);cc.extend([tint('grass',f*.68),tint('grass',f*.68),tint('grass',f),tint('grass',f),tint('grass',f*1.2)])
 add('grass',vs,fs,cc)
for i in range(C['art']['flower_count']):
 x=R.uniform(-116,116);z=R.uniform(-116,116)
 if river(x,z)<9 or road(x,z)<8 or max(abs(x),abs(z),(abs(x)+abs(z))*.7071)>116:continue
 y=height(x,z)+R.uniform(.28,.6);s=R.uniform(.07,.15);color=(1,.97,.80,1) if i%3 else (.98,.75,.20,1)
 vs=[(x,y,z)]+[(x+math.sin(j*math.tau/10)*s*(1 if j%2==0 else .45),y+.035,z+math.cos(j*math.tau/10)*s*(1 if j%2==0 else .45)) for j in range(10)]
 add('flower',vs,[(0,j+1,(j+1)%10+1) for j in range(10)],[color]*11)
# Small non-colliding gravel: detailed at robot height, batched and culled with flora.
for i in range(11000):
 x=R.uniform(-116,116);z=R.uniform(-116,116)
 if river(x,z)<9 or road(x,z)>11:continue
 y=height(x,z);r=R.uniform(.045,.19);h=R.uniform(.025,.10)
 vs=[(x-r,y,z-r*.4),(x+r*.3,y,z-r),(x+r,y,z+r*.4),(x-r*.4,y,z+r),(x-r*.2,y+h,z)]
 color=(.48,.46,.36,1) if i%3 else (.58,.55,.42,1)
 add('gravel',vs,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],[color]*5)
# Bake scene in Blender and export GLB with source retained.
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
mats={}
for kind,c in COL.items():
 m=bpy.data.materials.new('Sunreach_'+kind);m.diffuse_color=(*c,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(1,1,1,1);bs.inputs['Roughness'].default_value=.9
 attr=m.node_tree.nodes.new('ShaderNodeVertexColor');attr.layer_name='Paint';m.node_tree.links.new(attr.outputs['Color'],bs.inputs['Base Color']);mats[kind]=m
for (kind,cx,cz),(vs,fs,cs) in batches.items():
 # Blender Z up to glTF/Godot Y up: (x,-z,y).
 mesh=bpy.data.meshes.new(f'{kind}_{cx}_{cz}');mesh.from_pydata([(x,-z,y) for x,y,z in vs],[],fs);mesh.update()
 ob=bpy.data.objects.new(mesh.name,mesh);bpy.context.collection.objects.link(ob);mesh.materials.append(mats[kind])
 colors=mesh.color_attributes.new(name='Paint',type='FLOAT_COLOR',domain='POINT');colors.data.foreach_set('color',[v for c in cs for v in (*[(q/12.92 if q<=.04045 else ((q+.055)/1.055)**2.4) for q in c[:3]],c[3])])
 if kind in ('terrain','leaf','water','grass','flower','cliff','stone'):
  for p in mesh.polygons:p.use_smooth=True
 # Procedural physical scale UVs, preserved for hand-painting replacements.
 uv=mesh.uv_layers.new(name='Surface')
 for loop in mesh.loops:
  x,y,z=vs[loop.vertex_index]
  uv.data[loop.index].uv=(x*.2+z*.07,y*.2+z*.2)
bpy.ops.outliner.orphans_purge(do_recursive=True)
print('Saving',len(batches),'batches',len(colliders),'hulls',flush=True)
import hashlib
(DATA/'bake.json').write_text(json.dumps({str(p.relative_to(ROOT/'battlebots')):hashlib.sha256(p.read_bytes()).hexdigest() for p in [DATA/'layout.json',ROOT/'battlebots/data/arena_spawns.json',DATA/'heights.bin']},indent=2)+'\n')
(DATA/'collision.json').write_text(json.dumps(colliders,separators=(',',':'))+'\n')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art_source/sunreach/sunreach.blend'),compress=True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'sunreach.glb'),export_format='GLB',export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
print('SUNREACH BUILD COMPLETE',flush=True)
