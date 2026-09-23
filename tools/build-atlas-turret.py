"""Atlas MX roof turret with cannon and plasma attachments.

Blender 5.2 --background --python tools/build-atlas-turret.py [-- --quick]

Construction brief (Godot metres, X right, Y up, -Z forward, Atlas hull origin):
- Footprint: a rail-clamped adapter plate on the forward service cover of the
  existing roof (cover top Y=.498), raised on pads above the cover bolts. The
  traverse race is centred at X=0, Z=-.32, inside the cover width, clear of the
  rear stacks and corner sockets. The Atlas hull, mounts and collision envelope are unchanged.
- Moving envelopes: TurretYaw rotates about Y at the race centre. TurretPitch
  (trunnion) sits .25 m ahead of it at Y=.70 and rotates about X. Both weapon
  attachments share the mantlet's quick-change collar. The cannon barrel slides
  on CannonRecoil for recoil. The clearance audit below sweeps the full yaw and
  the published elevation range against the imported hull.
- Materials reuse the approved Atlas classes (primary/secondary enamel,
  machined, oxidised and dark recess) and add gun steel, copper coil windings
  and an emissive plasma lens. Maps are baked by atlas_surface_bake.py into a
  separate Atlas_Turret* set, so the approved hull maps stay untouched.

--quick writes an isolated reduced-resolution draft under
battlebots/exports/atlas-turret-preview. The default writes the runtime GLB,
maps and manifest, and review renders under art_source/atlas_turret.
"""
import bpy, bmesh, math, json, random, sys, struct
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art_source/atlas_turret'
RUNTIME = ROOT / 'battlebots/assets/models/atlas_runtime'
PREVIEW = ROOT / 'battlebots/exports/atlas-turret-preview'
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
random.seed(36036)

# Published pivots (also in AtlasGeometry and the manifest).
YAW = (0.0, .52, -.32)
PITCH = (0.0, .71, -.60)
# Elevation stop +30. Depression follows a measured per-bearing profile (the
# corner sockets and deck limit some bearings); DEPRESSION_FLOOR is its deepest.
DEPRESSION_FLOOR = -20.0
PITCH_LIMITS = (DEPRESSION_FLOOR, 30.0)
CANNON_MUZZLE = (0.0, .71, -1.545)
PLASMA_MUZZLE = (0.0, .71, -1.26)

def gv(p): return Vector((p[0], -p[2], p[1]))
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
# Blued, lightly oiled ordnance steel is darker and smoother than the hull.
gun = material('Atlas_GunMetal', (.24, .25, .255), .85, .50)
# Barrel-only finishes: drawn-tube streaks along the bore axis (Blender Y),
# denser abrasions and sparse heat oxidation; painted sleeves chip more.
gun['atlas_streak'] = (260.0, 5.0, 260.0); gun['atlas_scratch'] = .60; gun['atlas_grime'] = .22
# Machined brake blocks: abrasion and heat oxidation, no drawn-tube streaks.
gun_block = material('Atlas_GunMetalBrake', (.24, .25, .255), .85, .50)
gun_block['atlas_scratch'] = .64; gun_block['atlas_grime'] = .22
barrel_secondary = material('Atlas_PaintSecondaryBarrel', (.205, .225, .235), .08, .61)
barrel_primary = material('Atlas_PaintPrimaryBarrel', PRIMARY, .08, .66)
for m in (barrel_secondary, barrel_primary):
    m['atlas_face_wear'] = .60; m['atlas_streak'] = (160.0, 4.0, 160.0); m['atlas_grime'] = .15
copper = material('Atlas_CoilCopper', (.72, .38, .20), .95, .33)
ceramic = material('Atlas_InsulatorCeramic', (.78, .77, .72), .0, .45)
plasma_lens = material('Atlas_PlasmaLens', (.25, .85, 1.0), .05, .2, emission=3.0)
cyan = material('Atlas_StatusLens', (.1, .75, .72), .08, .24, emission=.6)
white = material('Atlas_Stencil', (.83, .86, .8), .05, .49)

groups = {}
def part(name, at=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None); bpy.context.collection.objects.link(obj)
    obj.empty_display_type = 'ARROWS'; obj.empty_display_size = .1
    obj.location = gv(at)
    if parent: obj.parent = parent; obj.matrix_parent_inverse = parent.matrix_world.inverted()
    groups[obj] = []; bpy.context.view_layer.update(); return obj

def mesh(name, verts, faces, mat, group, bevel=0):
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
        poly.use_smooth = bool(bevel)
    if bevel:
        mod = obj.modifiers.new('Forged edge radii', 'BEVEL'); mod.width = bevel; mod.segments = 3 if bevel >= .018 else 1
        mod.limit_method = 'ANGLE'; mod.angle_limit = .58
        if mat == paint:
            data.materials.append(paint_edge); mod.material = len(data.materials) - 1
        mod.harden_normals = True
        mod = obj.modifiers.new('Weighted machining normals', 'WEIGHTED_NORMAL'); mod.keep_sharp = True; mod.weight = 40
    groups[group].append(obj); return obj

def prism(name, outline, y0, y1, mat, group, bevel=.009, top=None):
    """Closed section between a lower and (optionally tapered) upper outline."""
    top = top or outline; n = len(outline)
    verts = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in top]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)

def loft(name, levels, mat, group, bevel=.009):
    """Closed shell through (y, outline) levels with matching vertex counts."""
    n = len(levels[0][1]); verts = [(x, y, z) for y, outline in levels for x, z in outline]
    faces = [tuple(reversed(range(n))), tuple(range((len(levels) - 1) * n, len(levels) * n))]
    for k in range(len(levels) - 1):
        faces += [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)

