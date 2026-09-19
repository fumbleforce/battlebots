"""Run with Blender against the saved source to verify actual mesh clearances."""
import bpy, json
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from pathlib import Path

scene=bpy.context.scene
deps=bpy.context.evaluated_depsgraph_get()
def world_vertices(o):return [o.matrix_world@v.co for v in o.data.vertices]
def tree(o):
    me=o.evaluated_get(deps).to_mesh()
    vs=[o.matrix_world@v.co for v in me.vertices]
    fs=[list(p.vertices) for p in me.polygons]
    result=BVHTree.FromPolygons(vs,fs)
    o.evaluated_get(deps).to_mesh_clear()
    return result

wheels=[o for o in scene.objects if o.type=='EMPTY' and o.name.startswith('Wheel')]
assert len(wheels)==4
obstacles=[o for o in scene.objects if o.type=='MESH' and o.name.startswith(('Angled upper','Thick lower','Flared angular','Segmented wheel arch','Recessed side armor','Shouldered hull','Faceted lower'))]
obstacle_trees=[(o.name,tree(o)) for o in obstacles]
intersections=[];wheel_bounds={}
for wheel in wheels:
    verts=[v for o in wheel.children if o.type=='MESH' for v in world_vertices(o)]
    lo=[min(v[i] for v in verts) for i in range(3)];hi=[max(v[i] for v in verts) for i in range(3)]
    assert hi[0]-lo[0]<.52, 'Wheel geometry must remain centered on its pivot'
    assert hi[2]<.85 and lo[2]>-.01, 'No displaced or floating tire sidewalls'
    wheel_bounds[wheel.name]={'min':lo,'max':hi}
    for o in wheel.children:
        if o.type!='MESH' or not o.name.startswith(('Rounded tire','Staggered traction')):continue
        tire_tree=tree(o)
        for name,obstacle_tree in obstacle_trees:
            if tire_tree.overlap(obstacle_tree):intersections.append([o.name,name])
assert not intersections, 'Visible wheel/armor surface intersections: '+str(intersections)
boss=next(o for o in scene.objects if o.name=='Flamer stand-off boss')
tower=next(o for o in scene.objects if o.name=='Tapered armored tower')
gap=min(v.y for v in world_vertices(boss))-max(v.y for v in world_vertices(tower))
assert gap>.045, 'External flamer boss must clear tower face'
report={'wheel_bounds_blender_m':wheel_bounds,'tire_armor_surface_intersections':intersections,'flamer_boss_tower_gap_m':gap}
Path(__file__).with_name('geometry_validation.json').write_text(json.dumps(report,indent=2))
print('GEOMETRY CHECK PASSED: actual tire/armor meshes do not intersect; sidewalls centered; external flamer mount clears tower.')
