"""STRIDER 09: camouflaged reverse-knee biped with a slab hammer arm (#61).

blender --background --python tools/build-nimble-strider.py [-- --quick] [--no-bake] [--no-render]

Construction brief (source metres = game metres / 3; hull frame X right, Y up,
-Z forward; hull origin = centre of the 1.0 x 0.5 x 1.1 collision box).

Fixed constraints
- Ride: hull centre 1.2 above ground (1.1 at the bottom of the stride bob).
- Node contract (flat under NimbleStrider): Hull; ThighL/R at the hips
  (x = +-.42, y = -.22, z = .05); ShinL/R at the knees directly below
  (upper segment .62); FootL/R at the ankles directly below (lower .66). The
  runtime (NimbleVisual._pose_strider) solves the knees backward (+Z) with 2-bone
  IK and keeps the feet level; the sole lies .075 below the ankle pivot. Reach
  1.28 covers the worst stride corner (1.18) with margin.
- Arm pivot exactly at the hammer socket (.64, -.10, -.25); geometry along -Z,
  head centre 1.2 out; it rotates about local X from -30 deg (strike) to +90 deg.

Construction (primary masses -> medium plates -> fasteners)
- Head: faceted dark-bronze monocoque with joined enamel armour: camouflaged
  roof and folded brow, olive side cheeks carrying the "09" stencil, a
  projecting gunmetal visor housing whose two amber slit eyes sit in real
  pockets, a chin fold back to the neck. A cast cannon sponson on the front-left
  cheek carries a mantlet and a thick-walled bored barrel with a ported brake.
  A camouflaged cooling pack closes the rear with recessed louvres; the antenna
  rises from a sprung base on the roof.
- Torso: dark bronze keel under a slewing neck ring; a folded camouflaged chest
  and rear closure; two sponsons whose outer wall plates drop as ears around
  the hip drives (and, on the right, the shoulder drive). Each hip is carried on
  both sides: an inboard motor drum on the keel and an outboard planetary drive
  on the ear, with the thigh boss between them.
- Legs: box-section dark-bronze members; the thigh carries a bolted camo cowl
  and a knee fork with an outboard knee drive; the shin is a tapered beam with a
  front guard and a rear damper strut on welded clevis lugs; the foot has an
  ankle fork, drive, heel block and three armoured, clawed toes.
- Arm: shoulder hub on the right ear's drive, armoured upper arm, telescopic
  ram with a guide rod, and a slab hammer: a bronze core, camo cheek plates,
  olive inset panels and a bolted hardened strike edge on its underside.

Palette (from the concept, not Atlas): sand-cream enamel with olive and umber
camouflage blotches; olive drab secondary enamel panels; dark oxidised bronze
frames with warmer machined bronze caps; cooler gunmetal drive drums and
ordnance; amber emissive eyes; off-white stencil.

Proof views: hero, rear, side, top, close-up (kit review) rendered in the
runtime garage stance (legs solved by the same IK the game uses, arm at rest).
Clearance: moving assemblies against the hull over a full stride at ride and at
the bob floor, the rest hang, and the arm from strike to overhead.
"""
import bpy, math, re, sys
from pathlib import Path
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nimble_model_kit as nk
import atlas_model_kit as kitmod
from nimble_model_kit import (setup, complete, outline, rounded, section, oriented, beam, stencil_text, coil,
                              part, mesh, prism, loft, box, cylinder, ring, turned, tube, gv, src, DATA, PARTS, SCALE, ROOT)

CHASSIS = 'strider_09'
PREFIX = 'Nimble09'
BOT = DATA[CHASSIS]

# ------------------------------------------------------------------ runtime contract
_GD = (ROOT / 'battlebots/scripts/presentation/nimble_visual.gd').read_text()


def _gd_const(name):
    """Numeric constant from NimbleVisual so the review pose matches the runtime."""
    expr = re.search(r'const %s := ([^\n#]+)' % name, _GD).group(1).strip()
    vec = re.match(r'Vector3\(([^)]*)\)', expr)
    if vec:
        return Vector([float(v) for v in vec.group(1).split(',')])
    return float(eval(expr.replace('PI', 'math.pi'), {'math': math}))


FOOT_OUTBOARD = _gd_const('STRIDER_FOOT_OUTBOARD')
ANKLE_HEIGHT = _gd_const('STRIDER_ANKLE_HEIGHT')
LIFT = _gd_const('STRIDER_LIFT')
KNEE_BEND = _gd_const('STRIDER_KNEE_BEND')
HAMMER_REST = _gd_const('HAMMER_REST')
HAMMER_RAISED = _gd_const('HAMMER_RAISED')
HAMMER_STRUCK = _gd_const('HAMMER_STRUCK')

RIDE = BOT['ride_height'] / SCALE
BOB = BOT['stride']['bob'] / SCALE
STEP = BOT['stride']['step_length'] / SCALE
SIZE = src(PARTS[CHASSIS]['size'])
SOCKET = Vector((0, SIZE.y * .5, -SIZE.z * .5 + .15)) + src(BOT['hammer_socket'])
HAMMER_REACH = 1.2

# Leg layout (authored rest: hanging straight down from the hip).
HIP_X, HIP_Y, HIP_Z = .42, -.22, .05
UPPER, LOWER = .62, .66
X = Vector((1, 0, 0)); Y = Vector((0, 1, 0)); Z = Vector((0, 0, 1))

# Concept-derived palette: (sRGB, metallic, roughness).
SAND = (.79, .72, .57)
PALETTE = {
    'primary': (SAND, .07, .64),                 # sand-cream enamel (camo base)
    'secondary': ((.27, .315, .205), .07, .62),  # olive drab enamel panels
    'steel': ((.56, .50, .42), .92, .34),        # machined bronze-steel caps and pins
    'oxidized': ((.20, .168, .125), .80, .52),   # dark oxidised bronze frames
    'dark': ((.030, .027, .024), .40, .55),      # recess floors
    'rubber': ((.050, .047, .043), .0, .86),
    'gun': ((.125, .125, .12), .86, .46),        # gunmetal drums and ordnance
    'hazard': ((.84, .46, .10), .07, .58),       # amber warning bands
    'stencil': ((.88, .86, .79), .05, .50),
    'spring': ((.30, .26, .20), .85, .42),
    'lenses': {'amber': ((1.0, .60, .16), 9.0)},
}
CAMO = {'colours': [(.30, .33, .215), (.34, .235, .145), SAND, (.34, .235, .145)],
        'stops': [0.0, .37, .43, .665], 'scale': 5.5}

