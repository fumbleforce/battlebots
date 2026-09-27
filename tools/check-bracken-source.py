"""Audit the saved Bracken source: fixed geometry, closed track clearance and
sampled turret sweep against the chassis. Run with Blender --background source
--python tools/check-bracken-source.py. Does not modify the saved source.
"""
import bpy, sys, json, math, re
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from atlas_model_kit import descendants

def tree(objects):
    verts=[]; faces=[]
    for obj in objects:
        if obj.type!='MESH': continue
        offset=len(verts)
        verts.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
        faces.extend(tuple(offset+i for i in p.vertices) for p in obj.data.polygons)
    return BVHTree.FromPolygons(verts,faces) if faces else None

hull=bpy.data.objects['BrackenHull']; yaw=bpy.data.objects['TurretYaw']; pitch=bpy.data.objects['TurretPitch']
hull_tree=tree(descendants(hull))
yaw_rest=yaw.matrix_basis.copy(); pitch_rest=pitch.matrix_basis.copy()
geometry=(ROOT/'battlebots/scripts/core/atlas_geometry.gd').read_text()
table=json.loads(re.search(r'"cannon_quad":(\[[^\n]+\])',geometry).group(1).rstrip(','))
# Same two-anchor rigid-ram solution as AtlasVisual, expressed in parent frames.
rams=[]
for side in ('L','R'):
    a=bpy.data.objects['ElevationBarrel'+side]; b=bpy.data.objects['ElevationRod'+side]
    for node,other in [(a,b),(b,a)]:
        origin=node.matrix_world.translation
        axis=(node.parent.matrix_world.inverted().to_3x3() @ (other.matrix_world.translation-origin)).normalized()
        rams.append((node,other,axis,node.matrix_basis.copy()))
def pose_rams():
    for node,other,axis,rest in rams:
        direction=(node.parent.matrix_world.inverted().to_3x3() @ (other.matrix_world.translation-node.matrix_world.translation)).normalized()
        node.matrix_basis=Matrix.Translation(rest.translation) @ axis.rotation_difference(direction).to_matrix().to_4x4() @ rest.to_3x3().to_4x4()
    bpy.context.view_layer.update()
contacts=[]
for bearing in range(0,360,5):
    floor=max(table[bearing//5],table[(bearing//5+1)%len(table)])
    for elevation in (floor,0,30):
        yaw.matrix_basis=yaw_rest @ Matrix.Rotation(math.radians(bearing),4,'Z')
        pitch.matrix_basis=pitch_rest @ Matrix.Rotation(math.radians(elevation),4,'X')
        bpy.context.view_layer.update()
        pose_rams()
        for obj in descendants(yaw):
            if obj.type!='MESH': continue
            collisions=tree([obj]).overlap(hull_tree)
            if collisions: contacts.append({'yaw':bearing,'pitch':elevation,'part':obj.name,'triangles':len(collisions)})
yaw.matrix_basis=yaw_rest; pitch.matrix_basis=pitch_rest
bpy.context.view_layer.update()
track_contacts=[]
for side in ('L','R'):
    drive=bpy.data.objects['DriveLeft' if side=='L' else 'DriveRight']
    static=tree([o for o in descendants(hull) if o.type=='MESH' and not o.name.startswith(('Tread_','Wheel_'))])
    for obj in descendants(drive):
        if obj.type=='MESH' and obj.name.startswith('Tread_'):
            count=len(tree([obj]).overlap(static))
            if count: track_contacts.append({'part':obj.name,'triangles':count})
report={'scope':'Saved Blender source. Turret vs hull at 72 bearings and 3 elevations each; track links vs all fixed hull/drive parts at authored phase. Excludes intentional coaxial joints, transient lifter sweep and native rendering.',
    'turret_contacts':contacts,'track_contacts':track_contacts,'packed_images':sum(bool(i.packed_file) for i in bpy.data.images)}
path=ROOT/'battlebots/exports/bracken-preview/source-audit.json'
path.write_text(json.dumps(report,indent=2)+'\n')
print('BRACKEN SOURCE AUDIT',len(contacts),'turret contacts;',len(track_contacts),'track contacts;',report['packed_images'],'packed images')
print(json.dumps(contacts[:8]+track_contacts[:8]))
if contacts or track_contacts: sys.exit(1)