def square_bore_face(name, center, half_w, half_h, bore, depth, mat, group, n=32):
    """Rectangular plate pierced by a round bore, facing -Z (muzzle faces)."""
    c = Vector(center); verts = []
    for dz in (-depth / 2, depth / 2):
        for i in range(n):
            a = i * math.tau / n; d = Vector((math.cos(a), math.sin(a)))
            k = min(half_w / max(abs(d.x), 1e-6), half_h / max(abs(d.y), 1e-6))
            verts.append((c.x + d.x * k, c.y + d.y * k, c.z + dz))
        for i in range(n):
            a = i * math.tau / n
            verts.append((c.x + math.cos(a) * bore, c.y + math.sin(a) * bore, c.z + dz))
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j, n + i), (2 * n + i, 3 * n + i, 3 * n + j, 2 * n + j),
                  (i, 2 * n + i, 2 * n + j, j), (n + i, n + j, 3 * n + j, 3 * n + i)]
    obj = mesh(name, verts, faces, mat, group)
    for k, poly in enumerate(obj.data.polygons): poly.use_smooth = k % 4 == 3
    return obj

def inside(point, outline):
    x, z = point; hit = False
    for (x1, z1), (x2, z2) in zip(outline, outline[1:] + outline[:1]):
        if (z1 > z) != (z2 > z) and x < x1 + (z - z1) * (x2 - x1) / (z2 - z1): hit = not hit
    return hit

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

def bolt(at, axis, group, r=.012, low=False):
    # low: countersunk barrel hardware, its crown only ~2 mm proud.
    p = Vector(at); d = Vector(axis).normalized(); h = .45 if low else 1.0
    if low: p = p - d * .002
    cylinder('Fastener recessed steel washer', p - d * .003, p + d * .001, r * 1.34, oxidized, group, 20, .001)
    turned('Rounded machined button fastener', p, d, [(.000, r), (.003 * h, r), (.008 * h, r * .88), (.011 * h, r * .62), (.011 * h, r * .35), (.005 * h, r * .35)], steel, group, 20, hex_socket=True)
    cylinder('Recessed fastener socket floor', p + d * .0048 * h, p + d * .0051 * h, r * .35, dark, group, 6, 0)

def tube(name, points, r, mat, group):
    for a, b in zip(points, points[1:]): cylinder(name, a, b, r, mat, group, 12, 0)

def plane_point(a, b, c, x, z):
    """Y on the plane through a,b,c at (x,z): seats hardware on sloped armor."""
    a, b, c = Vector(a), Vector(b), Vector(c); n = (b - a).cross(c - a)
    return a.y - (n.x * (x - a.x) + n.z * (z - a.z)) / n.y

root = part('AtlasTurret')
base = part('TurretBase', parent=root)
yaw = part('TurretYaw', YAW, root)
pitch = part('TurretPitch', PITCH, yaw)
cannon = part('AttachmentCannon', PITCH, pitch)
recoil = part('CannonRecoil', PITCH, cannon)
plasma = part('AttachmentPlasma', PITCH, pitch)
cx, cz = YAW[0], YAW[2]

# ---------------------------------------------------------------- base ring
# A machined adapter plate clamps into both recessed roof T-slots at X=+-.50
# through their 56 mm opening. It stands on four machined pads on the forward
# service cover (top .498), clearing the cover's 11 mm bolt crowns.
plate_y = .511
# The enlarged turret sits .18 m further aft so its race stays over the roof.
bz = -.14
for x in (-.20, .20):
    for z in (bz - .12, bz + .12):
        box('Adapter bearing pad', (x, .50475, z), (.070, .0125, .070), steel, base, .002)
outline = []
for sx, sz, start in [(1, 1, 0), (-1, 1, math.pi / 2), (-1, -1, math.pi), (1, -1, 3 * math.pi / 2)]:
    ox = sx * (.60 - .06); oz = bz + sz * (.54 - .06)
    for i in range(7):
        a = start + i * math.pi / 12; outline.append((ox + math.cos(a) * .06, oz + math.sin(a) * .06))
prism('Rail-clamped turret adapter plate', outline, plate_y, plate_y + .022, secondary, base, .004)
for x in (-.5, .5):
    # Inboard of the rail end closures (Z -.55..-.51) and clear of the nut.
    for z in (bz - .14, bz + .18):
        # Neck passes the rail lips; the wider foot sits under them on the floor.
        box('T-slot clamp neck', (x, .4965, z), (.040, .030, .060), steel, base, .002)
        box('Captured T-slot clamp foot', (x, .4790, z), (.078, .005, .060), steel, base, .001)
        bolt((x, plate_y + .022, z), (0, 1, 0), base, .013)
for x in (-.565, .565):
    box('Adapter plate stiffening rib', (x, plate_y + .031, bz), (.028, .018, .44), secondary, base, .003)
# Bolted traverse race: flange, raised bearing ring, rubber dust seal.
ring('Traverse race bolting flange', (cx, plate_y + .028, bz), (0, 1, 0), .530, .430, .012, steel, base, 96)
for i in range(24):
    a = i * math.tau / 24
    bolt((cx + math.cos(a) * .502, plate_y + .034, bz + math.sin(a) * .502), (0, 1, 0), base, .010)
turned('Machined traverse bearing race', (cx, plate_y + .034, bz), (0, 1, 0),
       [(0, .470), (.004, .478), (.018, .478), (.022, .469)], edge_steel, base, 96, open_end=True)
ring('Traverse race inner wall', (cx, plate_y + .045, bz), (0, 1, 0), .470, .440, .022, steel, base, 96)

