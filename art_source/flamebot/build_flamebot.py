"""Rebuild the fictional Flamebot 07 art asset in Blender (no gameplay logic)."""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector, Euler
import numpy as np

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / 'battlebots/assets/models/flamebot'
OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)

def material(name, color, metal=0, rough=.5, weather=False):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    if weather:
        rng=np.random.default_rng(17); n=512
        fine=rng.random((n,n)); coarse=rng.random((64,64)).repeat(8,0).repeat(8,1)
        for _ in range(5): coarse=(coarse+np.roll(coarse,1,0)+np.roll(coarse,-1,0)+np.roll(coarse,1,1)+np.roll(coarse,-1,1))/5
        a=np.ones((n,n,4),dtype=np.float32)
        a[:,:,:3]=np.array(color)[None,None,:]*(.72+.48*fine[:,:,None])
        chips=(coarse>.715)&(fine>.35)
        a[chips,:3]=np.array([.23,.24,.22])*(.55+fine[chips,None]*.65)
        rust=(coarse>.69)&(coarse<.715)&(fine>.55)
        a[rust,:3]=[.19,.065,.025]
        im=bpy.data.images.new(name+'_albedo',width=n,height=n)
        im.pixels.foreach_set(a.ravel()); im.pack()
        t=m.node_tree.nodes.new('ShaderNodeTexImage'); t.image=im
        m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color'])
    return m

red=material('Oxide red • chipped paint',(.39,.055,.029),.65,.49,True)
dark=material('Blackened steel',(.047,.054,.056),.82,.4,True)
steel=material('Exposed brushed edges',(.26,.29,.29),.85,.37,True)
rubber=material('Charcoal tire rubber',(.007,.008,.009),0,.87)
yellow=material('Ochre safety paint',(.8,.42,.045),.5,.45,True)
ivory=material('Warm stencil paint',(.8,.76,.61),.05,.74)
black=material('Recess shadow',(.006,.009,.011),.15,.8)
brass=material('Heat stained bronze',(.35,.18,.044),.8,.4)

def empty(name,loc=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=loc
    if parent: o.parent=parent
    o.empty_display_size=.12
    return o
root=empty('Flamebot07')
chassis=empty('Chassis',parent=root)
turret=empty('TurretYaw',(0,-.13,.91),root)

def finish(o,name,mat,parent,bevel=0):
    o.name=name; o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Machined edge','BEVEL'); mod.width=bevel; mod.segments=1
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    if parent:
        world=o.matrix_world.copy(); o.parent=parent; o.matrix_world=world
    return o
def box(name,loc,size,mat=red,parent=chassis,bevel=.015,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot); o=bpy.context.object
    o.dimensions=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,mat,parent,bevel)
