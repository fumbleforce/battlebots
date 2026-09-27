"""Bracken reference tank (#100): authored geometry, portable PBR and rig.

Run: blender --background --python tools/build-bracken.py -- [--quick] [--no-bake]
Quick outputs are isolated from production. All construction is in Godot source
metres, Y up, -Z forward. The existing Atlas driver applies the factor three.
The shared track loop, turret pivots, configured bore lines and lifter hinge are exact
contracts, not eyeballed placements. No copied Atlas hull meshes are used.

Review staging: a stationary complete tank on a neutral studio floor; camera
outside the rear-right/front-left corners, above the deck, looking at the centre.
The entire ramp, tracks and barrel ends stay in frame. Side and top orthographic
views expose joins/clearance. Warm large key at front-left, cool fill at right.
These are Blender source renders, never represented as native game captures.
"""
import bpy, math, sys, json, os
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import atlas_model_kit as k
import nimble_model_kit as nk
from atlas_model_kit import part, mesh, box, cylinder, ring, turned, bolt, prism, gv, descendants, finalize, export_model
from nimble_model_kit import section, oriented, beam, outline

QUICK = '--quick' in sys.argv
NO_BAKE = '--no-bake' in sys.argv
PREVIEW = ROOT / 'battlebots/exports/bracken-preview'
OUTPUT = PREVIEW / 'runtime' if QUICK or NO_BAKE else ROOT / 'battlebots/assets/models/bracken_runtime'
SOURCE = PREVIEW / 'source' if QUICK or NO_BAKE else ROOT / 'art_source/bracken'
for path in (PREVIEW, OUTPUT, SOURCE): path.mkdir(parents=True, exist_ok=True)
(PREVIEW / '.gdignore').write_text('')
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
k.groups.clear()

# Soft, slightly desaturated painted masses; warm bare steel, not black rubber.
paint = k.material('Bracken_PaintPrimary', (.40, .405, .275), .03, .82)
paint_edge = k.material('Bracken_PaintPrimaryEdge', (.40, .405, .275), .03, .82)
red = k.material('Bracken_PaintSecondary', (.56, .245, .15), .02, .83)
steel = k.material('Bracken_Metal', (.46, .445, .38), .35, .63)
dark = k.material('Bracken_Recess', (.095, .102, .088), .35, .80)
oxide = k.material('Bracken_OxidizedMetal', (.255, .225, .17), .65, .69)
track = k.material('Bracken_TrackSteel', (.32, .335, .30), .28, .78)
rubber = k.material('Bracken_Rubber', (.12, .125, .10), 0, .89)
stencil = k.material('Bracken_Stencil', (.85, .80, .60), 0, .81)
lens = k.material('Bracken_Lens', (.78, .62, .31), .12, .3)
k.paint = paint; k.paint_edge = paint_edge; k.steel = steel; k.oxidized = oxide; k.dark = dark
nk.M.update(paint=paint, secondary=red, steel=steel, oxidized=oxide, dark=dark)
for material in (paint, paint_edge, red):
    material['atlas_face_wear'] = .65
    material['atlas_grime'] = .34

assembly = part('BrackenSource')
hull = part('BrackenHull', parent=assembly)
body = part('Hull', parent=hull)
turret = part('BrackenTurret', parent=assembly)
lifter = part('BrackenLifter')
GEOMETRY = json.loads((ROOT/'battlebots/data/bracken_geometry.json').read_text())
TRACK_R, TRACK_HALF, TRACK_Y, TRACK_X = .44, .76, -.08, GEOMETRY['track_center_x']
TRACK_LENGTH = 4 * TRACK_HALF + math.tau * TRACK_R
SHOES = 52
YAW = Vector((0, .52, -.14))
PITCH = Vector((0, .77345, -.546))
BORES = GEOMETRY['barrels']
MUZZLE = 1.37025


def plate(name, points, normal, depth, material, group):
    n = len(points); d = Vector(normal).normalized() * depth / 2
    verts = [tuple(Vector(p) + d * s) for s in (-1, 1) for p in points]
    return mesh(name, verts, [tuple(reversed(range(n))), tuple(range(n, 2*n))] +
                [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)], material, group, .004)


