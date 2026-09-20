"""Rebuild the three original modular practice drones using Blender 5.2.
Run: blender --background --python art_source/practice_npcs/generate_practice_npcs.py
Authored hull: Godot 1.6 x .5 x 2m. Runtime fits canonical hull once.
All Detach_* objects retain true mesh/material parts for cosmetic destruction.
"""
import bpy, math, random
from pathlib import Path
from mathutils import Vector
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'battlebots/assets/models/practice_npcs'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = Path(__file__).resolve().parent
bpy.context.preferences.filepaths.save_version = 0
random.seed(4712)
N = 1024
rng = np.random.default_rng(4712)
noise = rng.random((N, N)).astype(np.float32)
scratches = np.zeros((N, N), np.float32)
for _ in range(750):
    x, y = rng.integers(0, N, 2)
    length = int(rng.integers(2, 35))
    scratches[y:min(y+2,N), x:min(x+length,N)] = rng.uniform(.2, 1)
chips = (noise > .996).astype(np.float32)
wear = np.maximum(scratches, chips)

def image(name, rgb, data=False):
    pixels = np.ones((N, N, 4), np.float32)
    pixels[:, :, :3] = rgb
    im = bpy.data.images.new(name, N, N)
    if data: im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(pixels.ravel())
    im.filepath_raw = str(OUT / (name + '.png'))
    im.file_format = 'PNG'
    im.save()
    im.pack()
    return im

rough = np.clip(.31 + noise*.10 + wear*.22, 0, 1)
orm = np.stack([np.ones_like(rough), rough, .74 + wear*.20], axis=-1)
orm_image = image('npc_orm', orm, True)
dx = np.gradient(noise*.012 + wear*.015, axis=1)
dy = np.gradient(noise*.012 + wear*.015, axis=0)
normal_image = image('npc_normal', np.stack([.5-dx*2,.5-dy*2,np.ones_like(noise)],axis=-1), True)

def material(name, color, metallic=.75, roughness=.34, painted=False, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes; links = mat.node_tree.links
    bs = nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color,1)
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = roughness
    if painted:
        base = np.asarray(color)[None,None,:]*(.92+noise[:,:,None]*.12)
        base = base*(1-wear[:,:,None]*.8)+np.array([.19,.21,.23])*wear[:,:,None]*.8
        tex = nodes.new('ShaderNodeTexImage'); tex.image = image(name+'_albedo',np.clip(base,0,1))
        links.new(tex.outputs['Color'],bs.inputs['Base Color'])
        tex = nodes.new('ShaderNodeTexImage'); tex.image = orm_image
        sep = nodes.new('ShaderNodeSeparateColor'); links.new(tex.outputs['Color'],sep.inputs['Color'])
        links.new(sep.outputs['Green'],bs.inputs['Roughness']); links.new(sep.outputs['Blue'],bs.inputs['Metallic'])
        tex = nodes.new('ShaderNodeTexImage'); tex.image = normal_image
        nm = nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value=.4
        links.new(tex.outputs['Color'],nm.inputs['Color']); links.new(nm.outputs['Normal'],bs.inputs['Normal'])
        bs.inputs['Coat Weight'].default_value=.25
        bs.inputs['Coat Roughness'].default_value=.22
    if emission:
        bs.inputs['Emission Color'].default_value=(*color,1)
        bs.inputs['Emission Strength'].default_value=emission
    return mat

paint_white=material('BULWARK ceramic enamel',(.56,.61,.64),painted=True)
paint_red=material('RAMMER crimson enamel',(.38,.026,.022),painted=True)
paint_teal=material('WATCHDOG petrol enamel',(.024,.22,.25),painted=True)
steel=material('Machined brushed titanium',(.32,.36,.39),.94,.22)
dark=material('Graphite powdercoat',(.027,.037,.045),.7,.43)
rubber=material('Tread vulcanized rubber',(.018,.023,.025),.02,.87)
brass=material('Heat stained brass',(.48,.28,.09),.86,.26)
hazard=material('Safety yellow',(.92,.51,.028),.6,.3,painted=True)
glass=material('Cold optics',(.03,.68,1),.45,.12,emission=3)
hot=material('Status amber',(.95,.15,.018),.2,.22,emission=3)