def cyl(name,loc,r,depth,mat=dark,parent=chassis,axis='Z',verts=24,bevel=.006):
    rot={'Z':(0,0,0),'Y':(math.pi/2,0,0),'X':(0,math.pi/2,0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc,rotation=rot)
    return finish(bpy.context.object,name,mat,parent,bevel)
def tube(name,loc,outer,inner,length,mat,parent,axis='Y',n=24):
    vs=[]
    for depth,r in [(-length/2,outer),(length/2,outer),(-length/2,inner),(length/2,inner)]:
        for i in range(n):
            a=i*math.tau/n; v=(r*math.cos(a),depth,r*math.sin(a))
            if axis=='X': v=(depth,r*math.cos(a),r*math.sin(a))
            if axis=='Z': v=(r*math.cos(a),r*math.sin(a),depth)
            vs.append(tuple(v[j]+loc[j] for j in range(3)))
    fs=[]
    for a,b in [(0,1),(1,3),(3,2),(2,0)]:
        for i in range(n): fs.append((a*n+i,a*n+(i+1)%n,b*n+(i+1)%n,b*n+i))
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(vs,[],fs); mesh.update()
    o=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(o)
    return finish(o,name,mat,parent,.003)
def hose(name,points,r=.025,parent=turret,mat=rubber):
    cu=bpy.data.curves.new(name,'CURVE'); cu.dimensions='3D'; cu.bevel_depth=r; cu.bevel_resolution=1; cu.resolution_u=12
    s=cu.splines.new('BEZIER'); s.bezier_points.add(len(points)-1)
    for p,v in zip(s.bezier_points,points): p.co=v; p.handle_left_type='AUTO'; p.handle_right_type='AUTO'
    o=bpy.data.objects.new(name,cu); bpy.context.collection.objects.link(o); o.data.materials.append(mat)
    w=o.matrix_world.copy(); o.parent=parent; o.matrix_world=w
    return o
def text(name,body,loc,size,rot,parent=chassis):
    cu=bpy.data.curves.new(name,'FONT'); cu.body=body; cu.align_x='CENTER'; cu.size=size; cu.extrude=.0004
    o=bpy.data.objects.new(name,cu); bpy.context.collection.objects.link(o); o.location=loc; o.rotation_euler=rot; cu.materials.append(ivory)
    bpy.context.view_layer.update()
    w=o.matrix_world.copy(); o.parent=parent; o.matrix_world=w
    return o
def bolt(loc,axis='Z',parent=chassis,r=.018):
    return cyl('Hex fastener',loc,r,.012,steel,parent,axis,6,.001)

box('Belly pan',(0,-.08,.3),(1.28,1.72,.18),dark)
box('Armored hull',(0,-.06,.53),(1.38,1.77,.44),red,bevel=.07)
box('Deck gasket',(0,-.08,.774),(1.39,1.66,.045),black)
box('Upper deck',(0,-.08,.805),(1.38,1.68,.07),red)
for x in [-.53,.53]:
    box('Deck service plate',(x,-.14,.847),(.26,1.15,.025),red)
    for y in [-.63,.33]:
        for dx in [-.095,.095]: bolt((x+dx,y,.867))
for x in [-.705,.705]:
    box('Side armor',(x,-.06,.55),(.035,1.42,.33),red)
    for y in [-.62,-.2,.24,.58]: bolt((x*1.035,y,.66),'X')
    text('Side 07','07',(x*1.031,.1,.48),.22,(math.pi/2,0,math.pi/2 if x>0 else -math.pi/2))

# Sloped broad ram: segmented plates leave readable black seams.
slope=-math.atan2(.61,.72)
for x,w,mat in [(-.58,.25,yellow),(-.3,.28,red),(0,.31,steel),(.3,.28,red),(.58,.25,yellow)]:
    box('Segmented front wedge',(x,.94,.39),(w,.96,.052),mat,rot=(slope,0,0),bevel=.008)
    for yy in [-.38,.38]:
        bolt((x,.94+yy*math.cos(slope)-.038*math.sin(slope),.39+yy*math.sin(slope)+.038*math.cos(slope)),r=.022)
    if mat==yellow:
        for yy in [-.30,-.1,.1,.3]:
            box('Wedge warning band',(x,.94+yy*math.cos(slope)-.03*math.sin(slope),.39+yy*math.sin(slope)+.03*math.cos(slope)),(w+.004,.092,.006),dark,rot=(slope,0,0),bevel=0)
text('Front hull stencil','07',(.29,1.05,.341),.21,(Euler((slope,0,0)).to_matrix() @ Euler((0,0,math.pi)).to_matrix()).to_euler())
text('Deck stencil','07',(.35,.35,.851),.22,(0,0,math.pi))
box('Front cooling recess',(-.29,.475,.791),(.4,.36,.026),black)
for y in [.34,.4,.46,.52,.58]: box('Front cooling slat',(-.29,y,.815),(.37,.023,.024),steel,bevel=.003)
box('Rear cooling surround',(0,-.963,.56),(.88,.04,.33),steel)
box('Rear cooling shadow',(0,-.993,.56),(.79,.03,.255),black)
for z in [.47,.55,.63]: box('Rear grille bar',(0,-1.014,z),(.76,.025,.025),dark,bevel=.003)
for x in [-.48,.48]:
    box('Rear bumper',(x,-.99,.35),(.3,.13,.105),dark)
    for z in [.4,.69]: bolt((x,-.984,z),'Y')

# Wheel pivots are independent; all tire/hub details follow each pivot.
for x in [-.82,.82]:
    for y in [-.58,.57]:
        wheel=empty(('WheelLeft' if x<0 else 'WheelRight')+('Front' if y>0 else 'Rear'),(x,y,.38),root)
        cyl('Axle',(x*.86,y,.38),.085,.3,steel,chassis,'X')
        cyl('Tire carcass',(x,y,.38),.37,.29,rubber,wheel,'X',32,.027)
        for i in range(20):
            a=i*math.tau/20
            box('Heavy tread',(x,y+.367*math.sin(a),.38+.367*math.cos(a)),(.32,.10,.053),rubber,wheel,.009,(-a,0,0))
        face=x+(.157 if x>0 else -.157)
        cyl('Rim outer',(face,y,.38),.258,.022,steel,wheel,'X',32)
        cyl('Red wheel dish',(face+math.copysign(.016,x),y,.38),.223,.025,red,wheel,'X',24)
        tube('Wheel inset ring',(face+math.copysign(.032,x),y,.38),.171,.15,.018,dark,wheel,'X',24)
        cyl('Hub cap',(face+math.copysign(.037,x),y,.38),.089,.035,dark,wheel,'X',16)
        cyl('Hub spindle',(face+math.copysign(.058,x),y,.38),.05,.018,steel,wheel,'X',12)
        for i in range(8):
            a=i*math.tau/8; bolt((face+math.copysign(.035,x),y+.193*math.sin(a),.38+.193*math.cos(a)),'X',wheel,.013)

cyl('Turret bearing',(0,-.13,.882),.43,.105,dark,chassis,'Z',48)
cyl('Turret ring',(0,-.13,.942),.36,.045,steel,turret,'Z',40)
box('Turret armored tower',(0,-.16,1.18),(.79,.71,.44),red,turret,.045)
box('Turret roof',(0,-.17,1.42),(.8,.73,.055),red,turret)
box('Top hatch',(-.07,-.25,1.465),(.41,.36,.045),dark,turret)
for x in [-.32,.32]:
    for y in [-.46,.09]: bolt((x,y,1.458),parent=turret)
for x in [-.414,.414]:
    box('Turret cheek plate',(x,-.12,1.19),(.035,.6,.37),red,turret)
    for y in [-.36,.11]:
        for z in [1.04,1.34]: bolt((x*1.04,y,z),'X',turret)

# Flame insignia, graphic mesh on both cheeks.
outline=[(-.09,0),(-.14,.055),(-.13,.14),(-.08,.105),(-.065,.22),(-.012,.165),(.005,.3),(.074,.2),(.09,.12),(.12,.145),(.14,.065),(.075,0)]
for side in [-1,1]:
    vs=[(side*.435,-.12+y,1.055+z*.82) for y,z in outline]
    me=bpy.data.meshes.new('Flame emblem'); me.from_pydata(vs,[],[tuple(range(len(vs)))]); me.update()
    o=bpy.data.objects.new('Ivory flame insignia',me); bpy.context.collection.objects.link(o); finish(o,o.name,ivory,turret)

# Stylized flamethrower: broad octagonal muzzle and perforated heat shield.
cyl('Flamer pivot',(-.17,.21,1.29),.176,.2,dark,turret,'Y')
cyl('Flamer barrel',(-.17,.58,1.31),.111,.68,dark,turret,'Y')
for y in [.30,.75,.89]: cyl('Barrel collar',(-.17,y,1.31),.13,.045,brass,turret,'Y')
sleeve=tube('Perforated heat shield',(-.17,.71,1.31),.16,.137,.33,yellow,turret)
# Actual holes through sleeve, not painted spots.
cutters=[]
for row,y in enumerate([.60,.70,.80]):
    for i in range(10):
        a=(i+.5*(row%2))*math.tau/10
        v=Vector((math.cos(a),0,math.sin(a)))
        bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=.023,depth=.095,location=Vector((-.17,y,1.31))+v*.155)
        c=bpy.context.object; c.rotation_euler=v.to_track_quat('Z','Y').to_euler(); cutters.append(c)
