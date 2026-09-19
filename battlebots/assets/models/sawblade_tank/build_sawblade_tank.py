"""Rebuild with Blender 4.0+: blender -b --python build_sawblade_tank.py"""
import bpy, bmesh, math, random, os, json
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
        geo=n.new('ShaderNodeNewGeometry')
        scale=n.new('ShaderNodeVectorMath'); scale.operation='SCALE'; scale.inputs[3].default_value=40
        grid=n.new('ShaderNodeVectorMath'); grid.operation='FLOOR'
        unscale=n.new('ShaderNodeVectorMath'); unscale.operation='SCALE'; unscale.inputs[3].default_value=.025
        l.new(geo.outputs['Position'],scale.inputs[0]); l.new(scale.outputs[0],grid.inputs[0]); l.new(grid.outputs[0],unscale.inputs[0])
        tex=n.new('ShaderNodeTexNoise'); tex.inputs['Scale'].default_value=18; tex.inputs['Detail'].default_value=1
        l.new(unscale.outputs[0],tex.inputs['Vector'])
        ramp=n.new('ShaderNodeValToRGB'); ramp.color_ramp.interpolation='CONSTANT'
        ramp.color_ramp.elements[0].position=.20; ramp.color_ramp.elements[0].color=(.08,.073,.06,1)
        ramp.color_ramp.elements[1].position=.29; ramp.color_ramp.elements[1].color=(*(c*.60 for c in color),1)
        ramp.color_ramp.elements.new(.39).color=(*(c*.84 for c in color),1)
        ramp.color_ramp.elements.new(.47).color=(*color,1)
        ramp.color_ramp.elements.new(.60).color=(*(min(c*1.13,1) for c in color),1)
        l.new(tex.outputs['Fac'],ramp.inputs[0]); l.new(ramp.outputs[0],bs.inputs['Base Color'])
    return m
yellow=mat('01 | worn ochre enamel',(.66,.32,.018),.45,.52,True)
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
def plate(name,depth,outline,thickness,m,axis='X',bevel=.006):
    vv=[]
    for offset in [-thickness/2,thickness/2]:
        for u,v in outline: vv.append((depth+offset,u,v) if axis=='X' else (u,depth+offset,v))
    count=len(outline); ff=[tuple(reversed(range(count))),tuple(range(count,2*count))]
    ff += [(j,(j+1)%count,(j+1)%count+count,j+count) for j in range(count)]
    mesh=bpy.data.meshes.new(name+' mesh'); mesh.from_pydata(vv,[],ff); mesh.update()
    bm=bmesh.new(); bm.from_mesh(mesh); bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    obj=bpy.data.objects.new(name,mesh); bot.objects.link(obj); return finish(obj,name,m,bevel)
def parent_keep(o,p):
    o.parent=p; o.matrix_parent_inverse=p.matrix_world.inverted()
def linear(o):
    for fc in o.animation_data.action.fcurves:
        for k in fc.keyframe_points: k.interpolation='LINEAR'
        fc.modifiers.new('CYCLES')

root=empty('SawbladeTank_ROOT')
box('Underside steel pan',(0,-.03,.29),(.94,1.63,.18),dark,.055)
box('Recessed chassis deck',(0,.03,.52),(.79,1.44,.13),dark,.025)
for x in [-.40,.40]: box('Load bearing longitudinal rail',(x,-.04,.54),(.11,1.60,.12),dark,.015)
for y in [-.62,-.15,.40]: box('Chassis crossmember',(0,y,.45),(1.16,.105,.105),dark,.012)

