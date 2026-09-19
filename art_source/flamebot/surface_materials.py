"""Crisp layered wear with CC0 scanned metal relief; see reference_textures/CREDITS.md."""

def scanned_map(filename,n):
    im=bpy.data.images.load(str(HERE/'reference_textures'/filename),check_existing=False)
    im.colorspace_settings.name='Non-Color'
    if tuple(im.size)!=(n,n):im.scale(n,n)
    data=np.empty(n*n*4,dtype=np.float32);im.pixels.foreach_get(data)
    bpy.data.images.remove(im)
    return data.reshape(n,n,4)[:,:,:3].copy()
def material(name,color,metal=0,rough=.9,weather=False,plate_edges=False):
    m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    p.inputs['Specular IOR Level'].default_value=.20;p.inputs['Coat Weight'].default_value=0
    if not weather:return m
    n=4096 if plate_edges else 2048
    rng=np.random.default_rng(803+sum(map(ord,name)))
    print('Authoring crisp PBR:',name,n,flush=True)
    def noise(size):
        seed=rng.random((size,size));samples=np.linspace(0,size-1,n)
        rows=np.array([np.interp(samples,np.arange(size),row) for row in seed],dtype=np.float32)
        return np.array([np.interp(samples,np.arange(size),row) for row in rows.T],dtype=np.float32).T
    fine=rng.random((n,n),dtype=np.float32);grain=noise(384);broad=noise(16)
    scan=scanned_map('green_metal_rust_diff_4k.jpg',n)
    scan_luma=scan[:,:,0]*.2126+scan[:,:,1]*.7152+scan[:,:,2]*.0722
    patina=np.clip((scan_luma/np.median(scan_luma))**2,.30,1.65)
    scan_normal=scanned_map('green_metal_rust_nor_gl_4k.jpg',n)*2-1
    scan_rough=scanned_map('green_metal_rust_rough_4k.jpg',n)[:,:,0]
    worn=scanned_map('rusty_painted_metal_diff_4k.jpg',n)
    worn_luma=worn.mean(axis=2)
    # Remove the broad corrugated-sheet bands; retain photographed scuff detail.
    worn_detail=np.clip(worn_luma/np.maximum(np.median(worn_luma,axis=0)[None,:],.035),.22,1.8)
    paint=('Oxide' in name or 'Ochre' in name)
    chip=np.zeros((n,n),dtype=bool);scratches=np.zeros((n,n),dtype=np.float32)
    s=n/2048
    def polygon(cx,cy,rx,ry):
        count=int(rng.integers(20,36));angles=np.linspace(0,math.tau,count,endpoint=False)
        radii=rng.uniform(.4,1.15,count)
        vx=cx+np.cos(angles)*radii*rx;vy=cy+np.sin(angles)*radii*ry
        x0=max(0,int(vx.min())-1);x1=min(n,int(vx.max())+2)
        y0=max(0,int(vy.min())-1);y1=min(n,int(vy.max())+2)
        if x1<=x0 or y1<=y0:return
        yy,xx=np.mgrid[y0:y1,x0:x1];inside=np.zeros(xx.shape,dtype=bool)
        for i in range(count):
            j=(i+1)%count
            inside^=((vy[i]>yy)!=(vy[j]>yy))&(xx<(vx[j]-vx[i])*(yy-vy[i])/(vy[j]-vy[i]+1e-9)+vx[i])
        chip[y0:y1,x0:x1]|=inside
    # Discrete jagged fragments instead of thresholded, blurry noise/camouflage.
    for _ in range(150 if paint else 80):
        x,y=rng.uniform(0,n,2);r=rng.uniform(3,30)*s
        polygon(x,y,r,r*rng.uniform(.25,1.8))
    for _ in range(24 if paint else 8):
        x,y=rng.uniform(0,n,2);r=rng.uniform(28,65)*s
        polygon(x,y,r,r*rng.uniform(.35,.85))
    if plate_edges:
        for _ in range(400):
            t=rng.uniform(0,n);d=rng.uniform(-4,20)*s;edge=int(rng.integers(4))
            x,y=[(t,d),(t,n-d),(d,t),(n-d,t)][edge]
            polygon(x,y,rng.uniform(8,45)*s,rng.uniform(6,28)*s)
        for _ in range(65):
            edge=int(rng.integers(4));t=rng.uniform(0,n);d=rng.uniform(8,34)*s
            x,y=[(t,d),(t,n-d),(d,t),(n-d,t)][edge]
            polygon(x,y,rng.uniform(25,90)*s,rng.uniform(14,55)*s)
    for _ in range(650 if paint else 1100):
        x,y=rng.uniform(0,n,2);length=rng.uniform(9,160)*s
        angle=rng.normal(-.55,.22) if rng.random()<.73 else rng.uniform(0,math.tau)
        steps=max(4,int(length*2));t=np.linspace(0,1,steps)
        xx=np.rint(x+np.cos(angle)*length*t).astype(int)
        yy=np.rint(y+np.sin(angle)*length*t+rng.uniform(-2,2)*s*np.sin(t*math.pi)).astype(int)
        ok=(xx>=1)&(xx<n-1)&(yy>=1)&(yy<n-1);xx=xx[ok];yy=yy[ok]
        value=rng.uniform(.35,1);scratches[yy,xx]=value
        if rng.random()<.25:scratches[yy+1,xx]=value*.6
    # Fine islands of surviving paint break up the large abrasions.
    chip &= (grain*.7+fine*.3)>.25
    erosion=chip.copy()
    for _ in range(max(1,int(s))):
        erosion=erosion&np.roll(erosion,1,0)&np.roll(erosion,-1,0)&np.roll(erosion,1,1)&np.roll(erosion,-1,1)
    primer=chip&~erosion;exposed=erosion|(scratches>.72)
    rgb=np.array(color,dtype=np.float32)[None,None,:]*(.74+.22*broad[:,:,None])
    rgb*=patina[:,:,None]*(.70+.30*worn_detail[:,:,None])
    rgb*=.94+.12*fine[:,:,None]
    steel_color=np.array([.22,.225,.21],dtype=np.float32)[None,None,:]*(.48+.52*worn_detail[:,:,None])
    steel_color*=.75+.4*grain[:,:,None]
    if paint:
        rgb[exposed]=steel_color[exposed];rgb[primer]=np.array([.058,.035,.021])
    else:
        rgb+=scratches[:,:,None]*.075;rgb[chip]*=.55
        oxidation=np.clip((.82-worn_detail)*.55,0,.32)[:,:,None]
        rgb=rgb*(1-oxidation)+np.array([.13,.058,.021])*oxidation
    pits=(fine>.997)&(grain>.44);rgb[pits]*=.34
    lip=np.maximum(np.roll(scratches,1,0)-scratches,0)
    rgb+=lip[:,:,None]*(.018 if paint else .04)
    rgba=np.ones((n,n,4),dtype=np.float32);rgba[:,:,:3]=np.clip(rgb,0,1)
    def image_node(suffix,pixels,linear=False):
        if linear and pixels.shape[0]>2048:
            pixels=(pixels[::2,::2]+pixels[1::2,::2]+pixels[::2,1::2]+pixels[1::2,1::2])*.25
        size=pixels.shape[0];im=bpy.data.images.new(name+'_'+suffix,width=size,height=size)
        if linear:im.colorspace_settings.name='Non-Color'
        im.pixels.foreach_set(pixels.ravel());im.update()
        if suffix=='albedo':
            cache=HERE/'_texture_cache';cache.mkdir(exist_ok=True)
            im.file_format='JPEG';im.filepath_raw=str(cache/(name.replace('•','-').replace('|','-')+'.jpg'))
            im.save(quality=98)
        im.pack()
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;tex.interpolation='Linear'
        return tex
    tex=image_node('albedo',rgba);m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    orm=np.ones_like(rgba)
    orm[:,:,1]=np.clip(rough+(scan_rough-.6)*.22+(grain-.5)*.045,.73,.99);orm[:,:,2]=metal
    if paint:
        orm[exposed,1]=.73+(fine[exposed]-.5)*.1;orm[exposed,2]=.94
        orm[primer,1]=.98;orm[primer,2]=.05
    tex=image_node('roughness_metallic',orm,True);sep=m.node_tree.nodes.new('ShaderNodeSeparateColor')
    m.node_tree.links.new(tex.outputs['Color'],sep.inputs['Color'])
    m.node_tree.links.new(sep.outputs['Green'],p.inputs['Roughness'])
    m.node_tree.links.new(sep.outputs['Blue'],p.inputs['Metallic'])
    height=.055*grain+.035*fine-.10*scratches-.075*chip.astype(np.float32)-.10*pits
    gy,gx=np.gradient(height);normals=np.stack((-gx*3,-gy*3,np.ones_like(height)),axis=2)
    normals[:,:,:2]+=scan_normal[:,:,:2]*(1.3 if paint else .85)
    normals/=np.linalg.norm(normals,axis=2)[:,:,None]
    nm=np.ones_like(rgba);nm[:,:,:3]=normals*.5+.5
    tex=image_node('normal',nm,True);normal=m.node_tree.nodes.new('ShaderNodeNormalMap')
    normal.inputs['Strength'].default_value=.8
    m.node_tree.links.new(tex.outputs['Color'],normal.inputs['Color'])
    m.node_tree.links.new(normal.outputs['Normal'],p.inputs['Normal'])
    return m