def emblem(center, right, up, size, group):
    # Original angular fern/chevron insignia, not a franchise emblem.
    c, r, u = Vector(center), Vector(right), Vector(up)
    n = r.cross(u).normalized()
    for side in (-1, 1):
        for level in (-.28, .07, .42):
            pts = [(0, level-.20), (side*.45, level+.10), (side*.45, level+.24), (0, level-.06)]
            plate('Cream fern stencil', [tuple(c+r*x*size+u*y*size) for x,y in pts], n, .001, stencil, group)
    plate('Fern stem', [tuple(c+r*x*size+u*y*size) for x,y in [(-.035,-.50),(.035,-.50),(.035,.57),(-.035,.57)]], n, .001, stencil, group)


# Narrow keel with folded shoulders. The red sloping panel is at +Z, opposite
# the forward ramp; review from this end to match the supplied composition.
section('Folded keel',[(-1.08,-.30),(-1.02,.16),(-.70,.33),(.58,.33),(1.06,-.22),(.94,-.37)],-.49,.49,paint,body,.016)
section('Belly return',[(-1.02,-.31),(-.87,-.43),(.83,-.43),(1.01,-.28)],-.43,.43,oxide,body,.012)
rear=part('RearGlacis',parent=hull)
n=Vector((0,.48,.55)).normalized()
def glacis(x,z,d=.012): return Vector((x,.33-(z-.58)*.55/.48,z))+n*d
plate('Tapered rear armor',[glacis(x,z) for x,z in [(-.44,.61),(.44,.61),(.32,1.065),(-.32,1.065)]],n,.045,paint,rear)
plate('Worn oxide-red enamel field',[glacis(x,z,.04) for x,z in [(-.29,.62),(.23,.62),(.20,.95),(-.22,.98)]],n,.003,red,rear)
for x,z in [(-.38,.66),(.38,.66),(-.28,1.0),(.28,1.0),(-.32,.86),(.32,.86)]: bolt(glacis(x,z,.042),n,rear,.016)
emblem(glacis(-.025,.79,.046),(1,0,0),(0,.55,-.48),.255,rear)
for s in (-1,1):
    shoulder=part('Shoulder'+str(s),parent=hull)
    section('Folded top shoulder',[(-.72,.31),(-.57,.42),(.51,.42),(.66,.29),(.50,.20),(-.66,.21)],s*.47-.09,s*.47+.09,paint,shoulder,.014)
    section('Red shoulder stripe',[(-.41,.427),(-.26,.445),(.35,.445),(.43,.415)],s*.47-.071,s*.47+.071,red,shoulder,.003)
    for z in (-.48,.40): bolt((s*.47,.438,z),(0,1,0),shoulder,.016)
    # Twin large diagonal suspension rams: exposed piston, collars and anchored eyes.
    ram=part('SuspensionRam'+str(s),parent=hull)
    a=Vector((s*.47,-.21,1.14)); b=Vector((s*.47,.38,.64)); v=(b-a).normalized(); length=(b-a).length
    for p in (a,b):
        cylinder('Ram through pin',p-Vector((.082,0,0)),p+Vector((.082,0,0)),.031,steel,ram,24,.003)
        for face in (-1,1): bolt(p+Vector((face*.085,0,0)),(face,0,0),ram,.022)
        ring('Spherical ram eye',p,(1,0,0),.074,.032,.09,oxide,ram,24)
        bolt(p+Vector((s*.052,0,0)),(s,0,0),ram,.026)
    for dx in (-.059,.059):
        section('Lower ram clevis',[(.94,-.30),(1.17,-.29),(1.20,-.20),(1.12,-.135),(.96,-.18)],s*.47+dx-.012,s*.47+dx+.012,paint,ram,.006)
        section('Upper ram clevis',[(.49,.29),(.69,.30),(.715,.38),(.65,.447),(.50,.41)],s*.47+dx-.012,s*.47+dx+.012,paint,ram,.006)
    turned('Suspension cylinder',a+v*.06,v,[(0,.04),(.04,.058),(.12,.061),(.36,.061),(.38,.074),(.42,.074),(.435,.042)],paint,ram,24)
    turned('Cylinder polished rod',b-v*.05,-v,[(0,.038),(.05,.033),(.31,.033),(.33,.027)],steel,ram,24)
    ring('Ram gland seal',a+v*.44,v,.043,.032,.018,dark,ram,24)
    for p in (a+v*.13,a+v*.37):
        turned('Hydraulic elbow',p+Vector((-s*.052,0,0)),(s,0,0),[(0,.025),(.025,.025),(.034,.018)],oxide,ram,12)
    k.tube('Braided return hose',[a+v*.13+Vector((-s*.075,0,0)),a+v*.20+Vector((-s*.14,0,0)),a+v*.36+Vector((-s*.15,0,0)),a+v*.39+Vector((-s*.075,0,0))],.013,rubber,ram)
    # Axle saddle, cast relieved edges, grease fitting; supports are below track top.
    for z in (-.73,.76):
        turned('Axle housing',(s*.45,-.08,z),(s,0,0),[(0,.12),(.10,.12),(.16,.092),(.24,.092)],oxide,body,24)
    # Front clevis is an authored fitted mount, not the generic runtime box adapter.
    section('Lifter clevis',[(-1.22,-.22),(-1.22,-.06),(-.86,.08),(-.71,-.13)],s*.44-.052,s*.44+.052,steel,body,.008)
    ring('Front hinge bearing',(s*.44,-.12,-1.1),(1,0,0),.09,.059,.10,paint,body,24)