def pos(p): return (p[0],-p[2],p[1])
def bevel(obj, amount=.015):
    if amount:
        mod=obj.modifiers.new('Machined edge radii','BEVEL'); mod.width=amount; mod.segments=3
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for face in obj.data.polygons: face.use_smooth=True
    mod=obj.modifiers.new('Weighted production normals','WEIGHTED_NORMAL'); mod.keep_sharp=True; mod.weight=40
    return obj
def box(label,p,size,mat,edge=.012):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos(p)); o=bpy.context.object; o.name=label
    o.dimensions=(size[0],size[2],size[1]); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat); return bevel(o,edge)
def cylinder(label,p,radius,depth,mat,axis='y',vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=pos(p))
    o=bpy.context.object; o.name=label
    if axis=='x': o.rotation_euler.y=math.pi/2
    elif axis=='z': o.rotation_euler.x=math.pi/2
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(mat); return bevel(o,.005)
def bolts(p,width,depth):
    for x in [-width/2,width/2]:
        for z in [-depth/2,depth/2]:
            cylinder('Captive hex bolt',(p[0]+x,p[1],p[2]+z),.023,.014,steel,vertices=6)
            cylinder('Fastener socket',(p[0]+x,p[1]+.008,p[2]+z),.009,.002,dark,vertices=6)
def group(label,objects,origin=(0,0,0)):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.join(); o=bpy.context.object; o.name=label
    bpy.context.scene.cursor.location=pos(origin)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return o
def collect(label,fn,origin=(0,0,0)):
    before=set(bpy.context.scene.objects); fn()
    return group(label,[o for o in bpy.context.scene.objects if o not in before],origin)
def wheel(x,z,paint,index):
    p=(x,-.045,z)
    def parts():
        cylinder('Pneumatic tyre',p,.255,.22,rubber,'x',48)
        for outward in [-1,1]:
            cylinder('Beadlock ring',(x+outward*.116,-.045,z),.204,.025,steel,'x')
            cylinder('Recessed wheel disc',(x+outward*.132,-.045,z),.174,.025,dark,'x')
            cylinder('Cast wheel hub',(x+outward*.148,-.045,z),.092,.04,paint,'x',12)
            cylinder('Axle nut',(x+outward*.172,-.045,z),.046,.045,brass,'x',6)
            for j in range(8):
                a=j*math.tau/8
                cylinder('Beadlock stud',(x+outward*.15,-.045+math.cos(a)*.151,z+math.sin(a)*.151),.013,.024,steel,'x',6)
        for j in range(28):
            a=j*math.tau/28
            o=box('Chevron tyre lug',(x,-.045+math.cos(a)*.25,z+math.sin(a)*.25),(.23,.041,.07),rubber,.005)
            o.rotation_euler.x=-a
    return collect('Detach_Drive_%s_Wheel%d'%('Left' if x<0 else 'Right',index),parts,p)
def hull(paint):
    box('Sealed load-bearing tub',(0,-.08,0),(1.32,.28,1.78),dark,.075)
    box('Bottom skid plate',(0,-.23,0),(1.36,.045,1.84),steel,.025)
    for z in [-.61,.58]: cylinder('Cross axle',(0,-.085,z),.075,1.55,steel,'x')
    for x in [-.45,.45]:
        box('Recessed cooling duct',(x,.16,.56),(.23,.08,.58),dark)
        for z in range(8): box('Angled cooling fin',(x,.204,.32+z*.067),(.24,.025,.028),steel,.003)
    for x in [-.58,.58]:
        cylinder('Rear exhaust',(x,.02,.94),.06,.18,dark,'z')
        cylinder('Exhaust inner',(x,.02,1.034),.043,.006,rubber,'z')
    for x in [-.54,.54]:
        box('Optics casing',(x,.13,-.91),(.23,.105,.075),dark,.016)
        for dx in [-.055,.055]: cylinder('Protected lens',(x+dx,.14,-.956),.028,.018,glass,'z')
