"""Rebuild with Blender 4.0+: blender -b --python build_sawblade_tank.py"""
import bpy, math, random, os, json
from mathutils import Vector
from math import pi, sin, cos
ROOT = os.path.dirname(os.path.abspath(__file__))
random.seed(24)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for block in bpy.data.collections:
    if block.name != 'Collection': bpy.data.collections.remove(block)
bot = bpy.data.collections.get('Collection'); bot.name = 'SAWBLADE TANK | model'
stage = bpy.data.collections.new('STUDIO | exclude from game export'); bpy.context.scene.collection.children.link(stage)

def mat(name, color, metal=.7, rough=.4, wear=False):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    n=m.node_tree.nodes; l=m.node_tree.links; bs=n.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
    if wear:
        tex=n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=22; tex.inputs['Detail'].default_value=0
        ramp=n.new('ShaderNodeValToRGB'); ramp.color_ramp.interpolation='CONSTANT'
        ramp.color_ramp.elements[0].position=.24; ramp.color_ramp.elements[0].color=(.075,.061,.042,1)
        ramp.color_ramp.elements[1].position=.32; ramp.color_ramp.elements[1].color=(*(c*.65 for c in color),1)
        ramp.color_ramp.elements.new(.43).color=(*color,1)
        ramp.color_ramp.elements.new(.61).color=(*(min(c*1.15,1) for c in color),1)
        l.new(tex.outputs['Fac'],ramp.inputs[0]); l.new(ramp.outputs[0],bs.inputs['Base Color'])
    return m
yellow=mat('01 | worn ochre enamel',(.60,.285,.012),.35,.57,True)
dark=mat('02 | graphite steel',(.055,.063,.066),.8,.43,True)
rubber=mat('03 | carbon tread pads',(.028,.033,.036),.15,.66)
steel=mat('04 | machined edge steel',(.39,.43,.46),.85,.29)
rust=mat('05 | oxidized saw steel',(.26,.245,.23),.65,.48,True)
cutting=mat('09 | freshly ground cutting steel',(.60,.62,.64),.55,.32)
chrome=mat('06 | hydraulic polished rods',(.62,.67,.71),.95,.2)
black=mat('07 | hazard charcoal',(.027,.03,.029),.35,.48,True)
hazard=yellow.copy(); hazard.name='08 | diagonal warning enamel'
n=hazard.node_tree.nodes; l=hazard.node_tree.links; bs=n.get('Principled BSDF')
geo=n.new('ShaderNodeNewGeometry'); sep=n.new('ShaderNodeSeparateXYZ'); l.new(geo.outputs['Position'],sep.inputs[0])
xy=n.new('ShaderNodeMath'); xy.operation='ADD'; l.new(sep.outputs['X'],xy.inputs[0]); l.new(sep.outputs['Y'],xy.inputs[1])
add=n.new('ShaderNodeMath'); add.operation='ADD'; l.new(xy.outputs[0],add.inputs[0]); l.new(sep.outputs['Z'],add.inputs[1])
mul=n.new('ShaderNodeMath'); mul.operation='MULTIPLY'; mul.inputs[1].default_value=16; l.new(add.outputs[0],mul.inputs[0])
sine=n.new('ShaderNodeMath'); sine.operation='SINE'; l.new(mul.outputs[0],sine.inputs[0])
gt=n.new('ShaderNodeMath'); gt.operation='GREATER_THAN'; l.new(sine.outputs[0],gt.inputs[0])
mix=n.new('ShaderNodeMixRGB'); mix.inputs[2].default_value=(.025,.028,.026,1); l.new(gt.outputs[0],mix.inputs[0]); l.new(n.get('Color Ramp').outputs[0],mix.inputs[1]); l.new(mix.outputs[0],bs.inputs['Base Color'])

def finish(o,name,m,bevel=0):
    o.name=name; o.data.materials.append(m)
    if o.type=='MESH': o.data.use_auto_smooth=True
    if bevel:
        mod=o.modifiers.new('Machined chamfers','BEVEL'); mod.width=bevel; mod.segments=1
        mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    return o