# Narrow service hatch and real radiator fins behind the traverse.
service=part('DeckService',parent=hull)
prism('Raised service hatch',outline(.55,.22,.04,dz=.41),.335,.36,red,service,.005)
for x in (-.22,.22): bolt((x,.367,.41),(0,1,0),service,.012)
for x in (-.13,.13): k.tube('Hatch grab handle',[(x-.04,.365,.42),(x-.04,.39,.42),(x+.04,.39,.42),(x+.04,.365,.42)],.009,steel,service)
nk.vent('Forward radiator',(0,.11,-1.06),.58,.20,.05,7,body,(0,0,-1))


def track_pose(distance,x):
    p=distance%TRACK_LENGTH; straight=2*TRACK_HALF; arc=math.pi*TRACK_R
    if p<straight: y,z,a=TRACK_Y+TRACK_R,-TRACK_HALF+p,0
    elif p<straight+arc:
        a=(p-straight)/TRACK_R; y,z=TRACK_Y+math.cos(a)*TRACK_R,TRACK_HALF+math.sin(a)*TRACK_R
    elif p<2*straight+arc: y,z,a=TRACK_Y-TRACK_R,TRACK_HALF-(p-straight-arc),math.pi
    else:
        a=math.pi+(p-2*straight-arc)/TRACK_R; y,z=TRACK_Y+math.cos(a)*TRACK_R,-TRACK_HALF+math.sin(a)*TRACK_R
    return (x,y,z),a

shoe_template=part('ShoeTemplate')
prism('Relieved cast track shoe',outline(.35,.096,.018),-.025,.022,track,shoe_template,.004)
# Three offset cleat faces and depressed hinge channels break the slab silhouette.
for x in (-.112,0,.112):
    prism('Raised tooth pad',outline(.094,.052,.008,dx=x),.022,.042,track,shoe_template,.003)
    box('Recess in pad',(x,.042,-.003),(.058,.002,.010),oxide,shoe_template,.001)
for s in (-1,1):
    turned('Interlocking link knuckle',(s*.112-.036,0,.055),(1,0,0),[(0,.020),(.017,.024),(.055,.024),(.073,.019)],oxide,shoe_template,12)
    turned('Through pin cap',(s*.170,0,.055),(s,0,0),[(0,.018),(.012,.018),(.020,.012),(.021,0)],steel,shoe_template,12)