def refine_armor_uvs(objects):
    plate=material('Oxide red | worn armor edges',(.255,.040,.025),.025,.91,True,plate_edges=True)
    prefixes=('Angled upper glacis','Thick lower ram plate','Recessed side armor',
              'Shouldered hull armor','Tapered armored tower','Angled tower cheek',
              'Sloping tower roof','Recessed turret deck','Rear service surround')
    refined=[]
    for o in objects:
        if o.type!='MESH' or not o.name.startswith(prefixes):continue
        if not any(m and m.name.startswith('Oxide red') for m in o.data.materials):continue
        for i,m in enumerate(o.data.materials):
            if m and m.name.startswith('Oxide red'):o.data.materials[i]=plate
        uv=o.data.uv_layers.active
        if uv is None:uv=o.data.uv_layers.new(name='UVMap')
        vs=np.array([tuple(v.co) for v in o.data.vertices]);lo=vs.min(axis=0);hi=vs.max(axis=0)
        for p in o.data.polygons:
            drop=int(np.argmax(np.abs(p.normal)));axes=[i for i in range(3) if i!=drop]
            for loop in p.loop_indices:
                v=o.data.vertices[o.data.loops[loop].vertex_index].co
                uv.data[loop].uv=tuple((v[a]-lo[a])/max(hi[a]-lo[a],1e-6) for a in axes)
        refined.append(o.name)
    return refined