def box(name,loc,size,m,bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,m,bevel)
def cyl(name,loc,r,depth,m,axis='X',verts=16,bevel=.007):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts,radius=r,depth=depth,location=loc)
    o=bpy.context.object
    if axis=='X': o.rotation_euler[1]=pi/2
    elif axis=='Y': o.rotation_euler[0]=pi/2
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    return finish(o,name,m,bevel)
def bar(name,a,b,width,depth,m):
    mid=(Vector(a)+Vector(b))/2; o=box(name,mid,(width,depth,(Vector(b)-Vector(a)).length),m)
    o.rotation_euler=Vector(b).__sub__(Vector(a)).to_track_quat('Z','Y').to_euler(); return o
def rod(name,a,b,r,m):
    a,b=Vector(a),Vector(b); o=cyl(name,(a+b)/2,r,(b-a).length,m,'Z',16)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler(); return o
def empty(name,loc=(0,0,0)):
    o=bpy.data.objects.new(name,None); bot.objects.link(o); o.location=loc; return o
def parent_keep(o,p):
    o.parent=p; o.matrix_parent_inverse=p.matrix_world.inverted()
def linear(o):
    for fc in o.animation_data.action.fcurves:
        for k in fc.keyframe_points: k.interpolation='LINEAR'
        fc.modifiers.new('CYCLES')

root=empty('SawbladeTank_ROOT')
box('Low belly chassis',(0,-.05,.38),(.95,1.7,.3),dark,.055)
box('Upper chassis deck',(0,-.05,.68),(.93,1.4,.14),yellow,.04)
box('Rear armor battery enclosure',(0,-.68,1.13),(1.02,.47,.96),yellow,.075)
box('Rear hazard face',(0,-.929,1.15),(.93,.025,.79),hazard,.045)
box('Rear central reinforcement',(0,-.95,1.15),(.16,.035,.83),dark)
box('Front central reinforcement',(0,-.428,1.15),(.16,.025,.81),dark)
for x in [-.524,.524]:
    box('Side hazard armor',(x,-.68,1.15),(.025,.38,.79),hazard,.02)
    for z in [.86,1.43]: cyl('Armor fastener',(x*1.035,-.68,z),.028,.018,steel,verts=6)
for x in [-.19,.19]:
    box('Handle foot',(x,-.68,1.625),(.12,.14,.045),dark)
    bar('Carry handle upright',(x,-.68,1.63),(x,-.68,1.78),.055,.055,dark)
rod('Carry handle grip',(-.19,-.68,1.78),(.19,-.68,1.78),.034,steel)

# Reference-like layered machinery fills the space between the rear pack and saw.
box('Central motor block',(0,-.03,.84),(.34,.53,.23),dark,.025)
for y in [-.23,-.12,-.01,.10]:
    box('Motor cooling rib',(0,y,.955),(.38,.037,.035),dark,.005)