shoe_mesh=finalize(shoe_template)
for s,label in [(-1,'L'),(1,'R')]:
    drive=part('DriveLeft' if s<0 else 'DriveRight',parent=hull)
    section('Cast suspension spine',[(-.87,-.16),(-.64,.10),(.64,.10),(.87,-.16),(.70,-.30),(-.70,-.30)],s*.59-.05,s*.59+.05,oxide,drive,.012)
    for j in range(SHOES):
        at,angle=track_pose(j*TRACK_LENGTH/SHOES,s*TRACK_X)
        node=part('Tread_%s_%02d'%(label,j),at,parent=drive); node.rotation_euler.x=angle
        obj=bpy.data.objects.new(node.name+'Surface',shoe_mesh.data); bpy.context.collection.objects.link(obj); obj.parent=node
    for z,title,radius in [(-.76,'Front',.388),(.76,'Rear',.388),(-.40,'Road0',.120),(0,'Road1',.120),(.40,'Road2',.120)]:
        y=TRACK_Y if title in ('Front','Rear') else -.35
        wheel=part('Wheel_%s_%s'%(label,title),(s*TRACK_X,y,z),parent=drive)
        # Stepped tread surface and recessed spoked disc; no featureless end cylinder.
        turned('Running rim',(s*.63,y,z),(s,0,0),[(0,radius*.87),(.023,radius),(.24,radius),(.263,radius*.86)],oxide,wheel,32)
        ring('Deep outer rim',(s*.902,y,z),(1,0,0),radius*.87,radius*.68,.038,paint,wheel,32)
        cylinder('Hub shadow disc',(s*.83,y,z),(s*.85,y,z),radius*.70,dark,wheel,32,.002)
        spokes=8 if radius>.2 else 5
        for i in range(spokes):
            t=i*math.tau/spokes
            p=Vector((s*.890,y+math.cos(t)*radius*.22,z+math.sin(t)*radius*.22))
            q=Vector((s*.875,y+math.cos(t+.13)*radius*.77,z+math.sin(t+.13)*radius*.77))
            beam('Reinforced cast spoke',p,q,.039 if radius>.2 else .019,.050 if radius>.2 else .026,paint,wheel,.005)
            bolt((s*.930,y+math.cos(t)*radius*.79,z+math.sin(t)*radius*.79),(s,0,0),wheel,.014 if radius>.2 else .007)
        if radius>.2:
            turned('Pressed wheel dish',(s*.881,y,z),(s,0,0),[(0,radius*.66),(.014,radius*.66),(.030,radius*.47),(.046,radius*.49),(.046,radius*.29)],paint,wheel,32)
            ring('Dish inner dark groove',(s*.930,y,z),(1,0,0),radius*.39,radius*.365,.009,oxide,wheel,32)
        turned('Oil seal and stepped axle',(s*.874,y,z),(s,0,0),[(0,radius*.31),(.029,radius*.31),(.045,radius*.23),(.076,radius*.23),(.085,radius*.15)],paint,wheel,24)
        bolt((s*.965,y,z),(s,0,0),wheel,.030 if radius>.2 else .012)
    # Low side cover sits below the top track run; separate panels shed on damage.
    cover=part('TrackSideCover'+label,parent=drive)
    section('Side girder armor',[(-.52,-.15),(-.38,.015),(.35,.015),(.53,-.16),(.36,-.31),(-.38,-.31)],s*.938-.018,s*.938+.018,paint,cover,.008)
    for i,z in enumerate((-.31,0,.31)):
        plate('Chipped red side field',[(s*.96,-.10,z-.10),(s*.96,-.10,z+.10),(s*.96,-.245,z+.085),(s*.96,-.245,z-.08)],(s,0,0),.003,red,cover)
        turned('Recessed side fastener socket',(s*.962,-.068,z),(s,0,0),[(0,.042),(.010,.042),(.018,.032)],oxide,cover,16)
        bolt((s*.981,-.068,z),(s,0,0),cover,.020)
    # Two local bridge guards leave most of the continuous track loop visible.
    for z in (-.38,.38):
        guard=part('TrackGuard'+label+str(z),parent=drive)
        section('Arched guard',[ (z-.12,.44),(z-.07,.482),(z+.08,.482),(z+.13,.435),(z+.10,.416),(z-.11,.419)],s*.73-.11,s*.73+.11,paint,guard,.006)
        section('Guard enamel cap',[(z-.065,.484),(z-.045,.493),(z+.063,.493),(z+.08,.484)],s*.73-.085,s*.73+.085,red,guard,.002)
        for dx in (-.08,.08): bolt((s*.73+dx,.496,z),(0,1,0),guard,.012)
        beam('Inner guard bracket',(s*.51,.17,z),(s*.545,.445,z),.035,.073,oxide,guard,.005)
        beam('Guard cross saddle',(s*.55,.445,z),(s*.68,.445,z),.026,.06,oxide,guard,.004)