M = setup(PREFIX, PALETTE, camo=CAMO)
P, OL, ST, OX, DK, RB, GN, HZ, AM = (M[k] for k in ('paint', 'secondary', 'steel', 'oxidized', 'dark', 'rubber', 'gun', 'hazard', 'amber'))


# ------------------------------------------------------------------ local helpers
def V(*a):
    return Vector(a[0] if len(a) == 1 else a)


def zprism(name, profile, z0, z1, mat, group, bevel=.006):
    """Closed prism extruded along Z from an (x, y) profile."""
    n = len(profile)
    verts = [(x, y, z0) for x, y in profile] + [(x, y, z1) for x, y in profile]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def zloft(name, levels, mat, group, bevel=.006):
    """Closed shell through (z, [(x, y)...]) levels with matching counts."""
    n = len(levels[0][1]); verts = [(x, y, z) for z, prof in levels for x, y in prof]
    faces = [tuple(reversed(range(n))), tuple(range((len(levels) - 1) * n, len(levels) * n))]
    for k in range(len(levels) - 1):
        faces += [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def dprism(name, origin, d, profile, width, mat, group, bevel=.004):
    """Prism in the vertical plane through `d` (u along d, v up), width across."""
    o = Vector(origin); d = Vector(d).normalized(); lat = Y.cross(d).normalized()
    n = len(profile)
    verts = [tuple(o + d * u + Y * v + lat * s * width / 2) for s in (-1, 1) for u, v in profile]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def arc(cx, cy, r, a0, a1, steps):
    return [(cx + math.cos(a0 + (a1 - a0) * i / steps) * r, cy + math.sin(a0 + (a1 - a0) * i / steps) * r) for i in range(steps + 1)]


def bolt(at, axis, group, r=.010, n=10):
    """Button fastener seated on its plane: washer, domed crown, hex drive, dark floor."""
    p = Vector(at); d = Vector(axis).normalized()
    cylinder('Fastener seated washer', p - d * .003, p + d * .001, r * 1.34, OX, group, n, 0)
    turned('Rounded machined button fastener', p, d, [(.000, r), (.003, r), (.007, r * .86), (.010, r * .6), (.010, r * .35), (.005, r * .35)],
           ST, group, n, hex_socket=True)
    cylinder('Recessed fastener socket floor', p + d * .0048, p + d * .0051, r * .35, DK, group, 6, 0)


def drive(name, p, axis, r, depth, group, bolts=8, cap_mat=None):
    """Planetary joint drive: bolted flange, gunmetal ring-gear drum, fins, bronze cap."""
    p = Vector(p); a = Vector(axis).normalized()
    turned(name + ' bolting flange', p, a, [(0, r), (.010, r), (.013, r * .95), (.013, 0)], GN, group, 40)
    turned(name + ' ring-gear drum', p, a, [(.012, r * .84), (depth * .62, r * .84), (depth * .68, r * .76), (depth * .70, 0)], OX, group, 40)
    for k in range(2):
        ring(name + ' cooling fin', p + a * (.020 + k * depth * .18), a, r * .90, r * .80, .004, GN, group, 32)
    turned(name + ' machined bronze cap', p + a * depth * .66, a,
           [(0, r * .54), (depth * .10, r * .54), (depth * .15, r * .47), (depth * .18, r * .34), (depth * .18, 0)], cap_mat or ST, group, 32)
    turned(name + ' retaining hex nut', p + a * depth * .82, a, [(0, r * .24), (depth * .14, r * .24), (depth * .18, r * .19), (depth * .18, r * .09), (depth * .10, r * .09)],
           GN, group, 6)
    for i in range(bolts):
        t = i * math.tau / bolts + math.pi / bolts
        rad = Matrix.Rotation(t, 3, a) @ (a.cross(Z) if abs(a.dot(Z)) < .9 else a.cross(X)).normalized()
        bolt(p + rad * r * .92 + a * .013, a, group, r=min(.007, r * .07), n=8)


def vent(name, center, w, h, depth, slats, group, face, wall_mat, floor_mat=None):
    """Real recessed louvre: dark floor, side walls, lips and angled slats."""
    c = Vector(center); f = Vector(face).normalized()
    across = X.copy() if abs(f.x) < .5 else Z.copy()
    up = Y.copy(); rot = Matrix((across, up, f)).transposed(); wall = .007
    oriented(name + ' floor', c - f * depth, (w, h, .006), rot, floor_mat or DK, group, .001)
    for s in (-1, 1):
        oriented(name + ' jamb', c + across * s * (w / 2 + wall / 2) - f * depth / 2, (wall, h + 2 * wall, depth), rot, wall_mat, group, .0015)
        oriented(name + ' lip', c + up * s * (h / 2 + wall / 2) - f * depth / 2, (w + 2 * wall, wall, depth), rot, wall_mat, group, .0015)
    for i in range(slats):
        y = -h / 2 + h * (i + .5) / slats
        oriented(name + ' louvre', c + up * y - f * depth * .5, (w - .002, .005, depth * .8), rot @ Matrix.Rotation(-.6, 3, 'X'), wall_mat, group, .001)


def plate(name, pts, normal, depth, mat, group, bevel=.004):
    """Plate of `depth` along `normal` from a 3D outline lying on its back face."""
    n = Vector(normal).normalized() * depth; k = len(pts)
    verts = [tuple(Vector(q)) for q in pts] + [tuple(Vector(q) + n) for q in pts]
    faces = [tuple(reversed(range(k))), tuple(range(k, 2 * k))] + [(i, (i + 1) % k, (i + 1) % k + k, i + k) for i in range(k)]
    return mesh(name, verts, faces, mat, group, bevel)


def zring(name, outer, inner, z0, z1, mat, group, bevel=.002):
    """Pierced frame along Z between two (x, y) loops with equal counts."""
    n = len(outer)
    verts = [(x, y, z) for z in (z0, z1) for x, y in outer] + [(x, y, z) for z in (z0, z1) for x, y in inner]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j, n + i), (2 * n + i, 3 * n + i, 3 * n + j, 2 * n + j),
                  (i, 2 * n + i, 2 * n + j, j), (n + i, n + j, 3 * n + j, 3 * n + i)]
    return mesh(name, verts, faces, mat, group, bevel)


