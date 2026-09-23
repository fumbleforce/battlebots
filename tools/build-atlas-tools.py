"""Atlas MX front tools: battering ram (#54), spear/forklift (#53) and spiked
grinder drum (#56).

Blender 5.2 --background --python tools/build-atlas-tools.py [-- --quick] [--no-render]

Construction brief (Godot metres, X right, Y up, -Z forward, Atlas hull origin;
runtime factor three applied by AtlasVisual, like the hull and turret):
- Every tool bolts to the existing quick-release coupler: the two rails the
  runtime adds at X=+-.25, Z=-.94..-1.34 end in a common backing plate at
  Z=-1.42, clear of the optional chin armour and the track noses. Nothing is glued to the hull shell; the audit below checks each tool
  and its moving extremes against the imported approved hull.
- Ram: a wide armoured prow on twin hydraulic punch cylinders. RamPunch slides
  RAM_PUNCH metres forward on a punch.
- Spear/forklift: a lift mast whose SpearCarriage rises SPEAR_LIFT metres,
  carrying SpearTines (two forged fork tines and a central barbed lance) that
  thrust SPEAR_THRUST metres forward.
- Grinder (v2, #69): a yoke beam across the coupler carries pivot housings
  outboard of the tracks. GrinderArms (fabricated tapered box arms, lift rams
  and a ribbed debris hood) pivot about X by up to GRINDER_RAISE degrees;
  GrinderDrum spins a full-width welded drum with chevron cutter teeth,
  chain-driven from a hydraulic motor at the right pivot.
- Materials use the approved Atlas classes; maps are baked into a separate
  Atlas_Tools* set so the hull and turret maps stay untouched.
"""
import bpy, math, json, sys, random
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import atlas_model_kit as kit
from atlas_model_kit import part, mesh, prism, box, cylinder, ring, turned, bolt, tube, gv, descendants, finalize, export_model

SOURCE = ROOT / 'art_source/atlas_tools'
RUNTIME = ROOT / 'battlebots/assets/models/atlas_runtime'
PREVIEW = ROOT / 'battlebots/exports/atlas-tools-preview'
QUICK = '--quick' in sys.argv
NO_RENDER = '--no-render' in sys.argv
PREVIEW.mkdir(parents=True, exist_ok=True)
(PREVIEW / '.gdignore').write_text('')
if QUICK:
    SOURCE = PREVIEW / 'source'
    RUNTIME = PREVIEW / 'runtime'
for path in [SOURCE, RUNTIME]: path.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
random.seed(54053)
M = kit.palette()
paint, secondary, steel, edge_steel, oxidized, rubber, dark = (M[k] for k in ('paint', 'secondary', 'steel', 'edge_steel', 'oxidized', 'rubber', 'dark'))
gun, gun_block, barrel_primary = M['gun'], M['gun_block'], M['barrel_primary']

# Published poses (also in AtlasGeometry and the manifest).
# In front of the optional chin armour (Z>-1.37) and the track noses (-1.23).
PLATE_Z = -1.42
RAM_PUNCH = .28
SPEAR_LIFT = .42
SPEAR_THRUST = .50
# Grinder v2 (#69, user: "much bigger ... quite lazy compared to the atlas
# model"): a full-width 0.8 m drum on fabricated arms under a debris hood.
GRINDER_PIVOT = (0.0, .10, -1.58)
GRINDER_AXLE = (0.0, .05, -2.58)
GRINDER_RADIUS = .40
GRINDER_SPIKE = .155
GRINDER_HALF_WIDTH = 1.08
GRINDER_RAISE = 34.0

def beam(name, a, b, w, h, mat, group, bevel=.014):
    """Box-section beam from a to b (w across X, h in the a-b/X plane)."""
    a = Vector(a); b = Vector(b); d = (b - a).normalized()
    side = Vector((1, 0, 0)); up = d.cross(side).normalized() * -1
    corners = []
    for p in (a, b):
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            corners.append(tuple(p + side * sx * w * .5 + up * sy * h * .5))
    return mesh(name, corners, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)], mat, group, bevel)

root = part('AtlasTools')
ram = part('ToolRam', (0, 0, 0), root)
spear = part('ToolSpear', (0, 0, 0), root)
grinder = part('ToolGrinder', (0, 0, 0), root)
TOOLS = {'ram': ram, 'spear': spear, 'grinder': grinder}

