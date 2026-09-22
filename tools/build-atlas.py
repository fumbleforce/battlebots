"""Atlas MX original modular chassis. Blender 5.2 --background --python tools/build-atlas.py.

All helper arguments use Godot meters: X right, Y up, -Z forward. No paid assets,
external texture dependencies or procedural runtime shaders. --quick writes an
isolated draft under exports/atlas-source-preview; default exports production
GLB, source BLEND, manifest and review views.
"""
import bpy, bmesh, math, json, random, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/atlas_mx'
RUNTIME = ROOT / 'battlebots/assets/models/atlas_runtime'
QUICK = '--quick' in sys.argv
if QUICK:
    preview = ROOT / 'battlebots/exports/atlas-source-preview'
    preview.mkdir(parents=True,exist_ok=True)
    (preview/'.gdignore').write_text('')
    SOURCE = preview / 'source'
    RUNTIME = preview / 'runtime'
for path in [SOURCE, RUNTIME]: path.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version=0
random.seed(29022)

def gv(p): return Vector((p[0], -p[2], p[1]))
def linear(v): return v / 12.92 if v <= .04045 else ((v+.055)/1.055)**2.4
def rgba(c): return tuple(linear(v) for v in c) + (1,)

# Solid authoring values are baked into unique UV atlases after geometry is
# finalized. Wear follows physical edges and joints rather than per-face UVs.
def material(name,color,metal=.0,rough=.4,emission=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=rgba(color)
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=rgba(color)
    bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough
    if emission:
        bs.inputs['Emission Color'].default_value=rgba(color);bs.inputs['Emission Strength'].default_value=emission
    return m
PRIMARY=(.86,.51,.055)
paint=material('Atlas_PaintPrimary',PRIMARY,.08,.66)
# Preserve the chamfer role for localized wear; it uses the same enamel.
paint_edge=material('Atlas_PaintPrimaryEdge',PRIMARY,.08,.66)
secondary=material('Atlas_PaintSecondary',(.205,.225,.235),.08,.61)
track_steel=material('Atlas_TrackSteel',(.33,.355,.375),.62,.64)
track_edge=material('Atlas_TrackEdge',(.48,.50,.51),.78,.55)
track_band=material('Atlas_TrackConnectingBand',(.40,.425,.445),.72,.58)
steel=material('Atlas_Metal',(.52,.55,.56),.92,.36)
edge_steel=material('Atlas_EdgeSteel',(.64,.65,.63),.95,.30)
oxidized=material('Atlas_OxidizedMetal',(.34,.315,.27),.80,.57)
rubber=material('Atlas_Rubber',(.045,.055,.06),.0,.84)
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
        if mat==paint or mat==track_steel:
            data.materials.append(paint_edge if mat==paint else track_edge)
            mod.material=len(data.materials)-1
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

def rounded_plate(name,p,size,corner,mat,group=hull,edge=.007):
    # Plan-view corner radius is independent of the thin machined edge chamfer.
    x,y,z=p;w,h,l=size;points=[]
    for sx,sz,start in [(1,1,0),(-1,1,math.pi/2),(-1,-1,math.pi),(1,-1,3*math.pi/2)]:
        cx=x+sx*(w*.5-corner);cz=z+sz*(l*.5-corner)
        for i in range(6):
            angle=start+i*math.pi/10
            points.append((cx+math.cos(angle)*corner,y,cz+math.sin(angle)*corner))
    return plate(name,points,(0,1,0),h,mat,group,edge)

def turned(name,p,axis,profile,mat,group=hull,n=32,hex_socket=False):
    # A lathed section gives hub caps real curved reflections rather than a
    # sequence of flat colored discs. Profile tuples are axial depth and radius.
    p=Vector(p);d=Vector(axis).normalized();t=d.cross(Vector((0,1,0)))
    if t.length<.01:t=d.cross(Vector((1,0,0)))
    t.normalize();bit=d.cross(t)
    verts=[]
    for j,(dep,radius) in enumerate(profile):
        for i in range(n):
            angle=i*math.tau/n
            radial=t*math.cos(angle)+bit*math.sin(angle)
            if hex_socket and j>=len(profile)-2:
                sector=i*6/n;corner=math.floor(sector);fraction=sector-corner
                a=corner*math.tau/6;b=(corner+1)*math.tau/6
                radial=(t*math.cos(a)+bit*math.sin(a))*(1-fraction)+(t*math.cos(b)+bit*math.sin(b))*fraction
            verts.append(tuple(p+d*dep+radial*radius))
    faces=[tuple(reversed(range(n))),tuple(range((len(profile)-1)*n,len(profile)*n))]
    for j in range(len(profile)-1):
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    obj=mesh(name,verts,faces,mat,group)
    for face in obj.data.polygons:face.use_smooth=len(face.vertices)==4
    if hex_socket:
        for face in list(obj.data.polygons)[-n:]:face.use_smooth=False
    return obj

def bolt(at,axis=(0,1,0),group=hull,r=.014):
    p=Vector(at);d=Vector(axis).normalized()
    cylinder('Fastener recessed steel washer',p-d*.003,p+d*.001,r*1.34,oxidized,group,20,.001)
    # A domed button head and an actual inset socket, not a black hexagon decal.
    turned('Rounded machined button fastener',p,d,[(.000,r),(.003,r),(.008,r*.88),(.011,r*.62),(.011,r*.35),(.005,r*.35)],steel,group,24,hex_socket=True)
    # The recessed floor is visibly lower than the crown; six flats identify
    # the drive without adding an artificial black outer outline.
    cylinder('Recessed fastener socket floor',p+d*.0048,p+d*.0051,r*.35,dark,group,6,0)

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
# Leave clearance for the inner track hinge tips throughout the upper strand.
verts=[(side*.700,y,z) for side in [-1,1] for z,y in profile]
n=len(profile)
mesh('Monocoque shadow shell',verts,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],dark,hull,.038)
box('Armored lower keel',(0,-.365,0),(1.40,.20,1.85),secondary,b=.052)
for sx in [-1,1]:
    box('Longitudinal plated sill',(sx*.66,-.24,-.015),(.12,.22,2.01),paint,b=.026)
    for z in [-.77,-.34,.15,.65]:bolt((sx*.721,-.23,z),(sx,0,0),r=.018)