# ------------------------------------------------------------- yaw housing
# One folded, low armored casting: a steep glacis, raked cheeks and a rear
# bustle. The enamel shell sits on a dark turret basket ring with a 4 mm seam.
cylinder('Turret basket ring', (cx, .569, cz), (cx, .591, cz), .318, secondary, yaw, 72, .004)
ring('Race rubber dust seal', (cx, .5725, cz), (0, 1, 0), .333, .316, .007, rubber, yaw, 72)
# Boxy armored casting after the user's references: vertical walls with a
# chamfered roof edge, and two forward cheeks framing a recessed gun embrasure
# for the block mantlet. Values are pre-scale (see TURRET_SCALE below).
# Cheeks reach Z=F; the embrasure floor NZ sits just behind the trunnion (rel -.28).
W, F, R, C, NX, NZ = .356, -.44, .40, .05, .235, -.225
def casting_outline(w, f, r, c, nx, nz):
    return [(-w + c, f), (-nx, f), (-nx, nz), (nx, nz), (nx, f), (w - c, f), (w, f + c), (w, r - c), (w - c, r), (-w + c, r), (-w, r - c), (-w, f + c)]
lower = casting_outline(W, F, R, C, NX, NZ)
upper = casting_outline(W - .045, F + .045, R - .045, .03, NX + .045, NZ + .045)
Y0, YW, Y1 = .595, .790, .835
shell = loft('Folded turret armor casting', [(Y0, [(x + cx, z + cz) for x, z in lower]), (YW, [(x + cx, z + cz) for x, z in lower]),
             (Y1, [(x + cx, z + cz) for x, z in upper])], paint, yaw, .018)
# Secondary roof plate: fitted 3 mm proud with a narrow seam, bolted on its edge.
roof = [(x * .90 + cx, z * .90 + cz + .012) for x, z in upper]
prism('Fitted turret roof plate', roof, Y1 - .002, Y1 + .014, secondary, yaw, .004)
for i, (x, z) in enumerate(roof):
    nx, nz = roof[(i + 1) % len(roof)]
    if math.hypot(nx - x, nz - z) < .15: continue
    for f in (.25, .75):
        px = x + (nx - x) * f; pz = z + (nz - z) * f
        inset = Vector((cx - px, 0, cz - pz)).normalized() * .03
        if inside((px + inset.x, pz + inset.z), roof):
            bolt((px + inset.x, Y1 + .014, pz + inset.z), (0, 1, 0), yaw, .010)

# Commander hatch: hinged ring, domed lid, rubber gasket, grab handle.
hx, hz = cx + .12, cz + .15
cylinder('Hatch ring seat', (hx, Y1 + .014, hz), (hx, Y1 + .030, hz), .105, secondary, yaw, 48, .003)
ring('Hatch rubber gasket', (hx, Y1 + .032, hz), (0, 1, 0), .093, .082, .004, rubber, yaw, 48)
turned('Domed hatch lid', (hx, Y1 + .030, hz), (0, 1, 0), [(0, .090), (.010, .089), (.020, .080), (.026, .060), (.029, .0)], paint, yaw, 48)
for dx in (-.03, .03):
    cylinder('Hatch hinge knuckle', (hx + dx - .018, Y1 + .038, hz + .098), (hx + dx + .018, Y1 + .038, hz + .098), .014, steel, yaw, 16, .002)
cylinder('Hatch hinge pin', (hx - .066, Y1 + .038, hz + .098), (hx + .066, Y1 + .038, hz + .098), .006, edge_steel, yaw, 12, 0)
tube('Hatch grab handle', [(hx - .04, Y1 + .052, hz - .045), (hx - .04, Y1 + .066, hz - .045), (hx + .04, Y1 + .066, hz - .045), (hx + .04, Y1 + .052, hz - .045)], .006, steel, yaw)

# Armored sensor head with an inset cyan lens, seated left of the hatch.
sx, sz = cx - .15, cz - .06
box('Sensor head armored housing', (sx, Y1 + .052, sz), (.10, .075, .12), secondary, yaw, .012)
box('Sensor lens protective pocket', (sx, Y1 + .054, sz - .061), (.074, .044, .010), dark, yaw, .004)
box('Recessed sensor lens', (sx, Y1 + .054, sz - .064), (.058, .030, .004), cyan, yaw, .002)
for dx in (-.035, .035): bolt((sx + dx, Y1 + .090, sz + .03), (0, 1, 0), yaw, .008)

# Lifting eyes welded to the roof plate corners.
for side in (-1, 1):
    x = cx + side * .258; z = cz + .30
    for dz in (-.018, .018):
        cylinder('Lifting eye weld seat', (x, Y1 + .012, z + dz), (x, Y1 + .022, z + dz), .012, steel, yaw, 16, .002)
    tube('Forged lifting eye', [(x, Y1 + .018, z - .018), (x, Y1 + .052, z - .012), (x, Y1 + .052, z + .012), (x, Y1 + .018, z + .018)], .007, secondary, yaw)

# Rear bustle: an actual recessed cooling aperture with a floor and louvers.
rz = cz + R
box('Bustle aperture recessed floor', (cx, .700, rz - .010), (.46, .120, .006), dark, yaw, .002)
for y in (.655, .745):
    box('Bustle aperture rail', (cx, y, rz + .002), (.50, .022, .024), paint, yaw, .004)
for x in (-.244, .244):
    box('Bustle aperture upright', (cx + x, .700, rz + .002), (.022, .112, .024), paint, yaw, .004)
for y in (.672, .690, .708, .726):
    box('Bustle recessed cooling louver', (cx, y, rz - .002), (.46, .007, .014), secondary, yaw, .002)