def backing_plate(group, width=1.10, height=.46, y=-.06):
    """Common coupler plate the rails bolt into, with its bolt pattern."""
    box('Coupler backing plate', (0, y, PLATE_Z), (width, height, .05), secondary, group, .012)
    for x in (-.25, .25):
        box('Coupler rail socket', (x, -.02, PLATE_Z + .05), (.13, .14, .07), steel, group, .004)
        for dy in (-.045, .045): bolt((x, -.02 + dy, PLATE_Z - .026), (0, 0, -1), group, .011)
    for sx in (-1, 1):
        for sy in (-1, 1): bolt((sx * (width * .5 - .05), y + sy * (height * .5 - .05), PLATE_Z - .026), (0, 0, -1), group, .012)

# -------------------------------------------------------------------- ram
# Wide armoured prow on twin punch cylinders and guide rods. The prow is a
# shallow chevron in plan with hardened striker plates on each facet, blunt
# forged studs on the nose and a top deflector lip.
backing_plate(ram, 1.30, .50)
punch = part('RamPunch', (0, 0, 0), ram)
for x in (-.40, .40):
    cylinder('Ram punch cylinder', (x, -.06, PLATE_Z - .02), (x, -.06, -1.58), .070, steel, ram, 32, .004)
    ring('Punch cylinder gland', (x, -.06, -1.575), (0, 0, 1), .080, .060, .022, edge_steel, ram, 32)
    cylinder('Ram punch piston rod', (x, -.06, -1.56), (x, -.06, -1.70), .040, edge_steel, punch, 24, .002)
for x, y in ((-.12, .15), (.12, .15), (-.12, -.27), (.12, -.27)):
    cylinder('Ram guide rod', (x, y, PLATE_Z - .02), (x, y, -1.70), .024, edge_steel, punch, 20, .002)
    ring('Guide rod bushing', (x, y, PLATE_Z - .04), (0, 0, 1), .038, .024, .03, steel, ram, 20)
RB, RN, RS, RW = -1.70, -1.90, -1.80, 1.08
chevron = [(-RW, RB), (-RW, RS), (-.28, RN), (.28, RN), (RW, RS), (RW, RB)]
prism('Armoured ram prow', chevron, -.44, .24, paint, punch, .022)
box('Prow backing bulkhead', (0, -.10, RB + .03), (2 * RW - .1, .60, .06), secondary, punch, .010)
def facet_plate(p0, p1, y0, y1, label):
    d = Vector((p1[0] - p0[0], 0, p1[1] - p0[1])).normalized(); n = Vector((d.z, 0, -d.x))
    if n.z > 0: n = -n
    t = .032; inset = .03
    a = Vector((p0[0], 0, p0[1])) + d * inset; b = Vector((p1[0], 0, p1[1])) - d * inset
    outline = [(a.x, a.z), (b.x, b.z), (b.x + n.x * t, b.z + n.z * t), (a.x + n.x * t, a.z + n.z * t)]
    prism(label, outline, y0, y1, edge_steel, punch, .006)
    for k in (.25, .75):
        q = a.lerp(b, k) + n * t
        for y in (y0 + .07, y1 - .07): bolt((q.x, y, q.z), (n.x, 0, n.z), punch, .011, low=True)
facet_plate((-.28, RN), (.28, RN), -.40, .20, 'Hardened nose striker plate')
facet_plate((-RW, RS), (-.28, RN), -.38, .18, 'Hardened facet striker plate')
facet_plate((.28, RN), (RW, RS), -.38, .18, 'Hardened facet striker plate')
for x in (-.16, .16):
    for y in (-.22, .02):
        turned('Blunt forged ram stud', (x, y, RN - .032), (0, 0, -1), [(0, .055), (.020, .052), (.052, .036), (.066, .018), (.070, 0)], edge_steel, punch, 24)
box('Prow top deflector lip', (0, .255, RS + .03), (2 * RW - .14, .035, .22), secondary, punch, .010)
for x in (-.7, -.35, 0, .35, .7): bolt((x, .274, RS + .03), (0, 1, 0), punch, .010)
for side in (-1, 1):
    box('Prow side cheek', (side * (RW + .012), -.10, (RB + RS) * .5), (.024, .60, abs(RS - RB) + .02), secondary, punch, .006)

# ---------------------------------------------------------- spear/forklift
# Forklift mast: two channel uprights on the plate, a central lift cylinder
# and a carriage on rollers. The carriage carries a backrest grille, two
# forged fork tines and a long barbed lance on its own thrust cylinder.
backing_plate(spear, 1.10, .46)
for side in (-1, 1):
    x = side * .43
    box('Mast channel web', (x, .02, -1.480), (.10, 1.00, .025), secondary, spear, .006)
    for dx in (-.045, .045): box('Mast channel flange', (x + dx, .02, -1.515), (.012, 1.00, .070), secondary, spear, .004)
    box('Mast foot bracket', (x, -.36, PLATE_Z - .06), (.16, .14, .07), steel, spear, .006)