def stencil(text, at, face, size, group):
    """nimble_model_kit.stencil_text with a lighter glyph resolution (budget)."""
    curve = bpy.data.curves.new('Stencil ' + text, 'FONT'); curve.body = text; curve.size = size
    curve.extrude = .0015; curve.align_x = 'CENTER'; curve.align_y = 'CENTER'; curve.resolution_u = 5
    obj = bpy.data.objects.new('Stencil ' + text, curve); bpy.context.collection.objects.link(obj)
    obj.rotation_euler = tuple(math.radians(a) for a in nk.STENCIL_EULER[face]); obj.location = gv(at)
    bpy.context.view_layer.objects.active = obj; bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.convert(target='MESH'); obj = bpy.context.object
    obj.data.materials.clear(); obj.data.materials.append(M['stencil']); obj.data.uv_layers.new(name='UVMap')
    nk.kit.groups[group].append(obj)
    return obj


def xplate(name, profile, x_face, thick, side, mat, group, bevel=.004):
    """Plate on a side face: (z, y) profile from the face outward along side*X."""
    a, b = sorted((x_face, x_face + side * thick))
    return section(name, profile, a, b, mat, group, bevel)


# ------------------------------------------------------------------ hull
def build_hull(root):
    hull = part('Hull', (0, 0, 0), root)
    # --- torso: dark bronze keel (backing structure) -------------------------
    prism('Torso keel monocoque', outline(.60, .80, .11, 0, -.01), -.335, -.035, OX, hull, .008,
          top=outline(.60, .80, .11, 0, -.01))
    # Folded chest armour: one section carried from the neck over the glacis to the belly.
    section('Folded chest armour', [(-.40, -.030), (-.465, -.060), (-.465, -.150), (-.405, -.300), (-.30, -.345), (-.30, -.030)],
            -.30, .30, P, hull, .008)
    # Olive impact plate seated on the lower glacis slope, bolted through it.
    a, b = V(0, -.150, -.465), V(0, -.300, -.405)
    t = (b - a).normalized(); n = V(0, -abs(t.z), -abs(t.y)).normalized()
    at = lambda x, u: a + (b - a) * u + X * x
    plate('Chest olive impact plate', [at(-.19, .1), at(.19, .1), at(.22, .25), at(.22, .78), at(.17, .9), at(-.17, .9), at(-.22, .78), at(-.22, .25)],
          n, .010, OL, hull, .003)
    for x in (-.17, .17):
        for u in (.25, .75):
            bolt(at(x, u) + n * .010, n, hull, .0095)
    # Raised louvre frame on the vertical chest band (its floor is the armour face).
    vent('Chest intake', (0, -.105, -.465 - .02), .34, .05, .018, 3, hull, (0, 0, -1), OX)
    # Rear closure with a service vent.
    section('Folded rear closure', [(.36, -.030), (.425, -.085), (.425, -.235), (.36, -.33), (.30, -.345), (.30, -.030)], -.30, .30, P, hull, .008)
    vent('Rear keel vent', (0, -.16, .425 + .022), .34, .09, .020, 4, hull, (0, 0, 1), OX)
    for x in (-.20, .20):
        for y in (-.09, -.23):
            bolt((x, y, .425), (0, 0, 1), hull, .0095)
    # Bolted access plates on the keel flanks, fore and aft of the hip motors.
    for s in (-1, 1):
        for z0, z1 in ((-.37, -.13), (.19, .36)):
            xplate('Keel flank access plate', [(z0, -.30), (z1, -.30), (z1, -.15), (z0, -.15)], s * .30, .008, s, OL, hull, .002)
            for z in (z0 + .025, z1 - .025):
                bolt((s * .308, -.225, z), (s, 0, 0), hull, .0075, n=8)
    # Belly skid plate.
    prism('Belly skid plate', outline(.44, .56, .06, 0, .0), -.35, -.33, GN, hull, .004)
    for x in (-.17, .17):
        for z in (-.2, .2):
            bolt((x, -.35, z), (0, -1, 0), hull, .009)

    # --- sponsons, ears and drives ----------------------------------------------
    for s in (-1, 1):
        # Folded sponson: a plan-chamfered block carried from the keel side to the ear.
        prism('Sponson folded armour', outline(.25, .66, .07, s * .395, -.03), -.118, -.03, P, hull, .008,
              top=outline(.23, .62, .06, s * .39, -.03))
        prism('Sponson structural floor', outline(.24, .60, .06, s * .40, -.03), -.127, -.115, OX, hull, .003)
        # Outer wall plate: sponson band plus a rounded ear around the hip drive
        # (and on the right, around the shoulder drive), one continuous outline.
        hip = Vector((s * HIP_X, HIP_Y, HIP_Z))
        prof = [(-.33, -.03), (.29, -.03), (.30, -.05), (.30, -.10)]
        prof += [(HIP_Z + .116 * math.cos(t), HIP_Y + .116 * math.sin(t)) for t in [math.radians(a) for a in range(40, -181, -20)]]
        if s > 0:
            prof += [(SOCKET.z + .105 * math.cos(t), SOCKET.y + .105 * math.sin(t)) for t in [math.radians(a) for a in range(-40, -181, -20)]]
            prof += [(-.355, -.05)]
        else:
            prof += [(-.20, -.13), (-.345, -.10), (-.345, -.05)]
        xplate('Sponson outer wall and drive ear', prof, s * .513, .032, s, P, hull, .006)
        # Olive inset panel on the ear, seated flush in the wall plane.
        drive('Hip planetary drive', (s * .545, HIP_Y, HIP_Z), (s, 0, 0), .105, .075, hull, bolts=6)
        # Inboard hip motor drum on the keel side (carries the thigh's inner face).
        turned('Hip motor drum', (s * .300, HIP_Y, HIP_Z), (s, 0, 0), [(0, .105), (.030, .105), (.040, .094), (.043, .06), (.043, .0)], GN, hull, 40)
        ring('Hip motor retaining collar', (s * .334, HIP_Y, HIP_Z), (s, 0, 0), .095, .07, .010, ST, hull, 40)
        # Sponson top fasteners.
        for z in (-.24, .02, .22):
            bolt((s * .43, -.03 + .0, z), (0, 1, 0), hull, .0095)
    # Right shoulder: drive housing on the ear, coaxial with the arm pivot.
    turned('Shoulder drive housing', (.545, SOCKET.y, SOCKET.z), (1, 0, 0), [(0, .092), (.010, .092), (.013, .086), (.028, .086), (.028, 0)], GN, hull, 40)
    for i in range(6):
        t = i * math.tau / 6
        bolt((.545 + .012, SOCKET.y + math.sin(t) * .098, SOCKET.z + math.cos(t) * .098), (1, 0, 0), hull, .0065, n=8)

    # --- neck: slewing ring between torso and head ------------------------------
    turned('Neck slewing drum', (0, -.04, -.02), (0, 1, 0), [(0, .34), (.012, .34), (.02, .325), (.045, .325), (.045, .0)], OX, hull, 48)
    ring('Neck machined race', (0, -.012, -.02), (0, 1, 0), .345, .30, .012, ST, hull, 48)

    # --- head: faceted monocoque ------------------------------------------------
    loft('Head faceted monocoque', [(.0, outline(.82, .84, .05, 0, -.02)), (.255, outline(.82, .86, .05, 0, -.02)),
                                    (.305, outline(.66, .70, .08, 0, -.02))], OX, hull, .008)
    # One folded roof section carries over both shoulders to the cheeks; it
    # overhangs the cooling pack at the rear as a short rain guard.
    roof = [(-.426, .236), (-.419, .262), (-.326, .327), (.326, .327), (.419, .262), (.426, .236), (.405, .236), (.33, .29), (-.33, .29), (-.405, .236)]
    zprism('Folded roof and shoulder armour', roof, -.36, .40, P, hull, .006)
    # Raised central spine plate (10 mm proud) carrying the hatch and a sensor block.
    prism('Roof spine plate', outline(.30, .64, .05, 0, .0), .322, .337, P, hull, .004, top=outline(.29, .63, .045, 0, .0))
    prism('Roof hatch seam floor', outline(.23, .25, .035, 0, .13), .334, .339, DK, hull, .001)
    prism('Roof service hatch', outline(.222, .242, .033, 0, .13), .336, .345, OL, hull, .003)
    for x in (-.088, .088):
        for z in (.035, .225):
            bolt((x, .345, z), (0, 1, 0), hull, .0080, n=10)
    for x in (-.05, .05):
        box('Hatch hinge leaf', (x, .339, .258), (.04, .006, .018), OX, hull, .001)
        cylinder('Hatch hinge barrel', (x - .018, .344, .253), (x + .018, .344, .253), .0065, ST, hull, 12, .001)
    # Sensor block on the spine front: a cast housing with a pocketed amber lens.
    zprism('Roof sensor housing', [(-.07, .335), (.07, .335), (.07, .37), (.05, .385), (-.05, .385), (-.07, .37)], -.30, -.19, GN, hull, .004)
    zring('Roof sensor bezel', rounded(.06, .030, .010, 2, 0, .36), rounded(.046, .018, .006, 2, 0, .36), -.307, -.296, ST, hull, .001)
    zprism('Roof sensor lens', rounded(.048, .020, .006, 2, 0, .36), -.302, -.298, AM, hull, .001)
    for x in (-.05, .05):
        bolt((x, .385, -.245), (0, 1, 0), hull, .0065, n=8)
    for s in (-1, 1):
        # Olive side cheek (the concept's stencilled panel) over the monocoque side.
        # Split into a stencilled front plate and a rear plate carrying a louvre;
        # the 8 mm seam between them shows the bronze monocoque beneath.
        xplate('Head side cheek front plate', [(-.40, .03), (.08, .03), (.08, .245), (-.35, .245), (-.40, .20)], s * .408, .024, s, OL, hull, .005)
        xplate('Head side cheek rear plate', [(.088, .03), (.34, .03), (.38, .07), (.38, .22), (.35, .245), (.088, .245)], s * .408, .024, s, OL, hull, .005)
        vent('Cheek louvre', (s * (.432 + .014), .135, .235), .17, .12, .012, 5, hull, (s, 0, 0), OX)
        for z, y in ((-.36, .06), (-.36, .215), (.05, .06), (.05, .215), (.35, .085), (.35, .21)):
            bolt((s * .432, y, z), (s, 0, 0), hull, .009, n=10)
        stencil('09', (s * .4330, .125, -.155), '+x' if s > 0 else '-x', .15, hull)
        # Grab rail: a bent tube whose feet are seated on the cheek plate.
        hx = s * .452
        tube('Cheek grab rail', [V(s * .432, .205, -.28), V(hx, .215, -.26), V(hx, .215, -.14), V(s * .432, .205, -.12)], .0075, ST, hull)
        for z in (-.28, -.12):
            cylinder('Grab rail foot pad', (s * .431, .205, z), (s * .437, .205, z), .014, OX, hull, 12, .001)
    # Brow: folded section over the visor, tucked under the roof's front edge.
    section('Folded brow armour', [(-.30, .318), (-.36, .323), (-.47, .262), (-.495, .232), (-.485, .205), (-.43, .205), (-.40, .24), (-.30, .29)], -.405, .405, P, hull, .006)
    # Chin fold from the visor housing back to the neck.
    section('Folded chin armour', [(-.475, .085), (-.46, .050), (-.40, .005), (-.35, .005), (-.35, .085)], -.405, .405, P, hull, .006)

    # Visor housing projecting from the monocoque; eyes in real slit pockets.
    vx, vy = .075, .145
    zprism('Visor housing', [(p[0], p[1]) for p in rounded(.50, .115, .035, 3, vx, vy)], -.505, -.42, GN, hull, .005)
    for ex in (vx - .115, vx + .115):
        zring('Eye pocket bezel', rounded(.18, .048, .016, 2, ex, vy), rounded(.152, .028, .009, 2, ex, vy), -.517, -.495, ST, hull, .0015)
        zprism('Eye pocket floor', rounded(.156, .032, .010, 2, ex, vy), -.508, -.504, DK, hull, 0)
        zprism('Amber slit eye', rounded(.146, .022, .008, 2, ex, vy), -.512, -.507, AM, hull, .001)
    box('Visor guard bar', (vx, vy - .064, -.50), (.46, .012, .012), OX, hull, .002)

    # Cannon sponson cast into the left cheek, mantlet and bored barrel.
    cx, cy = -.32, .12
    zprism('Cannon sponson casting', [(-.42, .04), (-.25, .04), (-.21, .08), (-.21, .20), (-.24, .225), (-.42, .225)], -.505, -.36, P, hull, .006)
    zprism('Cannon mantlet', [(p[0], p[1]) for p in rounded(.12, .11, .025, 3, cx, cy)], -.545, -.49, GN, hull, .004)
    for dy in (-.038, .038):
        bolt((cx - .042, cy + dy, -.546), (0, 0, -1), hull, .0065, n=8)
    bore = .019
    turned('Cannon barrel thick-walled tube', (cx, cy, -.54), (0, 0, -1),
           [(0, .040), (.05, .040), (.06, .034), (.39, .030), (.39, bore), (0, bore)], GN, hull, 28)
    turned('Cannon thermal sleeve', (cx, cy, -.60), (0, 0, -1), [(0, .042), (.11, .042), (.115, .036)], OL, hull, 28, open_end=True)
    ring('Cannon sleeve clamp band', (cx, cy, -.62), (0, 0, -1), .045, .036, .012, OX, hull, 28)
    # Ported muzzle brake: pierced block, side ports as real openings (two cheeks).
    mz = -.93
    # Pierced front and rear baffles joined by top and bottom bridges; the side
    # ports between them are real openings onto the bore.
    for z in (mz - .008, mz - .082):
        kitmod.square_bore_face('Muzzle brake pierced baffle', (cx, cy, z), .036, .034, bore, .016, GN, hull, 28)
    for yy in (-1, 1):
        box('Muzzle brake bridge', (cx, cy + yy * .029, mz - .045), (.072, .010, .09), GN, hull, .002)

    # Cooling pack closing the rear, with recessed louvres and support brackets.
    zprism('Cooling pack casing', [(-.30, .02), (.30, .02), (.30, .245), (.27, .282), (-.27, .282), (-.30, .245)], .38, .585, P, hull, .007)
    vent('Cooling pack louvre', (0, .14, .585 + .026), .46, .16, .024, 6, hull, (0, 0, 1), OX)
    prism('Cooling pack top grille frame', outline(.40, .12, .02, 0, .495), .280, .289, OX, hull, .002)
    for i in range(5):
        box('Cooling pack top fin', (-.16 + i * .08, .291, .495), (.012, .010, .10), GN, hull, .001)
    for s in (-1, 1):
        box('Cooling pack support bracket', (s * .22, -.005, .41), (.07, .07, .08), OX, hull, .004)
        for y in (.06, .20):
            bolt((s * .30, y, .52), (s, 0, 0), hull, .0085, n=10)
    # Lifting eyes on the roof shoulders: clevis blocks seated on the fold's
    # flat top, each carrying a forged ring on a cross pin.
    for x, z in ((.25, -.26), (-.25, .30)):
        box('Lifting eye clevis block', (x, .333, z), (.05, .014, .06), OX, hull, .002)
        for dz in (-.019, .019):
            box('Lifting eye cheek', (x, .352, z + dz), (.044, .028, .010), OX, hull, .002)
        cylinder('Lifting eye cross pin', (x, .356, z - .026), (x, .356, z + .026), .006, ST, hull, 10, 0)
        ring('Forged lifting eye', (x, .37, z), (0, 0, 1), .024, .013, .012, ST, hull, 20)
    # Antenna on a sprung base at the rear right of the roof.
    ax_, az_ = .22, .24
    turned('Antenna base', (ax_, .325, az_), (0, 1, 0), [(0, .03), (.012, .03), (.018, .02), (.03, .016), (.03, 0)], GN, hull, 20)
    coil('Antenna base spring', (ax_, .395, az_), .04, .012, .0028, 5, M['spring'], hull, 6, 14)
    cylinder('Antenna mast', (ax_, .355, az_), (ax_, .78, az_), .0055, OX, hull, 10, 0)
    turned('Antenna tip', (ax_, .78, az_), (0, 1, 0), [(0, .010), (.008, .010), (.014, .0)], ST, hull, 12)
    return hull