# Recessed flank cooling grilles: dark floor, proud frame, horizontal slats.
for side in (-1, 1):
    x = cx + side * W; z = cz - .10
    box('Flank grille recessed floor', (x + side * .002, .700, z), (.004, .100, .180), dark, yaw, .001)
    for y in (.643, .757):
        box('Flank grille frame rail', (x + side * .007, y, z), (.014, .014, .200), paint, yaw, .003)
    for dz in (-.093, .093):
        box('Flank grille frame upright', (x + side * .007, .700, z + dz), (.014, .100, .014), paint, yaw, .003)
    for i in range(5):
        box('Flank grille slat', (x + side * .005, .661 + i * .0195, z), (.010, .007, .172), secondary, yaw, .001)
    for dz in (-.093, .093):
        for y in (.643, .757): bolt((x + side * .014, y, z + dz), (side, 0, 0), yaw, .006)
# Stowage bins on the flanks (supported by brackets into the casting).
for side in (-1, 1):
    x = cx + side * W; z = cz + .22
    box('Flank stowage bin', (x + side * .030, .672, z), (.050, .080, .28), secondary, yaw, .008)
    box('Stowage bin lid strap', (x + side * .057, .672, z), (.004, .082, .026), steel, yaw, .001)
    for dz in (-.10, .10): box('Stowage bin bracket', (x + side * .002, .642, z + dz), (.018, .014, .03), steel, yaw, .002)

# Trunnion cheeks: armored bosses either side of the gun opening, carrying the
# elevation bearings. The opening between them is a real recess, not a decal.
# The casting's cheeks carry the elevation bearings on the embrasure walls.
for side in (-1, 1):
    turned('Elevation bearing collar', (side * NX, PITCH[1], PITCH[2]), (-side, 0, 0), [(0, .062), (.008, .062), (.016, .054), (.020, .042), (.022, .0)], steel, yaw, 40)
    for i in range(6):
        a = i * math.tau / 6
        bolt((side * (NX - .010), PITCH[1] + math.sin(a) * .050, PITCH[2] + math.cos(a) * .050), (-side, 0, 0), yaw, .006)
box('Embrasure recessed backing', (0, .705, cz + NZ - .004), (.40, .17, .012), dark, yaw, .003)

# -------------------------------------------------------------- mantlet
cylinder('Trunnion axle', (-.225, PITCH[1], PITCH[2]), (.225, PITCH[1], PITCH[2]), .040, steel, pitch, 32, .002)
box('Block cast gun mantlet', (0, PITCH[1], PITCH[2] - .030), (.30, .20, .15), paint, pitch, .026)
box('Mantlet armored face', (0, PITCH[1], PITCH[2] - .109), (.26, .16, .012), secondary, pitch, .006)
for dx in (-.105, .105):
    for dy in (-.060, .060): bolt((dx, PITCH[1] + dy, PITCH[2] - .115), (0, 0, -1), pitch, .008)
ring('Weapon quick-change collar', (0, PITCH[1], -.728), (0, 0, 1), .080, .052, .024, steel, pitch, 48)
for i in range(6):
    a = i * math.tau / 6 + math.pi / 6
    bolt((math.cos(a) * .066, PITCH[1] + math.sin(a) * .066, -.740), (0, 0, -1), pitch, .007)
cylinder('Collar bore shadow', (0, PITCH[1], -.722), (0, PITCH[1], -.726), .052, dark, pitch, 32, 0)

# ------------------------------------------------------------- cannon
PY = PITCH[1]
cylinder('Cannon cradle recoil sleeve', (0, PY, -.714), (0, PY, -.870), .078, secondary, cannon, 40, .006)
ring('Cradle front retaining band', (0, PY, -.862), (0, 0, 1), .083, .074, .016, steel, cannon, 40)
for side in (-1, 1):
    x = side * .066
    cylinder('Recuperator cylinder', (x, PY - .076, -.720), (x, PY - .076, -.842), .021, steel, cannon, 24, .003)
    turned('Recuperator end cap', (x, PY - .076, -.842), (0, 0, -1), [(0, .021), (.006, .020), (.010, .012)], edge_steel, cannon, 24)
    box('Recuperator saddle', (x * .75, PY - .058, -.765), (.04, .03, .03), secondary, cannon, .003)
# The barrel slides on CannonRecoil; its breech end stays inside the sleeve.
# A thick-walled steel tube (the profile returns along the 30 mm bore) carries
# painted thermal-sleeve sections, latched clamp bands and a bolted evacuator,
# so it shares the hull's enamel, wear and hardware language.
turned('Gun barrel steel tube', (0, PY, -.630), (0, 0, -1),
       [(0, .060), (.24, .060), (.25, .055), (.80, .050), (.82, .050), (.82, .030), (0, .030)], gun, recoil, 48)
cylinder('Deep bore shadow', (0, PY, -1.000), (0, PY, -1.004), .030, dark, recoil, 32, 0)
def sleeve(z0, z1, radius, material):
    length = z0 - z1
    turned('Thermal sleeve section', (0, PY, z0), (0, 0, -1),
           [(0, radius - .004), (.004, radius), (length - .004, radius), (length, radius - .004)], material, recoil, 48)
sleeve(-.870, -1.075, .066, barrel_secondary)
sleeve(-1.205, -1.370, .060, barrel_secondary)
turned('Painted bore evacuator', (0, PY, -1.075), (0, 0, -1),
       [(0, .060), (.012, .074), (.022, .080), (.108, .080), (.118, .074), (.130, .060)], barrel_primary, recoil, 48)
for i in range(8):
    a = i * math.tau / 8
    bolt((math.cos(a) * .080, PY + math.sin(a) * .080, -1.140), (math.cos(a), math.sin(a), 0), recoil, .006, low=True)
for z, radius in ((-.872, .066), (-1.073, .066), (-1.207, .060), (-1.368, .060)):
    ring('Sleeve clamp band', (0, PY, z), (0, 0, 1), radius + .005, radius - .004, .014, steel, recoil, 48)
    box('Clamp band latch', (0, PY + radius + .006, z), (.020, .006, .018), steel, recoil, .002)