box('Mast top crossbar', (0, .50, -1.500), (.96, .07, .09), paint, spear, .012)
box('Mast bottom crossbar', (0, -.46, -1.500), (.96, .06, .09), secondary, spear, .008)
cylinder('Mast lift cylinder', (0, -.44, -1.490), (0, .10, -1.490), .050, steel, spear, 28, .003)
lift = part('SpearCarriage', (0, 0, 0), spear)
cylinder('Mast lift ram', (0, .10, -1.490), (0, .46, -1.490), .028, edge_steel, lift, 20, .002)
CY = -.30
box('Fork carriage plate', (0, CY, -1.570), (.84, .26, .05), paint, lift, .012)
for side in (-1, 1):
    for y in (CY - .08, CY + .08):
        cylinder('Carriage mast roller', (side * .40, y, -1.520), (side * .43, y, -1.520), .028, steel, lift, 20, .002)
for x in (-.30, -.10, .10, .30):
    box('Load backrest bar', (x, CY + .30, -1.570), (.035, .40, .035), secondary, lift, .004)
box('Load backrest top rail', (0, CY + .49, -1.570), (.70, .04, .04), secondary, lift, .005)
thrust = part('SpearTines', (0, 0, 0), lift)
cylinder('Lance thrust cylinder', (0, CY + .03, -1.600), (0, CY + .03, -1.850), .045, steel, lift, 24, .003)
for side in (-1, 1):
    x = side * .27
    box('Fork tine shank', (x, CY - .01, -1.620), (.12, .30, .06), edge_steel, thrust, .010)
    # Forged tapered tine: thick at the heel, sharpened to a chisel point.
    heel, tip = -1.630, -2.780
    verts = [(x - .085, CY - .17, heel), (x + .085, CY - .17, heel), (x + .085, CY - .075, heel), (x - .085, CY - .075, heel),
             (x - .016, CY - .17, tip), (x + .016, CY - .17, tip), (x + .005, CY - .155, tip), (x - .005, CY - .155, tip)]
    mesh('Forged fork tine', verts, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)], edge_steel, thrust, .008)
    box('Tine heel gusset', (x, CY - .08, -1.670), (.10, .12, .08), steel, thrust, .006)
turned('Barbed lance shaft', (0, CY + .03, -1.850), (0, 0, -1), [(0, .044), (.78, .038)], gun, thrust, 24)
turned('Forged lance point', (0, CY + .03, -2.630), (0, 0, -1), [(0, .058), (.030, .064), (.230, .014), (.270, 0)], edge_steel, thrust, 28)
for i in range(4):
    a = i * math.tau / 4 + math.pi / 4; d = (math.cos(a), math.sin(a))
    mesh('Lance barb', [(d[0] * .036, CY + .03 + d[1] * .036, -2.760), (d[0] * .036, CY + .03 + d[1] * .036, -2.700),
                        (d[0] * .110, CY + .03 + d[1] * .110, -2.670), (d[0] * .014 - d[1] * .009, CY + .03 + d[1] * .014 + d[0] * .009, -2.720)],
         [(0, 1, 2), (0, 2, 3), (1, 3, 2), (0, 3, 1)], edge_steel, thrust)
ring('Lance shaft collar', (0, CY + .03, -1.870), (0, 0, 1), .052, .032, .03, steel, thrust, 24)

# ------------------------------------------------------------ grinder drum
# Forestry-mulcher construction at Atlas fidelity: a heavy yoke beam bolted
# across the coupler plate carries pivot housings outboard of the tracks. Two
# fabricated, tapered box arms (enamel side plates with lightening holes,
# secondary flanges, gussets and wear strips) hold the full-width drum under a
# ribbed debris hood with hazard edging. The drum is a welded, segmented steel
# shell with bolted end flanges and chevron rows of cutter teeth (welded base
# blocks with carbide pyramid tips). A hydraulic motor at the right pivot drives
# the drum through an enclosed chain case; big lift rams with hoses raise it.
backing_plate(grinder, 1.30, .50)
arms = part('GrinderArms', GRINDER_PIVOT, grinder)
drum = part('GrinderDrum', GRINDER_AXLE, arms)
px, py, pz = GRINDER_PIVOT; ax, ay, az = GRINDER_AXLE
ARM_X = GRINDER_HALF_WIDTH + .17
YZ = PLATE_Z - .085
# Yoke: a deep box beam across the whole front, bolted through the plate.
box('Grinder yoke beam', (0, py, YZ), (2 * ARM_X - .10, .26, .12), secondary, grinder, .018)
box('Yoke enamel face plate', (0, py, YZ - .064), (2 * ARM_X - .30, .20, .012), paint, grinder, .006)
for x in (-.9, -.6, -.3, 0.0, .3, .6, .9):
    bolt((x, py + .075, YZ - .071), (0, 0, -1), grinder, .011)
    bolt((x, py - .075, YZ - .071), (0, 0, -1), grinder, .011)