def panels(paint):
    def deck():
        box('Floating composite deck',(0,.155,.12),(1.10,.15,1.12),paint,.04)
        bolts((0,.237,.12),.96,.98)
        cylinder('Power hatch',(0,.246,.29),.17,.04,dark,vertices=12)
        cylinder('Hatch ring',(0,.27,.29),.135,.018,steel,vertices=12)
        box('Hatch release',(0,.29,.29),(.13,.025,.035),brass)
        for x in [-.21,.21]: box('Deck pinstripe',(x,.236,.15),(.025,.004,.80),hazard,.001)
    collect('Detach_Armor_Deck',deck,(0,.15,.12))
    for side in [-1,1]:
        def armor():
            box('Separate side armour',(side*.65,.08,0),(.11,.28,1.27),paint,.028)
            for z in [-.45,0,.45]:
                cylinder('Armor rivet',(side*.71,.09,z),.025,.02,steel,'x',6)
                box('Side anti-spall seam',(side*.711,.015,z),(.008,.028,.26),dark,.001)
        collect('Detach_Armor_'+('Left' if side<0 else 'Right'),armor,(side*.65,.08,0))
def wedge(paint):
    def blade():
        # Thick angular lifter, with a steel ground edge and segmented teeth.
        v=[(-.69,-.24,-1.02),(.69,-.24,-1.02),(.69,.17,-.50),(-.69,.17,-.50),
           (-.69,-.19,-1.02),(.69,-.19,-1.02),(.69,.23,-.50),(-.69,.23,-.50)]
        mesh=bpy.data.meshes.new('Forged wedge mesh'); mesh.from_pydata([pos(p) for p in v],[],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]); mesh.update()
        o=bpy.data.objects.new('Articulated wedge plate',mesh); bpy.context.collection.objects.link(o); o.data.materials.append(paint); bevel(o,.01)
        box('Forged cutting edge',(0,-.21,-1.018),(1.46,.06,.09),steel,.014)
        for x in [-.54,-.27,0,.27,.54]:
            box('Reinforced tooth',(x,-.22,-1.07),(.12,.08,.17),steel,.01)
            cylinder('Wedge captive bolt',(x,.135,-.59),.024,.018,dark,vertices=6)
        for x in [-.47,.47]: cylinder('Lifter hinge',(x,.13,-.5),.075,.14,brass,'x')
    collect('Detach_Weapon_Lifter',blade,(0,.13,-.5))
def spinner():
    def disc():
        cylinder('Vertical disc',(0,.1,-1.04),.33,.16,steel,'x',48)
        for s in [-1,1]:
            cylinder('Recessed spinner side',(s*.086,.1,-1.04),.235,.015,dark,'x')
            cylinder('Spinner bearing',(s*.103,.1,-1.04),.095,.08,brass,'x')
        for j in range(6):
            a=j*math.tau/6
            o=box('Replaceable carbide tooth',(0,.1+math.cos(a)*.31,-1.04+math.sin(a)*.31),(.23,.12,.12),hazard)
            o.rotation_euler.x=-a
    collect('Detach_Weapon_Spinner',disc,(0,.1,-1.04))
    for x in [-.24,.24]: box('Spinner bearing bracket',(x,.05,-.89),(.13,.23,.45),paint_red,.025)
