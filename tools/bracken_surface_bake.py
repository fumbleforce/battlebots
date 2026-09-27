"""Bracken's painted, low-gloss finish. Portable UV atlases, no runtime noise.
Large chipped enamel islands, warm undercoat, broad brushed value steps and
restrained physical-edge wear. Shares only the Atlas UV/bake/export machinery.
"""
import bpy
from atlas_surface_bake import _set, _math, _mix, _noise, _linear


def painterly(material, family, ao_image, primary_color, edge_image=None, face_wear=.7):
    old=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    color=tuple(old.inputs['Base Color'].default_value)
    metallic=float(old.inputs['Metallic'].default_value)
    roughness=float(old.inputs['Roughness'].default_value)
    nodes,links=material.node_tree.nodes,material.node_tree.links
    nodes.clear()
    output=nodes.new('ShaderNodeOutputMaterial'); bsdf=nodes.new('ShaderNodeBsdfPrincipled')
    geo=nodes.new('ShaderNodeNewGeometry'); pos=geo.outputs['Position']
    broad=_noise(nodes,links,pos,5.4,1.0)
    stepped=_math(nodes,links,'DIVIDE',_math(nodes,links,'FLOOR',_math(nodes,links,'MULTIPLY',broad,5)),5)
    base=_mix(nodes,links,stepped,tuple(c*.76 for c in color[:3])+(1,),tuple(c*1.15 for c in color[:3])+(1,))
    mapping=nodes.new('ShaderNodeVectorMath'); mapping.operation='MULTIPLY'; links.new(pos,mapping.inputs[0]); mapping.inputs[1].default_value=(.7,2,18)
    brush=_noise(nodes,links,mapping.outputs['Vector'],12,1)
    brush_fac=_math(nodes,links,'MULTIPLY',brush,.07)
    base=_mix(nodes,links,brush_fac,base,_linear((.63,.57,.39)))
    ao=nodes.new('ShaderNodeAmbientOcclusion'); ao.inputs['Distance'].default_value=.055; ao.samples=16; ao.only_local=True
    baked_ao=nodes.new('ShaderNodeTexImage'); baked_ao.image=ao_image
    coverage=1.0; rough=roughness; metal=metallic
    if family in ('Primary','Secondary'):
        patch=_noise(nodes,links,pos,18,2)
        threshold=_math(nodes,links,'GREATER_THAN',patch,.595 if family=='Secondary' else .635)
        if edge_image:
            edge=nodes.new('ShaderNodeTexImage'); edge.image=edge_image
            edge_patch=_math(nodes,links,'MULTIPLY',edge.outputs['Color'],_math(nodes,links,'GREATER_THAN',_noise(nodes,links,pos,36,1),.54))
            threshold=_math(nodes,links,'MAXIMUM',threshold,edge_patch)
        undercoat=_mix(nodes,links,_noise(nodes,links,pos,31,1),_linear((.24,.26,.22)),_linear((.40,.39,.28)))
        base=_mix(nodes,links,threshold,base,undercoat)
        coverage=_math(nodes,links,'SUBTRACT',1,threshold)
        metal=.06
        rough=_math(nodes,links,'ADD',.73,_math(nodes,links,'MULTIPLY',broad,.12))
    elif 'recess' not in material.name.lower() and 'rubber' not in material.name.lower():
        stain=_math(nodes,links,'MULTIPLY',_math(nodes,links,'GREATER_THAN',_noise(nodes,links,pos,24,1),.60),.48)
        base=_mix(nodes,links,stain,base,_linear((.28,.25,.19)))
    # Keep local occlusion subtle; large faces remain readable in soft daylight.
    shade=_math(nodes,links,'MULTIPLY',_math(nodes,links,'SUBTRACT',1,baked_ao.outputs['Color']),.27)
    base=_mix(nodes,links,shade,base,_linear((.08,.085,.07)))
    _set(links,bsdf.inputs['Base Color'],base); _set(links,bsdf.inputs['Metallic'],metal); _set(links,bsdf.inputs['Roughness'],rough)
    combine=nodes.new('ShaderNodeCombineColor'); combine.mode='RGB'
    for socket,val in zip(combine.inputs,(coverage,rough,metal)): _set(links,socket,val)
    emit=nodes.new('ShaderNodeEmission'); target=nodes.new('ShaderNodeTexImage'); nodes.active=target
    links.new(bsdf.outputs[0],output.inputs['Surface'])
    return dict(output=output,bsdf=bsdf,emit=emit,target=target,base=base,params=combine.outputs[0],ao=ao.outputs['AO'],family=family,original_color=color,metallic=metallic,roughness=roughness)