cyl('Transverse upper pivot shaft',(0,.24,1.26),.07,.75,dark)
for x in [-.39,.39]:
    sign=1 if x>0 else -1
    box('Rear linkage tower',(x,-.41,1.13),(.10,.16,.40),dark,.017)
    bar('Diagonal tower brace',(x,-.59,.80),(x,-.36,1.28),.075,.075,dark)
    box('Rear lower latch',(x,-.432,.86),(.12,.045,.19),dark,.012)
    for z in [.815,.915]: cyl('Latch bolt',(x,-.468,z),.024,.018,steel,'Y',6,.003)
    rod('Upper hydraulic cylinder',(x,-.37,1.19),(x,.01,1.29),.045,yellow)
    rod('Upper chrome piston',(x,.01,1.29),(x,.27,1.36),.018,chrome)
    rod('Actuator end collar',(x,-.06,1.272),(x,.00,1.288),.052,dark)
    cyl('Upper arm pivot',(x,.27,1.34),.068,.105,dark,verts=12)
    cyl('Upper arm pin',(x+sign*.062,.27,1.34),.029,.018,steel,verts=6)
    rod('Long side hydraulic body',(x,-.43,.75),(x,.02,.75),.075,yellow)
    rod('Long side piston',(x,.02,.75),(x,.48,.75),.029,chrome)
    for y in [-.44,-.03]: cyl('Side cylinder collar',(x,y,.75),.085,.045,dark,'Y',12)
    box('Hydraulic mounting saddle',(x,-.20,.69),(.17,.22,.045),dark,.007)
    for y in [-.28,-.13]: cyl('Saddle bolt',(x+sign*.089,y,.70),.019,.012,steel,verts=6,bevel=.002)
    box('Deck side rail',(x,.0,.65),(.075,1.22,.085),dark,.012)
    for y in [-.38,.01,.37]:
        box('Track support bracket',(x+sign*.07,y,.57),(.10,.10,.18),yellow,.009)
        cyl('Bracket pin',(x+sign*.13,y,.57),.023,.014,dark,verts=6,bevel=.003)
    # Shallow panel seams and rear housing feet break up the large armor block.
    box('Armor lower foot',(x,-.64,.70),(.19,.35,.09),dark,.015)
    for z in [1.03,1.105,1.18]:
        box('Rear pack intake',(x,-.438,z),(.115,.015,.025),black,.002)
    box('Pack corner spine',(x*1.19,-.433,1.18),(.052,.04,.63),yellow,.009)

# Individual tread shoes run along a stadium loop in the Y/Z plane.
A=.60; R=.285; Z=.345; L=4*A+2*pi*R; COUNT=44; FRAMES=120
def path(s):
    s=s%L
    if s<2*A: return -A+s,Z+R,0.
    s-=2*A
    if s<pi*R:
        q=s/R; return A+R*sin(q),Z+R*cos(q),-q
    s-=pi*R
    if s<2*A: return A-s,Z-R,-pi
    q=(s-2*A)/R; return -A-R*sin(q),Z-R*cos(q),-pi-q
for side,x in [('L',-.66),('R',.66)]:
    belt=empty('Track_'+side+'_ASSEMBLY')
    box('Track internal frame '+side,(x,0,.34),(.24,1.24,.31),dark,.045)
    for y,r in [(-A,.247),(A,.247),(-.22,.17),(.22,.17)]:
        wheel=empty('Drive wheel '+side+str(y),(x,y,Z))
        parts=[cyl('Plain wheel drum',(x,y,Z),r,.26,rubber,verts=12,bevel=0),cyl('Flat ochre wheel face',(x+(.14 if x>0 else -.14),y,Z),r*.81,.016,yellow,verts=12,bevel=0)]
        outer=x+(.155 if x>0 else -.155)
        parts.append(cyl('Flush axle cap',(outer,y,Z),r*.26,.022,dark,verts=8,bevel=0))
        bpy.context.view_layer.update()
        for o in parts: parent_keep(o,wheel)
        for f in [1,121]:
            wheel.rotation_euler[0]=-(f-1)/120*L/r; wheel.keyframe_insert(data_path='rotation_euler',frame=f)
        linear(wheel)
    for j in range(COUNT):
        # A single low-profile shoe: no stacked pads or protruding grousers.
        o=box('Tread_'+side+'_%02d'%j,(0,0,0),(.34,L/COUNT*.96,.046),dark,.004)
        o['preserve_shape']=True
        o.parent=belt
        for f in range(1,122):
            distance=j*L/COUNT+(f-1)*L/120
            y,z,ang=path(distance)
            ang-=2*pi*math.floor(distance/L)
            o.location=(x,y,z); o.rotation_euler[0]=ang
            o.keyframe_insert(data_path='location',frame=f); o.keyframe_insert(data_path='rotation_euler',frame=f)
        linear(o)
    sign=1 if x>0 else -1
    box('Side service armor '+side,(x+sign*.15,-.05,.47),(.055,.73,.34),yellow,.025)
    box('Service plate raised spine '+side,(x+sign*.183,.24,.47),(.025,.10,.33),yellow,.008)
    for z in [.405,.49]: box('Cooling slot '+side,(x+sign*.183,-.05,z),(.008,.40,.036),black,.002)
    for y in [-.31,.22]: cyl('Service plate bolt',(x+sign*.19,y,.57),.024,.018,steel,verts=6)