for side in (-1, 1):
    x = side * ARM_X
    # Pivot housing: a turned boss with a bolted retaining cap and grease nipple.
    turned('Arm pivot housing', (x - side * .13, py, pz), (side, 0, 0),
           [(0, .150), (.02, .165), (.20, .165), (.22, .150)], steel, grinder, 48)
    box('Pivot housing saddle', (x - side * .02, py - .05, (pz + YZ) * .5), (.24, .24, abs(pz - YZ) + .10), secondary, grinder, .016)
    for k in range(8):
        a_ = k * math.tau / 8
        bolt((x + side * .092, py + math.sin(a_) * .125, pz + math.cos(a_) * .125), (side, 0, 0), grinder, .010)
    # Work light on the yoke end.
    box('Yoke work light housing', (side * (ARM_X - .32), py + .17, YZ - .02), (.12, .08, .08), secondary, grinder, .010)
    box('Work light lens', (side * (ARM_X - .32), py + .17, YZ - .062), (.09, .05, .004), M['cyan'], grinder, .001)
# Fabricated tapered box arms, pivot to axle.
d = Vector((0, ay - py, az - pz)); L = d.length; d.normalize()
up = Vector((0, d.z, -d.y)) * -1
if up.y < 0: up = -up
def arm_point(t, h):
    base = Vector((0, py, pz)) + d * (t * L)
    return base + up * h
for side in (-1, 1):
    x = side * ARM_X
    h0, h1, w = .34, .24, .20
    # Side plates: a tapered prism in the arm plane, extruded across X.
    outline = []
    for t, sgn in ((0.0, 1), (1.0, 1), (1.0, -1), (0.0, -1)):
        q = arm_point(t, sgn * (h0 + (h1 - h0) * t) * .5)
        outline.append((q.z, q.y))
    verts = [(x - w * .5, y_, z_) for z_, y_ in outline] + [(x + w * .5, y_, z_) for z_, y_ in outline]
    mesh('Fabricated arm box', verts, [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], paint, arms, .016)
    # Top and bottom flanges and a wear strip, then lightening holes.
    for sgn in (1, -1):
        a0 = arm_point(.04, sgn * (h0 * .5 + .008)); a1 = arm_point(.96, sgn * (h1 * .5 + .008))
        beam('Arm flange', (x, a0.y, a0.z), (x, a1.y, a1.z), w + .04, .018, secondary, arms, .004)
    for k, t in enumerate((.28, .52, .74)):
        c = arm_point(t, 0)
        hr = .065 - k * .008
        cylinder('Arm lightening hole', (x + side * (w * .5 + .001), c.y, c.z), (x + side * (w * .5 - .006), c.y, c.z), hr, dark, arms, 28, 0)
        ring('Lightening hole rim', (x + side * (w * .5 + .002), c.y, c.z), (1, 0, 0), hr + .014, hr, .006, secondary, arms, 28)
    g = arm_point(.12, 0)
    box('Pivot gusset plate', (x - side * (w * .5 + .01), g.y - .02, g.z + .04), (.02, .30, .26), secondary, arms, .006)
    for t in (.18, .40, .62, .86):
        q = arm_point(t, h0 * .30)
        bolt((x + side * (w * .5 + .002), q.y, q.z), (side, 0, 0), arms, .009, low=True)
    # Hub boss and bearing cartridge at the axle.
    turned('Drum bearing cartridge', (x - side * .11, ay, az), (side, 0, 0),
           [(0, .120), (.02, .135), (.19, .135), (.21, .110)], steel, arms, 40)
    # Lift ram: a big cylinder from the yoke top to a lug on the arm.
    base = Vector((x - side * .02, py + .20, YZ - .02))
    lug = arm_point(.42, h0 * .5 + .02) + Vector((x - side * .02, 0, 0))
    box('Arm ram lug', tuple(lug + Vector((0, -.02, 0))), (.10, .08, .10), secondary, arms, .008)
    mid = base.lerp(lug, .55)
    cylinder('Arm lift cylinder barrel', tuple(base), tuple(mid), .072, steel, grinder, 32, .004)
    ring('Lift cylinder gland', tuple(mid), tuple(lug - base), .080, .045, .03, edge_steel, grinder, 32)
    cylinder('Arm lift piston rod', tuple(base.lerp(lug, .5)), tuple(lug), .040, edge_steel, arms, 24, .002)
    box('Lift cylinder base clevis', tuple(base + Vector((0, -.05, 0))), (.12, .08, .10), steel, grinder, .006)
    tube('Hydraulic hose', [tuple(base + Vector((side * .08, .02, .03))), tuple(base + Vector((side * .14, -.10, .04))), (side * (ARM_X - .12), py - .02, YZ + .02)], .016, rubber, grinder)