k.groups.pop(shoe_template)
bpy.data.objects.remove(shoe_template,do_unlink=True); bpy.data.objects.remove(shoe_mesh,do_unlink=True)

# Compact tank turret: wide cheek shields surround the paired guns; rear shell
# tapers into an offset sensor housing, rather than a stack of rectangular boxes.
turned('Traverse foundation',(0,.337,-.14),(0,1,0),[(0,.34),(.035,.34),(.05,.30),(.15,.30),(.157,.32)],oxide,body,48)
for i in range(16):
    t=i*math.tau/16
    p=(math.sin(t)*.313,.448,-.14+math.cos(t)*.313)
    bolt(p,(math.sin(t),0,math.cos(t)),body,.011)
for s in (-1,1):
    section('Traverse restraint lug',[(-.36,.36),(-.34,.42),(-.25,.43),(-.22,.36)],s*.29-.044,s*.29+.044,paint,body,.006)
yaw=part('TurretYaw',YAW,parent=turret)
ring('Traverse bearing race',(0,.516,-.14),(0,1,0),.322,.257,.031,steel,yaw,48)
for i in range(12):
    t=i*math.tau/12
    bolt((math.sin(t)*.288,.537,-.14+math.cos(t)*.288),(0,1,0),yaw,.010)
prism('Tapered rear turret shell',outline(.57,.68,.085,dz=-.02),.576,.94,paint,yaw,.015,outline(.49,.54,.08,dz=-.05))
section('Turret sloping back hood',[(.24,.62),(.31,.65),(.31,.84),(.17,.94),(.13,.90),(.24,.81)],-.245,.245,paint,yaw,.009)
plate('Rear inset hatch',[(-.13,.65,.324),(.13,.65,.324),(.13,.80,.324),(-.13,.80,.324)],(0,0,1),.014,oxide,yaw)
plate('Rear vent recess',[(-.095,.68,.334),(.095,.68,.334),(.095,.773,.334),(-.095,.773,.334)],(0,0,1),.003,dark,yaw)
for x in (-.067,0,.067): beam('Back hatch fins',(x,.68,.339),(x,.775,.339),.018,.02,steel,yaw,.002)
for x in (-.18,.18):
    for y in (.65,.82): bolt((x,y,.327),(0,0,1),yaw,.013)
