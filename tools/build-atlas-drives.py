"""Atlas MX alternative running gear: large off-road wheels and hydraulic legs.

Blender 5.2 --background --python tools/build-atlas-drives.py [-- --quick] [-- --no-render]

Construction brief (Godot metres, X right, Y up, -Z forward, Atlas hull origin):
- The approved hull, mounts and collision envelope are unchanged. Its tracked
  sponsons (hood, corner sockets, skirts, backbone plate and main axle bosses)
  are reused exactly as exported in atlas_mx.glb; only the track-specific road
  roller stubs, swing arms and return-roller axle are removed. The trimmed
  sponsons keep their approved hull maps.
- Large wheels (drive part standard_wheels): four 0.93 m lugged off-road tyres
  inside the former track envelope (X .775..1.155, bottom Y -.552, so the
  shared ground depth .555 is unchanged). Each wheel turns on a static finned
  hub motor bolted to the existing main axle boss at Z=+-.76.
- Hydraulic legs (drive part walker): four yaw/pitch/pitch legs whose slewing
  mounts are bolted to the same axle bosses: a planetary hip drive pitches the
  femur and a hydraulic ram folds the knee. Feet plant at the shared
  WalkerDrive footholds; the runtime solver (AtlasLegs) poses the coxa, femur,
  tibia, foot and knee ram from the published frames below.
- New parts reuse the approved Atlas material classes and are baked by
  atlas_surface_bake.py into a separate Atlas_Drive* map set, so the approved
  hull and turret maps stay untouched.

--quick writes an isolated reduced-resolution draft under
battlebots/exports/atlas-drives-preview. The default writes the runtime GLB,
maps, manifest and data/atlas_drive_rig.json, and review renders under
art_source/atlas_drives. Iteration flags (preview folder only): --no-bake
(geometry and audit, flat materials), --audit-only (stop after the clearance
audit), --stage-wheels / --stage-legs (quick unbaked review renders) and
--profile (per-part wheel triangle counts).
"""
import bpy, bmesh, math, json, random, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/atlas_drives'
RUNTIME = ROOT / 'battlebots/assets/models/atlas_runtime'
HULL = ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'
PREVIEW = ROOT / 'battlebots/exports/atlas-drives-preview'
QUICK = '--quick' in sys.argv
NO_RENDER = '--no-render' in sys.argv
NO_BAKE = '--no-bake' in sys.argv
PREVIEW.mkdir(parents=True, exist_ok=True)
(PREVIEW / '.gdignore').write_text('')
if QUICK or NO_BAKE:
    SOURCE = PREVIEW / 'source'
    RUNTIME = PREVIEW / 'runtime'
for path in [SOURCE, RUNTIME]: path.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
random.seed(47047)

# ------------------------------------------------------ published contract
# Mirrored in AtlasGeometry (runtime) and written to atlas_drives_manifest.json.
WHEEL_RADIUS = .467          # lug tips; bottom at Y -.552 like the track shoes
WHEEL_CENTER = (.945, -.085, .76)
WHEEL_WIDTH = .36
LEG_YAW_AXIS = (1.065, .76)   # X, Z of the vertical slewing axis (per side/end sign)
LEG_YAW_Y = -.03             # height of the femur pitch pin
COXA_REACH = .140            # slewing axis -> femur pitch pin, along the leg heading
FEMUR = .60
TIBIA = .80
ANKLE = .16                  # ankle ball centre above the sole contact
# Feet plant at the shared WalkerDrive footholds (MvpBot probes at 40% of the
# catalogue chassis size plus FOOT_SPREAD, at RIDE_HEIGHT), read from source.
import re
_walker = (ROOT / 'battlebots/scripts/simulation/walker_drive.gd').read_text()
def _walker_const(name): return float(re.search(r'const %s := ([0-9.]+) \* BotScale.FACTOR' % name, _walker).group(1))
_atlas_size = next(p for p in json.loads((ROOT / 'battlebots/data/mvp_parts.json').read_text())['parts'] if p['id'] == 'atlas_mx')['size']
FOOTHOLD_FRACTION = .4
BOT_SCALE_FACTOR = 3.0      # BotScale.FACTOR: catalogue size = source metres x 3
FOOT_NEUTRAL = (round(_atlas_size[0] / BOT_SCALE_FACTOR * FOOTHOLD_FRACTION + _walker_const('FOOT_SPREAD'), 4), -_walker_const('RIDE_HEIGHT'),
                round(_atlas_size[2] / BOT_SCALE_FACTOR * FOOTHOLD_FRACTION, 4))
# Coxa yaw stops, degrees from straight fore/aft: the inner fork plate clears
# the axle boss up to 4 degrees inboard; outboard travel is limited by the skirt.
COXA_YAW_LIMITS = (-4.0, 60.0)
# Highest ankle rise above stance the legs fold to; WalkerDrive lifts the hull
# onto a higher foothold, so taller rises are brief. Beyond it the foot stays
# at this height rather than folding the tibia into the slewing mount.
ANKLE_RISE_LIMIT = .30

def gv(p): return Vector((p[0], -p[2], p[1]))
def gd(v): return (v.x, v.z, -v.y)
def linear(v): return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
def rgba(c): return tuple(linear(v) for v in c) + (1,)

def material(name, color, metal=.0, rough=.4, emission=0):
    m = bpy.data.materials.new(name); m.use_nodes = True; m.diffuse_color = rgba(color)
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = rgba(color)
    bs.inputs['Metallic'].default_value = metal; bs.inputs['Roughness'].default_value = rough
    if emission:
        bs.inputs['Emission Color'].default_value = rgba(color); bs.inputs['Emission Strength'].default_value = emission
    return m

# Approved Atlas V5 values. Names keep the runtime paint-channel contract.
PRIMARY = (.86, .51, .055)
paint = material('Atlas_PaintPrimary', PRIMARY, .08, .66)
paint_edge = material('Atlas_PaintPrimaryEdge', PRIMARY, .08, .66)
secondary = material('Atlas_PaintSecondary', (.205, .225, .235), .08, .61)
steel = material('Atlas_Metal', (.52, .55, .56), .92, .36)
edge_steel = material('Atlas_EdgeSteel', (.64, .65, .63), .95, .30)
oxidized = material('Atlas_OxidizedMetal', (.34, .315, .27), .80, .57)
rubber = material('Atlas_Rubber', (.045, .055, .06), .0, .84)
dark = material('Atlas_Recess', (.026, .035, .039), .42, .51)
# Hard-chromed ram rods: brighter and smoother than machined steel.
chrome = material('Atlas_ChromeRod', (.70, .72, .72), .98, .16)
# Tyre compound: slightly lighter, rougher and more worn than seal rubber.
tyre = material('Atlas_TyreRubber', (.062, .066, .068), .0, .90)
tyre['atlas_grime'] = .22   # dusty, dried-mud patches (baker option)
brass = material('Atlas_ConnectorBrass', (.61, .40, .15), .8, .3)

groups = {}
def part(name, at=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(obj)
    obj.empty_display_type = 'ARROWS'; obj.empty_display_size = .1
    obj.location = gv(at)
    if parent: obj.parent = parent; obj.matrix_parent_inverse = parent.matrix_world.inverted()
    groups[obj] = []; bpy.context.view_layer.update(); return obj

def mesh(name, verts, faces, mat, group, bevel=0, smooth=None):
    data = bpy.data.meshes.new(name); data.from_pydata([gv(p) for p in verts], [], faces); data.update()
    bm = bmesh.new(); bm.from_mesh(data); bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(data); bm.free()
    obj = bpy.data.objects.new(name, data); bpy.context.collection.objects.link(obj); data.materials.append(mat)
    uv = data.uv_layers.new(name='UVMap')
    for poly in data.polygons:
        axis = max(range(3), key=lambda i: abs(poly.normal[i])); axes = [i for i in range(3) if i != axis]
        coords = [data.vertices[i].co for i in poly.vertices]
        mins = [min(p[a] for p in coords) for a in axes]; spans = [max(p[a] for p in coords) - mins[i] for i, a in enumerate(axes)]
        for j, loop in enumerate(poly.loop_indices):
            uv.data[loop].uv = [(coords[j][a] - mins[i]) / max(.001, spans[i]) for i, a in enumerate(axes)]
        poly.use_smooth = bool(bevel) if smooth is None else smooth
    if bevel:
        mod = obj.modifiers.new('Forged edge radii', 'BEVEL'); mod.width = bevel; mod.segments = 3 if bevel >= .018 else 1
        mod.limit_method = 'ANGLE'; mod.angle_limit = .58
        if mat == paint:
            data.materials.append(paint_edge); mod.material = len(data.materials) - 1
        mod.harden_normals = True
        mod = obj.modifiers.new('Weighted machining normals', 'WEIGHTED_NORMAL'); mod.keep_sharp = True; mod.weight = 40
    groups[group].append(obj); return obj

def prism(name, outline, y0, y1, mat, group, bevel=.009, top=None):
    """Closed section between a lower and (optionally tapered) upper XZ outline."""
    top = top or outline; n = len(outline)
    verts = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in top]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)

