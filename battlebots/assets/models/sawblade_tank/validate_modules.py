"""Verify saved module selectors, mounting hierarchy and palette; render examples."""
import bpy, os, json
from mathutils import Vector
ROOT=os.path.dirname(os.path.abspath(__file__))
root=bpy.data.objects['SawbladeTank_ROOT']; scene=bpy.context.scene
manifest=json.load(open(os.path.join(ROOT,'module_manifest.json')))
objects=list(bpy.data.collections['SAWBLADE TANK | model'].all_objects)
def refresh():
    root.update_tag(); scene.frame_set(1); bpy.context.view_layer.update()
def defaults():
    for key,value in manifest['selectors'].items(): root[key]=value['default']
    for key,value in manifest['palette'].items(): root[key]=value['default']
    refresh()
defaults()
checks=0
for key,value in manifest['selectors'].items():
    for choice in range(value['max']+1):
        root[key]=choice; refresh()
        for obj in objects:
            if 'module_slot' not in obj: continue
            expected=root[obj['module_slot']]!=obj['module_choice']
            assert obj.hide_render==expected,(key,choice,obj.name,'render')
            assert obj.hide_viewport==expected,(key,choice,obj.name,'viewport')
        checks+=1
    defaults()
for record in manifest['modules']:
    holder=bpy.data.objects[record['root']]
    assert holder.parent.name=='Socket_'+record['slot']
    assert holder.location.length<1e-5
    for obj in bpy.data.collections[record['collection']].objects:
        if obj.animation_data:
            assert all(fc.driver.is_valid for fc in obj.animation_data.drivers)
atlas=bpy.data.images['SawbladeTank | 4096 surface atlas']
assert tuple(atlas.size)==(4096,4096) and atlas.packed_file
root['paint_primary']=[.025,.29,.36,1]; refresh()
palette=bpy.data.node_groups['BOT_PALETTE | four player colors']
actual=palette.nodes['Primary paint'].outputs[0].default_value
assert max(abs(actual[i]-root['paint_primary'][i]) for i in range(4))<1e-5
defaults()
result={'modules':len(manifest['modules']),'selector_states_verified':checks,'shared_socket_hierarchy_verified':True,'visibility_drivers_verified':True,'palette_driver_verified':True,'packed_grayscale_atlas':[4096,4096]}
json.dump(result,open(os.path.join(ROOT,'module_validation.json'),'w'),indent=2)
print('MODULAR_ASSET_VERIFIED',result,flush=True)
scene.render.engine='BLENDER_EEVEE'; scene.eevee.taa_render_samples=64
scene.eevee.use_gtao=True; scene.eevee.gtao_distance=2; scene.eevee.gtao_factor=1.1
scene.render.resolution_x=1200; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.camera.data.ortho_scale=4.0
for label,selection,paint in [
    ('hammer_wheels',{'weapon':1,'drive':1,'armor_side':0,'armor_front':1,'exhaust':2},[.025,.29,.36,1]),
    ('ramp_armored',{'weapon':2,'drive':0,'armor_side':2,'armor_top':1,'armor_rear':1,'exhaust':3},None),
]:
    defaults()
    for key,value in selection.items(): root[key]=value
    if paint: root['paint_primary']=paint
    refresh(); scene.render.filepath=os.path.join(ROOT,'sawblade_tank_'+label+'.png')
    bpy.ops.render.render(write_still=True)
defaults()