prism('Roof red access lid',outline(.30,.28,.045,dz=.0),.942,.966,red,yaw,.006)
for x in (-.12,.12): bolt((x,.975,.025),(0,1,0),yaw,.009)
section('Armored sight hood',[(-.24,.97),(-.24,1.10),(-.15,1.15),(.02,1.13),(.06,.97)],-.12,.12,paint,yaw,.008)
plate('Sight black recess',[(-.072,1.006,-.248),(.072,1.006,-.248),(.072,1.08,-.248),(-.072,1.08,-.248)],(0,0,-1),.008,dark,yaw)
plate('Amber sight aperture',[(-.055,1.024,-.254),(.035,1.024,-.254),(.035,1.068,-.254),(-.055,1.068,-.254)],(0,0,-1),.002,lens,yaw)
turned('Radio foot',(-.17,.962,.11),(0,1,0),[(0,.04),(.035,.04),(.05,.022),(.075,.021)],oxide,yaw,16)
k.tube('Radio whip',[(-.17,1.028,.11),(-.17,1.17,.11),(-.18,1.25,.10)],.006,steel,yaw)
for s in (-1,1):
    section('Pitch bearing upright',[(-.63,.64),(-.64,.83),(-.48,.91),(-.28,.77),(-.25,.58)],s*.29-.038,s*.29+.038,oxide,yaw,.009)
    turned('Trunnion bearing',(s*.25,.77345,-.546),(s,0,0),[(0,.087),(.09,.087),(.11,.062),(.125,.062)],steel,yaw,24)
pitch=part('TurretPitch',PITCH,parent=yaw)
attachment=part('AttachmentCannonBracken',parent=pitch)
section('Shaped breech bridge',[(-.76,.64),(-.76,.88),(-.65,.93),(-.40,.86),(-.40,.68)],-.49,.49,oxide,attachment,.009)
prism('Bridge red enamel cover',outline(.62,.23,.035,dz=-.53),.907,.93,red,attachment,.004)
for x in (-.25,.25): bolt((x,.94,-.53),(0,1,0),attachment,.011)
nk.vent('Breech cooling inset',(0,.78,-.768),.43,.12,.026,5,attachment,(0,0,-1))
for s in (-1,1):
    shield=part('GunShield'+str(s),parent=attachment)
    section('Cast cassette side',[(-.91,.66),(-.89,.94),(-.76,1.00),(-.36,.96),(-.23,.86),(-.26,.64),(-.39,.59)],s*.565-.034,s*.565+.034,paint,shield,.012)
    plate('Red shield enamel',[(s*.602,.67,-.83),(s*.602,.94,-.78),(s*.602,.925,-.41),(s*.602,.84,-.30),(s*.602,.67,-.34)],(s,0,0),.005,red,shield)
    for y,z in [(.72,-.83),(.92,-.71),(.70,-.36),(.87,-.36)]: bolt((s*.611,y,z),(s,0,0),shield,.016)
    # Rear cassette door has an inset center and corners that follow the shield.
    section('Cassette back closure',[(-.31,.67),(-.31,.88),(-.21,.85),(-.21,.69)],s*.44-.105,s*.44+.105,paint,shield,.006)
for i,(dx,dy) in enumerate(BORES):
    x,y=dx,PITCH.y+dy
    recoil=part('CannonRecoilBracken_%d'%i,(x,y,PITCH.z),parent=attachment)
    turned('Recoil sleeve',(x,y,-.32),(0,0,-1),[(0,.064),(.035,.088),(.32,.088),(.35,.073),(.51,.073),(.54,.058)],paint,recoil,24)
    # Dark steel tube, stepped shoulders and open muzzle with substantial wall.
    turned('Stepped barrel',(x,y,-.77),(0,0,-1),[(0,.054),(.11,.049),(.43,.039),(.74,.036),(.98,.036),(1.10,.043)],oxide,recoil,24)
    for z,r in [(-.85,.077),(-1.03,.055),(-1.60,.050)]:
        ring('Raised retaining collar',(x,y,z),(0,0,1),r,.034,.044,steel,recoil,24)
    for a in (0,math.pi/2,math.pi,math.pi*1.5):
        cylinder('Breech axial bolt',(x+math.cos(a)*.067,y+math.sin(a)*.067,-.83),(x+math.cos(a)*.067,y+math.sin(a)*.067,-.87),.010,oxide,recoil,12,.001)
    ring('Hollow forged muzzle',(x,y,PITCH.z-MUZZLE+.045),(0,0,1),.059,.032,.09,steel,recoil,24)
    cylinder('Bore shadow',(x,y,PITCH.z-MUZZLE+.13),(x,y,PITCH.z-MUZZLE+.14),.032,dark,recoil,24,0)
    part('MuzzleCannonBracken_%d'%i,(x,y,PITCH.z-MUZZLE),parent=recoil)