def slab(name, outline, axis, d0, d1, mat, group, bevel=.006, frame=None):
    """Extrude a 2D outline (u, v) along a frame's third axis from d0 to d1.
    frame = (origin, u_axis, v_axis, w_axis) in Godot metres."""
    o, u, v, w = [Vector(a) for a in frame]
    n = len(outline)
    verts = [tuple(o + u * a + v * b + w * d) for d in (d0, d1) for a, b in outline]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)

def loft(name, levels, mat, group, bevel=.009):
    """Closed shell through (y, outline) levels with matching vertex counts."""
    n = len(levels[0][1]); verts = [(x, y, z) for y, outline in levels for x, z in outline]
    faces = [tuple(reversed(range(n))), tuple(range((len(levels) - 1) * n, len(levels) * n))]
    for k in range(len(levels) - 1):
        faces += [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)

def box(name, p, s, mat, group, b=.009):
    p = Vector(p); s = Vector(s) * .5
    return mesh(name, [tuple(p + Vector((x * s.x, y * s.y, z * s.z))) for x, y, z in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]],
                [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)], mat, group, b)

def _frame(axis):
    d = Vector(axis).normalized(); t = d.cross(Vector((0, 1, 0)))
    if t.length < .01: t = d.cross(Vector((1, 0, 0)))
    t.normalize(); return d, t, d.cross(t)

def cylinder(name, a, b, r, mat, group, n=24, bevel=.003):
    a = Vector(a); b = Vector(b); d, t, bit = _frame(b - a)
    verts = [tuple(p + (t * math.cos(i * math.tau / n) + bit * math.sin(i * math.tau / n)) * r) for p in [a, b] for i in range(n)]
    obj = mesh(name, verts, [tuple(reversed(range(n))), tuple(range(n, n * 2))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)], mat, group, bevel)
    for f in obj.data.polygons: f.use_smooth = len(f.vertices) == 4
    return obj

def ring(name, p, axis, outer, inner, width, mat, group, n=32):
    p = Vector(p); d, t, bit = _frame(axis)
    verts = [tuple(p + d * dep + (t * math.cos(i * math.tau / n) + bit * math.sin(i * math.tau / n)) * r)
             for dep, r in [(-width / 2, outer), (width / 2, outer), (-width / 2, inner), (width / 2, inner)] for i in range(n)]
    faces = []
    for i in range(n):
        j = (i + 1) % n; faces += [(i, j, j + n, i + n), (i + 2 * n, i + 3 * n, j + 3 * n, j + 2 * n), (i, i + 2 * n, j + 2 * n, j), (i + n, j + n, j + 3 * n, i + 3 * n)]
    obj = mesh(name, verts, faces, mat, group)
    for i, poly in enumerate(obj.data.polygons): poly.use_smooth = i % 4 < 2
    return obj

def turned(name, p, axis, profile, mat, group, n=32, hex_socket=False, open_end=False):
    """Lathed section; profile tuples are axial depth and radius."""
    p = Vector(p); d, t, bit = _frame(axis)
    verts = []
    for j, (dep, radius) in enumerate(profile):
        for i in range(n):
            angle = i * math.tau / n
            radial = t * math.cos(angle) + bit * math.sin(angle)
            if hex_socket and j >= len(profile) - 2:
                sector = i * 6 / n; corner = math.floor(sector); fraction = sector - corner
                a = corner * math.tau / 6; b = (corner + 1) * math.tau / 6
                radial = (t * math.cos(a) + bit * math.sin(a)) * (1 - fraction) + (t * math.cos(b) + bit * math.sin(b)) * fraction
            verts.append(tuple(p + d * dep + radial * radius))
    faces = [] if open_end else [tuple(reversed(range(n))), tuple(range((len(profile) - 1) * n, len(profile) * n))]
    for j in range(len(profile) - 1):
        for i in range(n): faces.append((j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i))
    obj = mesh(name, verts, faces, mat, group)
    for face in obj.data.polygons: face.use_smooth = len(face.vertices) == 4
    if hex_socket:
        for face in list(obj.data.polygons)[-n:]: face.use_smooth = False
    return obj

def bolt(at, axis, group, r=.012, low=False, n=18):
    # low: countersunk hardware, its crown only ~2 mm proud. n: radial segments
    # (a multiple of six keeps the hex socket regular).
    p = Vector(at); d = Vector(axis).normalized(); h = .45 if low else 1.0
    if low: p = p - d * .002
    cylinder('Fastener recessed steel washer', p - d * .003, p + d * .001, r * 1.34, oxidized, group, n, .001)
    turned('Rounded machined button fastener', p, d, [(.000, r), (.003 * h, r), (.008 * h, r * .88), (.011 * h, r * .62), (.011 * h, r * .35), (.005 * h, r * .35)], steel, group, n, hex_socket=True)
    cylinder('Recessed fastener socket floor', p + d * .0048 * h, p + d * .0051 * h, r * .35, dark, group, 6, 0)

def hex_nut(at, axis, group, r=.014, height=.012):
    """Wheel lug nut: flanged hex with a chamfered crown and threaded stud end."""
    p = Vector(at); d, t, bit = _frame(axis)
    cylinder('Lug nut flange', p, p + d * .003, r * 1.25, steel, group, 12, .001)
    n = 6; verts = []
    for dep, k in ((.003, 1.0), (height - .002, 1.0), (height, .82)):
        for i in range(n):
            a = i * math.tau / n + math.pi / 6
            verts.append(tuple(p + d * dep + (t * math.cos(a) + bit * math.sin(a)) * r * k))
    faces = [tuple(reversed(range(n))), tuple(range(2 * n, 3 * n))]
    for j in range(2):
        for i in range(n): faces.append((j * n + i, j * n + (i + 1) % n, (j + 1) * n + (i + 1) % n, (j + 1) * n + i))
    obj = mesh('Hex wheel lug nut', verts, faces, edge_steel, group, .0012)
    turned('Threaded wheel stud end', p + d * height, d, [(0, r * .42), (.004, r * .40), (.006, r * .30), (.0065, 0)], oxidized, group, 8)
    return obj

def tube(name, points, r, mat, group, n=12):
    for a, b in zip(points, points[1:]): cylinder(name, a, b, r, mat, group, n, 0)

def finalize(group, name=None):
    objects = groups[group]
    if not objects: return None
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        bpy.context.view_layer.objects.active = obj; obj.select_set(True)
        for mod in list(obj.modifiers): bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]; bpy.ops.object.join(); obj = bpy.context.object
    obj.data.transform(group.matrix_world.inverted() @ obj.matrix_world)
    obj.parent = group; obj.matrix_parent_inverse = Matrix.Identity(4); obj.matrix_basis = Matrix.Identity(4)
    obj.name = name or group.name + 'Surface'; obj.data.name = obj.name
    bpy.ops.object.select_all(action='DESELECT'); groups[group] = [obj]; return obj

def descendants(obj):
    result = [obj]
    for ch in obj.children: result += descendants(ch)
    return result

def instance(template, name, parent, matrix):
    """Linked copy of a finalized template mesh: shared data, shared bake UVs."""
    obj = template.copy(); obj.name = name; bpy.context.collection.objects.link(obj)
    obj.parent = parent; obj.matrix_parent_inverse = Matrix.Identity(4); obj.matrix_basis = matrix
    return obj

# ------------------------------------------------------------- hierarchy
root = part('AtlasDrives')
sponsons = part('Sponsons', parent=root)
wheels = part('WheelsLarge', parent=root)
legs = part('Legs', parent=root)

# ------------------------------------------------ approved sponson reuse
# Import the approved hull, keep its two sponson surfaces and delete only the
# components that belong to the track mechanism (found by connectivity and
# their published positions). Their materials still reference the hull maps.
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=str(HULL))
imported = [o for o in bpy.data.objects if o not in before]
removed_components = {}
sponson_objects = {}
for side, label in ((-1, 'Left'), (1, 'Right')):
    source = bpy.data.objects['Drive%sSurface' % label]
    obj = source.copy(); obj.data = source.data.copy(); bpy.context.collection.objects.link(obj)
    obj.parent = None; obj.matrix_world = source.matrix_world.copy()
    me = obj.data; M = obj.matrix_world
    parent_of = list(range(len(me.vertices)))
    def find(a):
        while parent_of[a] != a: parent_of[a] = parent_of[parent_of[a]]; a = parent_of[a]
        return a
    seen = {}
    for v in me.vertices:
        key = tuple(round(c * 20000) for c in (M @ v.co))
        if key in seen: parent_of[find(v.index)] = find(seen[key])
        else: seen[key] = v.index
    for poly in me.polygons:
        vs = list(poly.vertices)
        for v in vs[1:]: parent_of[find(v)] = find(vs[0])
    components = {}
    for poly in me.polygons: components.setdefault(find(poly.vertices[0]), []).append(poly.index)
    drop = []
    for faces in components.values():
        points = [gd(M @ me.vertices[v].co) for f in faces for v in me.polygons[f].vertices]
        lo = [min(p[i] for p in points) for i in range(3)]; hi = [max(p[i] for p in points) for i in range(3)]
        centre = [(lo[i] + hi[i]) * .5 for i in range(3)]
        roller = .70 < abs(centre[0]) < .96 and hi[1] < -.10
        return_roller = abs(hi[0]) < .86 and abs(centre[2]) < .05 and .15 < centre[1] < .22
        if roller or return_roller: drop += faces
    removed_components[label] = len(drop)
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in drop], context='FACES')
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS'); bm.to_mesh(me); bm.free()
    obj.name = 'Sponson' + label; me.name = obj.name
    obj.parent = sponsons; obj.matrix_parent_inverse = sponsons.matrix_world.inverted()
    sponson_objects[side] = obj
