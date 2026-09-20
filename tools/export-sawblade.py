"""Run with Blender 4.0: blender -b sawblade_tank.blend --python this_script.
Exports evaluated meshes and all modular alternatives without modifying the blend.
Blender drivers are authoring-only; module selection and motion run in Godot.
"""
import bpy
import json
from pathlib import Path

target = Path(bpy.data.filepath).parent.parent / 'sawblade_runtime'
target.mkdir(exist_ok=True)
root = bpy.data.objects['SawbladeTank_ROOT']
scene = bpy.context.scene
scene.frame_set(1)
objects = [root, *root.children_recursive]
manifest = {'source': 'SawbladeTank_ROOT', 'properties': {}}
for key, value in root.items():
    manifest['properties'][key] = {
        'default': list(value) if key.startswith('paint_') else value,
        **root.id_properties_ui(key).as_dict(),
    }
    # Blender UI defaults for colors are empty; retain the authored values.
    manifest['properties'][key]['default'] = list(value) if key.startswith('paint_') else value

for obj in objects:
    for prop in ('hide_render', 'hide_viewport'):
        obj.driver_remove(prop)
        setattr(obj, prop, False)
    obj.hide_set(False)
    if obj.animation_data:
        for track in obj.animation_data.nla_tracks:
            for strip in track.strips:
                if strip.action and strip.action.name.startswith('hammer_attack'):
                    obj.animation_data.action = strip.action
                    obj.animation_data.use_nla = False

# Save authored motion before removing actions. Tread samples become a compact
# distance-driven loop, independent of weapon animation and wall-clock time.
animated_treads = [o for o in objects if o.type == 'MESH' and o.animation_data and o.animation_data.action]
samples = {}
for frame in range(1, 121):
    scene.frame_set(frame)
    for obj in animated_treads:
        matrix = obj.matrix_world
        # Export the Blender world pose in glTF/Godot Y-up coordinates.
        pos = matrix.translation
        samples.setdefault(obj.name, []).append([round(pos.x, 6), round(pos.z, 6), round(-pos.y, 6), round(obj.rotation_euler.x, 6)])
scene.frame_set(1)
depsgraph = bpy.context.evaluated_depsgraph_get()
hammer = bpy.data.objects['Module_weapon_hammer']
hammer_samples = {}
for sample in range(129):
    frame = 1 + sample * 0.25
    scene.frame_set(int(frame), subframe=frame % 1)
    for obj in [hammer, *hammer.children_recursive]:
        matrix = obj.parent.matrix_world.inverted() @ obj.matrix_world if obj.parent else obj.matrix_world
        pos, quat, scale = matrix.decompose()
        hammer_samples.setdefault(obj.name, []).append([
            *[round(v, 6) for v in (pos.x, pos.z, -pos.y)],
            *[round(v, 6) for v in (quat.x, quat.z, -quat.y, quat.w)],
            *[round(v, 6) for v in (scale.x, scale.z, scale.y)]])
hammer_samples = {k: v for k, v in hammer_samples.items() if any(row != v[0] for row in v)}
scene.frame_set(1)
export_scene = bpy.data.scenes.new('SawbladeRuntime')
copies = {}
for obj in objects:
    if obj.type not in {'MESH', 'CURVE', 'EMPTY'}:
        continue
    if obj.type == 'EMPTY':
        copy = bpy.data.objects.new(obj.name + '_runtime', None)
    else:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        copy = bpy.data.objects.new(obj.name + '_runtime', mesh)
    copy['source_name'] = obj.name
    export_scene.collection.objects.link(copy)
    copies[obj] = copy
for obj, copy in copies.items():
    copy.parent = copies.get(obj.parent)
    copy.matrix_world = obj.matrix_world.copy()

# glTF cannot represent the source procedural paint graph. The supplied atlas
# already contains its surface detail; keep UVs and export portable PBR materials.
for mat in bpy.data.materials:
    if not mat.use_nodes:
        continue
    image = next((n.image for n in mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image), None)
    if image is None:
        continue
    old_bsdf = next((n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    metallic = old_bsdf.inputs['Metallic'].default_value if old_bsdf else 0.5
    roughness = old_bsdf.inputs['Roughness'].default_value if old_bsdf else 0.5
    mat.node_tree.nodes.clear()
    output = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
    bsdf = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = image
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    mat.node_tree.links.new(bsdf.outputs[0], output.inputs[0])

bpy.context.window.scene = export_scene
bpy.ops.export_scene.gltf(filepath=str(target / 'sawblade_runtime.glb'), export_format='GLB',
                          use_active_scene=True, export_animations=False,
                          export_extras=True, export_yup=True, export_cameras=False,
                          export_lights=False)
(target / 'sawblade_properties.json').write_text(json.dumps(manifest, indent=2) + '\n')
data_dir = target.parents[2] / 'data'
(data_dir / 'sawblade_treads.json').write_text(json.dumps(samples, separators=(',', ':')) + '\n')
(data_dir / 'sawblade_hammer.json').write_text(json.dumps(hammer_samples, separators=(',', ':')) + '\n')
print('SAWBLADE EXPORT', len(copies), 'nodes;', len(samples), 'moving tread objects')
