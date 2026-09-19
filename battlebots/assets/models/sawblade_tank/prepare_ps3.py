"""Called by build_sawblade_tank.py; finalize geometry and bake a 1K atlas."""
scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
for obj in list(bot.objects):
    if obj.type=='CURVE':
        obj.select_set(True); bpy.context.view_layer.objects.active=obj
        bpy.ops.object.convert(target='MESH'); obj.select_set(False)
meshes=[o for o in bot.objects if o.type=='MESH']
for obj in meshes:
    bpy.context.view_layer.objects.active=obj
    for mod in list(obj.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
def tri_count():
    count=0
    for obj in meshes:
        obj.data.calc_loop_triangles(); count+=len(obj.data.loop_triangles)
    return count
before=tri_count()
if before>18000:
    ratio=17500/before
    for obj in meshes:
        bpy.context.view_layer.objects.active=obj
        mod=obj.modifiers.new('PS3 geometry budget','DECIMATE'); mod.ratio=ratio
        bpy.ops.object.modifier_apply(modifier=mod.name)
print('PS3_TRIANGLES',before,tri_count(),flush=True)
for obj in meshes: obj.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.0015,area_weight=.5,correct_aspect=True)
bpy.ops.object.mode_set(mode='OBJECT')
atlas=bpy.data.images.new('SawbladeTank | 1024 color atlas',width=1024,height=1024,alpha=False)
materials=set(m for obj in meshes for m in obj.data.materials)
for material in materials:
    node=material.node_tree.nodes.new('ShaderNodeTexImage'); node.image=atlas
    material.node_tree.nodes.active=node
scene.cycles.samples=1
scene.render.bake.use_pass_direct=False; scene.render.bake.use_pass_indirect=False; scene.render.bake.use_pass_color=True
scene.render.bake.margin=4
# Bake a joined temporary copy: one bake pass, while original animated parts
# retain their separate objects and the exact same atlas UV coordinates.
bpy.ops.object.duplicate(linked=False)
bpy.ops.object.join()
bake_object=bpy.context.object
bake_object.name='TEMP_ATLAS_BAKE'
bpy.ops.object.bake(type='DIFFUSE')
atlas.filepath_raw=os.path.join(ROOT,'sawblade_tank_color_1024.png'); atlas.file_format='PNG'; atlas.save(); atlas.pack()
bake_mesh=bake_object.data
bpy.data.objects.remove(bake_object,do_unlink=True)
bpy.data.meshes.remove(bake_mesh)
for material in materials:
    nodes=material.node_tree.nodes; bs=nodes.get('Principled BSDF')
    for node in list(nodes):
        if node not in [bs,nodes.get('Material Output')]: nodes.remove(node)
    tex=nodes.new('ShaderNodeTexImage'); tex.image=atlas; tex.interpolation='Linear'
    material.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
scene.cycles.samples=24
bpy.ops.object.select_all(action='DESELECT'); root.select_set(True); bpy.context.view_layer.objects.active=root
scene['texture_budget']='One shared packed 1024 x 1024 sRGB color atlas. Scalar metal/roughness per surface; no procedural runtime textures.'
scene['triangle_count']=tri_count()