bpy.ops.object.select_all(action='DESELECT')
for c in cutters: c.select_set(True)
bpy.context.view_layer.objects.active=cutters[0]; bpy.ops.object.join(); cutter=bpy.context.object
bpy.context.view_layer.objects.active=sleeve
mod=sleeve.modifiers.new('Shield ventilation ports','BOOLEAN'); mod.operation='DIFFERENCE'; mod.object=cutter
bpy.ops.object.modifier_apply(modifier=mod.name); bpy.data.objects.remove(cutter,do_unlink=True)
tube('Octagonal flamer muzzle',(-.17,1.04,1.31),.155,.111,.22,dark,turret,n=8)
tube('Bright muzzle lip',(-.17,1.157,1.31),.157,.133,.026,steel,turret,n=8)
cyl('Dark flamer throat',(-.17,.97,1.31),.109,.008,black,turret,'Y')
for x in [-.31,-.03]: box('Muzzle locking lug',(x,1.04,1.31),(.037,.09,.044),brass,turret,.003)

# Six-barrel fictional minigun, separate roll pivot under turret yaw.
box('Minigun bracket',(.49,-.01,1.1),(.19,.22,.17),steel,turret)
box('Minigun receiver',(.57,.15,1.15),(.25,.31,.23),dark,turret,.026)
for x in [.445,.695]:
    box('Receiver armor',(x,.15,1.15),(.022,.24,.19),steel,turret,.006)
    for y in [.055,.235]: bolt((x*1.006,y,1.2),'X',turret,.015)