# The deep chamfered counterweight pack follows the side and top silhouettes.
box('Deep rear armor enclosure',(0,-.83,1.05),(1.10,.88,1.04),yellow,.085)
side_outline=[(-1.27,.61),(-1.19,.53),(-.47,.53),(-.39,.61),(-.39,1.49),(-.47,1.57),(-1.19,1.57),(-1.27,1.49)]
front_outline=[(-.55,.61),(-.47,.53),(.47,.53),(.55,.61),(.55,1.49),(.47,1.57),(-.47,1.57),(-.55,1.49)]
for x in [-.556,.556]:
    sign=1 if x>0 else -1
    # One broad vertical spine and two diagonal branches, not repeated stripes.
    plate('Side black vertical band',x+sign*.003,[(-.91,.62),(-.75,.62),(-.75,1.48),(-.91,1.48)],.004,black,bevel=0)
    for dz in [0,-.39]:
        plate('Side diagonal hazard branch',x+sign*.005,[(-.90,1.48+dz),(-.90,1.30+dz),(-1.17,1.04+dz),(-1.17,1.22+dz)],.004,black,bevel=0)
    for y,z in [(-.50,.68),(-.50,1.42),(-1.16,.66),(-1.16,1.43)]:
        cyl('Recessed armor screw',(x+sign*.017,y,z),.014,.007,dark,verts=6,bevel=.001)
for y in [-1.277,-.383]:
    box('Pack center black band',(0,y+(-.004 if y<-.8 else .004),1.05),(.18,.006,.86),black,.002)
    for sign in [-1,1]:
        for dz in [0,-.42]:
            outline=[(sign*.11,1.48+dz),(sign*.25,1.48+dz),(sign*.455,1.20+dz),(sign*.455,1.05+dz)]
            plate('End diagonal black chevron',y+(-.005 if y<-.8 else .005),outline,.004,black,'Y',0)
box('Black band across pack crown',(0,-.83,1.574),(.18,.68,.005),black,.001)
for x in [-.19,.19]:
    box('Handle mounting foot',(x,-.83,1.59),(.11,.12,.034),dark,.009)
    bar('Carry handle upright',(x,-.83,1.60),(x,-.83,1.74),.045,.048,dark)
    for yy in [-.86,-.80]: cyl('Handle screw',(x,yy,1.612),.009,.01,steel,'Z',6,.001)
rod('Carry handle grip',(-.19,-.83,1.74),(.19,-.83,1.74),.025,steel)

box('Central transmission',(0,-.04,.67),(.37,.65,.28),dark,.035)
cyl('Exposed drive motor',(0,.13,.83),.135,.42,dark,'Y',24)
for y in [-.05,.01,.07,.13,.19]:
    cyl('Motor cooling flange',(0,y,.83),.144,.018,black,'Y',24,.003)
cyl('Motor end cap',(0,.355,.83),.105,.026,steel,'Y',16)
cyl('Transverse upper pivot shaft',(0,.26,1.25),.042,.72,steel)
for x in [-.24,.24]: cyl('Upper shaft yellow collar',(x,.26,1.25),.095,.070,yellow,verts=16)
for x in [-.35,.35]:
    sign=1 if x>0 else -1
    box('Rear mechanism clevis',(x,-.32,1.02),(.10,.17,.25),dark,.016)
    bar('Rear triangular brace',(x,-.42,.80),(x,-.26,1.12),.065,.080,dark)
    box('Rear twin hinge bracket',(x,-.362,.80),(.13,.065,.24),dark,.013)
    for z in [.73,.865]: cyl('Pack mounting bolt',(x,-.319,z),.031,.022,steel,'Y',6,.004)
    rod('Diagonal lift ram sleeve',(x,-.28,1.075),(x,.06,1.215),.040,yellow)
    rod('Diagonal lift ram piston',(x,.06,1.215),(x,.30,1.31),.019,chrome)
    for y,z in [(-.28,1.075),(.30,1.31)]:
        cyl('Lift ram eye',(x,y,z),.061,.064,dark,verts=16)
        cyl('Lift ram pin',(x+sign*.045,y,z),.025,.024,steel,verts=6)
    box('Rectangular hydraulic jacket',(x,-.12,.745),(.15,.48,.16),yellow,.025)
    rod('Main exposed chrome ram',(x,.115,.745),(x,.52,.745),.029,chrome)
    rod('Rear hydraulic feed',(x,-.36,.745),(x,-.50,.745),.026,chrome)
    for y in [-.36,.12]: cyl('Main ram end collar',(x,y,.745),.082,.035,dark,'Y',16)
    bar('Lower frame link',(x,-.44,.63),(x,.53,.68),.055,.065,dark)
    box('Cylinder mounting saddle',(x,-.12,.64),(.19,.25,.055),dark,.008)
    for y in [-.25,.025]: cyl('Hydraulic jacket bolt',(x+sign*.084,y,.747),.017,.01,steel,verts=6,bevel=.002)
    for y in [-.26,.22]:
        box('Track hanger',(x+sign*.10,y,.57),(.09,.095,.16),yellow,.008)
        cyl('Hanger bolt',(x+sign*.155,y,.57),.018,.016,dark,verts=6)
    plate('Rear pack mounting gusset',x,[(-.96,.54),(-.39,.54),(-.29,.41),(-.63,.39)],.09,dark)
    curve=bpy.data.curves.new('Manifold hose','CURVE'); curve.dimensions='3D'; curve.bevel_depth=.012; curve.bevel_resolution=2
    sp=curve.splines.new('BEZIER'); sp.bezier_points.add(3)
    for bp,co in zip(sp.bezier_points,[(x,-.39,.83),(x+sign*.05,-.18,.93),(x+sign*.05,.07,.91),(x,.13,.79)]):
        bp.co=co; bp.handle_left_type='AUTO'; bp.handle_right_type='AUTO'
    ob=bpy.data.objects.new('Manifold return hose',curve); bot.objects.link(ob); ob.data.materials.append(rubber)