# Folded compact shell: narrow service seams over continuous structural armor.
sys.path.insert(0,str(ROOT/'tools'))
from atlas_front_shell import add_front_shell, add_shoulders
from atlas_armor_shell import add_side_skirts
add_front_shell(plate=plate,box=box,bolt=bolt,tube=tube,ring=ring,
                paint=paint,secondary=secondary,steel=steel,
                edge_steel=edge_steel,dark=dark,lamp=lamp)
from atlas_deck_shell import add_deck_shell
add_deck_shell(box=box,rounded_plate=rounded_plate,plate=plate,cylinder=cylinder,
               tube=tube,bolt=bolt,panel_bolts=panel_bolts,deck_text=deck_text,
               paint=paint,secondary=secondary,steel=steel,edge_steel=edge_steel,
               rubber=rubber,dark=dark,red=red,brass=brass)
# Supported corner sockets keep their published transforms and compact envelope.
CORNER_X=.93;CORNER_Z=.69
for side,group in [(-1,left),(1,right)]:
    add_shoulders(side,group,mesh=mesh,plate=plate,box=box,bolt=bolt,
                  cylinder=cylinder,ring=ring,paint=paint,secondary=secondary,
                  steel=steel,dark=dark)
# Independent drive pods: swingarm frame, two main wheels, three return rollers.
WHEEL_Y=-.08
for side,label,group in [(-1,'L',left),(1,'R',right)]:
    x=side*.94
    # Stationary frame and arms live inboard of rotating tire drums; axles bridge
    # the gap through their centers instead of broad panels cutting tire edges.
    box('Inboard drive backbone',(side*.720,-.08,0),(.050,.36,1.72),secondary,group,b=.012)
    for z in [-.29,.0,.29]:
        plate('Inboard suspension swing arm',[(side*.738,-.13,z-.10),(side*.738,-.35,z-.026),(side*.738,-.35,z+.030),(side*.738,-.12,z+.065)],(1,0,0),.020,secondary,group,.007)
    wheel_specs=[('Front',-.76,-.08,.388),('Rear',.76,-.08,.388)]+[('Roller'+str(i),z,-.330,.120) for i,z in enumerate([-.29,0,.29])]+[('Return',0,.185,.105)]
    for title,z,y,r in wheel_specs:
        # The upper return roller stays inside the frame, behind the thick side
        # casting; its bearing must not protrude through the cover's top edge.
        wx=side*.850 if title=='Return' else x
        half_width=.070 if title=='Return' else .180
        cylinder('Recessed wheel axle',(side*.729,y,z),(wx,y,z),r*.22,secondary,group,16,.002)
        wheel=part('Wheel_'+label+'_'+title,(wx,y,z),group)
        segments=64 if r>.2 else 40
        cylinder('Dark wheel carcass',(wx-half_width,y,z),(wx+half_width,y,z),r,rubber,wheel,segments,.006)
        ox=wx+side*(half_width+.006)
        turned('Rolled steel wheel rim',(ox,y,z),(side,0,0),[(-.005,r*.90),(-.004,r*.949),(.000,r*.965),(.006,r*.953),(.009,r*.889)],steel,wheel,segments)
        cylinder('Recessed painted wheel face' if r>.2 else 'Cast steel roller dish',(ox-side*.003,y,z),(ox+side*.017,y,z),r*.877,paint if r>.2 else oxidized,wheel,segments,.004)
        ring('Narrow hub seal',(ox+side*.019,y,z),(1,0,0),r*.405,r*.381,.003,rubber,wheel,segments)
        turned('Dished wheel bearing shoulder',(ox+side*.019,y,z),(side,0,0),[(0,r*.38),(.008,r*.37),(.018,r*.32),(.020,r*.27)],oxidized,wheel,segments)
        ring('Bearing retaining collar',(ox+side*.044,y,z),(1,0,0),r*.274,r*.220,.013,edge_steel,wheel,segments)
        turned('Rounded machined axle cap',(ox+side*.050,y,z),(side,0,0),[(0,r*.235),(.010,r*.233),(.022,r*.211),(.032,r*.166),(.037,r*.07)],steel,wheel,segments)
        for i in range(8 if r>.2 else 0):
            a=i*math.tau/8
            bolt((ox+side*.0185,y+math.sin(a)*r*.66,z+math.cos(a)*r*.66),(side,0,0),wheel,.016)
    add_side_skirts(side,group,plate=plate,box=box,bolt=bolt,cylinder=cylinder,
                    paint=paint,secondary=secondary,steel=steel,dark=dark)
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