gun=empty('MinigunSpin',(.57,.33,1.15),turret)
# empty() takes local coordinates; set intended world pivot.
gun.matrix_world.translation=Vector((.57,.33,1.15))
cyl('Rotating breech',(.57,.335,1.15),.103,.075,dark,gun,'Y',16)
for i in range(6):
    a=i*math.tau/6; x=.57+.065*math.cos(a); z=1.15+.065*math.sin(a)
    tube('Minigun barrel',(x,.56,z),.027,.016,.43,steel,gun,n=10)
    tube('Black barrel tip',(x,.787,z),.029,.017,.036,dark,gun,n=10)
    cyl('Bore shadow',(x,.765,z),.016,.006,black,gun,'Y',10,0)
for y in [.42,.71]: tube('Barrel cluster brace',(.57,y,1.15),.108,.086,.033,dark,gun,n=12)

# Rear-side fuel canister and curved supply hose.
cyl('Fuel canister',(.51,-.43,1.21),.135,.49,red,turret,'Z',24,.023)
for z in [.985,1.415]: cyl('Tank retaining band',(.51,-.43,z),.142,.032,steel,turret)
cyl('Tank cap',(.51,-.43,1.488),.054,.047,brass,turret)
box('Tank warning label',(.646,-.43,1.2),(.008,.16,.18),yellow,turret,.004)
text('Tank warning','!',(.654,-.43,1.135),.16,(math.pi/2,0,math.pi/2),turret)
hose('Fuel supply hose',[(.51,-.43,1.51),(.48,-.61,1.6),(.13,-.64,1.58),(-.24,-.48,1.52),(-.28,-.08,1.5),(-.22,.27,1.35)])
hose('Tank return hose',[(.55,-.4,.96),(.7,-.56,.96),(.74,-.66,1.22),(.7,-.6,1.51),(.51,-.43,1.51)],.022)
for z in [1.03,1.22,1.39]: box('Hose clasp',(.736,-.635,z),(.053,.04,.037),steel,turret,.004)
cyl('Antenna base',(-.29,-.43,1.49),.037,.085,dark,turret)
cyl('Antenna',(-.29,-.43,1.77),.009,.52,dark,turret,verts=10,bevel=0)
box('Rear tower vent',(0,-.528,1.2),(.38,.03,.25),steel,turret)
box('Rear tower vent inset',(0,-.547,1.2),(.33,.025,.2),black,turret)
for z in [1.13,1.19,1.25]: box('Tower vent slat',(0,-.568,z),(.32,.02,.014),steel,turret,.002)