# ------------------------------------------------------------------ legs
def build_leg(s, label, root):
    hip = V(s * HIP_X, HIP_Y, HIP_Z); knee = hip - Y * UPPER; ankle = knee - Y * LOWER
    out = X * s
    # ---------------------------------------------------------------- thigh
    thigh = part('Thigh' + label, tuple(hip), root)
    cylinder('Thigh hip pin boss', hip - X * .058, hip + X * .058, .084, OX, thigh, 40, .006)
    for d in (-1, 1):
        turned('Hip boss machined collar', hip + X * d * .058, X * d, [(0, .070), (.004, .068), (.006, .05), (.006, 0)], ST, thigh, 32)
    loft('Thigh box-section member', [(hip.y - .04, outline(.10, .115, .024, hip.x, hip.z)), (hip.y - .30, outline(.11, .125, .028, hip.x, hip.z)),
                                     (knee.y + .10, outline(.092, .10, .022, hip.x, hip.z))], OX, thigh, .007)
    # Camouflaged cowl bolted round the member, kept clear of the hip boss sweep.
    prism('Thigh armour cowl', outline(.150, .18, .042, hip.x, hip.z + .018), hip.y - .46, hip.y - .14, P, thigh, .007,
          top=outline(.154, .19, .046, hip.x, hip.z + .018))
    xplate('Thigh outer olive panel', [(hip.z - .055, hip.y - .40), (hip.z + .07, hip.y - .40), (hip.z + .08, hip.y - .38), (hip.z + .08, hip.y - .18),
                                       (hip.z + .06, hip.y - .16), (hip.z - .055, hip.y - .16), (hip.z - .065, hip.y - .18), (hip.z - .065, hip.y - .38)],
           hip.x + s * .074, .006, s, OL, thigh, .002)
    for z in (hip.z - .045, hip.z + .065):
        for y in (hip.y - .18, hip.y - .385):
            bolt((hip.x + s * .080, y, z), out, thigh, .0075, n=10)
    # Knee fork and outboard knee drive.
    fork = [(hip.z - .05, knee.y + .17), (hip.z + .05, knee.y + .17)] + [(hip.z + .075 * math.cos(t), knee.y + .075 * math.sin(t)) for t in [math.radians(a) for a in range(0, -181, -20)]]
    for d in (-1, 1):
        a, b = sorted((hip.x + d * .047, hip.x + d * .066))
        section('Thigh knee fork plate', fork, a, b, OX, thigh, .004)
    drive('Knee drive', knee + out * .066, out, .078, .05, thigh, bolts=6)
    turned('Knee pin retaining nut', knee - out * .066, -out, [(0, .032), (.008, .032), (.012, .026), (.013, 0)], ST, thigh, 20)

    # ---------------------------------------------------------------- shin
    shin = part('Shin' + label, tuple(knee), root)
    cylinder('Shin knee boss', knee - X * .043, knee + X * .043, .058, OX, shin, 40, .005)
    loft('Shin tapered member', [(knee.y - .035, outline(.086, .10, .022, hip.x, hip.z)), (knee.y - .30, outline(.084, .092, .02, hip.x, hip.z)),
                                 (ankle.y + .05, outline(.07, .075, .016, hip.x, hip.z))], OX, shin, .006)
    cylinder('Shin ankle boss', ankle - X * .043, ankle + X * .043, .044, OX, shin, 32, .004)
    # Front guard (enamel), bolted on raised standoffs, clear of the knee sweep.
    section('Shin front guard', [(hip.z - .040, knee.y - .15), (hip.z - .070, knee.y - .18), (hip.z - .082, knee.y - .24), (hip.z - .082, ankle.y + .24),
                                 (hip.z - .066, ankle.y + .17), (hip.z - .040, ankle.y + .15)], hip.x - .062, hip.x + .062, P, shin, .006)
    xplate('Shin guard olive flank', [(hip.z - .035, knee.y - .22), (hip.z + .03, knee.y - .25), (hip.z + .03, ankle.y + .30), (hip.z - .035, ankle.y + .26)],
           hip.x + s * .042, .006, s, OL, shin, .002)
    for y in (knee.y - .25, ankle.y + .23):
        for x in (-.03, .03):
            bolt((hip.x + x, y, hip.z - .082), (0, 0, -1), shin, .0075, n=10)
    # Rear damper strut on welded clevis lugs.
    for y in (knee.y - .10, ankle.y + .14):
        box('Damper clevis lug', (hip.x, y, hip.z + .055), (.05, .036, .045), OX, shin, .003)
        cylinder('Damper clevis pin', (hip.x - .028, y, hip.z + .075), (hip.x + .028, y, hip.z + .075), .007, ST, shin, 10, 0)
    rz = hip.z + .075
    turned('Damper barrel', (hip.x, knee.y - .115, rz), (0, -1, 0), [(0, .014), (.012, .022), (.24, .022), (.25, .019), (.25, 0)], GN, shin, 20)
    ring('Damper gland nut', (hip.x, knee.y - .368, rz), (0, 1, 0), .021, .011, .012, ST, shin, 20)
    cylinder('Damper chrome rod', (hip.x, knee.y - .36, rz), (hip.x, ankle.y + .155, rz), .011, ST, shin, 14, .001)
    tube('Shin hydraulic hose', [knee + V(s * .045, -.08, .03), knee + V(s * .05, -.30, .02), ankle + V(s * .045, .14, .02)], .008, RB, shin)

    # ---------------------------------------------------------------- foot
    foot = part('Foot' + label, tuple(ankle), root)
    sole = ankle.y - ANKLE_HEIGHT
    fork = [(hip.z + .065, ankle.y - .050)] + [(hip.z + .052 * math.cos(t), ankle.y + .052 * math.sin(t)) for t in [math.radians(a) for a in range(0, 181, 30)]] + [(hip.z - .065, ankle.y - .050)]
    for d in (-1, 1):
        a, b = sorted((hip.x + d * .047, hip.x + d * .066))
        section('Ankle fork plate', fork, a, b, OX, foot, .004)
    drive('Ankle drive', ankle + out * .066, out, .050, .036, foot, bolts=0)
    turned('Ankle pin retaining nut', ankle - out * .066, -out, [(0, .026), (.007, .026), (.010, .02), (.011, 0)], ST, foot, 20)
    prism('Heel block', outline(.15, .15, .04, hip.x, hip.z), sole + .012, ankle.y - .048, OX, foot, .005)
    prism('Heel rubber pad', outline(.13, .13, .035, hip.x, hip.z), sole, sole + .013, RB, foot, .003)
    # Two splayed front toes and an outward-raked rear spur (kept low and off
    # the shin's back so the damper clears it when the shin lies forward).
    for yaw, length, tall in ((-24, .30, .062), (24, .30, .062), (140, .19, .036)):
        a = math.radians(yaw); d = V(math.sin(a) * s, 0, -math.cos(a))
        root_pt = V(ankle.x, sole, ankle.z) + d * .045
        k = length * .60
        lat = Y.cross(d).normalized()
        # Proximal phalanx (bronze) with a camo top cap and a rubber pad.
        dprism('Toe phalanx', root_pt, d, [(0, .012), (k, .012), (k + .022, .026), (k, tall), (.0, tall * .92)], .056, OX, foot, .004)
        dprism('Toe camo armour cap', root_pt, d, [(.012, tall * .92 - .004), (k - .004, tall - .004), (k - .016, tall + .008), (.024, tall * .92 + .007)], .064, P, foot, .004)
        dprism('Toe rubber pad', root_pt, d, [(.0, .0), (k, .0), (k, .013), (.0, .013)], .052, RB, foot, .003)
        for u in (k * .35, k * .75):
            bolt(root_pt + d * u + Y * (tall * .92 + .007 + (tall - tall * .92) * u / k), Y, foot, .0055, n=8)
        knuckle = root_pt + d * (k + .008) + Y * tall * .55
        cylinder('Toe knuckle pin', knuckle - lat * .033, knuckle + lat * .033, .014, ST, foot, 14, .001)
        # Down-curved claw (gunmetal) ending at the ground.
        dprism('Toe claw', root_pt, d, [(k + .004, tall * .8), (k + .02, .012), (length - .02, .0), (length, .005), (length - .035, tall * .45), (k + .045, tall * .9)],
               .040, GN, foot, .003)
    return thigh, shin, foot