# Open muzzle brake: top/bottom plates and segmented cheeks leave a square
# channel with two real side ports per side; a pierced front face closes it.
for y in (-.042, .042):
    box('Muzzle brake plate', (0, PY + y, -1.480), (.150, .016, .090), gun_block, recoil, .004)
for side in (-1, 1):
    for z, length in ((-1.446, .022), (-1.491, .016)):
        box('Muzzle brake cheek', (side * .057, PY, z), (.036, .068, length), gun_block, recoil, .003)
    for z in (-1.449, -1.490):
        bolt((side * .075, PY, z), (side, 0, 0), recoil, .005, low=True)
square_bore_face('Muzzle brake front face', (0, PY, -1.535), .075, .050, .030, .020, gun_block, recoil)
box('Muzzle brake retaining key', (0, PY + .052, -1.480), (.022, .006, .05), steel, recoil, .001)

# -------------------------------------------------------------- plasma
cylinder('Plasma feed coupling', (0, PY, -.714), (0, PY, -.750), .060, steel, plasma, 40, .004)
box('Plasma emitter core housing', (0, PY, -.845), (.170, .140, .190), secondary, plasma, .016)
for side in (-1, 1):
    # Enamel side armor with inset capacitor windows and edge bolts.
    box('Emitter enamel side armor', (side * .094, PY, -.845), (.022, .150, .200), paint, plasma, .008)
    for z in (-.795, -.895):
        cylinder('Capacitor cell window', (side * .104, PY + .030, z + .03), (side * .104, PY + .030, z - .03), .010, plasma_lens, plasma, 16, 0)
        box('Capacitor window pocket', (side * .102, PY + .030, z), (.006, .030, .072), dark, plasma, .002)
    for y in (-.055, .055):
        for z in (-.760, -.930): bolt((side * .105, PY + y, z), (side, 0, 0), plasma, .007)
# Heat-sink fins sit in a recessed top channel.
box('Heat sink channel floor', (0, PY + .071, -.845), (.12, .004, .17), dark, plasma, .001)
for i in range(7):
    box('Machined heat sink fin', (0, PY + .086, -.775 - i * .023), (.11, .030, .006), steel, plasma, .001)
# Coil accelerator: copper windings on a steel core, separated by ceramic.
cylinder('Accelerator core tube', (0, PY, -.935), (0, PY, -1.180), .028, steel, plasma, 32, .002)
for i in range(4):
    z = -.970 - i * .052
    ring('Copper accelerator winding', (0, PY, z), (0, 0, 1), .064, .031, .028, copper, plasma, 48)
    ring('Ceramic winding separator', (0, PY, z - .026), (0, 0, 1), .058, .029, .006, ceramic, plasma, 48)
# Twin field rails above and below, supported by clamp blocks at each end.
for y in (-.080, .080):
    box('Field rail', (0, PY + y, -1.070), (.046, .018, .300), steel, plasma, .004)
    for z in (-.930, -1.205):
        box('Field rail support clamp', (0, PY + y * .82, z), (.056, .036, .024), secondary, plasma, .004)
    box('Field rail insulator strip', (0, PY + y * .93, -1.070), (.030, .006, .260), ceramic, plasma, .001)
turned('Flared emitter nozzle', (0, PY, -1.180), (0, 0, -1),
       [(0, .034), (.020, .040), (.050, .054), (.070, .058), (.075, .052)], steel, plasma, 48, open_end=True)
ring('Emitter focusing lens ring', (0, PY, -1.235), (0, 0, 1), .046, .022, .006, plasma_lens, plasma, 48)
cylinder('Emitter throat shadow', (0, PY, -1.220), (0, PY, -1.228), .022, dark, plasma, 24, 0)

# Muzzle markers are published for runtime effects and authoritative rays.
part('MuzzleCannon', CANNON_MUZZLE, recoil)
part('MuzzlePlasma', PLASMA_MUZZLE, plasma)

# ---------------------------------------------------- dual / quad upgrades
# Multi-barrel attachments reuse the approved single weapon: each barrel is a
# copy scaled in cross-section only (circles stay round, lengths unchanged) and
# offset from the bore axis. Each cannon barrel keeps its own recoil node.
VARIANTS = {'cannon_dual': (.82, [(-.078, 0.0), (.078, 0.0)]),
            'cannon_quad': (.66, [(-.064, .060), (.064, .060), (-.064, -.060), (.064, -.060)]),
            'plasma_dual': (.80, [(-.090, 0.0), (.090, 0.0)]),
            'plasma_quad': (.62, [(-.070, .062), (.070, .062), (-.070, -.062), (.070, -.062)])}
def copied(objects, s_cross, ox, oy, group):
    axis = gv((0, PY, 0))
    matrix = Matrix.Translation(gv((ox, oy, 0)) - gv((0, 0, 0))) @ Matrix.Translation(axis) \
        @ Matrix.Diagonal((s_cross, 1.0, s_cross, 1.0)) @ Matrix.Translation(-axis)
    for source in objects:
        obj = source.copy(); obj.data = source.data.copy(); bpy.context.collection.objects.link(obj)
        obj.data.transform(matrix); groups[group].append(obj)