# Apply modifiers, convert text/curves, UV unwrap, and merge per moving assembly.
for o in list(bpy.context.scene.objects):
    if o.type not in {'MESH','CURVE','FONT'}: continue
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
    bpy.ops.object.convert(target='MESH')
    for mod in list(o.modifiers):
        try: bpy.ops.object.modifier_apply(modifier=mod.name)
        except RuntimeError: pass
    bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.015)
    bpy.ops.object.mode_set(mode='OBJECT')
for pivot in [chassis,turret,gun]+[o for o in root.children if o.name.startswith('Wheel')]:
    children=[o for o in pivot.children if o.type=='MESH']
    if not children: continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in children: o.select_set(True)
    bpy.context.view_layer.objects.active=children[0]; bpy.ops.object.join(); bpy.context.object.name=pivot.name+'_Mesh'

asset=[o for o in bpy.context.scene.objects]
bpy.ops.object.select_all(action='DESELECT')
for o in asset: o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'flamebot_07.glb'),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
deps=bpy.context.evaluated_depsgraph_get()
tris=0
for o in asset:
    if o.type=='MESH':
        me=o.evaluated_get(deps).to_mesh(); me.calc_loop_triangles(); tris+=len(me.loop_triangles); o.evaluated_get(deps).to_mesh_clear()
corners=[o.matrix_world@Vector(c) for o in asset if o.type=='MESH' for c in o.bound_box]
stats={'triangles':tris,'mesh_objects':sum(o.type=='MESH' for o in asset),'blender_dimensions_m':[round(max(v[i] for v in corners)-min(v[i] for v in corners),3) for i in range(3)],'forward':'Blender +Y exports to Godot -Z','up':'Blender +Z exports to Godot +Y'}
(HERE/'asset_stats.json').write_text(json.dumps(stats,indent=2))

# Studio is source-only and excluded from GLB.
studio=bpy.data.collections.new('Studio • excluded from game export'); bpy.context.scene.collection.children.link(studio)
def move_studio(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    studio.objects.link(o)
floor=material('Studio floor',(.105,.125,.145),.05,.72)
o=box('Studio floor',(0,0,-.049),(200,200,.025),floor,None,0); move_studio(o)
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3.5,4.7,3.1)); cam=bpy.context.object; cam.name='Hero camera'; aim(cam,(0,.07,.87)); cam.data.type='ORTHO'; cam.data.ortho_scale=3.7; move_studio(cam); bpy.context.scene.camera=cam
for name,loc,power,size,col in [('Large warm key',(1,3,5),950,4,(1,.87,.73)),('Cool fill',(-3,1,2.7),750,3,(.72,.85,1)),('Rim strip',(1,-3,4),1300,3,(1,.91,.8))]:
    bpy.ops.object.light_add(type='AREA',location=loc); l=bpy.context.object; l.name=name; l.data.energy=power; l.data.shape='DISK'; l.data.size=size; l.data.color=col; aim(l,(0,0,.7)); move_studio(l)
scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=48; scene.cycles.use_denoising=True
scene.world.color=(.25,.25,.25); scene.render.resolution_x=1500; scene.render.resolution_y=1300; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.render.image_settings.file_format='PNG'
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_perspective='CAMERA'
            a.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'flamebot_07.blend'),compress=True)
scene.render.filepath=str(HERE/'flamebot_07_hero.png'); bpy.ops.render.render(write_still=True)
cam.location=(-3.5,-4.4,2.8); aim(cam,(0,-.05,.85))
scene.render.filepath=str(HERE/'flamebot_07_rear.png'); bpy.ops.render.render(write_still=True)
print('ASSET_STATS',stats)