# ------------------------------------------------------------------ hammer arm
def build_arm(root):
    p = SOCKET.copy()
    arm = part('Arm', tuple(p), root)
    fwd = -Z
    cylinder('Shoulder hub', p - X * .056, p + X * .058, .084, GN, arm, 40, .005)
    turned('Shoulder hub inner collar', p - X * .056, -X, [(0, .076), (.003, .074), (.004, .06), (.004, 0)], ST, arm, 32)
    drive('Shoulder hub outer cap', p + X * .058, X, .080, .045, arm, bolts=6)
    # Upper arm: box member and a camo armour sleeve with an olive inset.
    zloft('Upper arm member', [(p.z - .02, outline(.10, .13, .025, p.x, p.y)),
                               (p.z - .50, outline(.09, .11, .022, p.x, p.y))], OX, arm, .006)
    ax = p.x
    zloft('Upper arm armour sleeve', [(p.z - .12, outline(.15, .18, .04, ax, p.y + .005)),
                                      (p.z - .44, outline(.14, .16, .035, ax, p.y + .005))], P, arm, .007)
    xplate('Upper arm olive panel', [(p.z - .16, p.y - .055), (p.z - .40, p.y - .05), (p.z - .40, p.y + .055), (p.z - .16, p.y + .06)],
           ax + .066, .010, 1, OL, arm, .002)
    for z in (p.z - .175, p.z - .385):
        for y in (p.y - .04, p.y + .045):
            bolt((ax + .076, y, z), X, arm, .0075, n=10)
    # Telescopic ram and a parallel guide rod.
    turned('Arm ram barrel', (ax, p.y, p.z - .44), fwd, [(0, .05), (.02, .05), (.03, .046), (.33, .046), (.34, .04), (.34, 0)], OX, arm, 32)
    ring('Arm ram warning band', (ax, p.y, p.z - .70), fwd, .048, .044, .03, HZ, arm, 32)
    ring('Arm ram gland nut', (ax, p.y, p.z - .785), fwd, .036, .026, .02, ST, arm, 24)
    cylinder('Arm ram chrome rod', (ax, p.y, p.z - .78), (ax, p.y, p.z - 1.03), .026, ST, arm, 24, .002)
    head = p + fwd * HAMMER_REACH
    cylinder('Arm guide rod', (ax, p.y + .072, p.z - .44), (ax, p.y + .072, head.z + .15), .011, ST, arm, 12, .001)
    for z in (p.z - .60, p.z - .82):
        box('Guide rod clamp', (ax, p.y + .05, z), (.04, .05, .026), OX, arm, .003)
    # Slab hammer: bronze core, camo cheeks, olive insets, hardened strike edge.
    prof = [(.165, -.175), (-.195, -.175), (-.225, -.12), (-.145, .17), (.10, .17), (.165, .085)]
    rel = lambda pts, sc=1.0: [(head.z + z * sc, head.y + y * sc) for z, y in pts]
    section('Hammer slab core', rel(prof), ax - .05, ax + .05, OX, arm, .006)
    for s in (-1, 1):
        xplate('Hammer camo cheek plate', rel(prof, .95), ax + s * .049, .026, s, P, arm, .006)
        inset = [(.115, -.12), (-.155, -.12), (-.17, -.085), (-.105, .12), (.075, .12), (.115, .06)]
        xplate('Hammer olive inset panel', rel(inset), ax + s * .074, .006, s, OL, arm, .002)
        for z, y in ((.12, -.14), (-.16, -.14), (.11, .135), (-.12, .135)):
            bolt((ax + s * .075, head.y + y, head.z + z), X * s, arm, .0085, n=10)
    section('Hammer hardened strike edge', rel([(.17, -.168), (-.20, -.168), (-.232, -.118), (-.215, -.205), (.16, -.205), (.18, -.19)]),
            ax - .078, ax + .078, ST, arm, .004)
    turned('Hammer rod socket collar', (ax, head.y, head.z + .16), Z, [(0, .052), (.05, .052), (.06, .04), (.06, 0)], GN, arm, 32)
    return arm