variant_groups = {}
for label, (s_cross, offsets) in VARIANTS.items():
    family = label.split('_')[0]
    title = 'Attachment' + family.capitalize() + label.split('_')[1].capitalize()
    group = part(title, PITCH, pitch); variant_groups[label] = group
    source_body = groups[cannon] if family == 'cannon' else groups[plasma]
    for index, (ox, oy) in enumerate(offsets):
        copied(source_body, s_cross, ox, oy, group)
        if family == 'cannon':
            barrel = part('CannonRecoil%s_%d' % (label.split('_')[1].capitalize(), index), PITCH, group)
            copied(groups[recoil], s_cross, ox, oy, barrel)
            part('MuzzleCannon%s_%d' % (label.split('_')[1].capitalize(), index), (CANNON_MUZZLE[0] + ox, CANNON_MUZZLE[1] + oy, CANNON_MUZZLE[2]), barrel)
        else:
            part('MuzzlePlasma%s_%d' % (label.split('_')[1].capitalize(), index), (PLASMA_MUZZLE[0] + ox, PLASMA_MUZZLE[1] + oy, PLASMA_MUZZLE[2]), group)
    # A cast cradle block joins the barrels to the mantlet collar.
    xs = [o[0] for o in offsets]; ys = [o[1] for o in offsets]
    width = (max(xs) - min(xs)) + (.17 if family == 'cannon' else .15) * s_cross + .03
    height = (max(ys) - min(ys)) + .15 * s_cross + .03
    box('Multi-barrel cradle block', (0, PY + (max(ys) + min(ys)) * .5, -.742), (width, height, .050), paint, group, .014)
    box('Cradle block armored face', (0, PY + (max(ys) + min(ys)) * .5, -.769), (width - .03, height - .03, .006), secondary, group, .003)
    for sx in (-1, 1):
        for sy in (-1, 1):
            bolt((sx * (width * .5 - .022), PY + (max(ys) + min(ys)) * .5 + sy * (height * .5 - .022), -.773), (0, 0, -1), group, .007)

def finalize(group):
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
    obj.name = group.name + 'Surface'; bpy.ops.object.select_all(action='DESELECT'); return obj

# The user found the first turret far too small for the hull. Scale the whole
# rotating assembly about the basket-ring floor and move it aft onto the race.
# Bevel widths stay absolute, so chamfers remain fine metal edges.
TURRET_SCALE = 1.45
scale_point = gv((0, .569, -.32)); shift = gv((0, 0, bz + .32)) - gv((0, 0, 0))
M = Matrix.Translation(scale_point + shift) @ Matrix.Scale(TURRET_SCALE, 4) @ Matrix.Translation(-scale_point)
rotating = [g for g in groups if g not in (root, base)]
for group in rotating:
    for obj in groups[group]: obj.data.transform(M)
# Record every original pivot first: children follow their parent's move.
empties = [g for g in rotating if g is not yaw]
targets = {empty: M @ empty.matrix_world.translation for empty in empties}
yaw.matrix_world = Matrix.Translation(gv((0, .52, bz))); bpy.context.view_layer.update()
for empty in empties:
    empty.matrix_world = Matrix.Translation(targets[empty]); bpy.context.view_layer.update()
def godot(o): p = o.matrix_world.translation; return (round(p.x, 5), round(p.z, 5), round(-p.y, 5))
YAW = godot(yaw); PITCH = godot(pitch)
CANNON_MUZZLE = godot(bpy.data.objects['MuzzleCannon']); PLASMA_MUZZLE = godot(bpy.data.objects['MuzzlePlasma'])
MUZZLE_OFFSETS = {'cannon': round(PITCH[2] - CANNON_MUZZLE[2], 5), 'plasma': round(PITCH[2] - PLASMA_MUZZLE[2], 5)}
# Per-attachment barrel offsets from the single-barrel muzzle, pitch frame.
BARRELS = {'cannon': [[0.0, 0.0]], 'plasma': [[0.0, 0.0]]}
for label in VARIANTS:
    family = label.split('_')[0]; base_muzzle = CANNON_MUZZLE if family == 'cannon' else PLASMA_MUZZLE
    names = sorted(o.name for o in bpy.data.objects if o.type == 'EMPTY' and o.name.startswith('Muzzle' + family.capitalize() + label.split('_')[1].capitalize() + '_'))
    BARRELS[label] = [[round(godot(bpy.data.objects[n])[0] - base_muzzle[0], 5), round(godot(bpy.data.objects[n])[1] - base_muzzle[1], 5)] for n in names]
print('TURRET_PIVOTS', json.dumps({'yaw': YAW, 'pitch': PITCH, 'muzzle_offsets': MUZZLE_OFFSETS}))
for group in list(groups): finalize(group)
bpy.context.view_layer.update()

def descendants(obj):
    result = [obj]
    for ch in obj.children: result += descendants(ch)
    return result

