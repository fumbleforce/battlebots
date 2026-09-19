"""Install module selectors and shared palette after all visible parts are baked."""
selectors={
    'weapon':(0,2,'0 Saw / 1 Hammer / 2 Ramp'),
    'drive':(0,1,'0 Tracks / 1 Four wheels'),
    'armor_side':(1,2,'0 None / 1 Reference covers / 2 Heavy skirts and fenders'),
    'armor_top':(0,1,'0 None / 1 Top machinery guard'),
    'armor_front':(0,1,'0 None / 1 Front chin plate'),
    'armor_rear':(0,1,'0 None / 1 Rear pack armor'),
    'exhaust':(0,3,'0 None / 1 Small / 2 Medium dual / 3 Large dual'),
}
for key,(default,maximum,description) in selectors.items():
    root[key]=default
    root.id_properties_ui(key).update(min=0,max=maximum,description=description)
for obj in bot.all_objects:
    if 'module_slot' not in obj: continue
    for prop in ['hide_render','hide_viewport']:
        fc=obj.driver_add(prop); driver=fc.driver; driver.type='SCRIPTED'
        variable=driver.variables.new(); variable.name='selection'; variable.type='SINGLE_PROP'
        variable.targets[0].id=root; variable.targets[0].data_path='["'+obj['module_slot']+'"]'
        driver.expression='selection != '+str(obj['module_choice'])

palette=bpy.data.node_groups.new('BOT_PALETTE | four player colors','ShaderNodeTree')
output=palette.nodes.new('NodeGroupOutput')
palette_info=[
    ('paint_primary','Primary paint',(.66,.32,.018,1)),
    ('paint_secondary','Secondary paint',(.035,.041,.044,1)),
    ('paint_metal','Bare metal',(.58,.60,.62,1)),
    ('paint_rubber','Rubber',(.025,.029,.031,1)),
]
for key,label,color in palette_info:
    root[key]=list(color)
    root.id_properties_ui(key).update(min=0,max=1,subtype='COLOR',description='Shared '+label.lower()+' color; affects every module')
    palette.interface.new_socket(name=label,in_out='OUTPUT',socket_type='NodeSocketColor')
    node=palette.nodes.new('ShaderNodeRGB'); node.name=label; node.label=label
    node.outputs[0].default_value=color
    for component in range(4):
        fc=node.outputs[0].driver_add('default_value',component); driver=fc.driver
        variable=driver.variables.new(); variable.name='tint'; variable.type='SINGLE_PROP'
        variable.targets[0].id=root; variable.targets[0].data_path='["'+key+'"]['+str(component)+']'
        driver.expression='tint'
    palette.links.new(node.outputs[0],output.inputs[label])

material_slots={}
for material in materials:
    if material.name.startswith(('01','08')): channel='Primary paint'
    elif material.name.startswith(('04','05','06','09')): channel='Bare metal'
    elif material.name.startswith('03'): channel='Rubber'
    else: channel='Secondary paint'
    nodes=material.node_tree.nodes; links=material.node_tree.links
    tex=next(node for node in nodes if node.type=='TEX_IMAGE')
    palette_node=nodes.new('ShaderNodeGroup'); palette_node.node_tree=palette
    strength=nodes.new('ShaderNodeMath'); strength.operation='MULTIPLY'; strength.inputs[1].default_value=2
    links.new(tex.outputs['Color'],strength.inputs[0])
    mix=nodes.new('ShaderNodeMixRGB'); mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=1
    links.new(strength.outputs[0],mix.inputs[1]); links.new(palette_node.outputs[channel],mix.inputs[2])
    links.new(mix.outputs[0],nodes.get('Principled BSDF').inputs['Base Color'])
    material['palette_channel']=channel; material_slots[material.name]=channel

# Force newly installed palette drivers into the render dependency graph.
root.update_tag(); palette.update_tag()
for material in materials:
    material.node_tree.update_tag(); material.update_tag()
scene.frame_set(2); scene.frame_set(1); bpy.context.view_layer.update()
default_triangles=0
for obj in bot.all_objects:
    if obj.type=='MESH' and not obj.hide_render:
        obj.data.calc_loop_triangles(); default_triangles+=len(obj.data.loop_triangles)
scene['default_assembly_triangles']=default_triangles
scene['README']='Select SawbladeTank_ROOT > Object Properties > Custom Properties. Change weapon, drive, armor_* and exhaust integers; hover for choices. Four paint_* color swatches tint every module. Space plays the default saw/tracks. Select weapon=1 for hammer_attack: frames 1-33, impact at 9, hold through 12, then return. Reset to frame 1 to replay. Modules share named sockets; this is art authoring, not gameplay code.'
manifest={
    'version':2, 'animations':{'hammer_attack':hammer_metadata},
    'exhaust_geometry':{'axis':[0,-1,0],'lengths_m':{'small':.25,'medium':.40,'large':.60},'radii_m':{'small':.05,'medium':.068,'large':.095}}, 'coordinates':'Blender meters, Z up, +Y forward; glTF converts to Godot Y up / -Z forward',
    'sockets':{name:{'object':'Socket_'+name,'position':list(position)} for name,position in socket_positions.items()},
    'selectors':{name:{'default':value[0],'max':value[1],'choices':value[2]} for name,value in selectors.items()},
    'modules':module_records, 'palette':{key:{'label':label,'default':list(color)} for key,label,color in palette_info},
    'surface_texture':'sawblade_tank_surface_4096.png', 'shader_formula':'base_color = palette[channel] * (2 * surface_texture.r)',
    'material_palette_channels':material_slots,
    'default_assembly_triangles':default_triangles,'all_module_triangles':scene['triangle_count'],
    'integration_status':'Blender art modules and mounting data only; no game assembly, collision or combat implementation',
}
with open(os.path.join(ROOT,'module_manifest.json'),'w') as file: json.dump(manifest,file,indent=2)
readme=bpy.data.texts.new('START HERE - modular vehicle')
readme.write(scene['README']+'\n\n'+ '\n'.join(name+': '+value[2] for name,value in selectors.items()))
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='PROPERTIES': area.spaces.active.context='OBJECT'
print('MODULES_CONFIGURED',len(module_records),'default triangles',default_triangles,flush=True)
