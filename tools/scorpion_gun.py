"""Reference-driven modular HX-6 gun geometry for build-scorpion.py.

Call build(globals()) after the shared authoring helpers/groups exist. All
coordinates are authored Godot meters. GunMount, GunRotor and the fixed muzzle
are preserved; the main exporter applies the common two-degree rest depression.
"""
import math
import bpy
from mathutils import Vector


def build(ns):
    mesh, box, cylinder = (ns[k] for k in ('mesh', 'box', 'cylinder'))
    ring, bolt, tube = (ns[k] for k in ('ring', 'bolt', 'tube'))
    gun, rotor = ns['gun'], ns['rotor']
    orange, rubber, brass = ns['orange'], ns['rubber'], ns['brass']
    groups = ns['groups']
    simple = ns['simple']
    # The reference has a dark machined tool, not polished silver barrels.
    # The shared texture helper accepts artist-facing sRGB colors, like simple().
    metal = ns['textured']('Scorpion_GunParkerizedSteel', (.155, .164, .170), .86, .41, False)
    barrel_finish = ns['textured']('Scorpion_GunNitridedBarrels', (.073,.083,.091), .80, .42, False)
    jacket = simple('Scorpion_GunWarmBlackOxide', (.105, .106, .102), .84, .43)
    edges = simple('Scorpion_GunMachinedEdges', (.32, .32, .30), .96, .28)
    bore = simple('Scorpion_GunDeepBoreSteel', (.025, .030, .032), .68, .56)
    hardware = simple('Scorpion_GunFastenerSteel', (.245, .255, .257), .94, .31)
    optics = simple('Scorpion_GunCoatedLens', (.14, .22, .22), .66, .12)
    enamel = simple('Scorpion_GunIdentification', (.64, .63, .53), .23, .58)

    def finish_bevel(obj, width=.004, segments=3):
        mod = obj.modifiers.new('Machined tool edge', 'BEVEL')
        mod.width, mod.segments = width, segments
        mod.limit_method = 'ANGLE'
        mod.angle_limit = .48
        mod = obj.modifiers.new('Machined weighted normals', 'WEIGHTED_NORMAL')
        mod.keep_sharp = True
        return obj

    def octabox(name, x, y, z0, z1, width, height, chamfer, mat, group=gun):
        w, h, c = width*.5, height*.5, chamfer
        contour = [(-w+c,-h),(w-c,-h),(w,-h+c),(w,h-c),
                   (w-c,h),(-w+c,h),(-w,h-c),(-w,-h+c)]
        verts = [(x+dx,y+dy,z) for z in (z0,z1) for dx,dy in contour]
        faces = [tuple(reversed(range(8))),tuple(range(8,16))]
        faces += [(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)]
        return mesh(name, verts, faces, mat, group, .004)

    def lathe(name, x, y, profile, mat, group, segments=40, inner=None):
        """Axial turned part; optional real hollow interior with a deep back end."""
        verts = [(x+math.cos(i*math.tau/segments)*radius,
                  y+math.sin(i*math.tau/segments)*radius,z)
                 for z,radius in profile for i in range(segments)]
        faces=[]
        for row in range(len(profile)-1):
            for i in range(segments):
                j=(i+1)%segments
                faces.append((row*segments+i,row*segments+j,(row+1)*segments+j,(row+1)*segments+i))
        exterior_faces=len(faces)
        if inner:
            outer_count=len(verts)
            # Shallow helical lands are geometric, so the visible bore has depth.
            for row,(z,radius) in enumerate(inner):
                for i in range(segments):
                    angle=i*math.tau/segments
                    rad=radius + (.00045*math.cos(angle*6+(z+1.72)*32) if row>0 else 0)
                    verts.append((x+math.cos(angle)*rad,y+math.sin(angle)*rad,z))
            # Front chamfer: one continuous lip joins outer and inner surfaces.
            last=(len(profile)-1)*segments
            for i in range(segments):
                j=(i+1)%segments
                faces.append((last+i,last+j,outer_count+j,outer_count+i))
            lip_end=len(faces)
            for row in range(len(inner)-1):
                for i in range(segments):
                    j=(i+1)%segments
                    a=outer_count+row*segments
                    b=a+segments
                    faces.append((a+i,b+i,b+j,a+j))
            cap=outer_count+(len(inner)-1)*segments
            faces.append(tuple(range(cap,cap+segments)))
        else:
            faces += [tuple(reversed(range(segments))),
                      tuple(range((len(profile)-1)*segments,len(profile)*segments))]
            lip_end=exterior_faces
        obj=mesh(name,verts,faces,mat,group,0)
        if inner:
            obj.data.materials.append(edges)
            obj.data.materials.append(bore)
        for i,p in enumerate(obj.data.polygons):
            p.use_smooth=len(p.vertices)==4
            if inner and i>=exterior_faces: p.material_index=1 if i<lip_end else 2
        return obj

    def tiny_bolt(at, axis, group=gun, radius=.010):
        p=Vector(at);d=Vector(axis)
        cylinder('Recessed fastener counterbore',p-d*.001,p+d*.001,radius*1.42,bore,group,12,bevel=0)
        cylinder('Captive hardened hex',p+d*.001,p+d*.009,radius,hardware,group,6,bevel=0)
        cylinder('Deep hex socket',p+d*.0091,p+d*.0098,radius*.42,bore,group,6,bevel=0)

    def support_plate(name,z,width,outer=.139,small_holes=True):
        """Thick scalloped plate with six real separate through-holes."""
        n=72
        verts=[]
        for depth in (z-width*.5,z+width*.5):
            for i in range(n):
                a=i*math.tau/n
                rad=outer+.011*math.cos(a*6)
                verts.append((.66+math.cos(a)*rad,.27+math.sin(a)*rad,depth))
        faces=[tuple(reversed(range(n))),tuple(range(n,n*2))]
        faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        plate=mesh(name,verts,faces,jacket,rotor,0)
        holes=[(.66+math.cos(i*math.tau/6)*.087,.27+math.sin(i*math.tau/6)*.087,.0325) for i in range(6)]
        holes += [(.66,.27,.018)]
        if small_holes:
            holes += [(.66+math.cos((i+.5)*math.tau/6)*.039,.27+math.sin((i+.5)*math.tau/6)*.039,.0085) for i in range(6)]
        cv=[];cf=[];hn=24
        for x,y,r in holes:
            base=len(cv)
            for depth in (z-width,z+width):
                cv += [(x+math.cos(i*math.tau/hn)*r,y+math.sin(i*math.tau/hn)*r,depth) for i in range(hn)]
            cf += [tuple(base+i for i in reversed(range(hn))),tuple(base+hn+i for i in range(hn))]
            cf += [(base+i,base+(i+1)%hn,base+(i+1)%hn+hn,base+i+hn) for i in range(hn)]
        cutter=mesh('Temporary true barrel bores',cv,cf,jacket,rotor,0)
        mod=plate.modifiers.new('Precision individual barrel through-holes','BOOLEAN')
        mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
        bpy.context.view_layer.objects.active=plate
        bpy.ops.object.modifier_apply(modifier=mod.name)
        groups[rotor].remove(cutter)
        bpy.data.objects.remove(cutter,do_unlink=True)
        for p in plate.data.polygons:
            p.use_smooth = abs(p.normal.y) < .5
        finish_bevel(plate,.0022,2)
        for i in range(6):
            a=(i+.5)*math.tau/6
            tiny_bolt((.66+math.cos(a)*(outer-.004),.27+math.sin(a)*(outer-.004),z-width*.5-.001),
                      (0,0,-1),rotor,.0065)
        return plate

    # Detachable dovetail socket, reinforced trunnion and feed-side mounting.
    box('Gun quick-change dovetail foot',(.64,.095,-.54),(.31,.115,.31),jacket,gun,.008)
    box('Gun socket guide upper',(.64,.157,-.54),(.35,.047,.28),metal,gun,.004)
    for x in (.51,.77):
        box('Dovetail clamp jaw',(x,.157,-.54),(.045,.060,.30),edges,gun,.003)
        tiny_bolt((x,.191,-.46),(0,1,0),gun,.011)
        tiny_bolt((x,.191,-.64),(0,1,0),gun,.011)
    cylinder('Weapon trunnion axle',(.475,.22,-.42),(.855,.22,-.42),.079,metal,gun,24,bevel=.005)
    for side in (-1,1):
        x=.66+side*.203
        cylinder('Sealed trunnion cap',(x-side*.017,.22,-.42),(x,.22,-.42),.071,jacket,gun,24)
        cylinder('Trunnion locking pin',(x,.22,-.42),(x+side*.008,.22,-.42),.023,edges,gun,8,bevel=0)

    # Angular compact receiver; separate front casting and removable cheek plates.
    octabox('Octagonal parkerized receiver',.66,.29,-.935,-.43,.365,.30,.047,metal)
    octabox('Receiver front armor flange',.66,.27,-.963,-.902,.382,.322,.058,jacket)
    octabox('Rear feed end casting',.66,.29,-.476,-.397,.348,.279,.047,jacket)
    for side in (-1,1):
        x=.66+side*.187
        box('Recessed receiver side seam',(x,.293,-.687),(.012,.212,.376),bore,gun,.006)
        box('Removable machined receiver cheek',(x+side*.008,.293,-.687),(.018,.193,.357),jacket,gun,.006)
        # A narrow orange service tab follows the reference's restrained accents.
        box('Orange quick-release service tab',(x+side*.020,.293,-.467),(.017,.128,.044),orange,gun,.003)
        for z in (-.536,-.820):
            for y in (.222,.365): tiny_bolt((x+side*.020,y,z),(side,0,0),gun,.010)
        # Heat extraction channels terminate inside an actual dark recess.
        for z in (-.590,-.629,-.668,-.707):
            box('Jacket cooling flute',(x+side*.020,.257,z),(.008,.095,.016),bore,gun,.002)
            box('Jacket flute raised lip',(x+side*.023,.314,z),(.009,.009,.022),edges,gun,.0015)
        box('Receiver upper machined shoulder',(x+side*.004,.414,-.678),(.023,.020,.346),edges,gun,.003)
    # End-plate fasteners and visible concentric rotor bearing, behind the barrels.
    for x,y in ((.52,.17),(.80,.17),(.52,.385),(.80,.385)):
        tiny_bolt((x,y,-.969),(0,0,-1),gun,.011)
    lathe('Stepped rotor bearing case',.66,.27,[(-.915,.151),(-.967,.151),(-.982,.134),(-1.018,.134)],jacket,gun,48)
    ring('Fine bearing retaining race',(.66,.27,-.989),(0,0,1),.136,.122,.016,edges,gun,32)
    # Receiver machining marks remain geometric and sparse, never a silver cage.
    for i in range(12):
        a=i*math.tau/12
        tiny_bolt((.66+math.cos(a)*.143,.27+math.sin(a)*.143,-.970),(0,0,-1),gun,.0055)

    # Rear electrical motor and feeder gate replace the oversized ornamental drum.
    lathe('Rear electric drive motor',.66,.295,[(-.418,.105),(-.368,.108),(-.283,.092),(-.264,.085)],jacket,gun,40)
    for z in (-.36,-.341,-.322,-.303):
        ring('Motor cooling fin',(.66,.295,z),(0,0,1),.105,.080,.010,metal,gun,32)
    lathe('Drive motor end cover',.66,.295,[(-.270,.089),(-.248,.078)],metal,gun,32)
    for i in range(4):
        a=(i+.5)*math.tau/4
        tiny_bolt((.66+math.cos(a)*.063,.295+math.sin(a)*.063,-.246),(0,0,1),gun,.008)
    box('Keyed ammunition inlet',(.895,.25,-.563),(.17,.19,.215),metal,gun,.018)
    box('Feed gate replaceable cover',(.987,.25,-.563),(.028,.158,.178),jacket,gun,.009)
    for z in (-.501,-.625):
        for y in (.201,.299): tiny_bolt((1.004,y,z),(1,0,0),gun,.008)
    box('Feed gate orange inspection tab',(1.006,.25,-.563),(.005,.050,.084),orange,gun,.002)
    cylinder('Feeder vertical drive spindle',(.914,.16,-.566),(.914,.07,-.566),.052,jacket,gun,24)
    ring('Feeder spindle clamp',(.914,.12,-.566),(0,1,0),.058,.045,.018,edges,gun,24)
    tube('Protected motor power loom',[(.65,.30,-.25),(.60,.31,-.19),(.45,.22,-.21),(.43,.13,-.37)],.018,rubber,gun)
    for z in (-.29,-.32,-.35):
        ring('Loom coupling corrugation',(.435,.155,z),(0,0,1),.023,.015,.010,jacket,gun,16)
    # Feed chute enters the inboard socket. Visible links explain the mechanism.
    tube('Armored ammunition transfer chute',[(.875,.14,-.51),(.89,.07,-.48),(.79,.027,-.35),(.65,.045,-.28)],.047,jacket,gun)
    for index in range(6):
        p=Vector((.86,.062,-.44)).lerp(Vector((.68,.047,-.30)),index/5)
        cylinder('Contained linked feeder cartridge',p+Vector((-.017,0,-.019)),p+Vector((.017,0,.019)),.0105,brass,gun,10,bevel=0)

    # Raised rail and compact rectangular optic with recessed glass and adjusters.
    box('Receiver upper rail pedestal',(.66,.455,-.667),(.172,.043,.387),jacket,gun,.006)
    box('Picatinny rail spine',(.66,.481,-.667),(.111,.028,.361),metal,gun,.002)
    for i in range(9):
        z=-.505-i*.039
        box('Individual upper rail tooth',(.66,.496,z),(.164,.018,.019),edges,gun,.002)
    box('Optic locked dovetail saddle',(.66,.517,-.681),(.169,.038,.179),jacket,gun,.004)
    octabox('Compact raised gun optic',.66,.576,-.775,-.574,.173,.121,.021,metal)
    octabox('Optic recessed frontal socket',.66,.576,-.785,-.773,.137,.091,.016,bore)
    cylinder('Deep coated optic glass',(.66,.576,-.7855),(.66,.576,-.787),.037,optics,gun,32,bevel=0)
    ring('Optic lens recessed retaining ring',(.66,.576,-.789),(0,0,1),.047,.037,.009,hardware,gun,32)
    box('Optic sunshade top',(.66,.640,-.685),(.166,.012,.200),jacket,gun,.004)
    cylinder('Optic windage adjuster',(.746,.579,-.636),(.784,.579,-.636),.025,edges,gun,16)
    cylinder('Optic windage dial',(.781,.579,-.636),(.790,.579,-.636),.029,jacket,gun,12)
    cylinder('Optic elevation dial',(.66,.639,-.63),(.66,.661,-.63),.027,jacket,gun,12)
    for x in (.608,.712): tiny_bolt((x,.532,-.745),(0,1,0),gun,.007)
    # Inset serial tick marks and a small maintenance label, avoiding fake logos.
    box('Gun factory identification plate',(.854,.341,-.740),(.011,.039,.117),hardware,gun,.002)
    for i in range(9):
        box('Etched gun serial bar',(.860,.341,-.695-i*.0105),(.001,.023 if i%3 else .029,.003),bore,gun,.0004)
    box('Upper service ivory line',(.66,.438,-.875),(.175,.0015,.013),enamel,gun,.0005)

    # Six separate genuinely hollow gunmetal barrels. Their smooth turned walls
    # stop at the muzzle annulus; black bore caps are half a meter behind it.
    barrel_profile=[(-.987,.036),(-1.032,.036),(-1.040,.028),(-1.570,.028),
                    (-1.578,.0295),(-1.613,.0295),(-1.620,.028),(-1.702,.028),(-1.720,.0265)]
    bore_profile=[(-1.720,.0192),(-1.704,.0185),(-1.64,.0185),(-1.53,.0185),(-1.40,.0185),(-1.24,.0185)]
    for i in range(6):
        a=i*math.tau/6
        x=.66+math.cos(a)*.087;y=.27+math.sin(a)*.087
        lathe('Hollow rifled barrel %02d'%i,x,y,barrel_profile,barrel_finish,rotor,40,bore_profile)
        # Short dark reinforcement jackets have individual cooling ribs.
        for z in (-1.071,-1.096,-1.121):
            ring('Individual barrel heat rib',(x,y,z),(0,0,1),.0315,.027,.008,jacket,rotor,24)
        ring('Barrel root seating washer',(x,y,-1.027),(0,0,1),.037,.028,.012,edges,rotor,24)
    support_plate('Scalloped rear six-hole barrel support',-1.065,.045,.134,False)
    support_plate('Scalloped mid six-hole barrel support',-1.422,.039,.137,True)
    support_plate('Machined scalloped muzzle end plate',-1.675,.060,.139,True)
    lathe('Dark center torque shaft',.66,.27,[(-1.016,.015),(-1.664,.015),(-1.685,.018)],jacket,rotor,24)
    tiny_bolt((.66,.27,-1.708),(0,0,-1),rotor,.012)

    # Publish a concise authoring diagnostic; no additional runtime sockets.
    ns['gun_detail_manifest']={
        'barrels':6,'bore_radius':.0192,'bore_depth':.48,
        'scalloped_perforated_plates':3,'muzzle':[.66,.27,-1.72],
        'receiver':'angular parkerized steel with raised optic and side feeder'}