# Right side: hydraulic motor at the pivot and an enclosed chain case to the hub.
mx = ARM_X + .20
turned('Hydraulic drive motor', (mx - .05, py, pz), (1, 0, 0), [(0, .110), (.02, .125), (.17, .125), (.19, .095), (.21, .06)], secondary, arms, 40)
for k in range(8):
    a_ = k * math.tau / 8
    box('Motor cooling fin', (mx + .06, py + math.sin(a_) * .125, pz + math.cos(a_) * .125), (.14, .012, .03), steel, arms, .002)
tube('Motor hose', [(mx + .15, py + .05, pz), (mx + .18, py + .20, pz + .10), (ARM_X - .05, py + .22, YZ)], .018, rubber, grinder)
c0 = arm_point(0, 0); c1 = arm_point(1, 0)
beam('Chain case', (ARM_X + .15, c0.y, c0.z), (ARM_X + .15, c1.y, c1.z), .08, .30, secondary, arms, .018)
beam('Chain case enamel cover', (ARM_X + .196, c0.y, c0.z - .02), (ARM_X + .196, c1.y, c1.z + .02), .012, .22, paint, arms, .006)
for t in (.15, .5, .85):
    q = arm_point(t, 0)
    for sgn in (1, -1): bolt((ARM_X + .203, q.y + sgn * .10, q.z), (1, 0, 0), arms, .009, low=True)
turned('Hub sprocket cover', (ARM_X + .19, ay, az), (1, 0, 0), [(0, .16), (.02, .17), (.05, .15), (.06, .06)], steel, arms, 40)
# Debris hood over the top-rear of the drum: a ribbed curved shell.
HR, HW = GRINDER_RADIUS + GRINDER_SPIKE + .07, GRINDER_HALF_WIDTH + .05
arc = [math.radians(a_) for a_ in range(-30, 131, 10)]  # 0 = straight up, + toward the hull
def hood(a_, r): return (ay + math.cos(a_) * r, az + math.sin(a_) * r)
verts = []
for x in (-HW, HW):
    for a_ in arc: y_, z_ = hood(a_, HR); verts.append((x, y_, z_))
    for a_ in arc: y_, z_ = hood(a_, HR + .03); verts.append((x, y_, z_))
n = len(arc); faces = []
for i in range(n - 1):
    faces += [(i, i + 1, 2 * n + i + 1, 2 * n + i), (n + i, 3 * n + i, 3 * n + i + 1, n + i + 1)]
faces += [(0, 2 * n, 3 * n, n), (n - 1, 2 * n - 1, 4 * n - 1, 3 * n - 1)]
for i in range(n - 1):
    faces += [(i, n + i, n + i + 1, i + 1), (2 * n + i, 2 * n + i + 1, 3 * n + i + 1, 3 * n + i)]
mesh('Debris hood shell', verts, faces, paint, arms, .010)
for x in (-HW + .01, -HW * .5, 0, HW * .5, HW - .01):
    for i in range(0, n - 1, 1):
        a0, a1 = arc[i], arc[i + 1]
        y0, z0 = hood(a0, HR + .03); y1, z1 = hood(a1, HR + .03)
        beam('Hood rib', (x, y0, z0), (x, y1, z1), .03, .035, secondary, arms, .004)
for k in range(9):
    x = -HW + .12 + k * (2 * HW - .24) / 8
    y_, z_ = hood(arc[0], HR + .035)
    box('Hood hazard stripe', (x, y_ + .01, z_ - .012), (.10, .05, .012), dark if k % 2 else M['paint_edge'], arms, .002)