# ------------------------------------------------------------------ runtime poses
_C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def _to_blender(basis_cols, origin):
    x, y, z = basis_cols
    t = Matrix(((x.x, y.x, z.x, origin.x), (x.y, y.y, z.y, origin.y), (x.z, y.z, z.z, origin.z), (0, 0, 0, 1)))
    return _C @ t @ _C.inverted()


def _slide(v, n):
    return v - n * v.dot(n)


def solve_knee(hip, ankle, upper, lower, bend):
    """Mirror of NimbleVisual.solve_knee."""
    direction = (ankle - hip).normalized()
    distance = min(max((ankle - hip).length, abs(upper - lower) + .001), upper + lower - .001)
    along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
    out = _slide(bend, direction)
    out = out.normalized() if out.length > 1e-6 else _slide(Z, direction).normalized()
    return hip + direction * along + out * math.sqrt(max(0.0, upper * upper - along * along))


def segment(start, end):
    y = -(end - start).normalized()
    x = _slide(X.copy(), y)
    x = x.normalized() if x.length > 1e-6 else (-Z).cross(y).normalized()
    return _to_blender((x, y, x.cross(y)), start)


def pose_legs(legs, phase, floor, moving=1.0):
    """NimbleVisual._pose_strider for a stride phase and floor height."""
    for label, (thigh, shin, foot) in legs.items():
        side = -1 if label == 'L' else 1
        hip = V(side * HIP_X, HIP_Y, HIP_Z)
        cycle = (phase + (1.0 if label == 'R' else 0.0)) % 2.0
        z = -STEP * .5 + cycle * STEP; lift = 0.0
        if cycle >= 1.0:
            z = STEP * .5 - (cycle - 1.0) * STEP
            lift = LIFT * math.sin(math.pi * (cycle - 1.0))
        target = V(hip.x * FOOT_OUTBOARD, floor + ANKLE_HEIGHT + lift * moving, hip.z + z * moving)
        reach = UPPER + LOWER - .001
        off = target - hip
        ankle = hip + (off.normalized() * reach if off.length > reach else off)
        knee = solve_knee(hip, ankle, UPPER, LOWER, V(KNEE_BEND.x * side, KNEE_BEND.y, KNEE_BEND.z))
        thigh.matrix_basis = segment(hip, knee)
        shin.matrix_basis = segment(knee, ankle)
        foot.matrix_basis = Matrix.Translation(gv(ankle))


