"""Original lunar kit. Run Blender --background --python art_source/lunar/build.py.
All models/material maps authored here; no external meshes or scans.
Coordinates are Blender Z-up. Exported GLB is Godot Y-up, front +Z.
"""
import bpy, bmesh, math, random, pathlib, numpy as np
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'battlebots/assets/models/lunar'; OUT.mkdir(parents=True,exist_ok=True)
TEX=ROOT/'battlebots/assets/textures/lunar'; TEX.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
random.seed(62026)
def image(name,a):
    h,w=a.shape[:2]; im=bpy.data.images.new(name,width=w,height=h,alpha=True)
    im.pixels.foreach_set(a.astype(np.float32).ravel()); im.filepath_raw=str(TEX/(name+'.png')); im.file_format='PNG'; im.save(); return im
# Original periodic multi-scale relief fields, with separate physically meaningful maps.
N=2048; y,x=np.mgrid[0:N,0:N].astype(np.float32)/N
for k,base in enumerate([(.27,.28,.29),(.35,.35,.34),(.21,.23,.25),(.38,.34,.25)]):
    h=np.zeros((N,N),np.float32)
    rng=np.random.default_rng(912+k)
    for j in range(8):
        f=4*2**j; grid=rng.random((f,f),dtype=np.float32)
        xx=x*f; yy=y*f; ix=xx.astype(np.int32); iy=yy.astype(np.int32)
        u=xx-ix;v=yy-iy;u=u*u*(3-2*u);v=v*v*(3-2*v)
        noise=(grid[iy%f,ix%f]*(1-u)+grid[iy%f,(ix+1)%f]*u)*(1-v)+(grid[(iy+1)%f,ix%f]*(1-u)+grid[(iy+1)%f,(ix+1)%f]*u)*v
        h+=noise*(.62**j)
    h=(h-h.min())/(h.max()-h.min())
    fine=np.random.default_rng(110+k).random((N,N),dtype=np.float32)
    h=h*.8+fine*.2
    if k==1: h=np.power(h,3)
    rgb=np.stack([np.clip(c*(.55+h*.95),0,1) for c in base],axis=-1)
    image('surface%d_color'%k,np.concatenate([rgb,np.ones((N,N,1))],axis=-1))
    dx=(np.roll(h,-1,1)-np.roll(h,1,1))*2.5; dy=(np.roll(h,-1,0)-np.roll(h,1,0))*2.5
    n=np.stack([-dx,-dy,np.ones_like(h)],axis=-1); n/=np.linalg.norm(n,axis=-1,keepdims=True)
    image('surface%d_normal'%k,np.concatenate([n*.5+.5,np.ones((N,N,1))],axis=-1))
    orm=np.stack([np.clip(.65+h*.45,0,1),np.clip(.82+fine*.16,0,1),h,np.ones_like(h)],axis=-1)
    image('surface%d_relief'%k,orm)

def mat(name,color,metal=0,rough=.7,emission=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    if emission: p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
    return m
white=mat('Ceramic titanium',(.52,.55,.53),.45,.46); dark=mat('Recess graphite',(.035,.047,.056),.7,.4)
steel=mat('Machined edge',(.22,.27,.29),.8,.32); gold=mat('Thermal insulation',(.47,.28,.075),.7,.48)
amber=mat('Safety ochre',(.6,.27,.025),.25,.55); glow=mat('Service cyan',(.22,.7,.83),.15,.3,2)
rockmat=mat('Fractured basalt',(.28,.29,.3),0,.92)
def finish(o,name,m,bevel=0):
    o.name=name;o.data.materials.append(m)
    if bevel:
        mod=o.modifiers.new('Manufactured edge bevel','BEVEL');mod.width=bevel;mod.segments=3
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
        mod=o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL')
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def box(name,p,s,m=white,b=.035):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.scale=s
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,name,m,b)
def cyl(name,p,r,h,m=steel,rot=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=r,depth=h,location=p);o=bpy.context.object
    if rot:o.rotation_euler=rot
    return finish(o,name,m,.018)
def beam(name,a,b,r=.035,m=steel):
    a,b=Vector(a),Vector(b);o=cyl(name,(a+b)/2,r,(b-a).length,m);o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();return o

def export(name,objects):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    # Unique second UV set retained in editable sources for baked lighting.
    for o in objects:
        if o.type=='MESH':
            if not o.data.uv_layers:o.data.uv_layers.new(name='UVMap')
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),use_selection=True,export_format='GLB',export_apply=True)

for i in range(8):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=4,radius=1);o=bpy.context.object
    for v in o.data.vertices:
        p=v.co; noise=math.sin(p.x*7+i)*math.cos(p.y*5-i)*.13+math.sin(p.z*17+p.x*3)*.04
        p*=1+noise;p.x*=1.1+(i%3)*.3;p.y*=.8;p.z*=.7+(i%2)*.25
    bm=bmesh.new();bm.from_mesh(o.data)
    for j in range(4):
        a=i*1.31+j*1.7; normal=Vector((math.cos(a),math.sin(a),.3)).normalized()
        result=bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.0001,plane_co=normal*.77,plane_no=normal,clear_outer=True)
        edges=[e for e in result['geom_cut'] if isinstance(e,bmesh.types.BMEdge)]
        if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
    bm.to_mesh(o.data);bm.free();o.data.update();finish(o,'Basalt_%02d'%i,rockmat,.012)
    export('rock_%02d'%i,[o]);o.hide_set(True)