# Elevation actuators are two rigid authored pieces. Runtime aims both eyes at
# their actual anchors; no stretching UVs or clipping through the shield.
for s,label in [(-1,'L'),(1,'R')]:
    a=Vector(GEOMETRY['hydraulics']['turret_fixed']); a.x*=s
    b=Vector(GEOMETRY['hydraulics']['turret_moving']); b.x*=s
    axis=(b-a).normalized()
    ram=part('ElevationBarrel'+label,a,parent=yaw)
    rod=part('ElevationRod'+label,b,parent=pitch)
    turned('Elevation cylinder',a,axis,[(0,.031),(.035,.044),(.27,.044),(.30,.054),(.34,.054),(.36,.030)],paint,ram,24)
    turned('Elevation piston',b,-axis,[(0,.029),(.035,.027),(.365,.027),(.39,.021)],steel,rod,24)
    for p,grp in [(a,ram),(b,rod)]:
        ring('Actuator eye',p,(1,0,0),.052,.022,.054,oxide,grp,20)
        bolt(p+Vector((s*.03,0,0)),(s,0,0),grp,.018)
    k.tube('Turret hydraulic hose',[a+Vector((s*.055,0,-.09)),a+Vector((s*.11,-.02,-.17)),a+Vector((s*.10,-.07,-.34)),a+Vector((s*.08,-.06,-.43))],.011,rubber,yaw)

# Flipper: structural side beams with separate slats and red enamel remnants.
for x in (-.72,.72):
    section('Ramp folded edge beam',[(-1.0,.00),(-1.0,.055),(-.19,.145),(.03,.055),(.03,-.045),(-.17,.045)],x-.038,x+.038,paint,lifter,.007)
for z in (-.89,-.48,-.13): beam('Under-ramp crossbrace',(-.72,.018,z),(.72,.018,z),.055,.052,oxide,lifter,.005)
for i in range(6):
    x=-.59+i*.236
    slat=part('RampSlat%d'%i,parent=lifter)
    section('Pressed ramp slat',[(-.97,.021),(-.97,.038),(-.13,.112),(-.07,.063),(-.07,.023)],x-.112,x+.112,paint,slat,.004)
    if i in (1,2,4):
        plate('Faded ramp paint',[(x-.082,.052,-.84),(x+.069,.052,-.84),(x+.082,.090,-.43),(x-.07,.090,-.40)],(0,1,-.09),.002,red,slat)
    for z in (-.82,-.24): bolt((x,.05 if z<-.5 else .105,z),(0,1,-.09),slat,.010)
for x in (-.70,-.354,0,.354,.70):
    section('Raised ramp stiffener',[(-.98,.04),(-.96,.077),(-.17,.163),(-.12,.105)],x-.012,x+.012,steel,lifter,.003)
turned('Through hinge',(-.83,0,0),(1,0,0),[(0,.065),(.08,.065),(.08,.048),(1.56,.048),(1.56,.065),(1.66,.065)],steel,lifter,24)
for x in (-.64,-.44,.44,.64): ring('Hinge knuckle',(x,0,0),(1,0,0),.084,.055,.095,oxide,lifter,24)
for x in (-.60,-.20,.20,.60):
    section('Hardened tooth',[(-1.035,.01),(-.96,.055),(-.89,.055),(-.92,-.02)],x-.14,x+.14,steel,lifter,.003)

# Apply edge/normal modifiers, then share each finished shoe mesh across the loop.
for group in list(k.groups):
    if group.name in bpy.data.objects: finalize(group)

surface = {'skipped': True}
if not NO_BAKE:
    from atlas_surface_bake import bake_surface_atlases
    from bracken_surface_bake import painterly
    surface=bake_surface_atlases(assembly,lifter,[yaw],OUTPUT,quick=QUICK,prefix='Bracken_Surface',
        sizes={'Primary':2048,'Secondary':2048,'Track':1024,'Hardware':2048},face_wear=.76,primary_color=tuple(paint.diffuse_color),surface_graph=painterly)