def pose_arm(arm, angle):
    arm.matrix_basis = Matrix.Translation(gv(SOCKET)) @ Matrix.Rotation(angle, 4, 'X')


# ------------------------------------------------------------------ build
root = part('NimbleStrider')
build_hull(root)
legs = {label: build_leg(s, label, root) for s, label in ((-1, 'L'), (1, 'R'))}
arm = build_arm(root)
moving = [legs['L'][0], legs['L'][1], legs['L'][2], legs['R'][0], legs['R'][1], legs['R'][2], arm]
poses = {
    'stride': lambda t: pose_legs(legs, 2.0 * t, -RIDE),
    'stride_bob': lambda t: pose_legs(legs, 2.0 * t + .5, -(RIDE - BOB)),
    'hammer': lambda t: pose_arm(arm, HAMMER_STRUCK + (HAMMER_RAISED - HAMMER_STRUCK) * t),
}
def triangle_report():
    dg = bpy.context.evaluated_depsgraph_get(); rows = {}
    for group, objs in nk.kit.groups.items():
        for o in objs:
            m = o.evaluated_get(dg).to_mesh(); m.calc_loop_triangles()
            key = (group.name, o.name.split('.')[0]); rows[key] = rows.get(key, 0) + len(m.loop_triangles)
            o.evaluated_get(dg).to_mesh_clear()
    for (g, n), t in sorted(rows.items(), key=lambda r: -r[1])[:40]:
        print('NIMBLE_TRIS %-8s %-45s %6d' % (g, n, t))
    per = {}
    for (g, n), t in rows.items(): per[g] = per.get(g, 0) + t
    print('NIMBLE_TRIS_GROUPS', per)