# Single forged slate-grey shoes: no stacked black pad or bright shoulder frame.
# Separate connector strips bridge shoe centers and articulate halfway between
# them, exposing the actual chain connection through every open shoe gap.
proto=part('TreadPrototype')
box('Single slate track shoe',(0,0,0),(.438,.050,.118),track_steel,proto,b=.007)
for sx in [-1,1]:
    for z in [-.041,.041]:
        turned('Domed track rivet',(sx*.175,.025,z),(0,1,0),[(0,.0065),(.002,.0065),(.005,.0055),(.006,.003)],steel,proto,12)
    cylinder('Track hinge pin',(sx*.208,-.020,0),(sx*.226,-.020,0),.012,track_band,proto,12,0)
box('Inner drive engagement tooth',(0,-.039,0),(.068,.027,.050),track_band,proto,b=.005)
band_proto=part('ConnectorPrototype')
for sx in [-1,1]:
    box('Exposed connecting strap',(sx*.156,-.026,0),(.038,.025,LOOP/COUNT+.022),track_band,band_proto,b=.005)

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
band_mesh=finalize(band_proto)
# Eight shared UV variants retain lightweight repeated geometry while baking
# different wear at their representative positions. A single shoe texture made
# each scratch recur visibly on every adjacent link.
shoe_variants=[proto_mesh.data]+[proto_mesh.data.copy() for _ in range(7)]
for i,data in enumerate(shoe_variants):data.name='AtlasTreadVariant%02d'%i
for label,side,group in [('L',-1,left),('R',1,right)]:
    for i in range(COUNT):
        y,z,a=path(i*LOOP/COUNT)
        link=part('Tread_'+label+'_%02d'%i,(side*.94,y,z),group)
        # Godot X rotations are also Blender X rotations after coordinate change.
        link.rotation_euler.x=a
        obj=bpy.data.objects.new('TreadShoe',shoe_variants[(i+(3 if side>0 else 0))%8]);bpy.context.collection.objects.link(obj);obj.parent=link
        by,bz,ba=path((i+.5)*LOOP/COUNT)
        connector=part('TrackConnector_'+label+'_%02d'%i,(side*.94,by,bz),group)
        connector.rotation_euler.x=ba
        obj=bpy.data.objects.new('ConnectingStraps',band_mesh.data);bpy.context.collection.objects.link(obj);obj.parent=connector
