"""Validate saved world-space mechanics, including subframe motion and clearances."""
import bpy, math, json, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
ROOT=os.path.dirname(os.path.abspath(__file__))
scene=bpy.context.scene; root=bpy.data.objects['SawbladeTank_ROOT']
objects=list(bpy.data.collections['SAWBLADE TANK | model'].all_objects)
p=Vector((0,.29,.86)); base_yz=Vector((0,-.32,.745))
marker=bpy.data.objects['Hammer_Impact']; hinge=bpy.data.objects['Hammer_SWING_X']
face=bpy.data.objects['Hammer hardened striking face']
def frame(f):
    scene.frame_set(int(f),subframe=f-int(f)); bpy.context.view_layer.update()
def mesh_world(ob):
    deps=bpy.context.evaluated_depsgraph_get(); evaluated=ob.evaluated_get(deps)
    mesh=evaluated.to_mesh()
    verts=[evaluated.matrix_world@v.co for v in mesh.vertices]
    faces=[list(poly.vertices) for poly in mesh.polygons]
    evaluated.to_mesh_clear()
    return verts,faces
def tree(ob):
    verts,polys=mesh_world(ob)
    return BVHTree.FromPolygons(verts,polys)
def belongs(ob,parent):
    while ob:
        if ob==parent: return True
        ob=ob.parent
    return False

root['weapon']=1; root.update_tag()
minimum_z=10; minimum_overlap=10; maximum_pin_error=0; min_moment=10; lengths=[]; minimum_tail_clearance=10
for i in range(257):
    f=1+i/8; frame(f)
    verts,_=mesh_world(face); minimum_z=min(minimum_z,min(v.z for v in verts))
    for side,x in [('L',-.35),('R',.35)]:
        a=Vector((x,-.32,.745)); original=Vector((x,.47,.74))
        # Hinge's original world-space coordinates are canceled by its rest inverse.
        rot=hinge.matrix_world.to_3x3()
        expected=p+rot@(original-p)
        barrel=bpy.data.objects['Hammer_Cylinder_'+side]
        piston=bpy.data.objects['Hammer_Rod_'+side]
        error=(piston.matrix_world.translation-expected).length
        maximum_pin_error=max(maximum_pin_error,error,(barrel.matrix_world.translation-a).length)
        length=(expected-a).length; minimum_overlap=min(minimum_overlap,.44+.49-length)
        minimum_tail_clearance=min(minimum_tail_clearance,length-.49-.025)
        direction=(expected-a).normalized(); rest_direction=(original-a).normalized()
        barrel_direction=barrel.matrix_world.to_3x3()@rest_direction
        assert (barrel_direction-direction).length<.001,(f,side,'barrel alignment')
        moment=(expected-p).cross(direction).x
        min_moment=min(min_moment,abs(moment))
        assert moment>0,(f,side,'dead center or reversed leverage',moment)
        if side=='L' and f in [1,9]: lengths.append(length)
assert minimum_z>=-.001,minimum_z
assert maximum_pin_error<.001,maximum_pin_error
assert minimum_overlap>.13,minimum_overlap
assert minimum_tail_clearance>.05,minimum_tail_clearance
frame(9)
impact=marker.matrix_world.translation.copy()
normal=(marker.matrix_world.to_3x3()@Vector((0,0,-1))).normalized()
assert abs(impact.z)<.001 and (normal-Vector((0,0,-1))).length<1e-5,(impact,normal)
assert abs(min(v.z for v in mesh_world(face)[0]))<.001
frame(1); ready=hinge.matrix_world.copy()
frame(33); assert all(abs(hinge.matrix_world[i][j]-ready[i][j])<1e-6 for i in range(4) for j in range(4))
frame(100); assert all(abs(hinge.matrix_world[i][j]-ready[i][j])<1e-6 for i in range(4) for j in range(4))
for ob in [hinge]+[bpy.data.objects['Hammer_'+kind+'_'+side] for side in ['L','R'] for kind in ['Cylinder','Rod']]:
    track=ob.animation_data.nla_tracks['hammer_attack']
    assert len(track.strips)==1 and track.strips[0].repeat==1
    assert not any(fc.modifiers for fc in track.strips[0].action.fcurves)

# Surface intersection checks cover the moving head/arms/cranks against every
# drive and armor alternative. Hinge bearings and their through-shaft are
# intentional articulating contacts and are excluded from collision candidates.
motion_roots=[hinge]+[bpy.data.objects['Hammer_'+kind+'_'+side]
    for side in ['L','R'] for kind in ['Cylinder','Rod']]
moving=[ob for ob in objects if ob.type=='MESH' and any(belongs(ob,parent) for parent in motion_roots)]
fixed=[ob for ob in objects if ob.type=='MESH' and not belongs(ob,hinge)
       and (ob.get('module_slot') in ['drive','armor_side','armor_top','armor_front','armor_rear']
            or ('module_slot' not in ob and ob!=root))]
collisions=[]; samples=0
# All alternate drive and armor meshes can be checked together, even hidden.
for i in range(65):
    f=1+i/2; frame(f)
    fixed_trees=[(ob.name,tree(ob)) for ob in fixed]
    for ob in moving:
        moving_tree=tree(ob)
        for name,fixed_tree in fixed_trees:
            if moving_tree.overlap(fixed_tree): collisions.append((f,ob.name,name))
    samples+=1
assert not collisions,collisions[:30]

# Every exhaust's mouth is horizontal, has the authored length/radius, and
# clears the fitted rear armor (supported brackets pass underneath).
frame(1)
rear=[tree(ob) for ob in objects if ob.type=='MESH' and ob.get('module_slot')=='armor_rear']
exhausts={}
for label,length,radius in [('small',.25,.05),('medium',.40,.068),('large',.60,.095)]:
    pipes=[ob for ob in objects if ob.name.startswith('Horizontal hollow exhaust '+label)]
    for ob in pipes:
        vv,_=mesh_world(ob)
        assert abs(max(v.y for v in vv)-min(v.y for v in vv)-length)<1e-5
        assert abs((max(v.z for v in vv)+min(v.z for v in vv))/2-.68)<1e-5
        assert abs(max(v.z for v in vv)-min(v.z for v in vv)-2*radius)<1e-5
    for ob in objects:
        if ob.type=='MESH' and ob.get('module_slot')=='exhaust' and label in ob.name:
            assert not any(tree(ob).overlap(t) for t in rear),('rear armor',ob.name)
    exhausts[label]={'pipes':len(pipes),'length_m':length,'radius_m':radius,'rear_armor_clear':True}
result={'impact_face_center_m':list(impact),'impact_face_normal':list(normal),
    'minimum_face_height_m':minimum_z,'maximum_actuator_pin_error_m':maximum_pin_error,
    'minimum_rod_engagement_m':minimum_overlap,'minimum_hinge_moment_arm_m':min_moment,
    'minimum_rod_tail_clearance_m':minimum_tail_clearance,
    'pin_lengths_ready_impact_m':lengths,'kinematic_subframe_samples':257,
    'clearance_samples':samples,'all_drive_and_armor_surface_clearance':True,
    'single_shot_returns_and_holds':True,'exhausts':exhausts,
    'scope':'Authored visual mesh/kinematic checks; no game physics or damage validation'}
json.dump(result,open(os.path.join(ROOT,'mechanics_validation.json'),'w'),indent=2)
print('MECHANICS_VALIDATED',result,flush=True)
