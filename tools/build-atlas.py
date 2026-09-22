"""Atlas MX original modular chassis. Blender 5.2 --background --python tools/build-atlas.py.

All helper arguments use Godot meters: X right, Y up, -Z forward. No paid assets,
external texture dependencies or procedural runtime shaders. --quick renders a
preview; default exports production GLB, source BLEND, manifest and review views.
"""
import bpy, bmesh, math, json, random, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/atlas_mx'
RUNTIME = ROOT / 'battlebots/assets/models/atlas_runtime'
for path in [SOURCE, RUNTIME]: path.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
random.seed(29022)

def gv(p): return Vector((p[0], -p[2], p[1]))
def linear(v): return v / 12.92 if v <= .04045 else ((v+.055)/1.055)**2.4
def rgba(c): return tuple(linear(v) for v in c) + (1,)

# Face-mapped original enamel/steel finishes: broad clean paint, irregular sparse
# chips at face borders, directional fine tool marks and physical metal/roughness.
N=1024
Y,X=np.mgrid[0:N,0:N].astype(np.float32)
u,v=X/(N-1),Y/(N-1)
rng=np.random.default_rng(8522)
grain=rng.random((N,N),dtype=np.float32)
edge=np.minimum.reduce([u,1-u,v,1-v])
def smooth_noise(cells):
    samples=rng.random((cells,cells))
    grid=np.linspace(0,1,cells);target=np.linspace(0,1,N)
    rows=np.array([np.interp(target,grid,row) for row in samples])
    return np.array([np.interp(target,grid,rows[:,i]) for i in range(N)]).T.astype(np.float32)
wave=smooth_noise(38)*.72+smooth_noise(107)*.28
chips=(edge<(.0006+wave*.013)) & (wave>.655)
scratch=np.zeros((N,N),bool)
for _ in range(23):
    cx,cy=rng.uniform(.05,.95,2); length=rng.uniform(.002,.025)
    scratch |= (abs(v-cy-(u-cx)*.51)<.0006)&(abs(u-cx)<length)
chips |= scratch
for _ in range(72):
    cx,cy=rng.uniform(.008,.992,2)
    rx,ry=rng.uniform(.001,.008),rng.uniform(.0007,.003)
    island=((u-cx)/rx)**2+((v-cy)/ry)**2
    chips |= (island < (.56+wave*.5))

def img(name,data,noncolor=False):
    im=bpy.data.images.new(name,width=N,height=N,alpha=True)
    im.colorspace_settings.name='Non-Color' if noncolor else 'sRGB'
    a=np.ones((N,N,4),np.float32); a[:,:,:3]=np.clip(data,0,1)
    im.pixels.foreach_set(a.reshape(-1)); im.filepath_raw=str(RUNTIME/(name+'.png'))
    im.file_format='PNG';im.save();im.source='FILE';im.reload()
    return im

