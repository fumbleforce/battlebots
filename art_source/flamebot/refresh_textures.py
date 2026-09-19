"""Refresh only material/UV data on the approved Blender model, then export/render."""
import bpy,math,random,json,hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector
HERE=Path(__file__).resolve().parent
OUT=HERE.parents[1]/'battlebots/assets/models/flamebot'
root=bpy.data.objects['Flamebot07'];chassis=bpy.data.objects['Chassis']
turret=bpy.data.objects['TurretYaw'];gun=bpy.data.objects['MinigunSpin']
def belongs(o):
    while o:
        if o==root:return True
        o=o.parent
    return False
source_meshes=[o for o in bpy.context.scene.objects if o.type=='MESH' and belongs(o)]
def geometry_hash():
    h=hashlib.sha256()
    for o in sorted(source_meshes,key=lambda o:o.name):
        h.update(o.name.encode());h.update(np.array(o.matrix_world,dtype=np.float64).tobytes())
        h.update(np.array([tuple(v.co) for v in o.data.vertices],dtype=np.float32).tobytes())
        for p in o.data.polygons:h.update(np.array(p.vertices,dtype=np.int32).tobytes())
    return h.hexdigest()
before=geometry_hash()
exec(compile((HERE/'surface_materials.py').read_text(encoding='utf-8'),'surface_materials.py','exec'))
definitions=[('Oxide red • chipped paint',(.255,.040,.025),.025,.91),
             ('Blackened steel',(.06,.066,.069),.90,.85),
             ('Exposed brushed edges',(.20,.215,.21),.93,.79),
             ('Ochre safety paint',(.47,.28,.045),.025,.92)]
# Restore any earlier edge variant to its base before a repeat material iteration.
for o in source_meshes:
    for i,m in enumerate(o.data.materials):
        if m and m.name.startswith('Oxide red |'):o.data.materials[i]=bpy.data.materials['Oxide red • chipped paint']
for m in list(bpy.data.materials):
    if m.users==0:bpy.data.materials.remove(m)
for im in list(bpy.data.images):
    if im.users==0:bpy.data.images.remove(im)
for name,color,metal,rough in definitions:
    old=bpy.data.materials[name]
    refs=[(o,i) for o in source_meshes for i,m in enumerate(o.data.materials) if m==old]
    images=[n.image for n in old.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
    for o,i in refs:o.data.materials[i]=None
    bpy.data.materials.remove(old)
    for im in images:
        if im.users==0:bpy.data.images.remove(im)
        else:im.name='Superseded '+im.name
    new=material(name,color,metal,rough,True)
    for o,i in refs:o.data.materials[i]=new
refined_armor=refine_armor_uvs(source_meshes)
finish_secondary_surfaces()
after=geometry_hash();assert before==after,'Texture pass must preserve every approved vertex, face and transform'
clearance_report=json.loads((HERE/'asset_stats.json').read_text())['clearance_checks_m']
code=(HERE/'build_flamebot.py').read_text(encoding='utf-8-sig')
export_code=code[code.index('runtime_meshes=[]'):code.index('# Studio is source-only')]
exec(compile(export_code,'shared_asset_export','exec'))
for m in list(bpy.data.materials):
    if m.users==0:bpy.data.materials.remove(m)
for im in list(bpy.data.images):
    if im.users==0:bpy.data.images.remove(im)
asset_materials={m for o in source_meshes for m in o.data.materials if m and m.use_nodes}
asset_images={n.image for m in asset_materials for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
assert all(im.packed_file for im in asset_images),'Every model texture must be self-contained'
textures=[{'name':im.name,'size':list(im.size),'packed':bool(im.packed_file)} for im in sorted(asset_images,key=lambda im:im.name)]
report={'geometry_sha256_before':before,'geometry_sha256_after':after,'approved_geometry_unchanged':before==after,
        'refined_armor_surfaces':refined_armor,'textures':textures}
(HERE/'texture_validation.json').write_text(json.dumps(report,indent=2))
scene=bpy.context.scene;cam=scene.camera
configure_texture_render(scene)
def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
cam.location=(3.5,5.2,2.85);aim(cam,(0,.15,.82));cam.data.ortho_scale=3.8
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'flamebot_07.blend'),compress=True)
cam.location=(1.8,2.8,1.7);aim(cam,(.05,.82,.64));cam.data.ortho_scale=1.68
scene.render.filepath=str(HERE/'flamebot_07_texture_detail.png');bpy.ops.render.render(write_still=True)
render_code=code[code.index("scene.render.filepath=str(HERE/'flamebot_07_hero.png')"):]
cam.location=(3.5,5.2,2.85);aim(cam,(0,.15,.82));cam.data.ortho_scale=3.8
exec(compile(render_code,'shared_asset_renders','exec'))
print('TEXTURE PASS: approved geometry unchanged; packed maps and sharpened renders saved.',flush=True)