def clearance_report():
    """Where the sampled contacts are (hull-frame centroids of the hull triangles)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    def tree(objs):
        verts, polys = [], []
        for o in objs:
            m = o.evaluated_get(dg).to_mesh(); off = len(verts)
            verts += [o.matrix_world @ v.co for v in m.vertices]; polys += [[off + i for i in p.vertices] for p in m.polygons]
            o.evaluated_get(dg).to_mesh_clear()
        return BVHTree.FromPolygons(verts, polys), verts, polys
    hull_objs = [o for o in nk.descendants(root) if o.type == 'MESH' and not any(o in nk.descendants(g) for g in moving)]
    ht, hv, hp = tree(hull_objs)
    rest = {g: g.matrix_basis.copy() for g in moving}
    for label, pose in poses.items():
        for t in (0.0, .25, .5, .75, 1.0):
            pose(t); bpy.context.view_layer.update()
            for g in moving:
                mt, mv, mp = tree([o for o in nk.descendants(g) if o.type == 'MESH'])
                pairs = mt.overlap(ht)
                if pairs:
                    cs = {tuple(round(c, 2) for c in (lambda v: (v.x, v.z, -v.y))(sum((hv[i] for i in hp[b]), Vector()) / len(hp[b]))) for a, b in pairs}
                    ms = {tuple(round(c, 2) for c in (lambda v: (v.x, v.z, -v.y))(sum((mv[i] for i in mp[a]), Vector()) / len(mp[a]))) for a, b in pairs}
                    print('NIMBLE_CONTACT %s@%.2f %s hull=%s moving=%s' % (label, t, g.name, sorted(cs)[:4], sorted(ms)[:4]))
        for g, m in rest.items(): g.matrix_basis = m
    bpy.context.view_layer.update()


DIAG = '--diag' in sys.argv
if DIAG:
    triangle_report()
nk.NO_RENDER = True
complete(root, CHASSIS, PREFIX, moving, poses=poses, face_wear=.80)
if DIAG:
    clearance_report()
if '--no-render' not in sys.argv:
    # Review in the garage stance the runtime shows: IK-solved legs, arm at rest.
    pose_legs(legs, 0.0, -RIDE, moving=0.0)
    pose_arm(arm, HAMMER_REST)
    bpy.context.view_layer.update()
    nk.review(root, CHASSIS)
    # Extra face view with the hammer struck low: at rest it hangs in front of
    # the visor from the close-up camera.
    pose_arm(arm, HAMMER_STRUCK); bpy.context.view_layer.update()
    scene = bpy.context.scene; cam = scene.camera
    cam.location = gv((-1.0, RIDE + .35, -1.7))
    cam.rotation_euler = (gv((0, RIDE + .05, -.3)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.ortho_scale = 1.35
    scene.render.filepath = str(nk.PREVIEW / ('%s_face.png' % CHASSIS))
    bpy.ops.render.render(write_still=True)
    if '--stride-view' in sys.argv:
        # Diagnostic: the stride's front-foot extreme at the bottom of the bob,
        # where the shin lies furthest forward over its foot.
        root.location = gv((0, RIDE - BOB, 0))
        pose_legs(legs, 0.0, -(RIDE - BOB)); pose_arm(arm, HAMMER_STRUCK); bpy.context.view_layer.update()
        for name, at in (('stride_side', (-3.0, .5, 0)), ('stride_rear', (-1.6, .9, 2.4))):
            cam.location = gv(at)
            cam.rotation_euler = (gv((0, .45, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
            cam.data.ortho_scale = 2.6
            scene.render.filepath = str(nk.PREVIEW / ('%s_%s.png' % (CHASSIS, name)))
            bpy.ops.render.render(write_still=True)
print('NIMBLE_STRIDER_DONE')
