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

exec(compile((HERE / 'surface_materials.py').read_text(encoding='utf-8'), 'surface_materials.py', 'exec'))

red=material('Oxide red • chipped paint',(.255,.040,.025),.025,.91,True)
dark=material('Blackened steel',(.06,.066,.069),.90,.85,True)
steel=material('Exposed brushed edges',(.20,.215,.21),.93,.79,True)
rubber=material('Charcoal tire rubber',(.006,.007,.007),0,.97)
yellow=material('Ochre safety paint',(.47,.28,.045),.025,.92,True)
ivory=material('Warm stencil paint',(.8,.76,.61),.05,.74)
black=material('Recess shadow',(.006,.009,.011),.15,.8)
brass=material('Heat stained bronze',(.23,.13,.038),.85,.79)

def empty(name,loc=(0,0,0),parent=None):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o); o.location=loc
    if parent: o.parent=parent
    o.empty_display_size=.12
    bpy.context.view_layer.update()
    return o
root=empty('Flamebot07')
chassis=empty('Chassis',parent=root)
turret=empty('TurretYaw',(0,-.13,.91),root)

def finish(o,name,mat,parent,bevel=0):
    o.name=name; o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('Machined edge','BEVEL'); mod.width=bevel; mod.segments=2 if bevel>.012 else 1
        o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
    if parent:
        bpy.context.view_layer.update()
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

exec(compile((HERE / 'geometry_v2.py').read_text(encoding='utf-8'), 'geometry_v2.py', 'exec'))

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
source_meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
refined_armor=refine_armor_uvs(source_meshes)
finish_secondary_surfaces()
runtime_meshes=[]
for pivot in [chassis,turret,gun]+[o for o in root.children if o.name.startswith('Wheel')]:
    children=[o for o in pivot.children if o.type=='MESH']
    if not children: continue
    bpy.ops.object.select_all(action='DESELECT')
    copies=[]
    for o in children:
        c=o.copy();c.data=o.data.copy();bpy.context.collection.objects.link(c);c.select_set(True);copies.append(c)
    bpy.context.view_layer.objects.active=copies[0]; bpy.ops.object.join(); bpy.context.object.name=pivot.name+'_Mesh'
    runtime_meshes.append(bpy.context.object)

asset=[o for o in bpy.context.scene.objects if o.type=='EMPTY']+runtime_meshes
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
stats['editable_components']=len(source_meshes)
stats['clearance_checks_m']=clearance_report
(HERE/'asset_stats.json').write_text(json.dumps(stats,indent=2))
for o in runtime_meshes:bpy.data.objects.remove(o,do_unlink=True)

# Studio is source-only and excluded from GLB.
studio=bpy.data.collections.new('Studio • excluded from game export'); bpy.context.scene.collection.children.link(studio)
def move_studio(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    studio.objects.link(o)
floor=material('Studio floor',(.30,.32,.34),0,.94)
o=box('Studio floor',(0,0,-.015),(200,200,.025),floor,None,0); move_studio(o)
def aim(o,p): o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(3.5,5.2,2.85)); cam=bpy.context.object; cam.name='Hero camera'; aim(cam,(0,.15,.82)); cam.data.type='ORTHO'; cam.data.ortho_scale=3.8; move_studio(cam); bpy.context.scene.camera=cam
for name,loc,power,size,col in [('Large warm key',(1,3,5),1000,3,(1,.92,.84)),('Cool fill',(-3,1,2.7),650,3,(.85,.91,1)),('Rim strip',(1,-3,4),1000,3,(1,.94,.87))]:
    bpy.ops.object.light_add(type='AREA',location=loc); l=bpy.context.object; l.name=name; l.data.energy=power; l.data.shape='DISK'; l.data.size=size; l.data.color=col; aim(l,(0,0,.7)); move_studio(l)
scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=64; scene.cycles.use_denoising=True
scene.world.color=(.25,.25,.25); scene.render.resolution_x=1500; scene.render.resolution_y=1300; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'; scene.render.image_settings.file_format='PNG'
configure_texture_render(scene)
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
for screen in bpy.data.screens:
    for a in screen.areas:
        if a.type=='VIEW_3D':
            a.spaces.active.region_3d.view_perspective='CAMERA'
            a.spaces.active.shading.type='MATERIAL'
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'flamebot_07.blend'),compress=True)
scene.render.filepath=str(HERE/'flamebot_07_hero.png'); bpy.ops.render.render(write_still=True)
cam.location=(0,.2,6);cam.rotation_euler=(0,0,math.pi);cam.data.ortho_scale=3.9
scene.render.filepath=str(HERE/'flamebot_07_top.png');bpy.ops.render.render(write_still=True)
cam.location=(-3.5,-4.4,2.8);cam.data.ortho_scale=3.8; aim(cam,(0,-.05,.85))
scene.render.filepath=str(HERE/'flamebot_07_rear.png'); bpy.ops.render.render(write_still=True)
cam.location=(4,0,1.1);aim(cam,(0,.16,.88));cam.data.ortho_scale=3.45
scene.render.filepath=str(HERE/'flamebot_07_side.png');bpy.ops.render.render(write_still=True)
cam.location=(0,5,1.35);aim(cam,(0,.12,.86));cam.data.ortho_scale=3.1
scene.render.filepath=str(HERE/'flamebot_07_front.png');bpy.ops.render.render(write_still=True)
cam.location=(1.8,2.8,1.7);aim(cam,(.05,.82,.64));cam.data.ortho_scale=1.68
scene.render.filepath=str(HERE/'flamebot_07_texture_detail.png');bpy.ops.render.render(write_still=True)
print('ASSET_STATS',stats)