for root,filename in [(hull,'bracken.glb'),(turret,'bracken_turret.glb'),(lifter,'bracken_lifter.glb')]:
    export_model(root,filename,OUTPUT)
tris=0
for obj in descendants(assembly)+descendants(lifter):
    if obj.type=='MESH': obj.data.calc_loop_triangles(); tris+=len(obj.data.loop_triangles)
manifest={'generator':'tools/build-bracken.py','triangles':tris,'shoes_per_side':SHOES,
    'source_coordinates':'Godot metres; X right Y up -Z forward; runtime scale 3',
    'turret_yaw':list(YAW),'turret_pitch':list(PITCH),'barrels':BORES,'muzzle_distance':MUZZLE,
    'surface_atlases':surface,'visual_acceptance':'Pending user review; studio source renders only'}
(OUTPUT/'bracken_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for img in bpy.data.images:
    if img.source=='FILE': img.pack()
# Editable source and standalone GLB open as the complete assembled tank.
# Runtime exports above keep the attachment in its canonical local frame.
lifter.parent=assembly
lifter.location=gv((0,-.12,-1.10))
lifter.rotation_euler.x=.48
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in descendants(assembly): obj.select_set(True)
bpy.context.view_layer.objects.active=assembly
bpy.ops.export_scene.gltf(filepath=str(SOURCE/'bracken_complete.glb'),export_format='GLB',use_selection=True,
    export_yup=True,export_apply=True,export_materials='EXPORT',export_animations=False)
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'bracken.blend'))
print('BRACKEN_EXPORT',tris,str(OUTPUT),flush=True)

# Source-only review. Lifter is placed at its actual hinge and raised
# to show its ribs; turret stays at zero yaw so all bore lines are clear.
lifter.location=gv((0,-.12,-1.10)); lifter.rotation_euler.x=.48
floor=k.material('Studio_floor',(.40,.435,.38),0,.90)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.555)); bpy.context.object.data.materials.append(floor)
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.cycles.use_denoising=True
try:
    if os.environ.get('ATLAS_BAKE_DEVICE') == 'CPU': raise RuntimeError('CPU render requested')
    prefs=bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type='OPTIX'; prefs.get_devices()
    for device in prefs.devices: device.use=device.type=='OPTIX'
    scene.cycles.device='GPU'
except Exception: scene.cycles.device='CPU'
scene.world=scene.world or bpy.data.worlds.new('Bracken studio'); scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.73,.80,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.25
def light(name,at,power,color,size):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.color=color; data.shape='DISK'; data.size=size
    obj=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(obj); obj.location=gv(at)
    obj.rotation_euler=(gv((0,.2,0))-obj.location).to_track_quat('-Z','Y').to_euler()
light('Warm front key',(-3,5,-4),500,(1,.94,.81),2)
light('Cool fill',(4,3,1),200,(.79,.88,1),4)
light('Rear sunlight',(-2,4,4),650,(1,.92,.74),2)
camdata=bpy.data.cameras.new('ReviewCamera'); cam=bpy.data.objects.new('ReviewCamera',camdata); bpy.context.collection.objects.link(cam); scene.camera=cam
scene.render.resolution_x=1500; scene.render.resolution_y=1200; scene.render.resolution_percentage=75 if QUICK else 100
scene.view_settings.view_transform='AgX'
for label,at,scale in [('hero',(3.5,2.0,4.8),4.1),('front',(-3.8,2.2,-4.5),4.35),('side',(5,1.1,0),4.4),('top',(.001,6,0),4.5)]:
    cam.location=gv(at); cam.rotation_euler=(gv((0,.16,-.35))-cam.location).to_track_quat('-Z','Y').to_euler(); camdata.type='ORTHO'; camdata.ortho_scale=scale
    scene.render.filepath=str(PREVIEW/(label+'.png')); bpy.ops.render.render(write_still=True)
print('BRACKEN_REVIEW',str(PREVIEW),flush=True)