# Curved side skirts close the hood ends along its arc (an annular sector
# outside the drum flange), edged with a steel lip and bolted to the shell.
RIN = GRINDER_RADIUS + .075
for side in (-1, 1):
    verts = []
    for x in (side * (HW + .004), side * (HW + .026)):
        for a_ in arc: y_, z_ = hood(a_, RIN); verts.append((x, y_, z_))
        for a_ in arc: y_, z_ = hood(a_, HR + .03); verts.append((x, y_, z_))
    faces = []
    for i in range(n - 1):
        faces += [(i, n + i, n + i + 1, i + 1), (2 * n + i, 2 * n + i + 1, 3 * n + i + 1, 3 * n + i),
                  (i, i + 1, 2 * n + i + 1, 2 * n + i), (n + i, 3 * n + i, 3 * n + i + 1, n + i + 1)]
    faces += [(0, 2 * n, 3 * n, n), (n - 1, n + n - 1, 4 * n - 1, 3 * n - 1)]
    mesh('Hood side skirt', verts, faces, secondary, arms, .006)
    for i in range(n - 1):
        y0, z0 = hood(arc[i], RIN); y1, z1 = hood(arc[i + 1], RIN)
        beam('Skirt inner lip', (side * (HW + .03), y0, z0), (side * (HW + .03), y1, z1), .012, .02, steel, arms, .002)
    for a_ in arc[1:-1:3]:
        y_, z_ = hood(a_, HR - .02)
        bolt((side * (HW + .027), y_, z_), (side, 0, 0), arms, .009, low=True)
# Drum: welded segmented shell, end flanges, chevron cutter teeth.
cylinder('Drum axle', (-ARM_X - .12, ay, az), (ARM_X + .12, ay, az), .060, steel, drum, 24, .002)
cylinder('Drum shell', (-GRINDER_HALF_WIDTH, ay, az), (GRINDER_HALF_WIDTH, ay, az), GRINDER_RADIUS, gun, drum, 64, .008)
for k in range(1, 6):
    x = -GRINDER_HALF_WIDTH + k * 2 * GRINDER_HALF_WIDTH / 6
    ring('Drum segment weld bead', (x, ay, az), (1, 0, 0), GRINDER_RADIUS + .008, GRINDER_RADIUS - .01, .022, edge_steel, drum, 64)
for side in (-1, 1):
    x = side * GRINDER_HALF_WIDTH
    turned('Drum end flange', (x - side * .02, ay, az), (side, 0, 0), [(0, GRINDER_RADIUS + .05), (.04, GRINDER_RADIUS + .05), (.05, .10), (.07, .07)], steel, drum, 64)
    for k in range(10):
        a_ = k * math.tau / 10
        bolt((x + side * .031, ay + math.sin(a_) * (GRINDER_RADIUS - .04), az + math.cos(a_) * (GRINDER_RADIUS - .04)), (side, 0, 0), drum, .012)
