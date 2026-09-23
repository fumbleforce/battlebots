"""Four nimble bots (#61): Strider 09, Hellwheel 07, Pogo 03 and Skater 12.

Blender 5.2 --background --python tools/build-nimble-bots.py [-- --no-render]

Construction brief (Godot metres in each hull frame, X right, Y up, -Z forward;
the runtime factor three is applied once by NimbleVisual). The hull origin is
the centre of the chassis collision box from data/mvp_parts.json divided by
three; ride heights, footholds, gun pivots and the hammer socket come from
data/nimble_bots.json and are read here so the model and simulation agree.

Every moving assembly is a named empty with its geometry in its own frame:
- limbs (thighs, shins, arms) hang along -Y from their pivot, so the runtime
  points local -Y at the next joint;
- wheels spin about local X; coils stretch along local -Y (unit length);
- the gun follows the shared Scorpion gun frame: GunFrame sits at
  (gun pivot - ScorpionGeometry.GUN_PIVOT) so GunMount rotates about the
  shared pivot, GunBarrels spins about local Z and Muzzle marks the shot origin.

First-pass look development: chunky chamfered armour over a dark frame, flat
enamel/steel/rubber classes and emissive lenses. No baked maps yet; the camo
and hazard enamels are replaced at runtime by triplanar pattern materials.
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import atlas_model_kit as kit
from atlas_model_kit import part, mesh, prism, box, cylinder, ring, turned, bolt, gv, descendants, finalize, export_model

RUNTIME = ROOT / 'battlebots/assets/models/nimble_runtime'
PREVIEW = ROOT / 'battlebots/exports/nimble-preview'
NO_RENDER = '--no-render' in sys.argv
for path in (RUNTIME, PREVIEW): path.mkdir(parents=True, exist_ok=True)
(PREVIEW / '.gdignore').write_text('')
DATA = json.loads((ROOT / 'battlebots/data/nimble_bots.json').read_text())['bots']
PARTS = {p['id']: p for p in json.loads((ROOT / 'battlebots/data/mvp_parts.json').read_text())['parts']}
SCALE = 3.0
GUN_PIVOT = Vector((0.66, 0.22, -0.42))
GUN_MUZZLE = Vector((0.66, 0.27, -1.72))

def src(values): return Vector(values) / SCALE

bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
bpy.context.preferences.filepaths.save_version = 0
M = kit.palette()
steel, oxidized, rubber, dark, gun = M['steel'], M['oxidized'], M['rubber'], M['dark'], M['gun']
m = kit.material
camo = m('Nimble_Camo', (.60, .56, .40), .06, .68)
olive = m('Nimble_OliveDrab', (.25, .30, .19), .06, .66)
red = m('Nimble_OxideRed', (.52, .11, .07), .08, .62)
yellow = m('Nimble_SafetyYellow', (.87, .61, .07), .08, .60)
hazard = m('Nimble_Hazard', (.87, .61, .07), .08, .60)
frame = m('Nimble_Frame', (.15, .155, .16), .78, .46)
coil_red = m('Nimble_SpringEnamel', (.55, .13, .07), .55, .40)
amber = m('Nimble_LensAmber', (1.0, .55, .12), .05, .30, emission=7.0)
blue = m('Nimble_LensBlue', (.35, .62, 1.0), .05, .25, emission=6.0)
stencil = m('Nimble_Stencil', (.90, .88, .82), .05, .50)

# ------------------------------------------------------------------ helpers
def outline(w, d, c, dx=0.0, dz=0.0):
    """Chamfered rectangle in XZ (plan-view corner cut c)."""
    x, z = w / 2, d / 2
    return [(dx + a, dz + b) for a, b in [(-x + c, -z), (x - c, -z), (x, -z + c), (x, z - c), (x - c, z), (-x + c, z), (-x, z - c), (-x, -z + c)]]

def shell(name, w, d, c, y0, y1, mat, group, top=(1.0, 1.0), at=(0.0, 0.0), top_shift=(0.0, 0.0), bevel=.014):
    base = outline(w, d, c, *at)
    lid = outline(w * top[0], d * top[1], c * min(top), at[0] + top_shift[0], at[1] + top_shift[1])
    return prism(name, base, y0, y1, mat, group, bevel, lid)

def oriented(name, center, size, rotation, mat, group, bevel=.008):
    """Box of size about center, rotated by the Matrix rotation (3x3)."""
    c = Vector(center); s = Vector(size) * .5
    corners = [c + rotation @ Vector((x * s.x, y * s.y, z * s.z)) for x, y, z in
               [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    return mesh(name, [tuple(p) for p in corners], [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)], mat, group, bevel)

def beam(name, a, b, w, h, mat, group, bevel=.010):
    """Box-section member from a to b; w across the member in X-ish, h across in the bend plane."""
    a = Vector(a); b = Vector(b); d = (b - a).normalized()
    side = Vector((1, 0, 0)) if abs(d.x) < .9 else Vector((0, 0, 1))
    up = d.cross(side).normalized(); side = up.cross(d).normalized()
    rot = Matrix((side, d, up)).transposed()
    return oriented(name, (a + b) / 2, (w, (b - a).length, h), rot, mat, group, bevel)

def disc(name, p, axis, r, width, mat, group, n=28):
    p = Vector(p); d = Vector(axis).normalized()
    return cylinder(name, p - d * width / 2, p + d * width / 2, r, mat, group, n, .004)

def hub(name, p, axis, r, width, group):
    """Lathed joint cap: dark bearing, machined collar and a domed centre."""
    d = Vector(axis).normalized(); p = Vector(p)
    disc(name + ' bearing', p, d, r, width, frame, group)
    for s in (-1, 1):
        turned(name + ' collar', p + d * s * width / 2, d * s, [(0, r * .78), (.012, r * .78), (.018, r * .6), (.022, r * .35), (.022, 0.0)], steel, group, 24)

def lens(name, p, axis, r, mat, group):
    d = Vector(axis).normalized(); p = Vector(p)
    turned(name + ' bezel', p - d * .012, d, [(0, r * 1.35), (.02, r * 1.35), (.024, r * 1.1), (.018, r * 1.02)], frame, group, 28)
    turned(name, p, d, [(0, r), (.006, r * .92), (.012, r * .55), (.013, 0.0)], mat, group, 28)

def slot_eye(name, center, w, h, mat, group):
    """Rounded glowing visor slot on a -Z facing face."""
    c = Vector(center)
    box(name + ' recess', c + Vector((0, 0, .012)), (w + .05, h + .05, .03), dark, group, .006)
    box(name, c - Vector((0, 0, .004)), (w, h, .016), mat, group, .006)

STENCIL_EULER = {'+x': (90, 0, 90), '-x': (90, 0, -90), 'front': (90, 0, 180), 'top': (0, 0, 0)}

def stencil_text(text, at, face, size, group, mat=None):
    """Raised stencil numerals on a hull face: '+x', '-x', 'front' (-Z) or 'top'."""
    curve = bpy.data.curves.new('Stencil ' + text, 'FONT'); curve.body = text; curve.size = size
    curve.extrude = .004; curve.align_x = 'CENTER'; curve.align_y = 'CENTER'
    obj = bpy.data.objects.new('Stencil ' + text, curve); bpy.context.collection.objects.link(obj)
    # Blender text lies in its XY plane facing +Z and reads along +X.
    obj.rotation_euler = tuple(math.radians(a) for a in STENCIL_EULER[face])
    obj.location = gv(at)
    bpy.context.view_layer.objects.active = obj; bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.convert(target='MESH'); obj = bpy.context.object
    obj.data.materials.clear(); obj.data.materials.append(mat or stencil)
    kit.groups[group].append(obj); return obj

def coil(name, top, length, radius, wire, turns, mat, group, n=9, steps=26):
    """Helical spring from `top` down a unit-scaled length along -Y."""
    top = Vector(top); verts = []; faces = []
    total = int(turns * steps)
    for i in range(total + 1):
        t = i / total; a = t * turns * math.tau
        c = top + Vector((math.cos(a) * radius, -t * length, math.sin(a) * radius))
        tangent = Vector((-math.sin(a) * radius * turns * math.tau, -length, math.cos(a) * radius * turns * math.tau)).normalized()
        normal = Vector((math.cos(a), 0, math.sin(a))); binormal = tangent.cross(normal).normalized(); normal = binormal.cross(tangent)
        for k in range(n):
            b = k * math.tau / n
            verts.append(tuple(c + (normal * math.cos(b) + binormal * math.sin(b)) * wire))
    for i in range(total):
        for k in range(n):
            a0 = i * n + k; a1 = i * n + (k + 1) % n
            faces.append((a0, a1, a1 + n, a0 + n))
    faces += [tuple(reversed(range(n))), tuple(range(total * n, total * n + n))]
    obj = mesh(name, verts, faces, mat, group)
    for f in obj.data.polygons: f.use_smooth = True
    return obj

def tyre(name, center, radius, inner, width, lugs, group, lug_depth=.04):
    """Rubber tyre about X with chunky block tread, dished steel rim and hub."""
    c = Vector(center)
    ring(name + ' carcass', c, (1, 0, 0), radius - lug_depth, inner, width, rubber, group, 48)
    for i in range(lugs):
        a = i * math.tau / lugs
        rot = Matrix.Rotation(a, 3, 'X')
        for s in (-1, 1):
            p = c + rot @ Vector((s * width * .26, radius - lug_depth * .5, 0))
            oriented(name + ' tread block', p, (width * .44, lug_depth, math.tau * radius / lugs * .62), rot @ Matrix.Rotation(s * .18, 3, 'Y'), rubber, group, .006)
    turned(name + ' rim dish', c + Vector((-width * .42, 0, 0)), (1, 0, 0), [(0, inner + .01), (.02, inner), (.07, inner * .72), (.10, inner * .45), (.10, .0)], steel, group, 40)
    turned(name + ' rim back', c + Vector((width * .42, 0, 0)), (-1, 0, 0), [(0, inner + .01), (.02, inner), (.05, inner * .6), (.05, .0)], oxidized, group, 40)
    for i in range(8):
        a = i * math.tau / 8
        bolt(c + Vector((-width * .42 + .05, math.cos(a) * inner * .55, math.sin(a) * inner * .55)), (-1, 0, 0), group, r=inner * .1)

def minigun(prefix, pivot, barrels, radius, length, group_root, shroud_mat):
    """Shared Scorpion gun frame: GunFrame -> GunMount (pivot) -> GunBarrels, Muzzle."""
    pivot = Vector(pivot)
    frame_node = part('GunFrame', tuple(pivot - GUN_PIVOT), group_root)
    mount = part('GunMount', tuple(pivot), frame_node)
    muzzle = pivot + (GUN_MUZZLE - GUN_PIVOT)
    axis_y = muzzle.y
    breech_z = pivot.z + .10
    barrel_end = muzzle.z
    # Receiver and motor housing around the pivot.
    shell('Gun receiver', .20, .42, .04, pivot.y - .09, pivot.y + .12, shroud_mat, mount, at=(pivot.x, pivot.z - .12))
    box('Gun feed chute', (pivot.x + .11, pivot.y - .02, pivot.z - .05), (.06, .12, .24), frame, mount)
    hub('Gun trunnion', (pivot.x, pivot.y, pivot.z), (1, 0, 0), .07, .26, mount)
    rotor = part('GunBarrels', (pivot.x, axis_y, pivot.z - .3), mount)
    for i in range(barrels):
        a = i * math.tau / barrels
        off = Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
        cylinder('Gun barrel', Vector((pivot.x, axis_y, pivot.z - .3)) + off, Vector((pivot.x, axis_y, barrel_end + .02)) + off, .024, gun, rotor, 16, .002)
    for z in (pivot.z - .36, (pivot.z + barrel_end) * .5, barrel_end + .07):
        cylinder('Gun barrel clamp', (pivot.x, axis_y, z + .025), (pivot.x, axis_y, z - .025), radius + .045, frame, rotor, 20, .003)
    turned('Gun muzzle ring', (pivot.x, axis_y, barrel_end + .04), (0, 0, -1), [(0, radius + .05), (.04, radius + .05), (.05, radius + .02), (.05, radius - .02)], steel, rotor, 24, open_end=True)
    part('Muzzle', tuple(muzzle), mount)
    return frame_node, mount, rotor

def limb(prefix, pivot, length, w, d, armour, group, slim=False, piston=True):
    """Leg/arm segment hanging along -Y from `pivot`: frame, armour sleeve, joint hubs and a ram."""
    p = Vector(pivot)
    beam(prefix + ' frame', p, p - Vector((0, length, 0)), w * .55, d * .55, frame, group)
    sleeve = .62 if not slim else .45
    shell(prefix + ' armour', w, d, min(w, d) * .28, p.y - length * (.18 + sleeve), p.y - length * .18, armour, group,
          top=(.9, .92), at=(p.x, p.z - d * .08))
    hub(prefix + ' upper joint', p, (1, 0, 0), w * .42, w * 1.05, group)
    if piston:
        box(prefix + ' ram barrel', p + Vector((0, -length * .38, d * .55)), (w * .26, length * .44, w * .26), oxidized, group, .006)
        cylinder(prefix + ' ram rod', p + Vector((0, -length * .6, d * .55)), p + Vector((0, -length * .86, d * .55)), w * .08, steel, group, 12, .002)

# ------------------------------------------------------------------ Strider 09
def build_strider():
    bot = DATA['strider_09']; size = src(PARTS['strider_09']['size'])
    ride = bot['ride_height'] / SCALE
    root = part('NimbleStrider')
    hull = part('Hull', (0, 0, 0), root)
    # Faceted armoured head with a folded brow over the visor.
    shell('Head lower shell', .92, 1.02, .16, -.17, .06, camo, hull, top=(1.0, .98))
    shell('Head upper shell', .92, 1.0, .16, .06, .25, camo, hull, top=(.84, .82), top_shift=(0, .04))
    shell('Brow plate', .78, .16, .05, .12, .21, olive, hull, at=(0, -.47), top=(.95, .7), top_shift=(0, .03))
    box('Visor band', (0, .03, -.505), (.70, .15, .03), dark, hull)
    for x in (-.17, .17):
        slot_eye('Visor eye', (x, .035, -.522), .20, .052, amber, hull)
    box('Chin guard', (0, -.12, -.50), (.62, .08, .06), olive, hull, .01)
    for x in (-.40, .40):
        box('Cheek plate', (x * 1.13, -.02, -.12), (.05, .22, .62), olive, hull, .01)
    stencil_text('09', (.466, -.06, .12), '+x', .17, hull)
    stencil_text('09', (-.466, -.06, .12), '-x', .17, hull)
    # Brow cannon on the left cheek.
    box('Cannon mantlet', (-.30, .10, -.47), (.18, .15, .12), frame, hull)
    turned('Cannon barrel', (-.30, .10, -.52), (0, 0, -1), [(0, .055), (.34, .045), (.34, .06), (.44, .06), (.44, .03)], gun, hull, 24, open_end=True)
    # Rear power pack, vents and antenna.
    shell('Power pack', .66, .34, .08, -.06, .20, frame, hull, at=(0, .46))
    for i in range(5): box('Pack vent louvre', (0, .02 + i * .035, .635), (.52, .012, .02), dark, hull, .002)
    cylinder('Antenna mast', (.34, .25, .36), (.34, .72, .36), .008, frame, hull, 8, 0)
    turned('Antenna base', (.34, .25, .36), (0, 1, 0), [(0, .03), (.02, .03), (.03, .015)], steel, hull, 16)
    # Pelvis: box frame carrying both hip drives.
    shell('Pelvis frame', .64, .46, .10, -.30, -.17, frame, hull, at=(0, .05))
    for s in (-1, 1): hub('Hip drive', (s * .40, -.22, .05), (1, 0, 0), .10, .16, hull)
    for x, z in ((-.3, -.3), (.3, -.3), (-.3, .3), (.3, .3)): bolt((x, .25, z), (0, 1, 0), hull, r=.016)
    # Right shoulder carrying the hammer arm (hammer socket).
    socket = Vector((0, size.y * .5, -size.z * .5 + .15)) + src(bot['hammer_socket'])
    beam('Shoulder bracket', (.42, -.02, -.22), (socket.x, socket.y, socket.z), .10, .12, frame, hull)
    arm = part('Arm', tuple(socket), root)
    hub('Shoulder drive', socket, (1, 0, 0), .10, .16, arm)
    reach = 1.2
    beam('Upper arm', socket, socket + Vector((0, 0, -.58)), .10, .12, frame, arm)
    shell('Upper arm armour', .14, .38, .04, socket.y - .08, socket.y + .08, camo, arm, at=(socket.x, socket.z - .3))
    hub('Elbow', socket + Vector((0, 0, -.6)), (1, 0, 0), .075, .14, arm)
    beam('Forearm', socket + Vector((0, 0, -.6)), socket + Vector((0, 0, -reach + .12)), .07, .08, oxidized, arm)
    cylinder('Forearm ram', socket + Vector((0, .07, -.2)), socket + Vector((0, .07, -.8)), .025, steel, arm, 12, .002)
    # Paddle-shaped hammer head, like the concept's slab.
    head = socket + Vector((0, 0, -reach))
    shell('Hammer head', .38, .26, .07, head.y - .12, head.y + .12, camo, arm, at=(head.x, head.z))
    box('Hammer face', head + Vector((0, 0, -.14)), (.34, .2, .03), steel, arm, .006)
    for dx in (-.12, .12):
        for dy in (-.07, .07): bolt(head + Vector((dx, dy, -.155)), (0, 0, -1), arm, r=.014)
    legs = {}
    for side, label in ((-1, 'L'), (1, 'R')):
        hip = Vector((side * .40, -.22, .05))
        thigh = part('Thigh' + label, tuple(hip), root)
        limb('Thigh', hip, .62, .16, .20, camo, thigh)
        knee = hip - Vector((0, .62, 0))
        shin = part('Shin' + label, tuple(knee), root)
        limb('Shin', knee, .64, .12, .15, olive, shin, slim=True)
        hub('Knee', knee, (1, 0, 0), .075, .15, shin)
        ankle = knee - Vector((0, .64, 0))
        foot = part('Foot' + label, tuple(ankle), root)
        hub('Ankle', ankle, (1, 0, 0), .055, .12, foot)
        for dx, dz, length in ((-.07, -1, .26), (.07, -1, .26), (0, 1, .16)):
            a = ankle + Vector((dx, -.02, 0)); b = ankle + Vector((dx * 1.6, -.075, dz * length))
            beam('Toe', a, b, .07, .05, frame, foot)
            box('Toe pad', b + Vector((0, -.005, -dz * .02)), (.09, .04, .09), rubber, foot, .01)
        legs[label] = (thigh, shin, foot)
    return root

# ------------------------------------------------------------------ Hellwheel 07
def build_monowheel():
    bot = DATA['monowheel_07']
    wheel_r = bot['wheel']['radius'] / SCALE; wheel_w = bot['wheel']['width'] / SCALE; wheel_y = bot['wheel']['centre_y'] / SCALE
    root = part('NimbleMonowheel')
    hull = part('Hull', (0, 0, 0), root)
    # Two armoured fork pods either side of the tyre, joined over its crown.
    for s in (-1, 1):
        x = s * (wheel_w * .5 + .12)
        shell('Fork pod', .20, .82, .06, -.40, .14, red, hull, at=(x, 0), top=(.9, .92))
        # Hazard fender low on each pod, a flame warning plate on the right.
        box('Fender hazard plate', (s * (wheel_w * .5 + .225), -.30, -.08), (.03, .14, .52), hazard, hull, .008)
        hub('Axle bearing', (s * (wheel_w * .5 + .04), wheel_y, 0), (1, 0, 0), .09, .07, hull)
        for z in (-.3, .3): bolt((s * (wheel_w * .5 + .222), .02, z), (s, 0, 0), hull, r=.016)
    box('Flame warning plate', (wheel_w * .5 + .228, -.05, .18), (.012, .18, .18), stencil, hull, .004)
    shell('Crown bridge', .70, .64, .12, .16, .26, red, hull, at=(0, .04), top=(.95, .92))
    # Head: big optic eye over the tyre with two status lenses.
    shell('Head housing', .50, .52, .10, .26, .52, red, hull, at=(.04, -.06), top=(.86, .82), top_shift=(0, .03))
    lens('Main optic', (.04, .39, -.35), (0, 0, -1), .075, amber, hull)
    for dx, dy in ((.17, .43), (.17, .34)): lens('Status lens', (dx, dy, -.32), (0, 0, -1), .026, blue, hull)
    box('Head hazard band', (.04, .28, -.34), (.46, .04, .03), hazard, hull, .005)
    stencil_text('07', (-.376, -.08, .05), '-x', .16, hull)
    stencil_text('07', (.376, -.08, -.15), '+x', .16, hull)
    # Rocket pod on the right shoulder.
    shell('Rocket pod', .22, .30, .05, .30, .56, frame, hull, at=(.36, .12))
    for dx in (-.05, .05):
        for dy in (-.05, .05):
            turned('Rocket tube', (.36 + dx, .43 + dy, -.03), (0, 0, -1), [(0, .035), (.01, .035), (.01, .026), (-.05, .026)], dark, hull, 16)
            turned('Rocket tip', (.36 + dx, .43 + dy, .0), (0, 0, -1), [(0, .02), (.02, .0)], coil_red, hull, 12)
    cylinder('Antenna mast', (-.20, .52, .20), (-.20, 1.05, .20), .008, frame, hull, 8, 0)
    wheel = part('Wheel', (0, wheel_y, 0), root)
    tyre('Tyre', (0, wheel_y, 0), wheel_r, wheel_r * .64, wheel_w, 22, wheel)
    minigun('Gun', src(bot['gun_pivot']), 6, .045, 1.3, root, red)
    return root

# ------------------------------------------------------------------ Pogo 03
def build_pogo():
    bot = DATA['pogo_03']
    ride = bot['ride_height'] / SCALE
    root = part('NimblePogo')
    hull = part('Hull', (0, 0, 0), root)
    shell('Head body', .86, .82, .14, -.22, .12, yellow, hull, top=(.98, .97))
    shell('Head cap', .86, .82, .14, .12, .26, yellow, hull, top=(.84, .80), top_shift=(0, .02))
    for x in (-.14, .14):
        box('Eye recess', (x, .02, -.405), (.16, .22, .03), dark, hull, .01)
        box('Eye lens', (x, .02, -.418), (.11, .17, .012), amber, hull, .012)
    for i in range(4): box('Grille bar', (0, -.10 - i * .028, -.412), (.36, .012, .02), frame, hull, .002)
    stencil_text('03', (.428, -.07, .12), '+x', .17, hull)
    cylinder('Antenna mast', (.30, .26, .30), (.30, .78, .30), .008, frame, hull, 8, 0)
    shell('Top hatch', .30, .26, .05, .26, .29, frame, hull, at=(.06, .1))
    # Shoulder arms ending in glowing sensor pods.
    for s in (-1, 1):
        beam('Shoulder strut', (s * .42, -.02, .0), (s * .58, -.10, .02), .08, .08, frame, hull)
        shell('Sensor pod', .16, .24, .05, -.22, .02, yellow, hull, at=(s * .64, .02))
        box('Pod lamp', (s * .64, -.10, -.105), (.10, .08, .02), amber, hull, .01)
    # Spring seat and damper sleeve under the head.
    turned('Spring seat', (0, -.22, 0), (0, -1, 0), [(0, .24), (.03, .24), (.04, .20), (.04, .08)], frame, hull, 32)
    cylinder('Damper sleeve', (0, -.24, 0), (0, -.42, 0), .06, steel, hull, 20, .003)
    rest_hub = -ride + .35
    coil_node = part('Coil', (0, -.26, 0), root)
    coil('Coil spring', (0, -.26, 0), 1.0, .17, .04, 6.5, coil_red, coil_node)
    hub_node = part('Hub', (0, rest_hub, 0), root)
    turned('Hub plate', (0, rest_hub, 0), (0, 1, 0), [(0, .22), (.04, .22), (.05, .18), (.06, .07)], frame, hub_node, 32)
    cylinder('Damper rod', (0, rest_hub + .06, 0), (0, rest_hub + .34, 0), .03, steel, hub_node, 16, .002)
    for k, foothold in enumerate(bot['footholds']):
        f = src((foothold[0], 0, foothold[1]))
        direction = Vector((f.x, 0, f.z)).normalized()
        knee = Vector((0, rest_hub + .02, 0)) + direction * .30 + Vector((0, .06, 0))
        foot = Vector((f.x, -ride + .05, f.z))
        beam('Tripod thigh', (direction.x * .14, rest_hub, direction.z * .14), knee, .09, .1, yellow, hub_node)
        hub('Tripod knee', knee, direction.cross(Vector((0, 1, 0))), .05, .1, hub_node)
        beam('Tripod shin', knee, foot + Vector((0, .04, 0)), .07, .08, frame, hub_node)
        turned('Tripod foot', foot, (0, -1, 0), [(0, .09), (.03, .09), (.05, .05)], rubber, hub_node, 20)
    minigun('Gun', src(bot['gun_pivot']), 3, .04, 1.3, root, yellow)
    return root

# ------------------------------------------------------------------ Skater 12
def build_skater():
    bot = DATA['skater_12']
    ride = bot['ride_height'] / SCALE
    root = part('NimbleSkater')
    hull = part('Hull', (0, 0, 0), root)
    shell('Chassis tub', 1.02, 1.30, .18, -.20, .06, red, hull, top=(1.0, .98))
    shell('Deck armour', 1.0, 1.24, .18, .06, .20, red, hull, top=(.84, .86), top_shift=(0, .06))
    shell('Engine hump', .52, .44, .10, .20, .30, frame, hull, at=(0, .30))
    for i in range(5): box('Hump vent', (0, .22 + i * .02, .53), (.40, .012, .02), dark, hull, .002)
    # Head wedge at the nose with twin blue optics.
    shell('Head wedge', .56, .30, .08, -.14, .12, red, hull, at=(-.12, -.68), top=(.9, .8), top_shift=(0, .03))
    for x in (-.24, .0): lens('Optic', (x, -.01, -.835), (0, 0, -1), .055, blue, hull)
    box('Head brow', (-.12, .09, -.80), (.50, .04, .08), frame, hull, .006)
    stencil_text('12', (-.30, .205, .0), 'top', .20, hull)
    cylinder('Antenna mast', (.36, .20, .50), (.36, .75, .50), .008, frame, hull, 8, 0)
    legs = {}
    for fx, fz, label in ((-1, -1, 'FL'), (1, -1, 'FR'), (-1, 1, 'BL'), (1, 1, 'BR')):
        hip = Vector((fx * .46, -.10, fz * .50))
        hub('Hip drive', hip, (1, 0, 0), .09, .14, hull)
        thigh = part('Thigh' + label, tuple(hip), root)
        limb('Thigh', hip, .48, .12, .14, red, thigh)
        knee = hip - Vector((0, .48, 0))
        shin = part('Shin' + label, tuple(knee), root)
        limb('Shin', knee, .46, .09, .11, frame, shin, slim=True, piston=False)
        hub('Knee', knee, (1, 0, 0), .06, .12, shin)
        ankle = knee - Vector((0, .46, 0))
        wheel = part('Wheel' + label, tuple(ankle), root)
        tyre('Skate wheel', ankle, .13, .085, .09, 14, wheel, lug_depth=.018)
        box('Wheel fork', ankle + Vector((fx * .07, .05, 0)), (.03, .12, .08), frame, shin, .004)
    minigun('Gun', src(bot['gun_pivot']), 2, .05, 1.3, root, red)
    return root

BUILDERS = {'strider_09': build_strider, 'monowheel_07': build_monowheel, 'pogo_03': build_pogo, 'skater_12': build_skater}
manifest = {'generator': 'tools/build-nimble-bots.py', 'authoring': 'Godot metres in each hull frame, X right Y up -Z forward; runtime factor three applied by NimbleVisual',
            'look': 'First-pass look development: flat PBR enamel/steel/rubber classes, no baked maps', 'approval': 'Pending user visual approval', 'bots': {}}
roots = {}
for chassis, builder in BUILDERS.items():
    root = builder(); roots[chassis] = root
    for group in [g for g in list(kit.groups) if g in descendants(root)]:
        finalize(group)
    tris = 0
    for o in descendants(root):
        if o.type == 'MESH': o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
    export_model(root, chassis + '.glb', RUNTIME)
    manifest['bots'][chassis] = {'runtime': chassis + '.glb', 'triangles': tris,
                                 'nodes': sorted(o.name for o in descendants(root) if o.type == 'EMPTY')}
    for o in descendants(root): o.hide_render = True
(RUNTIME / 'nimble_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('NIMBLE_EXPORT', json.dumps({k: v['triangles'] for k, v in manifest['bots'].items()}))
if NO_RENDER:
    sys.exit(0)

# ------------------------------------------------------------------ review renders
floor = kit.material('Studio_Only', (.73, .75, .77), .0, .68)
def light(name, at, energy, color, size, target=(0, .5, 0)):
    d = bpy.data.lights.new(name, 'AREA'); d.energy = energy; d.shape = 'DISK'; d.size = size; d.color = color
    o = bpy.data.objects.new(name, d); bpy.context.collection.objects.link(o); o.location = gv(at)
    o.rotation_euler = (gv(target) - o.location).to_track_quat('-Z', 'Y').to_euler()
light('Large warm key', (-3.5, 5, -5), 420, (1, .97, .90), 4)
light('Cool side reflection', (4, 2, -1), 260, (.84, .92, 1), 3)
light('Rear rim', (-1, 3, 3), 300, (1, .95, .86), 2.5)
light('Front fill', (0, 1, -5), 110, (.94, .96, 1), 3)
scene = bpy.context.scene; scene.world = scene.world or bpy.data.worlds.new('Nimble studio'); scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.65, .69, .75, 1); scene.world.node_tree.nodes['Background'].inputs[1].default_value = .25
cam_data = bpy.data.cameras.new('NimbleCamera'); cam = bpy.data.objects.new('NimbleCamera', cam_data); bpy.context.collection.objects.link(cam); scene.camera = cam
scene.render.engine = 'CYCLES'; scene.cycles.samples = 48; scene.cycles.use_denoising = True
try:
    prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'OPTIX'; prefs.get_devices()
    for device in prefs.devices: device.use = device.type == 'OPTIX'
    scene.cycles.device = 'GPU'
except Exception: pass
scene.render.resolution_x = 1200; scene.render.resolution_y = 1000
scene.view_settings.view_transform = 'AgX'
for chassis, root in roots.items():
    ride = DATA[chassis]['ride_height'] / SCALE
    for o in descendants(root): o.hide_render = False
    root.location = gv((0, ride, 0))
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0)); plane = bpy.context.object; plane.data.materials.append(floor)
    cam.location = gv((2.2, ride + 1.1, -2.8)); cam.rotation_euler = (gv((0, ride * .6, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam_data.type = 'ORTHO'; cam_data.ortho_scale = 2.6
    scene.render.filepath = str(PREVIEW / (chassis + '_hero.png')); bpy.ops.render.render(write_still=True)
    for o in descendants(root): o.hide_render = True
    bpy.data.objects.remove(plane, do_unlink=True)
print('NIMBLE_COMPLETE', str(PREVIEW))
