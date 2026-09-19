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
obstacles=[o for o in scene.objects if o.type=='MESH' and o.name.startswith(('Angled upper','Thick lower','Solid plow','Folded solid wheel shield','Plow rear reinforcement','Segmented wheel arch','Recessed side armor','Shouldered hull','Faceted lower'))]
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
shields=[o for o in obstacles if o.name.startswith('Folded solid wheel shield')]
assert len(shields)==2
for shield in shields:
    edge_counts={}
    for face in shield.data.polygons:
        vertices=list(face.vertices)
        for a,b in zip(vertices,vertices[1:]+vertices[:1]):
            key=tuple(sorted((a,b)));edge_counts[key]=edge_counts.get(key,0)+1
    assert all(count==2 for count in edge_counts.values()), 'Wheel shields must be closed solid shells, not open plates'
shield_trees=[tree(o) for o in shields]
shield_hits=[]
for side in [-1,1]:
    for x in [.80,.93,1.07]:
        for z in [.12,.30,.48,.60]:
            origin=Vector((side*x,2.5,z));direction=Vector((0,-1,0))
            hits=[t.ray_cast(origin,direction) for t in shield_trees]
            hits=[h for h in hits if h[0] is not None]
            assert hits, 'Plow must intercept frontal approach to tire at '+str((side*x,z))
            closest=min(hits,key=lambda h:h[3]);assert closest[0].y>1.045
            shield_hits.append(list(closest[0]))
    o=next(o for o in shields if any(v.x*side>1.2 for v in world_vertices(o)))
    vs=world_vertices(o)
    outer=[v for v in vs if abs(v.x)>1.20 and v.z<.12]
    inner=[v for v in vs if abs(v.x)<.72 and v.z<.12]
    assert max(v.y for v in inner)-max(v.y for v in outer)>.20, 'Outer shield edge must fold backward in plan view'
for name in ['Oxide red • chipped paint','Ochre safety paint']:
    mat=bpy.data.materials[name];p=mat.node_tree.nodes.get('Principled BSDF')
    assert p.inputs['Roughness'].default_value>.88
    assert p.inputs['Metallic'].default_value<.05
    assert any(n.type=='NORMAL_MAP' for n in mat.node_tree.nodes)
boss=next(o for o in scene.objects if o.name=='Flamer stand-off boss')
tower=next(o for o in scene.objects if o.name=='Tapered armored tower')
gap=min(v.y for v in world_vertices(boss))-max(v.y for v in world_vertices(tower))
assert gap>.045, 'External flamer boss must clear tower face'
report={'wheel_bounds_blender_m':wheel_bounds,'tire_armor_surface_intersections':intersections,'closed_solid_wheel_shields':True,'frontal_tire_shield_ray_hits':shield_hits,'flamer_boss_tower_gap_m':gap,'matte_paint_and_normal_maps':True}
Path(__file__).with_name('geometry_validation.json').write_text(json.dumps(report,indent=2))
print('GEOMETRY CHECK PASSED: tires clear solid plow; 24 frontal tire rays intercepted; shield wings fold backward; matte PBR maps present; flamer mount clears tower.')