del groups[proto];bpy.data.objects.remove(proto_mesh,do_unlink=True);bpy.data.objects.remove(proto,do_unlink=True)
del groups[band_proto];bpy.data.objects.remove(band_mesh,do_unlink=True);bpy.data.objects.remove(band_proto,do_unlink=True)

MOUNTS={'MountPrimary':(0,0,-1.08),'MountTopFront':(0,.49,-.38),'MountTopRear':(0,.49,.40),'MountAuxiliary':(.48,.49,0),'MountRear':(0,.06,1.10),'MountSideLeft':(-1.207,-.02,0),'MountSideRight':(1.207,-.02,0)}
for side,label in [(-1,'Left'),(1,'Right')]:
    for z,end in [(-CORNER_Z,'Front'),(CORNER_Z,'Rear')]:MOUNTS['MountCorner'+label+end]=(side*CORNER_X,.545,z)
for name,pos in MOUNTS.items():
    marker=part(name,pos,hull);marker['purpose']='Addon attachment, Godot meters'

# Optional garage addons are separately grouped and never baked into the base.
# All use the actual rail/sill architecture. The pure base review hides them.
optional=[]
for title,heavy in [('ArmorSideReference',False),('ArmorSideHeavy',True)]:
    group=part(title,parent=hull);optional.append(group)
    for side in [-1,1]:
        x=side*(1.257 if heavy else 1.237)
        poly=[(x,-.24,-.54),(x,-.30,-.37),(x,-.30,.39),(x,-.17,.54),(x,.16,.43),(x,.16,-.43)]
        plate('Bolt-on side armor',poly,(1,0,0),.04 if not heavy else .074,paint,group,.022)
        for y,span in [(-.105,.22),(.10,.39)]:
            for z in [-span,span]:
                cylinder('Armor addon standoff',(side*1.20,y,z),(x,y,z),.027,secondary,group,16,.003)
                bolt((x+side*(.0215 if not heavy else .0385),y,z),(side,0,0),group,.018)
        for z in [-.23,0,.23]:
            box('Armor insert',(x+side*.04,-.04,z),(.014,.20,.088),secondary,group,.009)
        if heavy:
            for z in [-.53,.53]:box('Heavy impact rail',(side*1.302,-.05,z),(.092,.36,.13),secondary,group,.024)
group=part('ArmorTop',parent=hull);optional.append(group)
for x in [-.365,.365]:
    for z in [-.15,.50]:
        cylinder('Utility rack seated foot',(x,.486,z),(x,.531,z),.028,secondary,group,20,.003)
box('Top utility rack gasket',(0,.558,.18),(.82,.068,.80),dark,group,.025)
box('Top armored addon plate',(0,.599,.18),(.86,.05,.82),paint,group,.03)
panel_bolts(0,.6255,.18,.82,.79,group)
for x in [-.27,.27]:box('Top rack grip',(x,.632,.18),(.065,.018,.56),secondary,group,.008)
group=part('ArmorFront',parent=hull);optional.append(group)
for x in [-.52,.52]:
    box('Front impact beam attachment',(x,-.263,-1.175),(.080,.078,.090),secondary,group,.006)
box('Front addon impact beam',(0,-.263,-1.267),(1.38,.18,.15),secondary,group,.037)
for x in [-.5,0,.5]:box('Front beam sacrificial pad',(x,-.26,-1.355),(.32,.15,.035),paint,group,.016)
group=part('ArmorRear',parent=hull);optional.append(group)
box('Rear addon impact beam',(0,-.20,1.248),(1.38,.23,.16),secondary,group,.036)
for x in [-.51,.51]:
    box('Rear protective guard',(x,-.015,1.225),(.13,.53,.10),paint,group,.024)
    bolt((x,.15,1.276),(0,0,1),group,.019)
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
    bolt((x+side*.112,0,0),(side,0,0),lifter,.029)
    for z in [-.927,-.862]:box('Hardened leading wear tooth',(x,-.01,z),(.175,.026,.031),steel,lifter,.004)