for o in imported: bpy.data.objects.remove(o, do_unlink=True)
print('SPONSON_TRIM', json.dumps(removed_components))

# ----------------------------------------------------------- large wheel
# One left-hand wheel is authored at the origin: axle along X, the outer face
# toward -X. The runtime spins its pivot about X; right wheels are the same
# mesh turned 180 degrees about Y, so the directional tread still reads.
wheel_t = part('WheelTemplate')
hub_t = part('HubMotorTemplate')
W = WHEEL_WIDTH; R_BEAD = .285; R_CROWN = .440
def ax(a):  # axial position from the inner sidewall (a=0) to the outer (a=W)
    return W * .5 - a
def carcass_radius(a):
    """Carcass section: rounded shoulders into a flat crown."""
    edge = max(0.0, min(a, W - a))
    if edge >= .05: return R_CROWN
    k = edge / .05
    return R_BEAD + .03 + (R_CROWN - R_BEAD - .03) * math.sin(k * math.pi / 2) ** .55
profile = []
for i in range(19):
    a = W * i / 18
    profile.append((ax(a), carcass_radius(a)))
# Lathe depth runs along +X, so profiles pass ax(a) directly.
turned('Off-road tyre carcass', (0, 0, 0), (1, 0, 0),
       [(ax(0), R_BEAD - .004)] + profile + [(ax(W), R_BEAD - .004)],
       tyre, wheel_t, 72, open_end=True)
# Sidewall rim guard ribs (bead protectors), both faces.
for a, sgn in ((.004, 1), (W - .004, -1)):
    ring('Moulded bead protector rib', (ax(a), 0, 0), (1, 0, 0), R_BEAD + .042, R_BEAD + .018, .010, tyre, wheel_t, 48)
# Lugged tread: 18 pitches, two staggered chevron blocks per pitch, wrapping
# over the shoulders onto the sidewalls. Each block follows the carcass.
PITCHES = 20; R_TIP = WHEEL_RADIUS
def lug(s0, s1, a0, a1, skew, name, na=4, ns=2):
    """Block between arc positions s (radians) and axial a, skewed chevron.
    na/ns: grid steps across the tread and around the tyre."""
    top, bot = [], []
    for j in range(na + 1):
        a = a0 + (a1 - a0) * j / na
        shift = skew * (a - a0) / max(1e-6, (a1 - a0))
        base = carcass_radius(min(max(a, .0), W)) - .006
        edge = max(0.0, min(a, W - a))
        # Shoulder blocks wrap onto the sidewall as a raised skin, not paddles.
        tip = min(R_TIP - max(0.0, .045 - edge) * .55, base + .032)
        for i in range(ns + 1):
            s = s0 + (s1 - s0) * i / ns + shift
            # Slight draft: the tread face is narrower than the root.
            mid = (s0 + s1) * .5 + shift; s_top = mid + (s - mid) * .90
            top.append((ax(a), tip * math.cos(s_top), tip * math.sin(s_top)))
            bot.append((ax(a), base * math.cos(s), base * math.sin(s)))
    cols = ns + 1; n = len(top); verts = top + bot; faces = []
    for j in range(na):
        for i in range(ns):
            q = (j * cols + i, j * cols + i + 1, (j + 1) * cols + i + 1, (j + 1) * cols + i)
            faces.append(q); faces.append(tuple(reversed([k + n for k in q])))
    for j in range(na):  # the two circumferential walls
        faces.append((j * cols, (j + 1) * cols, (j + 1) * cols + n, j * cols + n))
        faces.append((j * cols + ns + n, (j + 1) * cols + ns + n, (j + 1) * cols + ns, j * cols + ns))
    for i in range(ns):  # the two axial ends
        faces.append((i + 1, i, i + n, i + 1 + n))
        last = na * cols
        faces.append((last + i, last + i + 1, last + i + 1 + n, last + i + n))
    return mesh(name, verts, faces, tyre, wheel_t, .0035)
pitch = math.tau / PITCHES
for k in range(PITCHES):
    s = k * pitch
    lug(s, s + pitch * .42, .006, W * .5 - .006, pitch * .24, 'Tread lug block inner')
    lug(s + pitch * .5, s + pitch * .92, W * .5 + .006, W - .006, -pitch * .24, 'Tread lug block outer')
    # Centre tie bar joins alternating blocks, as on heavy mud-terrain tyres.
    lug(s + pitch * .30, s + pitch * .62, W * .5 - .03, W * .5 + .03, 0, 'Tread centre tie bar', 1, 1)

# Steel wheel: rim barrel, flanges, slotted dish and bolted beadlock ring.
rim = [(ax(-.004), R_BEAD + .018), (ax(.004), R_BEAD + .020), (ax(.012), R_BEAD - .004), (ax(.08), R_BEAD - .012),
       (ax(.13), R_BEAD - .052), (ax(.23), R_BEAD - .052), (ax(.28), R_BEAD - .012), (ax(W - .012), R_BEAD - .004),
       (ax(W - .004), R_BEAD + .020), (ax(W + .004), R_BEAD + .018), (ax(W + .004), R_BEAD - .016),
       (ax(.23), R_BEAD - .064), (ax(.13), R_BEAD - .064), (ax(-.004), R_BEAD - .016)]
turned('Painted rim barrel', (0, 0, 0), (1, 0, 0), rim + rim[:1], paint, wheel_t, 72, open_end=True)
# Beadlock: machined ring clamping the outer bead, 24 bolts.
ring('Machined beadlock ring', (ax(W + .014), 0, 0), (1, 0, 0), R_BEAD + .030, R_BEAD - .016, .020, steel, wheel_t, 96)
for i in range(18):
    a = i * math.tau / 18 + math.tau / 36
    bolt((ax(W + .024), math.cos(a) * (R_BEAD + .008), math.sin(a) * (R_BEAD + .008)), (-1, 0, 0), wheel_t, .0085, n=12)