# ------------------------------------------------------ clearance audit
# Sampled surface-intersection audit of the moving turret against the imported
# approved hull GLB (base only; optional deck modules are reported separately).
def audit():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'))
    imported = [o for o in bpy.data.objects if o not in before]
    optional_names = {'ArmorSideReference', 'ArmorSideHeavy', 'ArmorTop', 'ArmorFront', 'ArmorRear', 'ExhaustSmall', 'ExhaustMedium', 'ExhaustLarge'}
    def owner(o):
        p = o
        while p is not None:
            if p.name.split('.')[0] in optional_names: return p.name.split('.')[0]
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
    hull_sets = {}
    for o in imported:
        if o.type == 'MESH': hull_sets.setdefault(owner(o), []).append(o)
    hull_trees = {k: tree(v) for k, v in hull_sets.items()}
    moving = {'yaw': [o for o in descendants(yaw) if o.type == 'MESH' and not any(o in descendants(a) for a in (pitch,))],
              'mantlet': [o for o in descendants(pitch) if o.type == 'MESH' and not any(o in descendants(a) for a in [cannon, plasma] + list(variant_groups.values()))],
              'cannon': [o for o in descendants(cannon) if o.type == 'MESH'],
              'plasma': [o for o in descendants(plasma) if o.type == 'MESH']}
    for label, group in variant_groups.items():
        moving[label] = [o for o in descendants(group) if o.type == 'MESH']
    static_tree = tree([o for o in descendants(base) if o.type == 'MESH'])
    report = {'scope': 'Sampled triangle-overlap audit against imported atlas_mx.glb. Per 5-degree bearing the lowest clear elevation of mantlet+attachment is measured (7-step bisection, 1 degree margin); the runtime rule (max of the two neighbouring samples) is then verified at every 2.5 degrees of yaw from that floor to the +30 degree stop in 2.5 degree steps. Adapter checked at rest.',
              'yaw_step_degrees': 5, 'contacts': {}}
    report['contacts']['adapter_vs_base'] = len(static_tree.overlap(hull_trees['base']))
    report['contacts']['adapter_vs_objects'] = sorted({o.name for o in hull_sets['base'] if static_tree.overlap(tree([o]))})
    yaw0 = yaw.matrix_basis.copy(); pitch0 = pitch.matrix_basis.copy()
    def pose(yaw_deg, pitch_deg):
        yaw.matrix_basis = yaw0 @ Matrix.Rotation(math.radians(yaw_deg), 4, 'Z')
        pitch.matrix_basis = pitch0 @ Matrix.Rotation(math.radians(pitch_deg), 4, 'X')
        bpy.context.view_layer.update()
    def hits(objs, hull_label='base'):
        return len(tree(objs).overlap(hull_trees[hull_label]))
    profile = {}
    for kind in ATTACHMENTS:
        objs = moving['mantlet'] + moving[kind]; values = []
        for yaw_deg in range(0, 360, 5):
            pose(yaw_deg, 0.0)
            if hits(objs):
                culprits = [o.name for o in objs if len(tree([o]).overlap(hull_trees['base']))]
                raise RuntimeError('%s collides with the hull at yaw %d, zero elevation: %s' % (kind, yaw_deg, culprits[:8]))
            pose(yaw_deg, DEPRESSION_FLOOR)
            if not hits(objs):
                values.append(DEPRESSION_FLOOR); continue
            lo, hi = DEPRESSION_FLOOR, 0.0
            for step in range(7):
                mid = (lo + hi) * .5; pose(yaw_deg, mid)
                if hits(objs): lo = mid
                else: hi = mid
            values.append(min(0.0, float(math.ceil(hi + 1.0))))
        profile[kind] = values
    report['depression_profile_degrees'] = profile
    def floor_at(kind, yaw_deg):
        i = int(yaw_deg // 5) % 72
        return max(profile[kind][i], profile[kind][(i + 1) % 72])
    worst = {}
    for half_step in range(144):
        yaw_deg = half_step * 2.5
        for kind in ATTACHMENTS:
            low = floor_at(kind, yaw_deg)
            pitches = [low + k * 2.5 for k in range(40) if low + k * 2.5 < PITCH_LIMITS[1]] + [PITCH_LIMITS[1]]
            for pitch_deg in pitches:
                pose(yaw_deg, pitch_deg)
                for label in ('yaw', 'mantlet', kind):
                    t = tree(moving[label])
                    for hull_label, hull_tree in hull_trees.items():
                        count = len(t.overlap(hull_tree))
                        if count:
                            key = label + '_vs_' + hull_label
                            worst.setdefault(key, []).append([yaw_deg, pitch_deg, count])
    yaw.matrix_basis = yaw0; pitch.matrix_basis = pitch0
    bpy.context.view_layer.update()
    report['contacts']['moving'] = {k: {'samples': len(v), 'first': v[:6]} for k, v in worst.items()}
    base_hits = {k: v for k, v in worst.items() if k.endswith('_vs_base')}
    report['base_clear'] = not base_hits and report['contacts']['adapter_vs_base'] == 0
    for o in imported: bpy.data.objects.remove(o, do_unlink=True)
    return report

ATTACHMENTS = ['cannon', 'plasma'] + list(VARIANTS)
clearance = audit()
print('TURRET_CLEARANCE', json.dumps(clearance))

sys.path.insert(0, str(ROOT / 'tools'))
from atlas_surface_bake import bake_surface_atlases
surface = bake_surface_atlases(root, cannon, [plasma] + list(variant_groups.values()), RUNTIME, quick=QUICK, prefix='Atlas_Turret', face_wear=.78,
                               families=('Primary', 'Secondary', 'Hardware'),
                               sizes={'Primary': 2048, 'Secondary': 1024, 'Hardware': 2048})

def export_model(obj, filename):
    bpy.ops.object.select_all(action='DESELECT')
    for item in descendants(obj): item.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = RUNTIME / filename
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_extras=True, export_animations=False, export_materials='EXPORT', export_texcoords=True, export_normals=True)
    # Reference the external canonical maps, as the hull GLB does.
    raw = path.read_bytes(); json_len = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_len]); binary = raw[20 + json_len + 8:]
    image_views = {im['bufferView'] for im in document.get('images', []) if 'bufferView' in im}
    for im in document.get('images', []):
        im.pop('bufferView', None); im.pop('mimeType', None); im['uri'] = im['name'] + '.png'
        if not (RUNTIME / im['uri']).exists(): raise RuntimeError('Missing portable material ' + im['uri'])
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

export_model(root, 'atlas_turret.glb')
stats = {}
for label, group in [('base', base), ('housing', yaw), ('mantlet', pitch), ('cannon', cannon), ('plasma', plasma)] + list(variant_groups.items()):
    objs = [o for o in descendants(group) if o.type == 'MESH']
    if label == 'housing': objs = [o for o in objs if o not in descendants(pitch)]
    if label == 'mantlet': objs = [o for o in objs if not any(o in descendants(a) for a in [cannon, plasma] + list(variant_groups.values()))]
    for o in objs: o.data.calc_loop_triangles()
    stats[label] = sum(len(o.data.loop_triangles) for o in objs)