box('Lifter front crossmember',(0,-.005,-.88),(1.638,.11,.12),secondary,lifter,.019)
box('Lifter pivot crossmember',(0,0,0),(1.638,.16,.18),secondary,lifter,.022)
for x in [-.45,0,.45]:
    box('Replaceable front skid pad',(x,.056,-.88),(.22,.015,.10),steel,lifter,.008)
    bolt((x,.065,-.88),group=lifter,r=.012)
for side in [-1,1]:
    box('Hydraulic hinge cover',(side*.29,.087,0),(.21,.053,.20),paint,lifter,.018)
    bolt((side*.29,.115,0),group=lifter,r=.022)

for group in list(groups):finalize(group)
bpy.context.view_layer.update()

def descendants(obj):
    result=[obj]
    for ch in obj.children:result+=descendants(ch)
    return result

asset_nodes=descendants(root)
sys.path.insert(0,str(ROOT/'tools'))
from atlas_surface_bake import bake_surface_atlases
surface_atlases=bake_surface_atlases(root,lifter,optional,RUNTIME,quick=QUICK)
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
base_corners=[o.matrix_world@Vector(p) for o in asset_nodes if o.type=='MESH' and o.parent not in optional for p in o.bound_box]
base_points=[(p.x,p.z,-p.y) for p in base_corners]
actual_bounds={'min':[round(min(p[i] for p in base_points),6) for i in range(3)],'max':[round(max(p[i] for p in base_points),6) for i in range(3)]}
manifest={'name':'Atlas MX','id':'atlas_mx','authoring':'Godot meters, X right Y up -Z forward, origin hull center','runtime':'atlas_mx.glb','source':'art_source/atlas_mx/atlas_mx.blend','mounts':MOUNTS,'optional_groups':[o.name for o in optional],'bounds':actual_bounds,'track':{'center_y':CY,'radius':R,'half_straight':HALF,'count_per_side':COUNT,'loop_length':LOOP,'x':.94,'shoe_thickness':.050,'rotation_axis':'X','name_pattern':'Tread_{L|R}_{00..39}','connecting_strips_per_gap':2,'connector_pattern':'TrackConnector_{L|R}_{00..39}','connector_phase_offset':.5*LOOP/COUNT},'wheel_radii':{'main':.388,'lower':.120,'return':.105},'triangles_all_options':sum(x['triangles'] for x in mesh_stats),'triangles_base':sum(len(o.data.loop_triangles) for o in asset_nodes if o.type=='MESH' and o.parent not in optional),'mesh_instances':len(mesh_stats),'material_slots':len(bpy.data.materials),'approval':'Pending user visual approval'}
manifest['surface_atlases']=surface_atlases
(RUNTIME/'atlas_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('ATLAS_EXPORT',json.dumps(manifest))
for group in optional:
    for obj in descendants(group):obj.hide_render=True;obj.hide_set(True)
for obj in descendants(lifter):obj.hide_render=True;obj.hide_set(True)

# Actual source asset studio, not generated concept art. Product reflection cards
# illuminate broad surfaces and small beveled edge catches without a black void.
floor=material('Studio_Only',(.73,.75,.77),.0,.68)
bpy.ops.mesh.primitive_plane_add(size=200,location=gv((0,actual_bounds['min'][1]-.001,0)))
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
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'atlas_mx.blend'),compress=True)
view('atlas_hero',(3.7,2.6,-4.8),ortho=3.85)
if '--quick' not in sys.argv:
    view('atlas_rear',(-3.7,2.4,4.8),ortho=3.85)
    view('atlas_front',(0,1.3,-5.5),ortho=3.5)
    view('atlas_side',(5.5,.5,0),ortho=3.55)
    view('atlas_top',(0,6,.001),ortho=3.4)
    view('atlas_mount_detail',(3.7,1.7,-4.8),target=(.7,.40,-.73),ortho=1.5)
    view('atlas_side_detail',(5.5,.15,0),target=(.94,-.01,0),ortho=1.56)
print('ATLAS_COMPLETE',str(SOURCE))
