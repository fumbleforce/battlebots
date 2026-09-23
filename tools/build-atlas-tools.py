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
- Grinder: GrinderArms, two thick box-section arms on bearing housings at the
  hull cheeks, pivot about X by up to GRINDER_RAISE degrees; GrinderDrum spins
  a spiked steel cylinder about X at the arm ends, chain-driven from a hub motor.
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
GRINDER_PIVOT = (0.0, .06, -1.50)
GRINDER_AXLE = (0.0, -.12, -2.34)
GRINDER_RADIUS = .25
GRINDER_SPIKE = .12
GRINDER_HALF_WIDTH = .78
GRINDER_RAISE = 38.0

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
# Two thick box-section arms on bearing housings bolted to the coupler plate
# and hull cheek brackets, lifted by hydraulic rams; the spiked drum spins on
# their ends, chain-driven from a hub motor in the right arm.
backing_plate(grinder, 1.30, .50)
arms = part('GrinderArms', GRINDER_PIVOT, grinder)
drum = part('GrinderDrum', GRINDER_AXLE, arms)
px, py, pz = GRINDER_PIVOT; ax, ay, az = GRINDER_AXLE
ARM_X = GRINDER_HALF_WIDTH + .12
for side in (-1, 1):
    x = side * ARM_X
    box('Arm pivot bracket', (x, py - .04, PLATE_Z - .01), (.20, .34, .12), secondary, grinder, .012)
    box('Bracket tie to plate', ((x + side * -.30) * .5 + side * .15, py - .06, PLATE_Z - .01), (abs(x) - .45, .12, .08), steel, grinder, .006)
    cylinder('Arm pivot bearing housing', (x - .09, py, pz), (x + .09, py, pz), .105, steel, grinder, 32, .004)
    bolt((x + side * .095, py, pz), (side, 0, 0), grinder, .030)
    beam('Thick grinder arm', (x, py, pz), (x, ay, az), .15, .24, paint, arms, .018)
    beam('Arm wear plate', (x + side * .077, py - .02, pz - .10), (x + side * .077, ay + .02, az + .12), .008, .16, edge_steel, arms, .003)
    for k in (.3, .6):
        p = Vector((x, py, pz)).lerp(Vector((x, ay, az)), k)
        bolt((x + side * .082, p.y + .05, p.z), (side, 0, 0), arms, .010, low=True)
        bolt((x + side * .082, p.y - .05, p.z), (side, 0, 0), arms, .010, low=True)
    cylinder('Drum axle bearing', (x - .09, ay, az), (x + .09, ay, az), .090, steel, arms, 32, .004)
    # Hydraulic lift ram from the plate top to the arm's mid-span.
    top = (side * (ARM_X - .02), .26, PLATE_Z - .05)
    mid = Vector((x, py, pz)).lerp(Vector((x, ay, az)), .45) + Vector((0, .13, 0))
    cylinder('Arm lift cylinder', top, tuple(Vector(top).lerp(mid, .55)), .048, steel, grinder, 24, .003)
    cylinder('Arm lift ram rod', tuple(Vector(top).lerp(mid, .5)), tuple(mid), .026, edge_steel, arms, 20, .002)
    box('Lift ram clevis', tuple(mid), (.07, .07, .07), steel, arms, .006)
# Chain drive: a housing along the right arm and a hub motor outboard.
box('Chain drive housing', (ARM_X + .105, (py + ay) * .5, (pz + az) * .5), (.05, .20, .80), secondary, arms, .010)
cylinder('Drum hub drive motor', (ARM_X + .13, ay, az), (ARM_X + .26, ay, az), .10, secondary, arms, 32, .010)
for k in range(6):
    a = k * math.tau / 6
    box('Motor cooling fin', (ARM_X + .20, ay + math.sin(a) * .10, az + math.cos(a) * .10), (.10, .02, .02), steel, arms, .002)
cylinder('Drum axle', (-ARM_X - .05, ay, az), (ARM_X + .05, ay, az), .050, steel, drum, 24, .002)
cylinder('Spiked drum core', (-GRINDER_HALF_WIDTH, ay, az), (GRINDER_HALF_WIDTH, ay, az), GRINDER_RADIUS, gun, drum, 48, .006)
for x in (-GRINDER_HALF_WIDTH, GRINDER_HALF_WIDTH):
    cylinder('Drum end flange', (x - .02, ay, az), (x + .02, ay, az), GRINDER_RADIUS + .045, steel, drum, 48, .004)
for x in (-.26, .26):
    ring('Drum reinforcing band', (x, ay, az), (1, 0, 0), GRINDER_RADIUS + .012, GRINDER_RADIUS - .01, .05, edge_steel, drum, 48)
ROWS, PER_ROW = 11, 12
for row in range(ROWS):
    x = -GRINDER_HALF_WIDTH + .07 + row * (2 * GRINDER_HALF_WIDTH - .14) / (ROWS - 1)
    for k in range(PER_ROW):
        a = (k + (row % 2) * .5) * math.tau / PER_ROW + row * .12
        d = Vector((0, math.sin(a), -math.cos(a)))
        base = Vector((x, ay, az)) + d * (GRINDER_RADIUS - .01)
        turned('Hardened grinder spike', tuple(base), tuple(d), [(0, .040), (.025, .036), (GRINDER_SPIKE, 0)], edge_steel, drum, 12)

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
    scene.render.filepath = str(SOURCE / (name + '.png')); bpy.ops.render.render(write_still=True)
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