# Exposed symmetric saw support, pivot bolts and hydraulic cylinders.
for x in [-.23,.23]:
    bar('Saw lift cheek',(x,.52,.42),(x,.30,1.30),.12,.14,yellow)
    bar('Axle fork',(x,.48,.77),(x,1.14,.96),.12,.13,dark)
    bar('Upper diagonal linkage',(x,.30,1.30),(x,-.58,1.08),.072,.09,yellow)
    bar('Lower linkage',(x,.48,.76),(x,-.63,.81),.075,.09,dark)
    rod('Hydraulic barrel',(x,-.57,.81),(x,-.06,.81),.065,yellow)
    rod('Hydraulic piston',(x,-.04,.81),(x,.44,.81),.028,chrome)
    for y in [-.52,-.08]: cyl('Hydraulic collar',(x,y,.81),.079,.04,dark,'Y')
    for y,z in [(.52,.42),(.30,1.30),(.48,.77),(1.14,.96),(-.58,1.08)]:
        cyl('Pivot bushing',(x,y,z),.089,.17,dark)
        cyl('Pivot hex bolt',(x+( .10 if x>0 else -.10),y,z),.048,.037,steel,verts=6)
    # Cable hose with intentional bowed routing.
    curve=bpy.data.curves.new('Hydraulic hose','CURVE'); curve.dimensions='3D'; curve.bevel_depth=.017; curve.bevel_resolution=1
    sp=curve.splines.new('BEZIER'); sp.bezier_points.add(3)
    for bp,co in zip(sp.bezier_points,[(x,-.68,.85),(x+.06,-.37,1.04),(x+.06,.05,1.08),(x,.26,1.24)]):
        bp.co=co; bp.handle_left_type='AUTO'; bp.handle_right_type='AUTO'
    o=bpy.data.objects.new('Black hydraulic hose',curve); bot.objects.link(o); o.data.materials.append(rubber)

center=Vector((0,1.16,.97)); saw=empty('Saw_SPIN_X',center)
# Thin plate with a ground, double-beveled cutting rim.
verts=[]; faces=[]; N=64
profile=[(-.027,.08),(-.027,.555),(-.004,.612),(.004,.612),(.027,.555),(.027,.08)]
for xx,rr in profile:
    for j in range(N):
        q=j*2*pi/N; verts.append((xx,1.16+rr*cos(q),.97+rr*sin(q)))
for k in range(len(profile)):
    for j in range(N): faces.append((k*N+j,k*N+(j+1)%N,((k+1)%len(profile))*N+(j+1)%N,((k+1)%len(profile))*N+j))
mesh=bpy.data.meshes.new('Ground saw rim mesh'); mesh.from_pydata(verts,[],faces); mesh.update()
disc=bpy.data.objects.new('Saw disc | sharpened bevel',mesh); bot.objects.link(disc); finish(disc,disc.name,rust)
disc.data.materials.append(cutting)
for polygon in disc.data.polygons:
    if polygon.index//N in [1,2,3]: polygon.material_index=1
disc['preserve_shape']=True; parts=[disc]
for x in [-.033,.033]:
    parts.append(cyl('Saw hub',(x*1.7,1.16,.97),.155,.07,dark,verts=24))
    parts.append(cyl('Saw locknut',(x*2.7,1.16,.97),.061,.05,yellow,verts=6))
    for j in range(6):
        q=j*2*pi/6
        parts.append(cyl('Hub bolt',(x*2.6,1.16+.115*cos(q),.97+.115*sin(q)),.018,.018,steel,verts=6))
