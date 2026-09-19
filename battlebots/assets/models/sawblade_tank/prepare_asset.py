"""Called by build_sawblade_tank.py; preserve geometry and bake a 4K atlas."""
scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT')
for obj in list(bot.all_objects):
    if obj.type=='CURVE':
        obj.select_set(True); bpy.context.view_layer.objects.active=obj
        bpy.ops.object.convert(target='MESH'); obj.select_set(False)
meshes=[o for o in bot.all_objects if o.type=='MESH']
for obj in meshes:
    bpy.context.view_layer.objects.active=obj
    for mod in list(obj.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
def tri_count():
    count=0
    for obj in meshes:
        obj.data.calc_loop_triangles(); count+=len(obj.data.loop_triangles)
    return count
print('MODEL_TRIANGLES',tri_count(),flush=True)
for obj in meshes: obj.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=.0015,area_weight=.5,correct_aspect=True)
bpy.ops.object.mode_set(mode='OBJECT')
atlas=bpy.data.images.new('SawbladeTank | 4096 surface atlas',width=4096,height=4096,alpha=False)
materials=set(m for obj in meshes for m in obj.data.materials)
for material in materials:
    # Bake neutral surface variation, not fixed paint hues. Shared palette
    # colors are applied afterward, so player recoloring needs no texture edit.
    nodes=material.node_tree.nodes; links=material.node_tree.links
    bs=nodes.get('Principled BSDF'); base=bs.inputs['Base Color']
    if base.is_linked:
        source=base.links[0].from_socket
    else:
        constant=nodes.new('ShaderNodeRGB'); constant.outputs[0].default_value=base.default_value[:]
        source=constant.outputs[0]
    gray=nodes.new('ShaderNodeRGBToBW'); links.new(source,gray.inputs[0])
    normalize=nodes.new('ShaderNodeMath'); normalize.operation='DIVIDE'
    color=material.diffuse_color
    normalize.inputs[1].default_value=max(.001,2*(color[0]*.2126+color[1]*.7152+color[2]*.0722))
    links.new(gray.outputs[0],normalize.inputs[0]); links.new(normalize.outputs[0],base)
    node=material.node_tree.nodes.new('ShaderNodeTexImage'); node.image=atlas
    material.node_tree.nodes.active=node
scene.cycles.samples=1
scene.render.bake.use_pass_direct=False; scene.render.bake.use_pass_indirect=False; scene.render.bake.use_pass_color=True
scene.render.bake.margin=8
# Bake a joined temporary copy: one bake pass, while original animated parts
# retain their separate objects and the exact same atlas UV coordinates.
bpy.ops.object.duplicate(linked=False)
bpy.ops.object.join()
bake_object=bpy.context.object
bake_object.name='TEMP_ATLAS_BAKE'
bpy.ops.object.bake(type='DIFFUSE')
atlas.filepath_raw=os.path.join(ROOT,'sawblade_tank_surface_4096.png'); atlas.file_format='PNG'; atlas.save(); atlas.pack()
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
scene['texture_budget']='4096 x 4096 packed grayscale surface atlas, multiplied by four shared editable palette colors.'
scene['triangle_count']=tri_count()