# Showcase bay built around a 12m x12m footprint, open front toward -Y.
start=set(bpy.data.objects)
box('Foundation', (0,0,.3),(11,8,.6),dark,.1)
box('Habitat shell',(0,1,2.35),(8,5,3.5),white,.18)
box('Roof armored cap',(0,1,4.22),(8.5,5.5,.3),dark,.07)
for x0 in [-3.85,3.85]:
    box('Corner structure',(x0,-1.5,2.3),(.32,.32,3.7),steel)
    for z0 in [1,2,3,3.8]:box('Corner joint',(x0,-1.72,z0),(.48,.12,.14),dark)
# inset airlock with segmented door, lintels and mechanical tracks
box('Airlock recess',(-1.8,-1.57,2),(2.4,.22,2.9),dark)
for x0 in [-2.35,-1.25]:box('Door leaf',(x0,-1.71,1.95),(1.02,.12,2.5),steel)
for x0 in [-3.04,-.56]:box('Door rail',(x0,-1.87,2),(.13,.2,2.9),white)
box('Airlock light',(-1.8,-1.88,3.5),(1.5,.07,.08),glow,.012)
for z0 in [.85,1.1,2.85]:box('Door rib',(-1.8,-1.8,z0),(2.05,.09,.09),dark,.015)
# window geometry with reveal, mullions and top shades
box('Window recess',(1.7,-1.62,2.75),(2.8,.25,1.12),dark)
box('Glazing',(1.7,-1.77,2.75),(2.52,.08,.88),glow,.02)
for x0 in [.5,1.3,2.1,2.9]:box('Window mullion',(x0,-1.85,2.75),(.055,.12,.98),steel,.01)
box('Window visor',(1.7,-1.93,3.4),(3,.6,.12),white)
# panels, flush fasteners, utility cabinets and vents
for x0 in [-3.5,-.2,3.4]:
    for z0 in [.9,3.7]:
        for dx in [-.12,.12]:cyl('Panel bolt',(x0+dx,-1.62,z0),.045,.055,steel,(math.pi/2,0,0))
for x0 in [4.6,-4.6]:
    cyl('Cryo vessel',(x0,1,1.85),.6,2.8,white)
    for z0 in [.6,1.5,2.8,3.1]:cyl('Tank strap',(x0,1,z0),.64,.10,dark)
    box('Insulated manifold',(x0,-.15,1.2),(1,.5,1.25),gold,.06)
    for z0 in [.8,1.2,1.6]:beam('Feed pipe',(x0,-.4,z0),(x0-1,-.4,z0),.055)
for x0 in [-2,1.9]:
    box('Roof HVAC',(x0,1.4,4.65),(2.5,2,.7),white,.08)
    for j in range(12):box('Louver',(x0-1.08+j*.195,.35,4.67),(.08,.1,.5),dark,.01)
    cyl('Vent stack',(x0,1.5,5.2),.3,.8,steel)
    cyl('Vent cap',(x0,1.5,5.6),.4,.15,dark)
# forward apron with grating, stairs, rails, cable bundles
for j in range(23):box('Apron grating',(-5+j*.45,-3,.66),(.09,2,.05),steel,.008)
for x0 in [-5,5]:
    for y0 in [-3.8,-2.8,-1.8]:beam('Rail post',(x0,y0,.65),(x0,y0,1.65))
    for z0 in [1.2,1.65]:beam('Rail',(x0,-3.8,z0),(x0,-1.8,z0))
for j in range(4):box('Stair',(-1.8,-4-j*.3,.53-j*.13),(2.8,.35,.15),steel,.025)
for j in range(4):beam('Cable spine',(-3.5+j*.12,2.8,.8),(-3.5+j*.12,2.8,4.3),.025,dark)
# gantry and machinery flank gives asymmetric profile
for x0 in [-5.1,1.4]:beam('Gantrypost',(x0,2,.6),(x0,2,6.7),.12)
beam('Gantry header',(-5.1,2,6.7),(1.4,2,6.7),.15)
for j in range(6):beam('Truss',(-5+j,2,6.7),(-4.4+j,2,6.1),.045)
box('Winch',(-4.2,2,6.15),(1,.8,.7),amber,.07)
beam('Winch cable',(-4.2,2,5.8),(-4.2,2,3.6),.015,dark)
export('service_bay',[o for o in bpy.data.objects if o not in start])
# save fully editable library, unhide rock assets spaced beside bay for inspection
for i in range(8):
    o=bpy.data.objects.get('Basalt_%02d'%i);o.hide_set(False);o.location=(15+i*3,0,1)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art_source/lunar/lunar_kit.blend'))
bpy.ops.file.make_paths_relative()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art_source/lunar/lunar_kit.blend'))
print('LUNAR ASSET BUILD PASS')
