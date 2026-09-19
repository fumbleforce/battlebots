"""Packed PBR maps for matte, abraded industrial steel rather than glossy enamel."""
def material(name,color,metal=0,rough=.9,weather=False):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    p.inputs['Specular IOR Level'].default_value=.20
    p.inputs['Coat Weight'].default_value=0
    if not weather:return m
    n=1024;rng=np.random.default_rng(72+sum(map(ord,name)))
    def noise(size):
        seed=rng.random((size,size));samples=np.linspace(0,size-1,n)
        rows=np.array([np.interp(samples,np.arange(size),row) for row in seed])
        return np.array([np.interp(samples,np.arange(size),row) for row in rows.T]).T
    broad=noise(12);medium=noise(48);grain=noise(192);fine=rng.random((n,n))
    paint=('Oxide' in name or 'Ochre' in name)
    # Organic chipped clusters, fine pitting and long scuffs share the PBR mask.
    wear=(.68*medium+.22*grain+.10*fine)>.665
    scratch=np.zeros((n,n),dtype=np.float32)
    for _ in range(400 if paint else 700):
        x,y=rng.integers(0,n,2);length=rng.uniform(7,95);angle=rng.uniform(-.8,.8)
        width=rng.uniform(.45,1.3);dx=np.cos(angle)*length;dy=np.sin(angle)*length
        xx=np.linspace(x,x+dx,int(length)*2).astype(int)%n
        yy=np.linspace(y,y+dy,int(length)*2).astype(int)%n
        scratch[yy,xx]=rng.uniform(.5,1)
        if width>1:scratch[(yy+1)%n,xx]=.5
    wear=wear|(scratch>.68)
    grime=np.clip(.48+.39*broad+.13*grain,.38,1)
    rgb=np.array(color)[None,None,:]*(grime[:,:,None])
    rgb=np.broadcast_to(rgb,(n,n,3)).copy()
    rgb*= (.82+.27*fine[:,:,None])
    exposed=np.array([.13,.14,.135])[None,None,:]*(.6+.55*grain[:,:,None])
    if paint:rgb[wear]=exposed[wear]
    else:rgb=np.clip(rgb+scratch[:,:,None]*.045,0,1)
    rust=(medium>.64)&(medium<.68)&(grain>.52)
    rgb[rust]=rgb[rust]*.45+np.array([.065,.026,.009])*.55
    rgba=np.ones((n,n,4),dtype=np.float32);rgba[:,:,:3]=rgb
    def image_node(suffix,pixels,linear=False):
        im=bpy.data.images.new(name+'_'+suffix,width=n,height=n)
        if linear:im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(pixels.ravel());im.update();im.pack()
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;tex.interpolation='Linear'
        return tex
    tex=image_node('albedo',rgba)
    m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    orm=np.ones_like(rgba)
    orm[:,:,1]=np.clip(rough+(medium-.5)*.12+(fine-.5)*.055,.73,.99)
    orm[:,:,2]=metal
    if paint:
        orm[wear,1]=.77+(fine[wear]-.5)*.1
        orm[wear,2]=.88
    orm[rust,1]=.97;orm[rust,2]=.10
    tex=image_node('roughness_metallic',orm,True)
    sep=m.node_tree.nodes.new('ShaderNodeSeparateColor')
    m.node_tree.links.new(tex.outputs['Color'],sep.inputs['Color'])
    m.node_tree.links.new(sep.outputs['Green'],p.inputs['Roughness'])
    m.node_tree.links.new(sep.outputs['Blue'],p.inputs['Metallic'])
    # Tangent-space peened-metal grain and recessed scratches export with the GLB.
    height=.58*grain+.11*fine-.17*scratch-.10*wear.astype(float)
    gy,gx=np.gradient(height)
    normals=np.stack((-gx*2.0,-gy*2.0,np.ones_like(height)),axis=2)
    normals/=np.linalg.norm(normals,axis=2)[:,:,None]
    nm=np.ones_like(rgba);nm[:,:,:3]=normals*.5+.5
    tex=image_node('normal',nm,True)
    normal=m.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.65
    m.node_tree.links.new(tex.outputs['Color'],normal.inputs['Color'])
    m.node_tree.links.new(normal.outputs['Normal'],p.inputs['Normal'])
    return m