def finish_secondary_surfaces():
    """Age the lettering and add restrained relief to rubber and bronze."""
    n=1024
    scan=scanned_map('green_metal_rust_diff_4k.jpg',n)
    detail=scan.mean(axis=2);detail=np.clip(detail/np.median(detail),.3,1.4)
    worn=scanned_map('rusty_painted_metal_diff_4k.jpg',n)
    ratio=worn[:,:,0]/np.maximum(worn[:,:,1],.02)
    normal_image=next(node.image for node in bpy.data.materials['Blackened steel'].node_tree.nodes
                      if node.type=='TEX_IMAGE' and node.image.name.endswith('_normal'))
    for name,strength in [('Warm stencil paint',.4),('Charcoal tire rubber',.12),('Heat stained bronze',.4)]:
        mat=bpy.data.materials[name];nodes=mat.node_tree.nodes;p=nodes.get('Principled BSDF')
        for node in list(nodes):
            if node.name.startswith('Surface detail'):nodes.remove(node)
        tex=nodes.new('ShaderNodeTexImage');tex.name='Surface detail normal';tex.image=normal_image
        norm=nodes.new('ShaderNodeNormalMap');norm.name='Surface detail relief';norm.inputs['Strength'].default_value=strength
        mat.node_tree.links.new(tex.outputs['Color'],norm.inputs['Color']);mat.node_tree.links.new(norm.outputs['Normal'],p.inputs['Normal'])
        if name!='Warm stencil paint':continue
        rgba=np.ones((n,n,4),dtype=np.float32)
        rgba[:,:,:3]=np.array([.56,.51,.39])[None,None,:]*detail[:,:,None]
        # Broken, dirty stencil pigment without changing the approved lettering mesh.
        damaged=ratio<np.percentile(ratio,18)
        rgba[damaged,:3]=np.array([.13,.105,.071])*detail[damaged,None]
        old=bpy.data.images.get('Warm stencil paint_albedo')
        if old and old.users==0:bpy.data.images.remove(old)
        im=bpy.data.images.new('Warm stencil paint_albedo',width=n,height=n)
        im.pixels.foreach_set(rgba.ravel());im.update();im.pack()
        tex=nodes.new('ShaderNodeTexImage');tex.name='Surface detail faded stencil';tex.image=im
        mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
        p.inputs['Roughness'].default_value=.94;p.inputs['Metallic'].default_value=0

def configure_texture_render(scene):
    scene.cycles.samples=160;scene.cycles.use_denoising=True
    scene.render.resolution_x=2400;scene.render.resolution_y=2080;scene.render.filter_size=.8
    try:
        prefs=bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type='OPTIX';prefs.get_devices();available=False
        for d in prefs.devices:d.use=d.type=='OPTIX';available=available or d.use
        if available:scene.cycles.device='GPU'
    except Exception:pass