def material(name,color,metal=.0,rough=.4,texture=False,emission=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=rgba(color)
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=rgba(color)
    bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    if emission:
        bs.inputs['Emission Color'].default_value=rgba(color);bs.inputs['Emission Strength'].default_value=emission
    if texture:
        base=np.ones((N,N,3),np.float32)*np.array(color,np.float32)
        base*=.97+grain[:,:,None]*.025+wave[:,:,None]*.008
        base[chips]=np.array((.24,.255,.27))*(.8+grain[chips,None]*.4)
        orm=np.ones((N,N,3),np.float32);orm[:,:,1]=rough+(grain-.5)*.03;orm[:,:,2]=metal
        orm[chips,1]=.34;orm[chips,2]=.92
        # Microtexture remains almost flat, avoiding the molten/plastic appearance.
        height=(grain-.5)*.008; height[chips]-=.035
        normal=np.stack([.5+(np.roll(height,1,1)-np.roll(height,-1,1)),.5+(np.roll(height,1,0)-np.roll(height,-1,0)),np.ones_like(grain)],2)
        for data,kind in [(base,'base'),(orm,'orm'),(normal,'normal')]:
            node=m.node_tree.nodes.new('ShaderNodeTexImage');node.image=img(name+'_'+kind,data,kind!='base')
            if kind=='base':m.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
            if kind=='orm':
                sp=m.node_tree.nodes.new('ShaderNodeSeparateColor');m.node_tree.links.new(node.outputs['Color'],sp.inputs['Color'])
                m.node_tree.links.new(sp.outputs['Green'],bs.inputs['Roughness']);m.node_tree.links.new(sp.outputs['Blue'],bs.inputs['Metallic'])
            if kind=='normal':
                nm=m.node_tree.nodes.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.22
                m.node_tree.links.new(node.outputs['Color'],nm.inputs['Color']);m.node_tree.links.new(nm.outputs['Normal'],bs.inputs['Normal'])
    return m

paint=material('Atlas_PaintPrimary',(.93,.58,.035),.16,.43,True)
secondary=material('Atlas_PaintSecondary',(.19,.225,.24),.68,.4,True)
track_steel=material('Atlas_TrackSteel',(.15,.16,.155),.74,.53,True)
steel=material('Atlas_Metal',(.43,.46,.48),.86,.32)
edge_steel=material('Atlas_EdgeSteel',(.64,.65,.63),.88,.3)
rubber=material('Atlas_Rubber',(.045,.055,.06),.06,.73)
dark=material('Atlas_Recess',(.026,.035,.039),.42,.51)
brass=material('Atlas_ConnectorBrass',(.61,.40,.15),.8,.3)
white=material('Atlas_Stencil',(.83,.86,.8),.05,.49)
lamp=material('Atlas_Lamp',(.94,.95,.86),.1,.24,emission=1.4)
red=material('Atlas_RearLens',(.85,.035,.014),.14,.25,emission=.7)
cyan=material('Atlas_StatusLens',(.1,.75,.72),.08,.24,emission=.6)
groups={}
def part(name,at=(0,0,0),parent=None):
    obj=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(obj)
    obj.empty_display_type='ARROWS';obj.empty_display_size=.1
    obj.location=gv(at)
    if parent:obj.parent=parent;obj.matrix_parent_inverse=parent.matrix_world.inverted()
    groups[obj]=[];bpy.context.view_layer.update();return obj

root=part('AtlasMX');hull=part('Hull',parent=root)
left=part('DriveLeft',parent=root);right=part('DriveRight',parent=root)

def mesh(name,verts,faces,mat,group,bevel=0):
    data=bpy.data.meshes.new(name);data.from_pydata([gv(p) for p in verts],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj);data.materials.append(mat)
    uv=data.uv_layers.new(name='UVMap')
    for poly in data.polygons:
        axis=max(range(3),key=lambda i:abs(poly.normal[i])); axes=[i for i in range(3) if i!=axis]
        coords=[data.vertices[i].co for i in poly.vertices]
        mins=[min(p[a] for p in coords) for a in axes];spans=[max(p[a] for p in coords)-mins[i] for i,a in enumerate(axes)]
        flip_u=random.random()>.5;flip_v=random.random()>.5
        for j,loop in enumerate(poly.loop_indices):
            values=[(coords[j][a]-mins[i])/max(.001,spans[i]) for i,a in enumerate(axes)]
            uv.data[loop].uv=(1-values[0] if flip_u else values[0],1-values[1] if flip_v else values[1])
        poly.use_smooth=bool(bevel)
    if bevel:
        mod=obj.modifiers.new('Forged edge radii','BEVEL');mod.width=bevel;mod.segments=3 if bevel>=.018 else 1;mod.limit_method='ANGLE';mod.angle_limit=.58
        mod.harden_normals=True
        mod=obj.modifiers.new('Weighted machining normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=40
    groups[group].append(obj);return obj

def box(name,p,s,mat,group=hull,b=.009):
    p=Vector(p);s=Vector(s)*.5
    return mesh(name,[tuple(p+Vector((x*s.x,y*s.y,z*s.z))) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(1,2,6,5),(0,4,7,3)],mat,group,b)

def cylinder(name,a,b,r,mat,group=hull,n=20,bevel=.003):
    a=Vector(a);b=Vector(b);d=(b-a).normalized();t=d.cross(Vector((0,1,0)))
    if t.length<.01:t=d.cross(Vector((1,0,0)))
    t.normalize();bit=d.cross(t)
    verts=[tuple(p+(t*math.cos(i*math.tau/n)+bit*math.sin(i*math.tau/n))*r) for p in [a,b] for i in range(n)]
    obj=mesh(name,verts,[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat,group,bevel)
    for f in obj.data.polygons:f.use_smooth=len(f.vertices)==4
    return obj

def ring(name,p,axis,outer,inner,width,mat,group=hull,n=24):
    p=Vector(p);d=Vector(axis).normalized();t=d.cross(Vector((0,1,0)))
    if t.length<.01:t=d.cross(Vector((1,0,0)))
    t.normalize();bit=d.cross(t)
    verts=[tuple(p+d*dep+(t*math.cos(i*math.tau/n)+bit*math.sin(i*math.tau/n))*r) for dep,r in [(-width/2,outer),(width/2,outer),(-width/2,inner),(width/2,inner)] for i in range(n)]
    faces=[]
    for i in range(n):
        j=(i+1)%n;faces +=[(i,j,j+n,i+n),(i+2*n,i+3*n,j+3*n,j+2*n),(i,i+2*n,j+2*n,j),(i+n,j+n,j+3*n,i+3*n)]
    obj=mesh(name,verts,faces,mat,group)
    for i,poly in enumerate(obj.data.polygons):poly.use_smooth=i%4<2
    return obj

def plate(name,outline,normal,depth,mat,group=hull,b=.008):
    vec=Vector(normal).normalized()*depth*.5;n=len(outline)
    return mesh(name,[tuple(Vector(p)+vec*s) for s in [-1,1] for p in outline],[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat,group,b)

def bolt(at,axis=(0,1,0),group=hull,r=.014):
    p=Vector(at);d=Vector(axis)
    cylinder('Recessed fastener seat',p-d*.003,p+d*.002,r*1.5,dark,group,10,0)
    cylinder('Captive hex fastener',p+d*.001,p+d*.010,r,edge_steel,group,6,0)
    cylinder('Hex socket',p+d*.0101,p+d*.0106,r*.44,dark,group,6,0)

def tube(name,points,r,mat,group=hull):
    for a,b in zip(points,points[1:]):cylinder(name,a,b,r,mat,group,10,0)

def panel_bolts(cx,y,cz,w,l,group=hull):
    for x in [-1,1]:
        for z in [-1,1]:bolt((cx+x*(w*.5-.035),y,cz+z*(l*.5-.035)),group=group)

def deck_text(body,at,size,group=hull):
    curve=bpy.data.curves.new('Factory stencil','FONT');curve.body=body;curve.align_x='CENTER';curve.align_y='CENTER'
    curve.size=size;curve.resolution_u=2;curve.extrude=0
    obj=bpy.data.objects.new('Factory stencil '+body,curve);bpy.context.collection.objects.link(obj);obj.location=gv(at);obj.rotation_euler.z=math.pi
    curve.materials.append(white);bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
    bpy.ops.object.convert(target='MESH');groups[group].append(bpy.context.object);bpy.ops.object.select_all(action='DESELECT')

# Central uninterrupted armored silhouette, generous chamfers and separate panels.
profile=[(-1.08,-.29),(-1.13,.01),(-.67,.42),(.82,.42),(1.09,.20),(1.06,-.30),(.86,-.43),(-.83,-.43)]
verts=[(side*.72,y,z) for side in [-1,1] for z,y in profile]
n=len(profile)
mesh('Monocoque shadow shell',verts,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],dark,hull,.038)
box('Armored lower keel',(0,-.365,0),(1.40,.20,1.85),secondary,b=.052)
for sx in [-1,1]:
    box('Longitudinal plated sill',(sx*.66,-.24,-.015),(.12,.22,2.01),paint,b=.026)
    for z in [-.77,-.34,.15,.65]:bolt((sx*.729,-.23,z),(sx,0,0),r=.018)

# Sloping yellow front face with a perimeter gasket and embedded headlamps.
front=[(-.655,.028,-1.15),(.655,.028,-1.15),(.655,.428,-.698),(-.655,.428,-.698)]
plate('Front armor gasket',front,(0,.75,-.66),.041,rubber,b=.018)
front=[(-.628,.04,-1.165),(.628,.04,-1.165),(.628,.42,-.728),(-.628,.42,-.728)]
plate('Forged sloping nose armor',front,(0,.75,-.66),.04,paint,b=.025)
front_normal=Vector((0,.755,-.656))
for sx in [-1,1]:
    for y,z in [(.372,-.80),(.10,-1.108)]:bolt(Vector((sx*.562,y,z))+front_normal*.03,front_normal,r=.022)
    # Square sealed headlights read from normal game view.
    base=Vector((sx*.46,.055,-1.176))
    obj=box('Headlight black bezel',base,(.156,.077,.057),dark,b=.019)
    box('Headlight machined rim',base+Vector((0,0,-.032)),(.135,.059,.015),edge_steel,b=.012)
    box('Headlight ivory lens',base+Vector((0,0,-.041)),(.107,.040,.012),lamp,b=.009)
    box('Front bumper cheek',(sx*.515,-.24,-1.107),(.24,.12,.12),paint,b=.026)
box('Front tool receiver',(0,-.10,-1.155),(.47,.14,.11),secondary,b=.018)
box('Front receiver slot',(0,-.10,-1.213),(.31,.06,.012),dark,b=.006)
for sx in [-1,1]:bolt((sx*.198,-.10,-1.22),(0,0,-1),r=.015)

# Three strong chevrons on the sloping face, flush geometry preserves clean UVs.
for cx in [-.25,0,.25]:
    outline=[]
    for x,t in [(-.062,0),(.02,0),(.11,.50),(.02,1),(-.062,1),(.025,.50)]:
        yy=.14+t*.19
        outline.append(tuple(Vector((cx+x,yy,-1.165+(yy-.04)*(.437/.38)))+front_normal*.0217))
    plate('Inset directional chevron',outline,front_normal,.0025,secondary,b=0)

# Deck gasket, four corner armor segments and two interchangeable bolted plates.
box('Deck elastomer seam',(0,.418,.06),(1.42,.053,1.50),rubber,b=.037)
box('Flat modular deck',(0,.446,.06),(1.38,.047,1.46),paint,b=.032)
for z,l in [(-.385,.40),(.14,.44),(.635,.25)]:
    box('Recessed interchangeable top plate',(0,.478,z),(.70,.028,l),dark,b=.018)
    box('Removable top equipment blank',(0,.489,z),(.655,.022,l-.044),secondary,b=.014)
    panel_bolts(0,.502,z,.64,l-.028)
    if z==.14:
        for i in range(7):box('Cooling grille louver',(0,.506,z-.15+i*.046),(.50,.02,.023),edge_steel,b=.005)
    else:
        for x in [-.22,.22]:box('Deck anti-slip inset',(x,.503,z),(.06,.003,l-.13),rubber,b=.003)
deck_text('ATLAS  /  MX',(0,.505,-.385),.059)
deck_text('SERVICE  04',(0,.505,.635),.036)
for z in [-.695,.864]:
    for x in [-.19,.19]:box('Recessed lifting handle foot',(x,.464,z),(.105,.041,.08),dark,b=.012)
    tube('Forged lifting handle',[(-.19,.475,z),(-.145,.522,z),(.145,.522,z),(.19,.475,z)],.021,secondary)

# Two substantial T-slot rails, repeated slotted recesses and docking collars.
for sx in [-1,1]:
    x=sx*.50
    box('Continuous addon rail foundation',(x,.486,.04),(.205,.055,1.33),dark,b=.016)
    for z in [-.47,.025,.52]:
        box('Modular rail armor segment',(x,.516,z),(.196,.032,.46),paint,b=.015)
        box('Rail center channel',(x,.535,z),(.065,.008,.34),dark,b=.006)
        for zz in [-.14,.14]:bolt((x,.538,z+zz),r=.014)
    for z in [-.64,.73]:
        cylinder('Flush docking collar',(x,.478,z),(x,.505,z),.075,steel,n=24,bevel=.004)
        cylinder('Docking receiver socket',(x,.505,z),(x,.51,z),.051,dark,n=20,bevel=0)
        bolt((x,.514,z),r=.022)

# Four track guards echo the reference while leaving the tread mechanism visible.
for side,group in [(-1,left),(1,right)]:
    x=side*.944
    for z in [-.62,0,.62]:
        box('Yellow segmented track fender',(x,.431,z),(.391,.079,.55),paint,group,b=.020)
        box('Fender inset wear strip',(x,.476,z),(.25,.016,.34),secondary,group,b=.012)
        for sx in [-1,1]:
            for zz in [-.209,.209]:bolt((x+sx*.144,.478,z+zz),group=group,r=.012)
        for zz in [-.13,.0,.13]:box('Fender fine channel',(x,.487,z+zz),(.18,.008,.016),dark,group,b=.003)
        if z<-.5:
            box('Front fender recessed latch',(x,.487,z-.172),(.17,.014,.046),dark,group,b=.007)
            box('Front fender steel latch',(x,.495,z-.172),(.102,.012,.022),steel,group,b=.004)
        elif z>.5:
            deck_text('LIFT',(x,.489,z+.095),.045,group)
            for xx in [-.08,.08]:ring('Rear fender tie-down',(x+xx,.507,z-.12),(1,0,0),.029,.018,.015,secondary,group,12)
    for z in [-.96,.96]:
        cylinder('Outer service cap',(x,.395,z),(x,.445,z),.090,secondary,group,24,.005)
        ring('Service cap highlight',(x,.447,z),(0,1,0),.074,.055,.009,steel,group)

# Rear service architecture: recessed radiator, inset panel and twin tail lights.
box('Rear service plate',(0,.025,1.095),(1.31,.55,.049),paint,b=.038)
box('Rear radiator gasket',(0,.193,1.135),(.80,.285,.045),rubber,b=.023)
box('Deep radiator well',(0,.195,1.163),(.71,.214,.018),dark,b=.018)
for y in [.123,.169,.215,.261]:box('Rear radiator louver',(0,y,1.181),(.64,.024,.027),secondary,b=.008)
box('Rear bumper',(0,-.255,1.108),(1.30,.19,.09),secondary,b=.024)
box('Blank serial plate',(0,-.161,1.164),(.38,.16,.018),dark,b=.008)
for x in [-.17,.17]:
    for y in [-.216,-.105]:bolt((x,y,1.176),(0,0,1),r=.009)
for sx in [-1,1]:
    p=Vector((sx*.53,-.075,1.157))
    cylinder('Rear lamp bezel',p,p+Vector((0,0,.031)),.065,dark,n=24)
    ring('Rear lamp steel rim',p+Vector((0,0,.031)),(0,0,1),.054,.039,.009,steel)
    cylinder('Recessed red lamp',p+Vector((0,0,.03)),p+Vector((0,0,.04)),.039,red,n=24)
    for y in [-.24,.27]:bolt((sx*.585,y,1.144),(0,0,1),r=.02)
    # Service quick disconnects tucked inside rails, recognizably functional.
    cylinder('Brass power connector',(sx*.615,.1,1.131),(sx*.615,.1,1.181),.033,brass,n=12)
    tube('Rear protected harness',[(sx*.62,.10,1.15),(sx*.70,.15,.97),(sx*.71,.29,.75)],.016,rubber)

# Independent drive pods: swingarm frame, two main wheels, three return rollers.
WHEEL_Y=-.08
for side,label,group in [(-1,'L',left),(1,'R',right)]:
    x=side*.94
    box('Drive pod inner structure',(x,-.08,0),(.32,.36,1.72),dark,group,b=.075)
    for z in [-.47,.0,.47]:
        plate('Suspension swing arm',[(side*1.057,-.21,z-.22),(side*1.057,-.29,z+.07),(side*1.057,-.18,z+.13),(side*1.057,-.11,z-.18)],(1,0,0),.054,secondary,group,.015)
    wheel_specs=[('Front',-.76,-.08,.388),('Rear',.76,-.08,.388)]+[('Roller'+str(i),z,-.30,.145) for i,z in enumerate([-.39,0,.39])]+[('Return',0,.185,.105)]
    for title,z,y,r in wheel_specs:
        wheel=part('Wheel_'+label+'_'+title,(x,y,z),group)
        cylinder('Dark wheel carcass',(x-.18,y,z),(x+.18,y,z),r,rubber,wheel,32 if r>.2 else 20,.008)
        ox=x+side*.186
        ring('Polished wheel rim',(ox,y,z),(1,0,0),r*.955,r*.885,.012,steel,wheel,48 if r>.2 else 20)
        cylinder('Recessed painted wheel face',(ox-side*.003,y,z),(ox+side*.017,y,z),r*.877,paint if r>.2 else secondary,wheel,48 if r>.2 else 20,.006)
        ring('Recessed hub machining line',(ox+side*.018,y,z),(1,0,0),r*.49,r*.47,.003,secondary,wheel,32 if r>.2 else 20)
        cylinder('Wheel bearing socket',(ox+side*.032,y,z),(ox+side*.055,y,z),r*.34,dark,wheel,24 if r>.2 else 16,.003)
        ring('Axle machined bearing',(ox+side*.062,y,z),(1,0,0),r*.255,r*.17,.026,steel,wheel,20)
        cylinder('Axle cap',(ox+side*.052,y,z),(ox+side*.086,y,z),r*.17,secondary,wheel,16,.003)
        for i in range(8 if r>.2 else 0):
            a=i*math.tau/8
            bolt((ox+side*.034,y+math.sin(a)*r*.66,z+math.cos(a)*r*.66),(side,0,0),wheel,.016)
    # Three real inset diagonal apertures cut through a forged trapezoidal plate.
    sx=side*1.143
    outline=[(sx,-.055,-.455),(sx,-.20,-.30),(sx,-.20,.30),(sx,-.055,.455),(sx,.18,.34),(sx,.18,-.34)]
    plate('Side armor gasket',outline,(1,0,0),.035,rubber,group,.018)
    cover_outline=[(sx+side*.028,-.20,-.30),(sx+side*.028,-.20,.40),(sx+side*.028,.18,.27),(sx+side*.028,.18,-.43)]
    cover=plate('Slotted forged side cover',cover_outline,(1,0,0),.042,paint,group,0)
    for z in [-.18,-.015,.15]:
        slot=[(sx,-.115,z-.009),(sx,-.115,z+.039),(sx,.10,z-.041),(sx,.10,z-.089)]
        cutter=plate('Slot cutting tool',slot,(1,0,0),.30,dark,group,0)
        bpy.context.view_layer.objects.active=cover
        mod=cover.modifiers.new('Actual ventilation aperture','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cutter;mod.solver='EXACT'
        bpy.ops.object.modifier_apply(modifier=mod.name)
        groups[group].remove(cutter);bpy.data.objects.remove(cutter,do_unlink=True)
    bevel=cover.modifiers.new('Forged cover chamfer','BEVEL');bevel.width=.008;bevel.segments=2
    normal=cover.modifiers.new('Cover weighted normals','WEIGHTED_NORMAL');normal.keep_sharp=True
    for z in [-.31,.31]:
        for y in [-.16,.13]:bolt((sx+side*.049,y,z),(side,0,0),group,.016)

# A continuous capsule path, shared in the manifest for exact runtime tread motion.
R=.44;HALF=.76;CY=-.08;COUNT=40;LOOP=4*HALF+math.tau*R
def path(t):
    d=t%LOOP
    if d<2*HALF:return (CY+R,-HALF+d,0)
    d-=2*HALF
    if d<math.pi*R:
        a=d/R;return (CY+R*math.cos(a),HALF+R*math.sin(a),a)
    d-=math.pi*R
    if d<2*HALF:return (CY-R,HALF-d,math.pi)
    d-=2*HALF;a=d/R
    return (CY-R*math.cos(a),-HALF-R*math.sin(a),math.pi+a)

# Author one tread shoe and instance mesh data across 80 links. 3D layers, pins,
# polished shoulders and recessed grip inserts retain strong readable separation.
proto=part('TreadPrototype')
box('Beveled forged track shoe',(0,0,0),(.438,.062,.129),secondary,proto,b=.009)
box('Worn steel contact pad',(0,.034,0),(.333,.018,.099),track_steel,proto,b=.009)
for sx in [-1,1]:
    box('Polished track shoulder',(sx*.199,.033,0),(.027,.018,.110),steel,proto,b=.003)
    for z in [-.041,.041]:
        cylinder('Track rivet',(sx*.166,.043,z),(sx*.166,.052,z),.0085,edge_steel,proto,8,0)
    cylinder('Track hinge pin',(sx*.208,-.005,-.064),(sx*.229,-.005,-.064),.016,steel,proto,10,0)
box('Inner drive engagement tooth',(0,-.045,0),(.081,.035,.062),dark,proto,b=.006)

def finalize(group):
    objects=groups[group]
    if not objects:return None
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        bpy.context.view_layer.objects.active=obj;obj.select_set(True)
        for mod in list(obj.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    for obj in objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();obj=bpy.context.object
    obj.data.transform(group.matrix_world.inverted()@obj.matrix_world)
    obj.parent=group;obj.matrix_parent_inverse=Matrix.Identity(4);obj.matrix_basis=Matrix.Identity(4)
    obj.name=group.name+'Surface';bpy.ops.object.select_all(action='DESELECT');return obj

proto_mesh=finalize(proto)
for label,side,group in [('L',-1,left),('R',1,right)]:
    for i in range(COUNT):
        y,z,a=path(i*LOOP/COUNT)
        link=part('Tread_'+label+'_%02d'%i,(side*.94,y,z),group)
        # Godot X rotations are also Blender X rotations after coordinate change.
        link.rotation_euler.x=a
        obj=bpy.data.objects.new('TreadShoe',proto_mesh.data);bpy.context.collection.objects.link(obj);obj.parent=link
del groups[proto];bpy.data.objects.remove(proto_mesh,do_unlink=True);bpy.data.objects.remove(proto,do_unlink=True)

MOUNTS={'MountPrimary':(0,0,-1.08),'MountTopFront':(0,.49,-.38),'MountTopRear':(0,.49,.40),'MountAuxiliary':(.48,.49,0),'MountRear':(0,.06,1.10),'MountSideLeft':(-.74,.14,.10),'MountSideRight':(.74,.14,.10)}
for name,pos in MOUNTS.items():
    marker=part(name,pos,hull);marker['purpose']='Addon attachment, Godot meters'

# Optional garage addons are separately grouped and never baked into the base.
# All use the actual rail/sill architecture. The pure base review hides them.
optional=[]
for title,heavy in [('ArmorSideReference',False),('ArmorSideHeavy',True)]:
    group=part(title,parent=hull);optional.append(group)
    for side in [-1,1]:
        x=side*1.192
        poly=[(x,-.24,-.54),(x,-.30,-.37),(x,-.30,.39),(x,-.17,.54),(x,.16,.43),(x,.16,-.43)]
        plate('Bolt-on side armor',poly,(1,0,0),.04 if not heavy else .074,paint,group,.022)
        for z in [-.39,.39]:
            for y in [-.2,.10]:bolt((x+side*(.028 if not heavy else .045),y,z),(side,0,0),group,.018)
        for z in [-.23,0,.23]:
            box('Armor insert',(x+side*.04,-.04,z),(.014,.20,.088),secondary,group,.009)
        if heavy:
            for z in [-.53,.53]:box('Heavy impact rail',(side*1.237,-.05,z),(.092,.36,.13),secondary,group,.024)
group=part('ArmorTop',parent=hull);optional.append(group)
box('Top utility rack gasket',(0,.558,.18),(.82,.068,.80),dark,group,.025)
box('Top armored addon plate',(0,.599,.18),(.86,.05,.82),paint,group,.03)
panel_bolts(0,.63,.18,.82,.79,group)
for x in [-.27,.27]:box('Top rack grip',(x,.632,.18),(.065,.018,.56),secondary,group,.008)
group=part('ArmorFront',parent=hull);optional.append(group)
box('Front addon impact beam',(0,-.263,-1.267),(1.38,.18,.15),secondary,group,.037)
for x in [-.5,0,.5]:box('Front beam sacrificial pad',(x,-.26,-1.355),(.32,.15,.035),paint,group,.016)
group=part('ArmorRear',parent=hull);optional.append(group)
box('Rear addon impact beam',(0,-.20,1.248),(1.38,.23,.16),secondary,group,.036)
for x in [-.51,.51]:
    box('Rear protective guard',(x,-.015,1.225),(.13,.53,.10),paint,group,.024)
    bolt((x,.15,1.287),(0,0,1),group,.019)
for title,height,radius in [('ExhaustSmall',.23,.039),('ExhaustMedium',.40,.046),('ExhaustLarge',.58,.057)]:
    group=part(title,parent=hull);optional.append(group)
    for side in [-1,1]:
        at=Vector((side*.49,.44,.72))
        cylinder('Exhaust cassette base',at,at+Vector((0,.065,0)),radius*1.6,secondary,group,20,.005)
        # Hollow open stacks with real black interior and bright retaining bands.
        ring('Hollow exhaust tube',at+Vector((0,height*.5+.04,0)),(0,1,0),radius,radius*.70,height,secondary,group,20)
        for y in [.09,height+.04]:ring('Stack rolled collar',at+Vector((0,y,0)),(0,1,0),radius*1.10,radius*.69,.021,steel,group,20)
        cylinder('Exhaust inner darkness',at+Vector((0,height-.04,0)),at+Vector((0,height-.035,0)),radius*.68,dark,group,20,0)

# Starter attachment in the existing lifter mechanism's LOCAL frame. Contact
# dimensions and pivot remain the canonical weapon; this only replaces its art.
lifter=part('AtlasLifter')
for side in [-1,1]:
    x=side*.702
    profile=[(-.95,-.056),(-.91,.012),(-.28,.064),(.035,.060),(.052,-.054)]
    verts=[(x+sx*.080,y,z) for sx in [-1,1] for z,y in profile];n=len(profile)
    mesh('Forged tapered lifter tine',verts,[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],paint,lifter,.014)
    box('Tine wear strip',(x,.065,-.435),(.072,.012,.64),secondary,lifter,.005)
    for z in [-.16,-.61]:bolt((x,.074,z),group=lifter,r=.012)
    cylinder('Lifter pivot bearing',(x-.097,0,0),(x+.097,0,0),.077,dark,lifter,24,.004)
    ring('Lifter pivot seal',(x+side*.104,0,0),(1,0,0),.061,.043,.014,steel,lifter,24)
    bolt((x+side*.117,0,0),(side,0,0),lifter,.029)
    for z in [-.927,-.862]:box('Hardened leading wear tooth',(x,-.01,z),(.175,.026,.031),steel,lifter,.004)
box('Lifter front crossmember',(0,-.005,-.88),(1.638,.11,.12),secondary,lifter,.019)
box('Lifter pivot crossmember',(0,0,0),(1.638,.16,.18),secondary,lifter,.022)
for x in [-.45,0,.45]:
    box('Replaceable front skid pad',(x,.056,-.88),(.22,.015,.10),steel,lifter,.008)
    bolt((x,.073,-.88),group=lifter,r=.012)
for side in [-1,1]:
    box('Hydraulic hinge cover',(side*.29,.087,0),(.21,.053,.20),paint,lifter,.018)
    bolt((side*.29,.12,0),group=lifter,r=.022)

for group in list(groups):finalize(group)
bpy.context.view_layer.update()

def descendants(obj):
    result=[obj]
    for ch in obj.children:result+=descendants(ch)
    return result

asset_nodes=descendants(root)
def export_model(obj,filename):
    bpy.ops.object.select_all(action='DESELECT')
    for item in descendants(obj):item.select_set(True)
    bpy.context.view_layer.objects.active=obj
    path=RUNTIME/filename
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_animations=False,export_materials='EXPORT',export_texcoords=True,export_normals=True)
    # Reference the one canonical map set from both assets. This is legal glTF
    # and avoids Godot extracting duplicate texture files for every attachment.
    raw=path.read_bytes();json_len=struct.unpack_from('<I',raw,12)[0]
    document=json.loads(raw[20:20+json_len]);binary=raw[20+json_len+8:]
    image_views={im['bufferView'] for im in document.get('images',[]) if 'bufferView' in im}
    for im in document.get('images',[]):
        im.pop('bufferView',None);im.pop('mimeType',None);im['uri']=im['name']+'.png'
        if not (RUNTIME/im['uri']).exists():raise RuntimeError('Missing portable material '+im['uri'])
    remap={};views=[];packed=bytearray()
    for i,view in enumerate(document['bufferViews']):
        if i in image_views:continue
        while len(packed)%4:packed.append(0)
        start=view.get('byteOffset',0);chunk=binary[start:start+view['byteLength']]
        new_view=dict(view);new_view['byteOffset']=len(packed);remap[i]=len(views);views.append(new_view);packed.extend(chunk)
    for accessor in document.get('accessors',[]):
        if 'bufferView' in accessor:accessor['bufferView']=remap[accessor['bufferView']]
    document['bufferViews']=views;document['buffers'][0]['byteLength']=len(packed)
    while len(packed)%4:packed.append(0)
    jb=json.dumps(document,separators=(',',':')).encode('utf8')
    while len(jb)%4:jb+=b' '
    path.write_bytes(struct.pack('<4sII',b'glTF',2,12+8+len(jb)+8+len(packed))+struct.pack('<I4s',len(jb),b'JSON')+jb+struct.pack('<I4s',len(packed),b'BIN\0')+packed)
export_model(root,'atlas_mx.glb')
export_model(lifter,'atlas_lifter.glb')
tris=sum(len(o.data.loop_triangles) for o in [] )
mesh_stats=[]
for obj in asset_nodes:
    if obj.type=='MESH':
        obj.data.calc_loop_triangles();mesh_stats.append({'name':obj.name,'triangles':len(obj.data.loop_triangles)})
manifest={'name':'Atlas MX','id':'atlas_mx','authoring':'Godot meters, X right Y up -Z forward, origin hull center','runtime':'atlas_mx.glb','source':'art_source/atlas_mx/atlas_mx.blend','mounts':MOUNTS,'optional_groups':[o.name for o in optional],'bounds':{'min':[-1.18,-.56,-1.25],'max':[1.18,.55,1.25]},'track':{'center_y':CY,'radius':R,'half_straight':HALF,'count_per_side':COUNT,'loop_length':LOOP,'x':.94,'shoe_thickness':.062,'rotation_axis':'X','name_pattern':'Tread_{L|R}_{00..39}'},'triangles_all_options':sum(x['triangles'] for x in mesh_stats),'triangles_base':sum(len(o.data.loop_triangles) for o in asset_nodes if o.type=='MESH' and o.parent not in optional),'mesh_instances':len(mesh_stats),'material_slots':len(bpy.data.materials),'approval':'Pending user visual approval'}
(RUNTIME/'atlas_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('ATLAS_EXPORT',json.dumps(manifest))
for group in optional:
    for obj in descendants(group):obj.hide_render=True;obj.hide_set(True)
for obj in descendants(lifter):obj.hide_render=True;obj.hide_set(True)

# Actual source asset studio, not generated concept art. Product reflection cards
# illuminate broad surfaces and small beveled edge catches without a black void.
floor=material('Studio_Only',(.73,.75,.77),.0,.68)
bpy.ops.mesh.primitive_plane_add(size=200,location=gv((0,-.568,0)))
bpy.context.object.name='StudioFloor';bpy.context.object.data.materials.append(floor)
def light(name,at,energy,color,size,target=(0,0,0)):
    d=bpy.data.lights.new(name,'AREA');d.energy=energy;d.shape='DISK';d.size=size;d.color=color
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=gv(at);o.rotation_euler=(gv(target)-o.location).to_track_quat('-Z','Y').to_euler()
light('Large warm key',(-3.5,5,-4),350,(1,.97,.90),4)
light('Cool side reflection',(4,2,.5),230,(.84,.92,1),3)
light('Rear rim',(-1,3,3),380,(1,.95,.86),2.5)
light('Front fill',(0,1,-4),60,(.94,.96,1),3)
scene=bpy.context.scene;scene.world=scene.world or bpy.data.worlds.new('Atlas studio');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.69,.75,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.25
cam_data=bpy.data.cameras.new('AssetReviewCamera');cam=bpy.data.objects.new('AssetReviewCamera',cam_data);bpy.context.collection.objects.link(cam);scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=32 if '--quick' in sys.argv else 96;scene.cycles.use_denoising=True
try:
    prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
    for device in prefs.devices:device.use=device.type=='OPTIX'
    scene.cycles.device='GPU'
except Exception:pass
scene.render.resolution_x=1600;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=.0
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
def view(name,at,target=(0,-.015,0),ortho=3.8):
    cam.location=gv(at);cam.rotation_euler=(gv(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.type='ORTHO';cam_data.ortho_scale=ortho
    scene.render.filepath=str(SOURCE/(name+'.png'));bpy.ops.render.render(write_still=True)
for image in bpy.data.images:
    if image.source=='FILE':image.pack()
cam.location=gv((3.7,2.6,-4.8));cam.rotation_euler=(gv((0,-.015,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.type='ORTHO';cam_data.ortho_scale=3.85
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'atlas_mx.blend'))
view('atlas_hero',(3.7,2.6,-4.8),ortho=3.85)
if '--quick' not in sys.argv:
    view('atlas_rear',(-3.7,2.4,4.8),ortho=3.85)
    view('atlas_front',(0,1.3,-5.5),ortho=3.5)
    view('atlas_side',(5.5,.5,0),ortho=3.55)
    view('atlas_top',(0,6,.001),ortho=3.4)
print('ATLAS_COMPLETE',str(SOURCE))