# Dish: an inner hub disc and an outer mounting ring joined by six forged
# spokes. The windows between them are real openings onto the hub motor.
DISH = ax(W - .052)
def sector(r0, r1, a0, a1, steps):
    pts = [(r1 * math.cos(a0 + (a1 - a0) * i / steps), r1 * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]
    pts += [(r0 * math.cos(a1 - (a1 - a0) * i / steps), r0 * math.sin(a1 - (a1 - a0) * i / steps)) for i in range(steps + 1)]
    return pts
ring('Dish outer mounting ring', (DISH, 0, 0), (1, 0, 0), R_BEAD - .010, .225, .024, paint, wheel_t, 96)
ring('Dish hub disc', (DISH, 0, 0), (1, 0, 0), .142, .060, .030, paint, wheel_t, 64)
for k in range(6):
    c = k * math.tau / 6
    spoke = sector(.130, .232, c - .21, c + .21, 5)
    # A tapered, slightly dished spoke: thicker at the hub.
    slab('Forged wheel spoke', [(u, v) for u, v in spoke], None, -.016, .016, paint, wheel_t, .006,
         frame=((DISH, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0)))
# Hub: raised centre, eight lug nuts, domed machined hub cap (after the
# approved sprocket caps) seated in an oxidised retaining collar.
turned('Wheel hub centre', (DISH - .015, 0, 0), (-1, 0, 0), [(0, .118), (.020, .118), (.030, .110), (.034, .090), (.034, .0)], secondary, wheel_t, 64)
for i in range(8):
    a = i * math.tau / 8
    hex_nut((DISH - .049, math.cos(a) * .088, math.sin(a) * .088), (-1, 0, 0), wheel_t, .0125, .014)
ring('Hub cap retaining collar', (DISH - .052, 0, 0), (1, 0, 0), .068, .056, .012, oxidized, wheel_t, 48)
turned('Domed machined hub cap', (DISH - .052, 0, 0), (-1, 0, 0), [(0, .058), (.012, .057), (.030, .048), (.044, .030), (.050, .0)], edge_steel, wheel_t, 48)
if '--profile' in sys.argv:
    tally = {}
    dg = bpy.context.evaluated_depsgraph_get()
    for o in groups[wheel_t]:
        m = o.evaluated_get(dg).to_mesh(); m.calc_loop_triangles()
        key = o.name.split('.')[0]; tally[key] = tally.get(key, 0) + len(m.loop_triangles); o.evaluated_get(dg).to_mesh_clear()
    print('WHEEL_PROFILE', json.dumps(sorted(tally.items(), key=lambda kv: -kv[1])))
wheel_mesh = finalize(wheel_t, 'AtlasWheelLarge')

# Static hub motor: bolted to the approved main axle boss (outer end X .94),
# a finned drum with a brake caliper, visible through the spoke windows.
hx1 = -1.030   # left side; the drum ends 11 mm inside the spoke dish
cylinder('Hub motor axle adapter', (-.905, -.085, 0), (-.955, -.085, 0), .092, secondary, hub_t, 40, .004)
for i in range(6):
    a = i * math.tau / 6
    bolt((-.957, -.085 + math.cos(a) * .072, math.sin(a) * .072), (-1, 0, 0), hub_t, .008, n=12)
cylinder('Finned hub motor drum', (-.955, -.085, 0), (hx1, -.085, 0), .182, secondary, hub_t, 64, .006)
for k in range(5):
    x = -.965 - k * .014
    ring('Hub motor cooling fin', (x, -.085, 0), (1, 0, 0), .205, .180, .006, secondary, hub_t, 64)
turned('Hub motor bearing cap', (hx1, -.085, 0), (-1, 0, 0), [(0, .150), (.008, .150), (.014, .128), (.016, .06), (.016, 0)], steel, hub_t, 48)
# Brake caliper on the drum top, with a braided line to the hood underside.
box('Brake caliper body', (-.985, .105, 0), (.06, .045, .12), oxidized, hub_t, .008)
for dz in (-.035, .035): bolt((-1.016, .105, dz), (-1, 0, 0), hub_t, .007, n=12)
hub_mesh = finalize(hub_t, 'AtlasHubMotor')

WHEEL_NODES = {}
for side, sl in ((-1, 'L'), (1, 'R')):
    for end, el in ((-1, 'Front'), (1, 'Rear')):
        centre = (side * WHEEL_CENTER[0], WHEEL_CENTER[1], end * WHEEL_CENTER[2])
        pivot = part('Wheel_%s_%s' % (sl, el), centre, wheels)
        spin = Matrix.Identity(4) if side < 0 else Matrix.Rotation(math.pi, 4, 'Z')
        instance(wheel_mesh, 'WheelLarge_%s_%s' % (sl, el), pivot, spin)
        mount = Matrix.Translation(gv((0, 0, end * WHEEL_CENTER[2]))) @ (Matrix.Identity(4) if side < 0 else Matrix.Rotation(math.pi, 4, 'Z'))
        instance(hub_mesh, 'HubMotor_%s_%s' % (sl, el), wheels, mount)
        WHEEL_NODES['Wheel_%s_%s' % (sl, el)] = centre
del groups[wheel_t], groups[hub_t]
for obj in (wheel_mesh, hub_mesh, wheel_t, hub_t): bpy.data.objects.remove(obj, do_unlink=True)

# ------------------------------------------------------------ hydraulic legs
# Parts are authored once in canonical frames (Godot metres) and instanced per
# leg. Segment frames: +Y runs from the joint pin along the segment, the pin
# is local Z, and local X is the segment's top (femur) or outer face (tibia).
# The runtime (AtlasLegs) and pose() below build the same frames:
#   h = horizontal heading slewing axis -> ankle, hinge Z = up x h,
#   segment X = Y x Z; coxa X = h, Y = up; foot Y = ground normal, X = heading.
T = 1.35                     # section scale: Atlas-weight members, lengths unchanged
# The femur pitches on a planetary hip drive on the coxa fork's outboard plate:
# no fixed-eye ram can cover the femur's swing across the terrain envelope.
HIP_DRIVE_DEPTH = .10        # outboard protrusion of the drive beyond the fork plate
KNEE_FEMUR = (.115, .10)     # knee ram eye on the femur top (X, Y)
KNEE_TIBIA = (.08, -.15)     # knee ram eye on the tibia horn (X, Y), above the knee
mount_t = part('LegMountTemplate'); coxa_t = part('LegCoxaTemplate'); femur_t = part('LegFemurTemplate')
tibia_t = part('LegTibiaTemplate'); foot_t = part('LegFootTemplate')

def pin(group, at, half, r, nut=True):
    x, y = at
    cylinder('Hardened joint pin', (x, y, -half), (x, y, half), r, edge_steel, group, 24, .002)
    if nut:
        for sgn in (-1, 1):
            turned('Castellated pin retaining nut', (x, y, sgn * half), (0, 0, sgn), [(0, r * 1.3), (.008, r * 1.3), (.012, r * 1.1), (.013, 0)], steel, group, 24)

def plate_xy(name, outline, z0, z1, mat, group, bevel=.004):
    """Plate in the XY plane of a canonical frame, extruded along Z."""
    return slab(name, outline, None, z0, z1, mat, group, bevel, frame=((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)))

def rounded(points_before, centre, radius, a0, a1, points_after, steps=10):
    arc = [(centre[0] + math.cos(a0 + (a1 - a0) * i / steps) * radius, centre[1] + math.sin(a0 + (a1 - a0) * i / steps) * radius) for i in range(steps + 1)]
    return points_before + arc + points_after

def section(hx, hz, c):
    """Chamfered rectangular beam section (x, z), c = corner chamfer."""
    return [(-hx + c, -hz), (hx - c, -hz), (hx, -hz + c), (hx, hz - c), (hx - c, hz), (-hx + c, hz), (-hx, hz - c), (-hx, -hz + c)]

# Static slewing mount bolted to the approved axle boss end face (local X
# WEB = hull X .94). Two bearing collars carry the coxa spindle.
WEB = .94 - LEG_YAW_AXIS[0]
# Bearing collar centres: spread above and below the pin so the femur and
# lift ram clear them across the terrain envelope.
UPPER_COLLAR, LOWER_COLLAR = .17, -.27
box('Slewing mount web plate', (WEB + .008, (UPPER_COLLAR + LOWER_COLLAR) * .5, 0), (.018, UPPER_COLLAR - LOWER_COLLAR + .26, .22), secondary, mount_t, .004)
for y in (UPPER_COLLAR, LOWER_COLLAR):
    ring('Slewing bearing collar', (0, y, 0), (0, 1, 0), .100, .062, .056, steel, mount_t, 48)
    box('Collar support arm', ((WEB + .018 - .05) * .5, y, 0), (-WEB - .018 + .05, .056, .13), secondary, mount_t, .006)
    cylinder('Collar grease nipple', (.07, y + .022, .07), (.08, y + .032, .08), .006, brass, mount_t, 10, 0)
for y in (-.13, .03):
    for z in (-.075, .075):
        bolt((WEB + .018, y, z), (1, 0, 0), mount_t, .011)
# Triangular stiffeners above the upper arm and below the lower arm, outside
# the femur and ram sweep between the collars.
for sgn in (-1, 1):
    for y0, y1 in ((UPPER_COLLAR + .028, UPPER_COLLAR + .125), (LOWER_COLLAR - .028, LOWER_COLLAR - .125)):
        slab('Web stiffening gusset', [(WEB + .018, y0), (WEB + .018, y1), (-.07, y0)], None, sgn * .05 - .006, sgn * .05 + .006, secondary, mount_t, .002,
             frame=((0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1)))

# Coxa: spindle through both collars, hub sleeve, a fork carrying the femur
# pitch pin, and the planetary hip drive on the fork plate at drive_sign * Z.
# Two variants keep the drive outboard: +Z faces outboard on right-front and
# left-rear legs, inboard on the others (hinge Z = up x heading).
def build_coxa(group, drive_sign):
    cylinder('Coxa slewing spindle', (0, LOWER_COLLAR - .055, 0), (0, UPPER_COLLAR + .055, 0), .058, steel, group, 40, .003)
    cylinder('Coxa hub sleeve', (0, LOWER_COLLAR + .030, 0), (0, UPPER_COLLAR - .030, 0), .082, secondary, group, 48, .006)
    for y, sgn in ((UPPER_COLLAR + .029, 1), (LOWER_COLLAR - .029, -1)):
        turned('Spindle retaining nut', (0, y, 0), (0, sgn, 0), [(0, .074), (.018, .074), (.025, .060), (.026, 0)], steel, group, 24)
    fork = rounded([(.0, -.20), (.07, -.20)], (COXA_REACH, 0), .074 * T, -math.pi * .62, math.pi * .5, [(.0, .074 * T)], 12)
    face = .082 * T
    for sgn in (-1, 1):
        plate_xy('Coxa fork plate', fork, sgn * .056 * T, sgn * face, paint, group, .006)
        # Plate bolts sit above and below the axle boss the fork sweeps past.
        for y in (-.185, .05): bolt((.04, y, sgn * face), (0, 0, sgn), group, .009)
    pin(group, (COXA_REACH, 0), face + .006, .026 * T, nut=False)
    turned('Castellated pin retaining nut', (COXA_REACH, 0, -drive_sign * (face + .006)), (0, 0, -drive_sign),
           [(0, .026 * T * 1.3), (.008, .026 * T * 1.3), (.012, .026 * T * 1.1), (.013, 0)], steel, group, 24)
    # Planetary hip drive: bolted flange, finned ring-gear drum, end cap and a
    # hydraulic motor with its supply port, coaxial with the femur pin.
    at = Vector((COXA_REACH, 0, drive_sign * face)); axis = (0, 0, drive_sign); d = HIP_DRIVE_DEPTH
    turned('Hip drive bolting flange', at, axis, [(0, .110), (.012, .110), (.014, .102), (.014, .0)], steel, group, 48)
    turned('Hip drive ring-gear drum', at, axis, [(.012, .094), (d * .55, .094), (d * .60, .088), (d * .64, .070), (d * .64, .0)], secondary, group, 48)
    for k in range(3):
        ring('Hip drive cooling fin', at + Vector(axis) * (.022 + k * .011), axis, .104, .092, .004, secondary, group, 48)
    cylinder('Hip drive hydraulic motor', at + Vector(axis) * d * .60, at + Vector(axis) * d * .94, .044, secondary, group, 32, .004)
    turned('Hip drive motor end cap', at + Vector(axis) * d * .94, axis, [(0, .046), (.004, .046), (.006, .038), (.006, 0)], steel, group, 32)
    cylinder('Hip drive supply port', at + Vector(axis) * d * .80 + Vector((0, .040, 0)), at + Vector(axis) * d * .80 + Vector((0, .062, 0)), .010, brass, group, 12, .001)
    for i in range(8):
        a = i * math.tau / 8 + math.tau / 16
        bolt(at + Vector((math.cos(a) * .101, math.sin(a) * .101, drive_sign * .014)), axis, group, .0075, n=12)
build_coxa(coxa_t, 1)
coxa_mirror_t = part('LegCoxaMirrorTemplate')
build_coxa(coxa_mirror_t, -1)

# Femur: box-section beam, pin boss, knee fork, bolted armour and ram lugs.
L1 = FEMUR
cylinder('Femur root pin boss', (0, 0, -.052 * T), (0, 0, .052 * T), .062 * T, secondary, femur_t, 48, .005)
loft('Femur box-section beam', [(.04, section(.055 * T, .048 * T, .018)), (.30, section(.064 * T, .050 * T, .020)), (L1 - .09, section(.050 * T, .046 * T, .016))], paint, femur_t, .012)
box('Femur knee crossbar', (0, L1 - .11, 0), (.10 * T, .05, .156 * T), secondary, femur_t, .006)
knee_fork = rounded([(-.05 * T, L1 - .15), (.05 * T, L1 - .15)], (0, L1), .068 * T, 0, math.pi, [], 12)
for sgn in (-1, 1):
    plate_xy('Femur knee fork plate', knee_fork, sgn * .054 * T, sgn * .080 * T, paint, femur_t, .006)
    for y in (L1 - .12, L1 - .06): bolt((.0, y, sgn * .080 * T), (0, 0, sgn), femur_t, .008)
pin(femur_t, (0, L1), .092 * T, .024 * T)
# Top armour on the +X face, bolted through to the beam.
slab('Femur top armour plate', section(.040 * T, .15, .02), None, .0, .012, secondary, femur_t, .003,
     frame=((.064 * T, (L1 + .12) * .5, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0)))
for y in (.20, .30, .40):
    for z in (-.034, .034): bolt((.064 * T + .012, y, z), (1, 0, 0), femur_t, .0085)
# Knee ram lug: paired plates with a cross pin, clear of the ram eye.
for (lx, ly), sgn_x in ((KNEE_FEMUR, 1),):
    for sgn in (-1, 1):
        plate_xy('Ram lug plate', rounded([(sgn_x * .055, ly - .05), (sgn_x * .055, ly + .05)], (lx, ly), .034, math.pi * .5 * sgn_x, -math.pi * .5 * sgn_x, [], 8),
                 sgn * .030, sgn * .045, secondary, femur_t, .003)
    pin(femur_t, (lx, ly), .052, .019, nut=False)
tube('Femur hydraulic hose', [(.040, .06, .070), (.075, .20, .070), (.075, .46, .070), (.045, L1 - .12, .080)], .011, rubber, femur_t, 10)

# Tibia: pin boss, ram horn, tapered beam, bolted shin armour, ankle socket.
L2 = TIBIA
cylinder('Tibia knee pin boss', (0, 0, -.050 * T), (0, 0, .050 * T), .056 * T, secondary, tibia_t, 48, .005)
horn = [(-.06, .025), (.06, .045), (KNEE_TIBIA[0] + .034, KNEE_TIBIA[1] + .012), (KNEE_TIBIA[0] + .012, KNEE_TIBIA[1] - .034), (KNEE_TIBIA[0] - .028, KNEE_TIBIA[1] - .014), (-.055, -.04)]
for sgn in (-1, 1):
    plate_xy('Tibia ram horn plate', horn, sgn * .030, sgn * .050, paint, tibia_t, .005)
pin(tibia_t, KNEE_TIBIA, .058, .019, nut=False)
loft('Tibia tapered beam', [(.05, section(.052 * T, .044 * T, .016)), (.35, section(.050 * T, .042 * T, .015)), (L2 - .16, section(.040 * T, .036 * T, .012))], secondary, tibia_t, .009)
slab('Shin guard armour plate', [(-.07, .11), (.07, .11), (.076, .17), (.066, L2 * .62), (0, L2 * .62 + .06), (-.066, L2 * .62), (-.076, .17)], None, .0, .014, paint, tibia_t, .006,
     frame=((.052 * T + .012, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0)))
for y in (.15, .31, .45):
    for z in (-.045, .045): bolt((.052 * T + .026, y, z), (1, 0, 0), tibia_t, .0085)
for y in (.20, .40):
    box('Shin guard standoff', (.052 * T + .006, y, 0), (.014, .03, .06), steel, tibia_t, .002)
turned('Ankle socket housing', (0, L2 - .17, 0), (0, 1, 0), [(0, .052), (.02, .060), (.090, .074), (.108, .072), (.110, .048)], steel, tibia_t, 40)
ring('Ankle socket clamp band', (0, L2 - .115, 0), (0, 1, 0), .080, .068, .016, oxidized, tibia_t, 40)
tube('Tibia hydraulic hose', [(.0, .04, .072), (.025, .20, .066), (.025, L2 - .22, .056), (.0, L2 - .17, .04)], .010, rubber, tibia_t, 10)

# Foot: ankle ball, rubber dust boot, bolted pad housing and a cleated sole.
turned('Ankle ball', (0, -.062, 0), (0, 1, 0), [(0, 0), (.010, .040), (.025, .058), (.062, .064), (.100, .058), (.114, .040), (.124, 0)], edge_steel, foot_t, 32)
turned('Ankle dust boot', (0, -.118, 0), (0, 1, 0), [(0, .092), (.012, .088), (.020, .072), (.029, .082), (.038, .066), (.047, .074), (.056, .058), (.062, .050)], rubber, foot_t, 40)
turned('Foot pad housing', (0, -.13, 0), (0, 1, 0), [(0, .205), (.008, .205), (.014, .196), (.022, .194), (.026, .150), (.044, .106), (.050, .086)], paint, foot_t, 64)
ring('Foot pad armour band', (0, -.1245, 0), (0, 1, 0), .209, .195, .011, secondary, foot_t, 64)
for i in range(10):
    a = i * math.tau / 10 + math.tau / 20
    bolt((math.cos(a) * .172, -.1075, math.sin(a) * .172), (0, 1, 0), foot_t, .009)
cylinder('Foot rubber sole', (0, -.160, 0), (0, -.130, 0), .208, rubber, foot_t, 64, .005)
for i in range(6):
    a = i * math.tau / 6
    slab('Sole grip cleat', [(-.05, -.016), (.05, -.016), (.05, .016), (-.05, .016)], None, -.006, .003, rubber, foot_t, .003,
         frame=((math.cos(a) * .12, -.160, math.sin(a) * .12), (math.cos(a), 0, math.sin(a)), (-math.sin(a), 0, math.cos(a)), (0, 1, 0)))

MOUNT = finalize(mount_t, 'AtlasLegMount'); COXA = finalize(coxa_t, 'AtlasLegCoxa'); COXA_MIRROR = finalize(coxa_mirror_t, 'AtlasLegCoxaMirror')
FEMUR_MESH = finalize(femur_t, 'AtlasLegFemur'); TIBIA_MESH = finalize(tibia_t, 'AtlasLegTibia'); FOOT = finalize(foot_t, 'AtlasLegFoot')

C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
def to_blender(origin, x, y, z):
    m = Matrix.Identity(4)
    for i in range(3):
        m[i][0], m[i][1], m[i][2], m[i][3] = x[i], y[i], z[i], origin[i]
    return C @ m @ C.inverted()
UP = Vector((0, 1, 0))

def pose(side, end, ankle, normal=UP):
    """Mirror of AtlasLegs.solve: all frames in the hull frame (source metres)."""
    axis = Vector((side * LEG_YAW_AXIS[0], LEG_YAW_Y, end * LEG_YAW_AXIS[1]))
    ankle = Vector((ankle.x, min(ankle.y, FOOT_NEUTRAL[1] + ANKLE + ANKLE_RISE_LIMIT), ankle.z))
    flat = ankle - axis
    if Vector((flat.x, 0, flat.z)).length > .02: outward = math.degrees(math.atan2(side * flat.x, end * flat.z))
    else:  # degenerate: keep the neutral stance heading (AtlasLegs neutral_yaw)
        rest = neutral_ankle(side, end) - axis; outward = math.degrees(math.atan2(side * rest.x, end * rest.z))
    outward = math.radians(max(COXA_YAW_LIMITS[0], min(COXA_YAW_LIMITS[1], outward)))
    h = Vector((side * math.sin(outward), 0, end * math.cos(outward))); femur_pin = axis + h * COXA_REACH
    rel = ankle - femur_pin; au = rel.dot(h); av = rel.y
    d = max(abs(FEMUR - TIBIA) + .002, min(FEMUR + TIBIA - .002, math.hypot(au, av)))
    eu, ev = au / math.hypot(au, av), av / math.hypot(au, av)
    along = (FEMUR ** 2 - TIBIA ** 2 + d * d) / (2 * d); rise = math.sqrt(max(0, FEMUR ** 2 - along ** 2))
    knee = femur_pin + h * (along * eu - rise * ev) + UP * (along * ev + rise * eu)
    ankle = femur_pin + h * (eu * d) + UP * (ev * d)
    z = UP.cross(h).normalized()
    frames = {'Coxa': (axis, h, UP, h.cross(UP))}
    for label, start, stop in (('Femur', femur_pin, knee), ('Tibia', knee, ankle)):
        y = (stop - start).normalized(); frames[label] = (start, y.cross(z), y, z)
    n = Vector(normal).normalized(); fx = (h - n * h.dot(n)).normalized()
    frames['Foot'] = (ankle, fx, n, fx.cross(n))
    def at(label, u, v):
        o, x, y, _ = frames[label]; return o + x * u + y * v
    anchors = {'Knee': (at('Femur', *KNEE_FEMUR), at('Tibia', *KNEE_TIBIA))}
    for label, (a, b) in anchors.items():
        y = (b - a).normalized(); frames[label + 'Barrel'] = (a, y.cross(z), y, z)
        y = (a - b).normalized(); frames[label + 'Rod'] = (b, y.cross(z), y, z)
    return frames, {k: (a - b).length for k, (a, b) in anchors.items()}

LEGS = [(side, end, sl, el) for side, sl in ((-1, 'L'), (1, 'R')) for end, el in ((-1, 'Front'), (1, 'Rear'))]
def neutral_ankle(side, end):
    return Vector((side * FOOT_NEUTRAL[0], FOOT_NEUTRAL[1] + ANKLE, end * FOOT_NEUTRAL[2]))
# Sampled envelope: fore/aft and lateral foot travel, swing lift and terrain
# footholds between WalkerDrive's step ceiling and its reach below the stance.
_step = _walker_const('MAX_STEP'); _reach = _walker_const('REACH') - _walker_const('RIDE_HEIGHT')
GAIT = [(dx, dy, dz) for dx in (-.08, 0, .08) for dy in (-_reach * .9, -.2, 0, .12, .25, ANKLE_RISE_LIMIT, _step * .9) for dz in (-.20, 0, .20)]
ranges = {'Knee': [9, 0]}
for side, end, _, _ in LEGS:
    for dx, dy, dz in GAIT:
        _, lengths = pose(side, end, neutral_ankle(side, end) + Vector((side * dx, dy, end * dz)))
        for k, v in lengths.items(): ranges[k][0] = min(ranges[k][0], v); ranges[k][1] = max(ranges[k][1], v)
# The longest barrel and rod that never meet an eye at the shortest eye
# distance; the rod must still overlap the gland at the longest.
RAM_EYE_CLEARANCE = {'barrel': .05, 'rod': .04}; RAM_MIN_OVERLAP = .02
RAMS = {}
for label, (lo, hi) in ranges.items():
    barrel = round(lo - RAM_EYE_CLEARANCE['barrel'], 4); rod = round(lo - RAM_EYE_CLEARANCE['rod'], 4)
    overlap = rod - (hi - barrel)
    if overlap < RAM_MIN_OVERLAP: raise RuntimeError('%s ram stroke too long for its eyes: overlap %.3f' % (label, overlap))
    RAMS[label] = {'barrel': barrel, 'rod': rod, 'eye_min': round(lo, 4), 'eye_max': round(hi, 4), 'min_overlap': round(overlap, 4)}
print('LEG_RAMS', json.dumps(RAMS))
ram_meshes = {}
for label, spec in RAMS.items():
    rb, rr = .044, .025   # barrel and rod radii
    g = part('Leg%sBarrelTemplate' % label)
    ring('Ram barrel eye', (0, 0, 0), (0, 0, 1), .036, .0195, .054, steel, g, 32)
    cylinder('Ram barrel eye neck', (0, .026, 0), (0, .044, 0), .028, steel, g, 24, .002)
    turned('Ram barrel base collar', (0, .042, 0), (0, 1, 0), [(0, rb + .004), (.016, rb + .004), (.020, rb)], steel, g, 40)
    cylinder('Hydraulic ram barrel', (0, .060, 0), (0, spec['barrel'] - .02, 0), rb, secondary, g, 40, .002)
    turned('Ram gland nut', (0, spec['barrel'] - .022, 0), (0, 1, 0), [(0, rb + .005), (.018, rb + .005), (.022, rb * .8), (.022, rr + .002)], steel, g, 6 * 6)
    cylinder('Ram hose port', (rb - .004, .085, 0), (rb + .018, .085, 0), .011, brass, g, 12, .001)
    ram_meshes[label + 'Barrel'] = finalize(g, 'AtlasLeg%sBarrel' % label)
    g = part('Leg%sRodTemplate' % label)
    ring('Ram rod eye', (0, 0, 0), (0, 0, 1), .032, .0195, .050, steel, g, 32)
    cylinder('Ram rod eye neck', (0, .024, 0), (0, .040, 0), rr + .004, steel, g, 24, .002)
    cylinder('Hard-chromed ram rod', (0, .040, 0), (0, spec['rod'], 0), rr, chrome, g, 32, .0015)
    ram_meshes[label + 'Rod'] = finalize(g, 'AtlasLeg%sRod' % label)

LEG_TEMPLATES = {'Coxa': COXA, 'Femur': FEMUR_MESH, 'Tibia': TIBIA_MESH, 'Foot': FOOT, **ram_meshes}
# +Z of the coxa faces outboard where side * end < 0 (see build_coxa).
def coxa_template(side, end): return COXA if side * end < 0 else COXA_MIRROR
leg_nodes = {}
for side, end, sl, el in LEGS:
    tag = '%s_%s' % (sl, el)
    axis = (side * LEG_YAW_AXIS[0], LEG_YAW_Y, end * LEG_YAW_AXIS[1])
    turn = Matrix.Identity(4) if side > 0 else Matrix.Rotation(math.pi, 4, 'Z')
    instance(MOUNT, 'LegMount_' + tag, legs, Matrix.Translation(gv(axis)) @ turn)
    frames, _ = pose(side, end, neutral_ankle(side, end))
    for label, template in LEG_TEMPLATES.items():
        if label == 'Coxa': template = coxa_template(side, end)
        leg_nodes[(tag, label)] = instance(template, 'Leg%s_%s' % (label, tag), legs, to_blender(*frames[label]))
def apply_pose(side, end, tag, ankle, normal=UP):
    frames, lengths = pose(side, end, ankle, normal)
    for label in LEG_TEMPLATES: leg_nodes[(tag, label)].matrix_basis = to_blender(*frames[label])
    return lengths
for template in [MOUNT, COXA_MIRROR, *LEG_TEMPLATES.values()]:
    group = template.parent
    del groups[group]; bpy.data.objects.remove(template, do_unlink=True); bpy.data.objects.remove(group, do_unlink=True)
bpy.context.view_layer.update()

# ------------------------------------------------------------ review studio
def studio(samples):
    """Import the approved hull beneath the drives, tracks hidden, and light it."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(HULL))
    hull_objects = [o for o in bpy.data.objects if o not in before]
    for o in hull_objects:
        if o.name.split('.')[0] in ('DriveLeft', 'DriveRight', 'ArmorSideReference', 'ArmorSideHeavy', 'ArmorTop', 'ArmorFront', 'ArmorRear', 'ExhaustSmall', 'ExhaustMedium', 'ExhaustLarge'):
            for d in descendants(o): d.hide_render = True
    floor = material('Studio_Only', (.73, .75, .77), .0, .68)
    bpy.ops.mesh.primitive_plane_add(size=200, location=gv((0, -.555, 0)))
    bpy.context.object.data.materials.append(floor); studio_floor = bpy.context.object
    def light(name, at, energy, color, size, target=(0, 0, 0)):
        d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.shape = 'DISK'; d.size = size; d.color = color
        o = bpy.data.objects.new(name, d); bpy.context.collection.objects.link(o); o.location = gv(at); o.rotation_euler = (gv(target) - o.location).to_track_quat('-Z', 'Y').to_euler()
    light('Large warm key', (-3.5, 5, -4), 520, (1, .97, .90), 4)
    light('Cool side reflection', (4, 2, .5), 330, (.84, .92, 1), 3)
    light('Rear rim', (-1, 3, 3), 480, (1, .95, .86), 2.5)
    light('Front fill', (0, 1, -4), 90, (.94, .96, 1), 3)
    light('Low bounce', (2.5, -.3, -2.5), 60, (1, .98, .95), 3)
    scene = bpy.context.scene; scene.world = scene.world or bpy.data.worlds.new('Drive studio'); scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.65, .69, .75, 1); scene.world.node_tree.nodes['Background'].inputs[1].default_value = .25
    cam_data = bpy.data.cameras.new('DriveReviewCamera'); cam = bpy.data.objects.new('DriveReviewCamera', cam_data); bpy.context.collection.objects.link(cam); scene.camera = cam
    scene.render.engine = 'CYCLES'; scene.cycles.samples = samples; scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'OPTIX'; prefs.get_devices()
        for device in prefs.devices: device.use = device.type == 'OPTIX'
        scene.cycles.device = 'GPU'
    except Exception: pass
    scene.render.resolution_x = 1600; scene.render.resolution_y = 1200
    scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'
    def view(name, at, target=(0, 0, 0), ortho=3.4, folder=SOURCE):
        cam.location = gv(at); cam.rotation_euler = (gv(target) - cam.location).to_track_quat('-Z', 'Y').to_euler(); cam_data.type = 'ORTHO'; cam_data.ortho_scale = ortho
        scene.render.filepath = str(Path(folder) / (name + '.png')); bpy.ops.render.render(write_still=True)
    return view, hull_objects, studio_floor

def show_only(group):
    for g in (wheels, legs):
        for o in descendants(g): o.hide_render = g is not group

if '--stage-legs' in sys.argv:
    view, _, floor_obj = studio(16)
    floor_obj.location = gv((0, -.95, 0))
    bpy.context.scene.render.resolution_x = 1000; bpy.context.scene.render.resolution_y = 750
    show_only(legs)
    view('stage_legs_hero', (3.8, 2.0, -4.2), target=(0, -.3, 0), ortho=4.0, folder=PREVIEW)
    view('stage_legs_side', (6, -.2, 0), target=(0, -.3, 0), ortho=4.0, folder=PREVIEW)
    view('stage_legs_front', (0, -.2, -6), target=(0, -.3, 0), ortho=4.0, folder=PREVIEW)
    view('stage_legs_detail', (2.6, .3, -2.9), target=(1.1, -.35, -1.0), ortho=1.6, folder=PREVIEW)
    print('STAGE_LEGS_DONE'); sys.exit(0)

if '--stage-wheels' in sys.argv:
    view, _, _ = studio(16)
    bpy.context.scene.render.resolution_x = 1000; bpy.context.scene.render.resolution_y = 750
    show_only(wheels)
    view('stage_wheels_hero', (3.4, 2.2, -3.8), folder=PREVIEW)
    view('stage_wheels_side', (6, 0, 0), folder=PREVIEW)
    view('stage_wheels_detail', (2.6, .2, -1.9), target=(.95, -.1, -.76), ortho=1.4, folder=PREVIEW)
    view('stage_wheels_low', (2.2, -.35, -.2), target=(.9, -.2, -.2), ortho=2.0, folder=PREVIEW)
    print('STAGE_WHEELS_DONE'); sys.exit(0)

# ------------------------------------------------------ clearance audit
# Sampled triangle-overlap audit against the imported approved hull and the
# trimmed sponsons. Wheels are checked at eight spin phases across one tread
# pitch; legs across the sampled gait envelope (GAIT). Intended contacts (hub
# adapters and slewing mounts bolted to the axle bosses) are reported apart.
def world_tree(objs):
    verts = []; polys = []
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        dg = o.evaluated_get(depsgraph); m = dg.to_mesh()
        off = len(verts); verts += [o.matrix_world @ v.co for v in m.vertices]
        polys += [[off + i for i in p.vertices] for p in m.polygons]; dg.to_mesh_clear()
    tree = BVHTree.FromPolygons(verts, polys) if polys else None
    if tree: tree_points[id(tree)] = (verts, polys)
    return tree
tree_points = {}
def overlap_at(a, b):
    """Hull-frame centroid of the first overlapping triangle of b (diagnostics)."""
    pairs = a.overlap(b)
    if not pairs: return None
    verts, polys = tree_points[id(b)]; poly = polys[pairs[0][1]]
    c = sum((verts[i] for i in poly), Vector()) / len(poly)
    return [round(v, 3) for v in gd(c)]

def audit():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(HULL))
    imported = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    hull_surface = [o for o in imported if o.type == 'MESH' and o.name.startswith('HullSurface')]
    static = {-1: world_tree(hull_surface + [sponson_objects[-1]]), 1: world_tree(hull_surface + [sponson_objects[1]])}
    hull_tree = world_tree(hull_surface)
    report = {'scope': 'Sampled triangle-overlap audit against the imported atlas_mx.glb HullSurface and the trimmed sponsons. '
                       'Wheels: 8 spin phases over one tread pitch. Legs: %d foot offsets per leg (fore/aft +-.20, lateral +-.08, height -%.2f..+%.2f).' % (len(GAIT), _reach * .9, _step * .9),
              'wheels': {}, 'legs': {}, 'intended_contacts': {}}
    step = math.tau / PITCHES / 8
    for side, sl in ((-1, 'L'), (1, 'R')):
        for el in ('Front', 'Rear'):
            pivot = bpy.data.objects['Wheel_%s_%s' % (sl, el)]; rest = pivot.matrix_basis.copy(); hits = 0
            hub = bpy.data.objects['HubMotor_%s_%s' % (sl, el)]
            hub_tree = world_tree([hub])
            for k in range(8):
                pivot.matrix_basis = rest @ Matrix.Rotation(k * step, 4, 'X'); bpy.context.view_layer.update()
                tree = world_tree([o for o in descendants(pivot) if o.type == 'MESH'])
                hits += len(tree.overlap(static[side])) + len(tree.overlap(hub_tree))
            pivot.matrix_basis = rest
            report['wheels']['%s_%s' % (sl, el)] = hits
            report['intended_contacts']['HubMotor_%s_%s' % (sl, el)] = len(hub_tree.overlap(static[side]))
    bpy.context.view_layer.update()
    moving = ['Coxa', 'Femur', 'Tibia', 'Foot', 'KneeBarrel', 'KneeRod']
    # Pairs that never share a pin; adjacent parts meet at pins by design.
    apart = [('Tibia', 'Coxa'), ('Foot', 'Femur'), ('Foot', 'Coxa'), ('KneeBarrel', 'Coxa'), ('KneeRod', 'Coxa'),
             ('KneeBarrel', 'Mount'), ('Tibia', 'Mount')]
    for side, end, sl, el in LEGS:
        tag = '%s_%s' % (sl, el); result = {'static': {}, 'parts': {}}
        mount = bpy.data.objects['LegMount_' + tag]
        report['intended_contacts']['LegMount_' + tag] = len(world_tree([mount]).overlap(static[side]))
        for dx, dy, dz in GAIT:
            apply_pose(side, end, tag, neutral_ankle(side, end) + Vector((side * dx, dy, end * dz)))
            bpy.context.view_layer.update()
            trees = {label: world_tree([leg_nodes[(tag, label)]]) for label in moving}
            trees['Mount'] = world_tree([mount])
            for label in moving:
                count = len(trees[label].overlap(static[side]))
                if label != 'Coxa': count += len(trees[label].overlap(trees['Mount']))
                if count:
                    where = 'hull' if trees[label].overlap(hull_tree) else ('mount' if label != 'Coxa' and trees[label].overlap(trees['Mount']) else 'sponson')
                    target = hull_tree if where == 'hull' else (trees['Mount'] if where == 'mount' else static[side])
                    result['static'].setdefault(label + '_vs_' + where, []).append([dx, dy, dz, count, overlap_at(trees[label], target)])
            for a, b in apart:
                count = len(trees[a].overlap(trees[b]))
                if count: result['parts'].setdefault(a + '_vs_' + b, []).append([dx, dy, dz, count])
        apply_pose(side, end, tag, neutral_ankle(side, end))
        report['legs'][tag] = {k: {'samples': len(v), 'first': v[:4]} for k, v in {**result['static'], **result['parts']}.items()}
    bpy.context.view_layer.update()
    report['wheels_clear'] = not any(report['wheels'].values())
    report['legs_clear'] = not any(report['legs'].values())
    for o in imported: bpy.data.objects.remove(o, do_unlink=True)
    return report

clearance = audit()
print('DRIVE_CLEARANCE', json.dumps(clearance))
if '--audit-only' in sys.argv: sys.exit(0)

# ------------------------------------------------------------------- bake
# Only the new running gear is baked; the reused sponsons keep their approved
# hull materials. Wheels and legs never coexist, so the legs are the baker's
# separately-offset assembly and cast no occlusion onto the wheels.
sys.path.insert(0, str(ROOT / 'tools'))
from atlas_surface_bake import bake_surface_atlases
sponsons.parent = None
bpy.context.view_layer.update()
if NO_BAKE:
    surface = {'skipped': True}
else:
    surface = bake_surface_atlases(wheels, legs, [], RUNTIME, quick=QUICK, prefix='Atlas_Drive', face_wear=.80,
                                   families=('Primary', 'Secondary', 'Hardware'),
                                   sizes={'Primary': 2048, 'Secondary': 2048, 'Hardware': 4096})
sponsons.parent = root; sponsons.matrix_parent_inverse = Matrix.Identity(4)
bpy.context.view_layer.update()

def export_model(obj, filename):
    bpy.ops.object.select_all(action='DESELECT')
    for item in descendants(obj): item.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = RUNTIME / filename
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_extras=True, export_animations=False, export_materials='EXPORT', export_texcoords=True, export_normals=True)
    # Reference the external canonical maps (the drive set and, for the reused
    # sponsons, the approved hull set) instead of embedding copies.
    raw = path.read_bytes(); json_len = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_len]); binary = raw[20 + json_len + 8:]
    image_views = {im['bufferView'] for im in document.get('images', []) if 'bufferView' in im}
    for im in document.get('images', []):
        im.pop('bufferView', None); im.pop('mimeType', None)
        stem = im['name'][:-4] if im['name'].lower().endswith('.png') else im['name']
        im['uri'] = stem + '.png'
        if not (RUNTIME / im['uri']).exists() and not (HULL.parent / im['uri']).exists():
            raise RuntimeError('Missing portable material ' + im['uri'])
    remap = {}; views = []; packed = bytearray()
    for i, view in enumerate(document['bufferViews']):
        if i in image_views: continue
        while len(packed) % 4: packed.append(0)
        start = view.get('byteOffset', 0); chunk = binary[start:start + view['byteLength']]
        new_view = dict(view); new_view['byteOffset'] = len(packed); remap[i] = len(views); views.append(new_view); packed.extend(chunk)
    for accessor in document.get('accessors', []):
        if 'bufferView' in accessor: accessor['bufferView'] = remap[accessor['bufferView']]
    document['bufferViews'] = views; document['buffers'][0]['byteLength'] = len(packed)
    while len(packed) % 4: packed.append(0)
    jb = json.dumps(document, separators=(',', ':')).encode('utf8')
    while len(jb) % 4: jb += b' '
    path.write_bytes(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(jb) + 8 + len(packed)) + struct.pack('<I4s', len(jb), b'JSON') + jb + struct.pack('<I4s', len(packed), b'BIN\0') + packed)
    return document

document = export_model(root, 'atlas_drives.glb')

def triangles(objs):
    total = 0
    for o in objs:
        o.data.calc_loop_triangles(); total += len(o.data.loop_triangles)
    return total
meshes_of = lambda g: [o for o in descendants(g) if o.type == 'MESH']
stats = {'sponsons': triangles(meshes_of(sponsons)), 'wheels_large': triangles(meshes_of(wheels)), 'legs': triangles(meshes_of(legs)),
         'wheel_each': triangles([bpy.data.objects['WheelLarge_L_Front']]),
         'leg_each': triangles([o for o in meshes_of(legs) if o.name.endswith('_L_Front')])}
manifest = {'name': 'Atlas MX drive configurations', 'id': 'atlas_drives', 'runtime': 'atlas_drives.glb',
            'authoring': 'Godot metres in the Atlas hull frame, X right Y up -Z forward; runtime factor three applied by AtlasVisual',
            'generator': 'tools/build-atlas-drives.py',
            'configurations': {'traction': 'approved tracks in atlas_mx.glb', 'standard_wheels': 'Sponsons + WheelsLarge', 'walker': 'Sponsons + Legs'},
            'sponsons': {'source': 'atlas_mx.glb DriveLeftSurface/DriveRightSurface', 'removed_track_faces': removed_components},
            'wheels': {'radius': WHEEL_RADIUS, 'width': WHEEL_WIDTH, 'centers': WHEEL_NODES, 'pitches': PITCHES,
                       'nodes': 'Wheel_{L|R}_{Front|Rear} pivots spin about local X'},
            'legs': {'yaw_axis': LEG_YAW_AXIS, 'pin_height': LEG_YAW_Y, 'coxa_reach': COXA_REACH, 'femur': FEMUR, 'tibia': TIBIA,
                     'ankle': ANKLE, 'foot_neutral': FOOT_NEUTRAL, 'coxa_yaw_limits_degrees': COXA_YAW_LIMITS, 'ankle_rise_limit': ANKLE_RISE_LIMIT,
                     'anchors': {'knee_femur': KNEE_FEMUR, 'knee_tibia': KNEE_TIBIA}, 'hip_drive_depth': HIP_DRIVE_DEPTH,
                     'rams': RAMS, 'nodes': 'Leg{Mount|Coxa|Femur|Tibia|Foot|KneeBarrel|KneeRod}_{L|R}_{Front|Rear}'},
            'triangles': stats, 'clearance': clearance, 'surface_atlases': surface, 'approval': 'Pending user visual approval'}
(RUNTIME / 'atlas_drives_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
# Runtime rig: the exported data file AtlasDriveRig reads (typed, no defaults).
rig = {'_comment': 'Generated by tools/build-atlas-drives.py from the authored atlas_drives.glb; regenerate instead of editing. Atlas source metres in the hull frame (X right, Y up, -Z forward; the runtime applies the shared factor-three scale). Presentation only: authoritative walker footholds stay in WalkerDrive.',
       'wheels': {'_comment': 'Large off-road wheels spin about local X at this lug-tip radius.', 'radius': WHEEL_RADIUS},
       'legs': {'_comment': 'Yaw/pitch/pitch hydraulic legs. The coxa slews about a vertical axis at (+-yaw_axis_x, pin_height, +-yaw_axis_z); the femur pin sits coxa_reach along the heading. Heading yaw is limited to [coxa_yaw_min_degrees, coxa_yaw_max_degrees] from straight fore/aft (positive outboard); the ankle rises at most ankle_rise_limit above its stance height. The femur pitches on a planetary hip drive; the knee ram eyes are (X, Y) in the femur and tibia segment frames.',
                'yaw_axis_x': LEG_YAW_AXIS[0], 'yaw_axis_z': LEG_YAW_AXIS[1], 'pin_height': LEG_YAW_Y, 'coxa_reach': COXA_REACH,
                'femur': FEMUR, 'tibia': TIBIA, 'ankle': ANKLE, 'ankle_rise_limit': ANKLE_RISE_LIMIT,
                'coxa_yaw_min_degrees': COXA_YAW_LIMITS[0], 'coxa_yaw_max_degrees': COXA_YAW_LIMITS[1],
                'knee_femur': list(KNEE_FEMUR), 'knee_tibia': list(KNEE_TIBIA)}}
rig_path = (ROOT / 'battlebots/data/atlas_drive_rig.json') if not (QUICK or NO_BAKE) else (RUNTIME / 'atlas_drive_rig.json')
rig_path.write_text(json.dumps(rig, indent='\t') + '\n')
print('DRIVES_EXPORT', json.dumps(stats))

if NO_RENDER:
    print('DRIVES_COMPLETE', str(RUNTIME)); sys.exit(0)

# ------------------------------------------------------------ review renders
view, _, floor_obj = studio(24 if QUICK else 96)
show_only(wheels)
view('drives_wheels_hero', (3.4, 2.2, -3.8))
view('drives_wheels_rear_quarter', (-3.4, 2.0, 3.8))
view('drives_wheels_side', (6, .1, 0), target=(0, -.05, 0))
view('drives_wheels_detail', (2.6, .2, -1.9), target=(.95, -.1, -.76), ortho=1.4)
floor_obj.location = gv((0, -.95, 0))
show_only(legs)
# A mid-stride pose: diagonal pair planted, the other pair swinging.
for side, end, sl, el in LEGS:
    lift = .16 if (side < 0) == (end < 0) else 0
    apply_pose(side, end, '%s_%s' % (sl, el), neutral_ankle(side, end) + Vector((0, lift, -.12 if lift else .08)))
view('drives_legs_hero', (3.8, 2.0, -4.2), target=(0, -.3, 0), ortho=4.0)
view('drives_legs_rear_quarter', (-3.8, 1.6, 4.2), target=(0, -.3, 0), ortho=4.0)
view('drives_legs_side', (6, -.2, 0), target=(0, -.3, 0), ortho=4.0)
view('drives_legs_detail', (2.9, .4, -3.0), target=(1.2, -.3, -1.05), ortho=1.7)
print('DRIVES_COMPLETE', str(SOURCE))