corners = [o.matrix_world @ Vector(p) for o in descendants(root) if o.type == 'MESH' for p in o.bound_box]
points = [(p.x, p.z, -p.y) for p in corners]
manifest = {'name': 'Atlas MX turret', 'id': 'atlas_turret', 'runtime': 'atlas_turret.glb',
            'authoring': 'Godot metres in the Atlas hull frame, X right Y up -Z forward; runtime factor three applied by AtlasVisual',
            'generator': 'tools/build-atlas-turret.py', 'yaw_pivot': YAW, 'pitch_pivot': PITCH,
            'pitch_limits_degrees': PITCH_LIMITS, 'muzzles': {'cannon': CANNON_MUZZLE, 'plasma': PLASMA_MUZZLE}, 'muzzle_offsets': MUZZLE_OFFSETS, 'barrels': BARRELS, 'turret_scale': TURRET_SCALE,
            'nodes': ['TurretBase', 'TurretYaw', 'TurretPitch', 'AttachmentCannon', 'CannonRecoil', 'AttachmentPlasma', 'MuzzleCannon', 'MuzzlePlasma'],
            'bounds_all_attachments': {'min': [round(min(p[i] for p in points), 5) for i in range(3)], 'max': [round(max(p[i] for p in points), 5) for i in range(3)]},
            'triangles': stats, 'clearance': clearance, 'surface_atlases': surface, 'approval': 'Pending user visual approval'}
(RUNTIME / 'atlas_turret_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('TURRET_EXPORT', json.dumps({k: manifest[k] for k in ('triangles', 'bounds_all_attachments')}))

if NO_RENDER:
    print('TURRET_COMPLETE', str(RUNTIME)); sys.exit(0)

# ------------------------------------------------------------ review renders
# Actual source renders with the hull imported beneath, not concept art.
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'battlebots/assets/models/atlas_runtime/atlas_mx.glb'))
for o in list(bpy.data.objects):
    if o.name.split('.')[0] in ('ArmorSideReference', 'ArmorSideHeavy', 'ArmorTop', 'ArmorFront', 'ArmorRear', 'ExhaustSmall', 'ExhaustMedium', 'ExhaustLarge', 'AtlasLifter'):
        for d in descendants(o): d.hide_render = True
floor = material('Studio_Only', (.73, .75, .77), .0, .68)
bpy.ops.mesh.primitive_plane_add(size=200, location=gv((0, -.555, 0)))
bpy.context.object.data.materials.append(floor)
def light(name, at, energy, color, size, target=(0, .4, -.3)):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.shape = 'DISK'; d.size = size; d.color = color
    o = bpy.data.objects.new(name, d); bpy.context.collection.objects.link(o); o.location = gv(at); o.rotation_euler = (gv(target) - o.location).to_track_quat('-Z', 'Y').to_euler()
light('Large warm key', (-3.5, 5, -4), 350, (1, .97, .90), 4)
light('Cool side reflection', (4, 2, .5), 230, (.84, .92, 1), 3)
light('Rear rim', (-1, 3, 3), 380, (1, .95, .86), 2.5)
light('Front fill', (0, 1, -4), 60, (.94, .96, 1), 3)
scene = bpy.context.scene; scene.world = scene.world or bpy.data.worlds.new('Turret studio'); scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.65, .69, .75, 1); scene.world.node_tree.nodes['Background'].inputs[1].default_value = .25
cam_data = bpy.data.cameras.new('TurretReviewCamera'); cam = bpy.data.objects.new('TurretReviewCamera', cam_data); bpy.context.collection.objects.link(cam); scene.camera = cam
scene.render.engine = 'CYCLES'; scene.cycles.samples = 24 if QUICK else 80; scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'OPTIX'; prefs.get_devices()
    for device in prefs.devices: device.use = device.type == 'OPTIX'
    scene.cycles.device = 'GPU'
except Exception: pass
scene.render.resolution_x = 1600; scene.render.resolution_y = 1200
scene.view_settings.view_transform = 'AgX'; scene.view_settings.look = 'AgX - Medium High Contrast'
def view(name, at, target=(0, .45, -.45), ortho=2.6):
    cam.location = gv(at); cam.rotation_euler = (gv(target) - cam.location).to_track_quat('-Z', 'Y').to_euler(); cam_data.type = 'ORTHO'; cam_data.ortho_scale = ortho
    scene.render.filepath = str(SOURCE / (name + '.png')); bpy.ops.render.render(write_still=True)
def show(attachment):
    for group in [cannon, plasma] + list(variant_groups.values()):
        for o in descendants(group): o.hide_render = group != attachment
yaw.rotation_euler.z = math.radians(-28); pitch.rotation_euler.x = math.radians(8)
show(cannon); view('turret_cannon_hero', (3.2, 2.4, -4.0), ortho=3.4)
show(plasma); view('turret_plasma_hero', (3.2, 2.4, -4.0), ortho=3.4)
if not QUICK:
    show(cannon); view('turret_cannon_detail', (2.4, 1.7, -3.2), target=(0, .76, -1.0), ortho=1.7)
    show(plasma); view('turret_plasma_detail', (2.4, 1.7, -3.2), target=(0, .76, -.95), ortho=1.7)
    yaw.rotation_euler.z = 0; pitch.rotation_euler.x = 0
    show(cannon); view('turret_top', (0, 6, -.319), target=(0, 0, -.32), ortho=3.2)
    view('turret_rear_quarter', (-3.4, 2.2, 3.6), target=(0, .5, -.2), ortho=3.4)
yaw.rotation_euler.z = math.radians(-28); pitch.rotation_euler.x = math.radians(8)
for label, group in variant_groups.items():
    show(group); view('turret_' + label + '_detail', (2.4, 1.7, -3.2), target=(0, .76, -1.0), ortho=1.9)
bpy.ops.wm.save_as_mainfile(filepath=str(PREVIEW / 'atlas_turret.blend'), compress=True)
print('TURRET_COMPLETE', str(SOURCE))