def tracks(paint):
    for side in [-1,1]:
        def pod():
            box('Track drivetrain',(side*.71,-.06,0),(.24,.28,1.54),dark,.07)
            for z in [-.57,-.19,.19,.57]:
                cylinder('Steel road wheel',(side*.73,-.065,z),.18,.26,steel,'x')
                cylinder('Track hub',(side*.88,-.065,z),.075,.035,brass,'x',12)
            for y in [-.24,.13]:
                for j in range(16): box('Individual steel tread link',(side*.73,y,-.7+j*.094),(.34,.065,.082),dark,.009)
            for z in [-.79,.79]:
                for j in range(5): box('Curved end tread',(side*.73,-.2+j*.065,z),(.34,.065,.067),dark,.01)
            box('Track upper guard',(side*.71,.19,.14),(.29,.09,1.04),paint,.025)
            for z in [-.32,.1,.54]: box('Track guard warning stripe',(side*.71,.238,z),(.26,.003,.065),hazard,.001)
        collect('Detach_Drive_'+('Left' if side<0 else 'Right')+'_Track',pod,(side*.73,-.06,0))
def gun():
    def housing():
        cylinder('Turret bearing',(.34,.26,-.1),.25,.09,steel)
        box('Offset rotary gun mantlet',(.47,.35,-.35),(.57,.30,.62),paint_teal,.065)
        box('Ammunition box',(.17,.39,-.27),(.24,.33,.43),dark,.025)
        for z in [-.4,-.3,-.2]: box('Ammo box stiffener',(.039,.39,z),(.02,.3,.025),steel,.002)
        for j in range(8): cylinder('Exposed linked rounds',(.27+j*.043,.40,-.62),.025,.14,brass,'z',12)
        cylinder('Receiver',(.66,.27,-.77),.155,.43,dark,'z')
        cylinder('Receiver steel ring',(.66,.27,-.95),.166,.04,steel,'z')
    collect('Detach_Weapon_Receiver',housing,(.47,.29,-.35))
    def barrels():
        for j in range(6):
            a=j*math.tau/6
            x=.66+math.cos(a)*.095; y=.27+math.sin(a)*.095
            cylinder('Rotating fluted barrel',(x,y,-1.31),.033,.80,steel,'z',16)
            cylinder('Dark barrel bore',(x,y,-1.716),.021,.008,dark,'z',16)
        for z in [-1.02,-1.53]: cylinder('Barrel retaining ring',(.66,.27,z),.142,.052,dark,'z',32)
        cylinder('Central spindle',(.66,.27,-1.31),.03,.79,brass,'z',16)
    collect('Detach_Weapon_Barrels',barrels,(.66,.27,-1.1))

for variant,paint in [('wedge',paint_white),('bruiser',paint_red),('sentry',paint_teal)]:
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    collect('Structural_Chassis',lambda: hull(paint))
    panels(paint)
    if variant=='sentry':
        tracks(paint); gun()
        def glacis():
            box('Removable sloped front armour',(0,.075,-.82),(1.22,.19,.18),paint,.045)
            for x in [-.44,0,.44]:
                cylinder('Front armor captive bolt',(x,.18,-.82),.023,.016,steel,vertices=6)
        collect('Detach_Armor_Front',glacis,(0,.075,-.82))
    else:
        for x in [-.70,.70]:
            for i,z in enumerate([-.57,.57]): wheel(x,z,paint,i)
        if variant=='wedge': wedge(paint)
        else: spinner()
    # One authored ID plate, engraved bars, bumper reinforcement and rear lights.
    def details():
        box('Serialized manufacturer plate',(0,.252,.67),(.30,.018,.13),steel,.008)
        for j in range(11): box('Laser engraved machine ID',(-.115+j*.022,.263,.68),(.008,.002,.056 if j%3 else .08),dark,.001)
        box('Rear crash bar',(0,-.02,.91),(1.40,.15,.12),dark,.022)
        for x in [-.46,.46]: box('Recessed rear beacon',(x,.08,.973),(.16,.045,.01),hot,.005)
    collect('Chassis_detail',details)
    bpy.ops.object.select_all(action='SELECT')
    for o in list(bpy.context.selected_objects):
        bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(variant+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(variant+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_materials='EXPORT')
    print('PRACTICE ASSET',variant,len(bpy.context.scene.objects),'objects')
print('PRACTICE NPC ASSETS COMPLETE')