# Unequal drive/idler radii produce the reference's sloping upper belt profile.
A=.60; R=.285; Z=.345; RR=.19; RZ=.25; COUNT=44; FRAMES=120
phi=math.atan2(Z-RZ,2*A); distance_centers=math.hypot(2*A,Z-RZ)
theta_top=phi+math.acos((RR-R)/distance_centers)
theta_bottom=phi-math.acos((RR-R)/distance_centers)
rear_top=Vector((-A+RR*cos(theta_top),RZ+RR*sin(theta_top)))
front_top=Vector((A+R*cos(theta_top),Z+R*sin(theta_top)))
rear_bottom=Vector((-A+RR*cos(theta_bottom),RZ+RR*sin(theta_bottom)))
front_bottom=Vector((A+R*cos(theta_bottom),Z+R*sin(theta_bottom)))
straight=(front_top-rear_top).length; front_arc=R*(theta_top-theta_bottom); rear_arc=RR*(2*pi-theta_top+theta_bottom)
L=2*straight+front_arc+rear_arc
def path(s):
    s=s%L
    if s<straight:
        p=rear_top+(front_top-rear_top)*(s/straight); return p.x,p.y,theta_top-pi/2
    s-=straight
    if s<front_arc:
        q=theta_top-s/R; return A+R*cos(q),Z+R*sin(q),q-pi/2
    s-=front_arc
    if s<straight:
        p=front_bottom+(rear_bottom-front_bottom)*(s/straight); return p.x,p.y,theta_bottom-pi/2
    q=theta_bottom-(s-straight)/RR; return -A+RR*cos(q),RZ+RR*sin(q),q-pi/2
drive_start=set(bot.objects)
for side,x in [('L',-.66),('R',.66)]:
    belt=empty('Track_'+side+'_ASSEMBLY')
    plate('Track internal frame '+side,x,[(-.60,.17),(.60,.17),(.60,.52),(-.60,.36)],.24,dark,bevel=.015)
    for y,r,wz in [(-A,.155,RZ),(A,.247,Z),(-.22,.13,.22),(.22,.15,.25)]:
        wheel=empty('Drive wheel '+side+str(y),(x,y,wz))
        parts=[cyl('Plain wheel drum',(x,y,wz),r,.26,rubber,verts=16,bevel=.004),cyl('Flat ochre wheel face',(x+(.14 if x>0 else -.14),y,wz),r*.81,.016,yellow,verts=16,bevel=.004)]
        outer=x+(.155 if x>0 else -.155)
        parts.append(cyl('Flush axle cap',(outer,y,wz),r*.26,.022,dark,verts=8,bevel=0))
        for k in range(8):
            angle=k*pi/4
            ob=box('Flush wheel spoke',(outer,y+cos(angle)*r*.58,wz+sin(angle)*r*.58),(.003,r*.26,r*.17),dark,0)
            ob.rotation_euler.x=angle; parts.append(ob)
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
    plate('Tapered side service armor '+side,x+sign*.151,[(.10,.60),(-.19,.56),(-.49,.44),(-.49,.22),(.10,.22)],.049,yellow)
    box('Service cover vertical flange '+side,(x+sign*.181,.065,.41),(.027,.105,.37),yellow,.012)
    for z in [.33,.415]: box('Recessed rectangular cooling slot '+side,(x+sign*.180,-.205,z),(.006,.29,.032),black,.001)
    for y,z in [(.065,.565),(.065,.255),(-.44,.255)]: cyl('Service plate bolt',(x+sign*.192,y,z),.017,.012,steel,verts=6,bevel=.002)