for j in range(24):
    q=j*2*pi/24
    # Swept asymmetric wedge tapers from a wide root to a fine cutting point.
    # Local 2D outline uses radial distance and tangent offset.
    outline=[(.582,-.065),(.677,-.020),(.606,.055)]
    vv=[]
    for side in [-1,1]:
        for i,(rr,tt) in enumerate(outline):
            thickness=.004 if i==1 else .031
            vv.append((side*thickness,1.16+rr*cos(q)-tt*sin(q),.97+rr*sin(q)+tt*cos(q)))
    mm=bpy.data.meshes.new('Ground carbide wedge'); mm.from_pydata(vv,[],[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)]); mm.update()
    o=bpy.data.objects.new('Carbide cutting tooth %02d'%j,mm); bot.objects.link(o); finish(o,o.name,cutting)
    o['preserve_shape']=True; parts.append(o)
bpy.context.view_layer.update()
for o in parts: parent_keep(o,saw)
for f in [1,121]:
    saw.rotation_euler[0]=-(f-1)/120*12*pi; saw.keyframe_insert(data_path='rotation_euler',frame=f)
linear(saw)
for o in list(bot.objects):
    if o!=root and o.parent is None: o.parent=root

# Studio scene is separate from the model collection.
def to_stage(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    stage.objects.link(o)
floor=box('Studio floor',(0,0,-.025),(200,200,.04),mat('Studio slate',(.045,.059,.074),.15,.58),0); to_stage(floor)
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3.45,4.7,2.85)); camera=bpy.context.object; camera.name='Camera | front three quarter'; aim(camera,(0,.30,.83)); to_stage(camera)
camera.data.type='ORTHO'; camera.data.ortho_scale=3.65; bpy.context.scene.camera=camera
for name,loc,power,size,color in [('Key',(1,3,5),700,4,(1,.85,.66)),('Fill',(-3,1,2.6),450,3,(.66,.8,1)),('Rim',(1,-3,4),900,3,(1,.93,.8))]:
    bpy.ops.object.light_add(type='AREA',location=loc); o=bpy.context.object; o.name=name; o.data.energy=power; o.data.shape='DISK'; o.data.size=size; o.data.color=color; aim(o,(0,0,.7)); to_stage(o)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
scene.world.color=(.18,.18,.18); scene.render.resolution_x=1400; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
scene.render.fps=30; scene.frame_start=1; scene.frame_end=120; scene.frame_set(1)
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.view_settings.view_transform='AgX'
scene['README']='Press Space to play. Frames 1-120 loop at 30 fps; frame 121 is matching seam. Tracks travel one full circuit; saw rotates six turns. Blender +Y forward / Z up maps to Godot -Z forward / Y up. Studio collection is presentation only.'
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA'
            area.spaces.active.shading.type='MATERIAL'
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
exec(compile(open(os.path.join(ROOT,'prepare_ps3.py')).read(),'prepare_ps3.py','exec'))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'sawblade_tank.blend'),compress=True)
scene.render.image_settings.file_format='PNG'; scene.render.filepath=os.path.join(ROOT,'sawblade_tank_preview.png'); bpy.ops.render.render(write_still=True)
# Verify all links move, and the seam reproduces their original transforms.
moving=[o for o in bot.objects if o.name.startswith('Tread_')]
scene.frame_set(1); start={o.name:o.matrix_world.copy() for o in moving}
scene.frame_set(31); assert all((o.matrix_world.translation-start[o.name].translation).length>.1 for o in moving)
scene.frame_set(121); assert all((o.matrix_world.translation-start[o.name].translation).length<1e-5 for o in moving)
assert abs(saw.rotation_euler.x+12*pi)<1e-4
deps=bpy.context.evaluated_depsgraph_get(); triangles=0
for o in bot.objects:
    if o.type=='MESH':
        mesh=o.evaluated_get(deps).to_mesh(); mesh.calc_loop_triangles(); triangles+=len(mesh.loop_triangles); o.evaluated_get(deps).to_mesh_clear()
with open(os.path.join(ROOT,'validation.json'),'w') as f: json.dump({'tread_links':len(moving),'loop_frames':120,'fps':30,'saw_revolutions_per_loop':6,'evaluated_mesh_triangles':triangles,'moving_links_verified':True,'loop_seam_verified':True},f,indent=2)
print('SAWBLADE_TANK_VALIDATED',triangles)