ROWS, PER_ROW = 13, 12
for row in range(ROWS):
    t = row / (ROWS - 1)
    x = -GRINDER_HALF_WIDTH + .09 + t * (2 * GRINDER_HALF_WIDTH - .18)
    # Chevron: the phase runs outward from the centre in both directions.
    phase = abs(t - .5) * 2.2
    for k in range(PER_ROW):
        a_ = (k + (row % 2) * .5) * math.tau / PER_ROW + phase
        dvec = Vector((0, math.sin(a_), -math.cos(a_)))
        tang = Vector((0, math.cos(a_), math.sin(a_)))
        base = Vector((x, ay, az)) + dvec * GRINDER_RADIUS
        c = base + dvec * .035
        # Welded base block, then a carbide pyramid raked into the spin.
        verts = []
        for sx in (-1, 1):
            for st in (-1, 1):
                for sr in (-1, 1):
                    verts.append(tuple(c + Vector((sx * .038, 0, 0)) + tang * (st * .045) + dvec * (sr * .035)))
        mesh('Cutter tooth base block', verts, [(0, 2, 6, 4), (1, 5, 7, 3), (0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6)], steel, drum, .004)
        top = c + dvec * .035
        tip = top + dvec * (GRINDER_SPIKE - .07) - tang * .03
        quad = [top + Vector((sx * .03, 0, 0)) + tang * (st * .035) for sx, st in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        mesh('Carbide cutter tip', [tuple(q) for q in quad] + [tuple(tip)], [(3, 2, 1, 0), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], edge_steel, drum)

# Pivots stay with their groups; join each group's meshes.
MOVING = {'RamPunch': punch, 'SpearCarriage': lift, 'SpearTines': thrust, 'GrinderArms': arms, 'GrinderDrum': drum}
for group in list(kit.groups): finalize(group)
bpy.context.view_layer.update()

# ------------------------------------------------------ clearance audit
def audit():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'))
    imported = [o for o in bpy.data.objects if o not in before]
    optional = {'ArmorSideReference', 'ArmorSideHeavy', 'ArmorTop', 'ArmorFront', 'ArmorRear', 'ExhaustSmall', 'ExhaustMedium', 'ExhaustLarge', 'AtlasLifter'}
    def owner(o):
        p = o
        while p is not None:
            if p.name.split('.')[0] in optional: return p.name.split('.')[0]
            p = p.parent
        return 'base'
    bpy.context.view_layer.update()
    def tree(objs):
        verts = []; polys = []
        for o in objs:
            dg = o.evaluated_get(bpy.context.evaluated_depsgraph_get()); m = dg.to_mesh()
            off = len(verts); verts += [o.matrix_world @ v.co for v in m.vertices]
            polys += [[off + i for i in p.vertices] for p in m.polygons]; dg.to_mesh_clear()
        return BVHTree.FromPolygons(verts, polys) if polys else None
    hull = {}
    for o in imported:
        if o.type == 'MESH': hull.setdefault(owner(o), []).append(o)
    trees = {k: tree(v) for k, v in hull.items()}
    rest = {g: g.matrix_basis.copy() for g in MOVING.values()}
    def pose(label, amount):
        for g, m in rest.items(): g.matrix_basis = m.copy()
        if label == 'ram': punch.matrix_basis = rest[punch] @ Matrix.Translation(gv((0, 0, -RAM_PUNCH)) * amount)
        if label == 'spear':
            lift.matrix_basis = rest[lift] @ Matrix.Translation(gv((0, SPEAR_LIFT, 0)) * amount)
            thrust.matrix_basis = rest[thrust] @ Matrix.Translation(gv((0, 0, -SPEAR_THRUST)) * amount)
        if label == 'grinder': arms.matrix_basis = rest[arms] @ Matrix.Rotation(math.radians(GRINDER_RAISE) * amount, 4, 'X')
        bpy.context.view_layer.update()
    report = {'scope': 'Triangle-overlap of each tool at rest, half and full travel against the imported atlas_mx.glb (base and optional modules).', 'contacts': {}}
    for label, group in TOOLS.items():
        objs = [o for o in descendants(group) if o.type == 'MESH']
        for amount in (0.0, .5, 1.0):
            pose(label, amount)
            t = tree(objs)
            for hull_label, hull_tree in trees.items():
                count = len(t.overlap(hull_tree))
                if count:
                    culprits = sorted({o.name for o in objs if len(tree([o]).overlap(hull_tree))})
                    report['contacts']['%s@%.1f_vs_%s' % (label, amount, hull_label)] = {'triangles': count, 'objects': culprits[:6]}
        pose(label, 0.0)
    report['base_clear'] = not any(k.endswith('_vs_base') for k in report['contacts'])
    for o in imported: bpy.data.objects.remove(o, do_unlink=True)
    return report

clearance = audit()
print('TOOLS_CLEARANCE', json.dumps(clearance))

from atlas_surface_bake import bake_surface_atlases
surface = bake_surface_atlases(root, ram, [spear, grinder], RUNTIME, quick=QUICK, prefix='Atlas_Tools', face_wear=.74,
                               families=('Primary', 'Secondary', 'Hardware'), sizes={'Primary': 2048, 'Secondary': 1024, 'Hardware': 2048})
export_model(root, 'atlas_tools.glb', RUNTIME)
def godot(p): return [round(p[0], 5), round(p[1], 5), round(p[2], 5)]
stats = {}
for label, group in TOOLS.items():
    objs = [o for o in descendants(group) if o.type == 'MESH']
    for o in objs: o.data.calc_loop_triangles()
    stats[label] = sum(len(o.data.loop_triangles) for o in objs)
manifest = {'name': 'Atlas MX front tools', 'id': 'atlas_tools', 'runtime': 'atlas_tools.glb', 'generator': 'tools/build-atlas-tools.py',
            'authoring': 'Godot metres in the Atlas hull frame, X right Y up -Z forward; runtime factor three applied by AtlasVisual',
            'nodes': ['ToolRam', 'RamPunch', 'ToolSpear', 'SpearCarriage', 'SpearTines', 'ToolGrinder', 'GrinderArms', 'GrinderDrum'],
            'ram': {'nose_z': RN, 'facet_z': RS, 'half_width': RW, 'y': [-.44, .24], 'punch': RAM_PUNCH},
            'spear': {'lift': SPEAR_LIFT, 'thrust': SPEAR_THRUST, 'tip_z': -2.90, 'tine_x': .27, 'tine_y': CY - .13, 'lance_y': CY + .03},
            'grinder': {'pivot': godot(GRINDER_PIVOT), 'axle': godot(GRINDER_AXLE), 'radius': GRINDER_RADIUS, 'spike': GRINDER_SPIKE,
                        'half_width': GRINDER_HALF_WIDTH, 'raise_degrees': GRINDER_RAISE},
            'triangles': stats, 'clearance': clearance, 'surface_atlases': surface, 'approval': 'Pending user visual approval'}
(RUNTIME / 'atlas_tools_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('TOOLS_EXPORT', json.dumps({'triangles': stats}))
if NO_RENDER:
    print('TOOLS_COMPLETE', str(RUNTIME)); sys.exit(0)

# ------------------------------------------------------------ review renders
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'))
for o in list(bpy.data.objects):
    if o.name.split('.')[0] in ('ArmorSideReference', 'ArmorSideHeavy', 'ArmorTop', 'ArmorRear', 'ExhaustSmall', 'ExhaustMedium', 'ExhaustLarge', 'AtlasLifter'):
        for d in descendants(o): d.hide_render = True
floor = kit.material('Studio_Only', (.73, .75, .77), .0, .68)
bpy.ops.mesh.primitive_plane_add(size=200, location=gv((0, -.555, 0)))
bpy.context.object.data.materials.append(floor)
def light(name, at, energy, color, size, target=(0, .1, -1.4)):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.shape = 'DISK'; d.size = size; d.color = color
    o = bpy.data.objects.new(name, d); bpy.context.collection.objects.link(o); o.location = gv(at); o.rotation_euler = (gv(target) - o.location).to_track_quat('-Z', 'Y').to_euler()
light('Large warm key', (-3.5, 5, -5), 380, (1, .97, .90), 4)
light('Cool side reflection', (4, 2, -1), 240, (.84, .92, 1), 3)
light('Rear rim', (-1, 3, 3), 300, (1, .95, .86), 2.5)
light('Front fill', (0, 1, -5), 90, (.94, .96, 1), 3)
scene = bpy.context.scene; scene.world = scene.world or bpy.data.worlds.new('Tools studio'); scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.65, .69, .75, 1); scene.world.node_tree.nodes['Background'].inputs[1].default_value = .25
cam_data = bpy.data.cameras.new('ToolsCamera'); cam = bpy.data.objects.new('ToolsCamera', cam_data); bpy.context.collection.objects.link(cam); scene.camera = cam
scene.render.engine = 'CYCLES'; scene.cycles.samples = 24 if QUICK else 80; scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'OPTIX'; prefs.get_devices()
    for device in prefs.devices: device.use = device.type == 'OPTIX'
    scene.cycles.device = 'GPU'
except Exception: pass
scene.render.resolution_x = 1600; scene.render.resolution_y = 1200
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'
def view(name, at, target=(0, .0, -1.5), ortho=3.6):
    cam.location = gv(at); cam.rotation_euler = (gv(target) - cam.location).to_track_quat('-Z', 'Y').to_euler(); cam_data.type = 'ORTHO'; cam_data.ortho_scale = ortho
    scene.render.filepath = str(SOURCE / (name + '.png'))
    try: bpy.ops.render.render(write_still=True)
    except RuntimeError:
        # A busy GPU (other sessions rendering) falls back to the CPU.
        scene.cycles.device = 'CPU'; bpy.ops.render.render(write_still=True)
def show(tool):
    for group in TOOLS.values():
        for o in descendants(group): o.hide_render = group != tool
for label, group in TOOLS.items():
    show(group)
    view('tool_' + label + '_hero', (3.6, 2.2, -5.0))
    if not QUICK: view('tool_' + label + '_side', (5.0, .3, -1.6), target=(0, -.1, -1.7), ortho=3.0)
arms.rotation_euler.x = math.radians(GRINDER_RAISE); lift.location = lift.location + gv((0, SPEAR_LIFT, 0)) - gv((0, 0, 0))
show(grinder); view('tool_grinder_raised', (3.6, 2.2, -5.0))
show(spear); view('tool_spear_lifted', (3.6, 2.2, -5.0))
bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW / 'atlas_tools.blend'), compress=True)
print('TOOLS_COMPLETE', str(SOURCE))