# Exposed symmetric saw support, pivot bolts and hydraulic cylinders.
drive_objects=set(bot.objects)-drive_start
weapon_start=set(bot.objects)
for x in [-.23,.23]:
    bar('Broad saw lift cheek',(x,.52,.42),(x,.30,1.30),.14,.19,yellow)
    bar('Axle fork',(x,.48,.77),(x,1.14,.96),.12,.13,dark)
    bar('Upper diagonal linkage',(x,.30,1.30),(x,-.31,1.04),.045,.055,yellow)
    bar('Lower linkage',(x,.48,.76),(x,-.63,.81),.075,.09,dark)
    rod('Central hydraulic barrel',(x,-.28,.90),(x,.01,.90),.052,dark)
    rod('Central hydraulic piston',(x,.02,.90),(x,.44,.90),.023,chrome)
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
weapon_objects=set(bot.objects)-weapon_start
for o in list(bot.objects):
    if o!=root and o.parent is None: o.parent=root
exec(compile(open(os.path.join(ROOT,'build_modules.py')).read(),'build_modules.py','exec'))

# Studio scene is separate from the model collection.
def to_stage(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    stage.objects.link(o)
floor=box('Studio floor',(0,0,-.025),(200,200,.04),mat('Studio slate',(.045,.059,.074),.15,.58),0); to_stage(floor)
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-3.7,4.7,2.5)); camera=bpy.context.object; camera.name='Camera | front three quarter'; aim(camera,(0,.15,.84)); to_stage(camera)
camera.data.type='ORTHO'; camera.data.ortho_scale=3.8; bpy.context.scene.camera=camera
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
exec(compile(open(os.path.join(ROOT,'prepare_asset.py')).read(),'prepare_asset.py','exec'))
exec(compile(open(os.path.join(ROOT,'configure_modules.py')).read(),'configure_modules.py','exec'))
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT,'sawblade_tank.blend'),compress=True)
scene.render.image_settings.file_format='PNG'; scene.render.filepath=os.path.join(ROOT,'sawblade_tank_preview.png'); bpy.ops.render.render(write_still=True)
# Verify all links move, and the seam reproduces their original transforms.
moving=[o for o in bot.all_objects if o.name.startswith('Tread_')]
scene.frame_set(1); start={o.name:o.matrix_world.copy() for o in moving}
scene.frame_set(31); assert all((o.matrix_world.translation-start[o.name].translation).length>.1 for o in moving)
scene.frame_set(121); assert all((o.matrix_world.translation-start[o.name].translation).length<1e-5 for o in moving)
assert abs(saw.rotation_euler.x+12*pi)<1e-4
deps=bpy.context.evaluated_depsgraph_get(); triangles=0
for o in bot.all_objects:
    if o.type=='MESH':
        mesh=o.evaluated_get(deps).to_mesh(); mesh.calc_loop_triangles(); triangles+=len(mesh.loop_triangles); o.evaluated_get(deps).to_mesh_clear()
with open(os.path.join(ROOT,'validation.json'),'w') as f: json.dump({'tread_links':len(moving),'loop_frames':120,'fps':30,'saw_revolutions_per_loop':6,'evaluated_mesh_triangles':triangles,'moving_links_verified':True,'loop_seam_verified':True},f,indent=2)
print('SAWBLADE_TANK_VALIDATED',triangles)
