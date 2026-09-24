"""SKATER 12 (#61): a low red armoured quadruped on leg-end wheels, twin cannons.

blender --background --python tools/build-nimble-skater.py [-- --quick] [--no-bake] [--no-render]

Construction brief (Godot metres in the source hull frame: X right, Y up,
-Z forward; the runtime applies the factor three once; origin = centre of the
1.2 x 0.5 x 1.4 collision box, 0.75 above the ground at ride height).

Fixed constraints (data/nimble_bots.json skater_12, nimble_visual.gd):
- Hips (+-.46, -.10, +-.50); wheel centres at footholds (+-.85, +-.75), 0.13
  above the floor; tyre outer radius 0.13. Thigh .46 + shin .48 reaches the
  0.70 stance, 0.59 when crouched and the 0.93 rear kick.
- The runtime points each segment's local -Y at the next joint and derives
  local X by sliding world X off it. In the stance this makes the knee hinge
  ~ thigh local X / shin local Z, the thigh's world top local -Z (front legs)
  or +Z (rear legs), and the shin's local X ~ world X. Wheels keep the hull's
  X axle and only spin. Hence: ball hips, clevis knees with a drive drum on
  the thigh, a single-sided inboard fork and a guard hoop outside the tyre's
  bounding sphere so the tilting shin can never cut the upright tyre.
- Gun pivot (.32, .28, .20), muzzle 1.3 ahead; pitch -35..+22 deg. The
  barrels sweep the whole right-front quadrant, so the body is split: a torso
  (x -.40...145) with the head, a gun slot between two trunnion cheeks, and
  a right side rail (x .425...60) that carries the right hips. A folded well
  floor/chin tray joins the rail to the torso under the gun's sweep.

Primary masses: torso loft (folded shoulders, glacis, lower apron) over a
backing monocoque; two side rails; the head; four legs and wheels; the gun.
Medium: armour segments with narrow seams, hip slew drives on the rails,
trunnion cheeks, radiator hump with a real louvred aperture, face plate with
tubular optics, rear bulkhead radiator, keel skid, clevis knees, fork arms,
mudguards, dished wheels. Small: seated fasteners, hoses, lamp bar, stencil.

Palette (from the concept, not Atlas): weathered brick-red enamel, dark
charcoal-brown painted structure, rust-brown oxidized hardware, bright
machined pins, ochre tyre bands, off-white "12", blue optics, amber lamp bar.
Proof views: hero, rear, side, top, close-up of the posed stance (the GLB
stays in the rest pose the runtime reads), plus the sampled clearance audit.
"""
import bpy, math, sys
from pathlib import Path
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nimble_model_kit as nmk
from nimble_model_kit import (M, src, section, oriented, beam, coil, minigun, rounded, outline)
import atlas_model_kit as kit
from atlas_model_kit import part, mesh, prism, box, cylinder, ring, turned, tube, gv

CHASSIS = 'skater_12'
PREFIX = 'Nimble12'
BOT = nmk.DATA[CHASSIS]
RIDE = BOT['ride_height'] / nmk.SCALE
CROUCH = .15                       # physics lowers the hull up to this far at speed
WHEEL_R = .13                      # runtime SKATER_WHEEL_RADIUS
WHEEL_W = .09
KICK_BACK, KICK_OUT = .32, .12     # runtime SKATER_KICK_BACK / _OUT
KNEE_BEND = Vector((.5, 1.0, 0.0)) # runtime SKATER_KNEE_BEND
THIGH, SHIN = .46, .48
FACE_WEAR = .82                    # baker threshold: higher = sparser face abrasion; the concept wears on edges
HIP = Vector((.46, -.10, .50))
PIVOT = src(BOT['gun_pivot'])
BARREL_R, BARREL_SPACING = .040, .048   # clamps (r .100) stay inboard of the right rail (x .425)
TX, TW = -.1275, .2725             # torso centre x and half width (x -.40 .. .145)
RAIL_IN, RAIL_OUT = .425, .60
LABELS = (('FL', -1, -1), ('FR', 1, -1), ('BL', -1, 1), ('BR', 1, 1))

PALETTE = {
    # Brick-red enamel: dielectric paint, broad matte sheen.
    'primary': ((.50, .10, .066), .07, .62),
    # Charcoal-brown painted frames and castings.
    'secondary': ((.165, .155, .145), .10, .58),
    'steel': ((.56, .55, .53), .92, .36),
    # Rust-brown worn hardware (the concept's joint collars and forks).
    'oxidized': ((.31, .225, .165), .78, .58),
    'dark': ((.026, .025, .024), .40, .55),
    'rubber': ((.047, .045, .043), .0, .86),
    'gun': ((.21, .21, .215), .86, .46),
    # Ochre tyre bands and accents.
    'hazard': ((.78, .50, .12), .08, .58),
    'stencil': ((.86, .84, .78), .05, .50),
    'spring': ((.36, .34, .31), .82, .42),
    'lenses': {'blue': ((.30, .62, 1.0), 7.0), 'amber': ((1.0, .42, .08), 5.0)},
}


# ------------------------------------------------------------------ local helpers
def zloft(name, levels, mat, group, bevel=.008):
    """Closed shell through (z, [(x, y), ...]) cross-sections: folded armour along the body."""
    n = len(levels[0][1])
    verts = [(x, y, z) for z, prof in levels for x, y in prof]
    faces = [tuple(reversed(range(n))), tuple(range((len(levels) - 1) * n, len(levels) * n))]
    for k in range(len(levels) - 1):
        faces += [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def slab(name, outline2d, frame, d0, d1, mat, group, bevel=.005):
    """Extrude a 2D (u, v) outline along w between d0 and d1; frame = (origin, u, v, w)."""
    o, u, v, w = [Vector(a) for a in frame]
    n = len(outline2d)
    verts = [tuple(o + u * a + v * b + w * d) for d in (d0, d1) for a, b in outline2d]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def arc(cu, cv, r, a0, a1, steps):
    return [(cu + math.cos(a0 + (a1 - a0) * i / steps) * r, cv + math.sin(a0 + (a1 - a0) * i / steps) * r) for i in range(steps + 1)]


def chamfered(hx, hz, c):
    return [(-hx + c, -hz), (hx - c, -hz), (hx, -hz + c), (hx, hz - c), (hx - c, hz), (-hx + c, hz), (-hx, hz - c), (-hx, -hz + c)]


def fastener(at, axis, group, r=.0085):
    """Seated washer, domed button head with a real hex socket and dark floor (12-sided)."""
    p = Vector(at); d = Vector(axis).normalized()
    cylinder('Fastener seated washer', p - d * .002, p + d * .0012, r * 1.32, M['oxidized'], group, 12, 0)
    turned('Domed button fastener', p, d, [(0, r), (.0055, r * .9), (.009, r * .6), (.009, r * .36), (.0042, r * .36)],
           M['steel'], group, 12, hex_socket=True)
    cylinder('Fastener socket floor', p + d * .0044, p + d * .0047, r * .34, M['dark'], group, 6, 0)


def hex_nut(at, axis, group, r=.009, h=.008):
    """Hex-head cap screw for bolt circles: a real six-sided head, chamfered crown."""
    p = Vector(at); d = Vector(axis).normalized()
    turned('Hex head cap screw', p - d * .001, d, [(0, r), (h, r), (h + .0015, r * .78), (h + .0015, 0.0)], M['steel'], group, 6)


def small_bolt(at, axis, group, r=.006):
    """Hex cap screw on a seated washer: the cheaper fastener for dense bolt circles."""
    p = Vector(at); d = Vector(axis).normalized()
    cylinder('Fastener seated washer', p - d * .002, p + d * .0012, r * 1.45, M['oxidized'], group, 12, 0)
    hex_nut(p + d * .0012, d, group, r, r * .75)


def lug(name, center, size, rotation, mat, group, draft=.72):
    """Moulded tread lug: a drafted block (crown smaller than the root) whose
    tapered walls catch light like a chamfer without bevel geometry."""
    c = Vector(center); sx, sy, sz = (v * .5 for v in size)
    pts = []
    for y, k in ((-sy, 1.0), (sy, draft)):
        pts += [c + rotation @ Vector((x * sx * (1 if k == 1.0 else .9), y, z * sz * k)) for x, z in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return mesh(name, [tuple(q) for q in pts], [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], mat, group, 0)


def sphere(name, p, r, mat, group, n=24, rings=12, axis=(0, 1, 0)):
    prof = [(-r * math.cos(math.pi * i / rings), max(.0006, r * math.sin(math.pi * i / rings))) for i in range(rings + 1)]
    return turned(name, p, axis, prof, mat, group, n)


def mirror(pts, side):
    return [(x * side, y) for x, y in pts]


# ------------------------------------------------------------------ torso
def torso_profile(roof, w, belly=-.20, inset=0.0):
    """Folded section: flat roof, broad shoulder facets, vertical walls, lower apron."""
    w -= inset; roof -= inset; belly += inset
    half = [(w - .115, roof), (w - .016, roof - .096), (w, roof - .114), (w, -.07), (w - .055, belly + .02), (w - .105, belly)]
    right = [(TX + x, y) for x, y in half]
    left = [(TX - x, y) for x, y in reversed(half)]
    return right + left


# (z, roof, half width): rear cap, haunch, back, shoulders, glacis, nose.
TORSO = [(.668, .195, .252), (.625, .232, TW), (.30, .248, TW), (-.10, .250, TW), (-.40, .232, TW), (-.53, .150, TW), (-.645, .060, .250)]
ARMOUR = .030                      # backing inset: seams reveal this depth


def torso_at(z):
    for (za, ra, wa), (zb, rb, wb) in zip(TORSO, TORSO[1:]):
        if zb <= z <= za:
            t = (za - z) / (za - zb)
            return ra + (rb - ra) * t, wa + (wb - wa) * t
    return (TORSO[0][1], TORSO[0][2]) if z > TORSO[0][0] else (TORSO[-1][1], TORSO[-1][2])


def torso_levels(z0, z1, inset=0.0):
    """Sections from z0 down to z1 (z0 > z1), interpolated from the TORSO table."""
    zs = [z0] + [row[0] for row in TORSO if z1 < row[0] < z0] + [z1]
    return [(z, torso_profile(*torso_at(z), inset=inset)) for z in zs]


def roof_y(z):
    return torso_at(z)[0]


def clip(poly, x, keep):
    """Clip a convex (x, y) polygon by the vertical line at x; keep = +1 keeps x >= line."""
    out = []
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        in0 = (x0 - x) * keep >= 0; in1 = (x1 - x) * keep >= 0
        if in0: out.append((x0, y0))
        if in0 != in1:
            t = (x - x0) / (x1 - x0); out.append((x, y0 + (y1 - y0) * t))
    return out


RB, RT = .020, .100                # rail underside and top: the crouched thighs pass beneath


def clip_y(poly, y, keep):
    """Clip a convex (x, y) polygon by the horizontal line at y; keep = +1 keeps y >= line."""
    return [(b, a) for a, b in clip([(b, a) for a, b in poly], y, keep)]


def rail_profile(side, top=RT, inset=0.0, inner=None):
    xi = (inner if inner is not None else RAIL_IN) + inset
    xo = RAIL_OUT - inset; t = top - inset; b = RB + inset
    pts = [(xi, b + .015), (xi, t - .01), (xi + .01, t), (xo - .02, t), (xo, t - .02), (xo, RB + .036 + inset * .5), (xo - .045, b), (xi + .02, b)]
    return mirror(pts, side)


def stencil(text, at, right, normal, size, group):
    """Raised stencil on any plane: reads along `right`, faces `normal` (hull frame)."""
    right = Vector(right).normalized(); normal = Vector(normal).normalized(); up = normal.cross(right)
    curve = bpy.data.curves.new('Stencil ' + text, 'FONT'); curve.body = text; curve.size = size
    curve.extrude = .0015; curve.align_x = 'CENTER'; curve.align_y = 'CENTER'
    obj = bpy.data.objects.new('Stencil ' + text, curve); bpy.context.collection.objects.link(obj)
    obj.matrix_world = Matrix((gv(right), gv(up), gv(normal))).transposed().to_4x4()
    obj.location = gv(at)
    bpy.context.view_layer.objects.active = obj; bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.convert(target='MESH'); obj = bpy.context.object
    obj.data.materials.clear(); obj.data.materials.append(M['stencil'])
    obj.data.uv_layers.new(name='UVMap')
    kit.groups[group].append(obj)
    return obj


def build_hull(root):
    hull = part('Hull', (0, 0, 0), root)
    paint, sec, steel, oxid, dark = M['paint'], M['secondary'], M['steel'], M['oxidized'], M['dark']

    # --- Torso: continuous backing monocoque, three armour segments over it.
    zloft('Torso backing monocoque', torso_levels(.660, -.636, inset=ARMOUR), sec, hull, .004)
    # The red carapace stops at the waist; the dark lower hull (the backing, set
    # back by the armour thickness) carries the belly, a shadowed overhang line.
    WAIST = -.055
    def carapace(levels): return [(z, clip_y(p, WAIST, 1)) for z, p in levels]
    zloft('Torso carapace back', carapace(torso_levels(.297, -.097)), paint, hull, .007)
    zloft('Torso carapace shoulder and glacis', carapace(torso_levels(-.103, -.645)), paint, hull, .007)
    # Haunch segment: built around a real cooling aperture. Side strips run the
    # full length; bridges close it front and rear; the floor is the backing.
    hx, hz0, hz1 = .118, .600, .360
    for keep, title in ((-1, 'left'), (1, 'right')):
        zloft('Torso haunch armour ' + title + ' strip', [(z, clip(p, TX + keep * hx, keep)) for z, p in carapace(torso_levels(.668, .303))], paint, hull, .007)
    for z0, z1, title in ((.668, hz0, 'rear bridge'), (hz1, .303, 'front bridge')):
        zloft('Torso haunch armour ' + title, [(z, clip(clip(p, TX - hx, 1), TX + hx, -1)) for z, p in carapace(torso_levels(z0, z1))], paint, hull, .005)
    zloft('Cooling aperture floor', [(z, [(TX - hx, roof_y(z) - ARMOUR - .004), (TX + hx, roof_y(z) - ARMOUR - .004), (TX + hx, roof_y(z) - ARMOUR + .002),
                                          (TX - hx, roof_y(z) - ARMOUR + .002)]) for z in (hz0, hz1)], dark, hull, 0)
    for i in range(9):
        z = hz1 + .016 + i * (hz0 - hz1 - .032) / 8
        oriented('Cooling louvre', (TX, roof_y(z) - ARMOUR * .5, z), (2 * hx - .002, .024, .004), Matrix.Rotation(.62, 3, 'X'), sec, hull, .001)
    box('Cooling aperture centre stiffener', (TX, roof_y(.48) - ARMOUR * .5 - .003, (hz0 + hz1) / 2), (.012, ARMOUR - .004, hz0 - hz1), sec, hull, .002)
    for x in (TX - hx - .03, TX + hx + .03):
        for z in (hz0 + .03, hz1 - .03):
            fastener((x, roof_y(z), z), (0, 1, 0), hull, .0075)

    # Framed cooling grille on the lower hull's right wall, under the gun slot.
    gx = TX + TW - ARMOUR
    box('Side grille recess floor', (gx + .0015, -.10, .30), (.003, .07, .40), dark, hull, .0005)
    for dz in (-.207, .207):
        box('Side grille jamb', (gx + .010, -.10, .30 + dz), (.02, .09, .014), sec, hull, .002)
    for dy in (-.041, .041):
        box('Side grille sill', (gx + .010, -.10 + dy, .30), (.02, .008, .428), sec, hull, .002)
    for i in range(10):
        z = .30 - .18 + i * .04
        oriented('Side grille louvre', (gx + .009, -.10, z), (.016, .066, .004), Matrix.Rotation(.6, 3, 'Y'), sec, hull, .001)
    for side in (-1, 1):
        for z in (-.40, .50):
            fastener((TX + side * (TW - ARMOUR + .0005), -.12, z), (side, 0, 0), hull, .007)

    # Belly keel skid carries the lower apron; its chamfered ends ride over debris.
    zloft('Belly keel skid', [(z, [(TX + x, y) for x, y in [(-.19, -.198), (.19, -.198), (.215, -.215), (.19, -.245), (-.19, -.245), (-.215, -.215)]])
                              for z in (.60, -.56)], sec, hull, .006)
    for z in (-.44, .52):
        fastener((TX, -.245, z), (0, -1, 0), hull, .008)

    # --- Flush service hatch on the back segment; unit number on roof and facet.
    ry = roof_y(.10)
    slab('Roof service hatch seal', outline(.26, .30, .03), ((TX, ry + .0005, .10), (1, 0, 0), (0, 0, 1), (0, 1, 0)), 0, .001, dark, hull, 0)
    slab('Roof service hatch plate', outline(.25, .29, .028), ((TX, ry + .0005, .10), (1, 0, 0), (0, 0, 1), (0, 1, 0)), 0, .006, paint, hull, .002)
    for dx in (-.10, .10):
        for dz in (-.12, .12):
            fastener((TX + dx, ry + .0065, .10 + dz), (0, 1, 0), hull, .0075)
    stencil('12', (TX, ry + .0075, .10), (1, 0, 0), (0, 1, 0), .16, hull)
    roof, w = torso_at(-.02)
    n = Vector((-.096, .099, 0)).normalized()
    facet = Vector((TX - (w - .0655), roof - .048, -.02))
    stencil('12', facet + n * .0015, (0, 0, 1), n, .105, hull)

    # --- Head: folded shell over a neck casting, face plate, binocular optics.
    HX, HW = -.13, .20
    def head_prof(w, roof, chin):
        half = [(w - .06, roof), (w - .005, roof - .045), (w, roof - .06), (w, chin + .05), (w - .045, chin)]
        return [(HX + x, y) for x, y in half] + [(HX - x, y) for x, y in reversed(half)]
    zloft('Head neck casting', [(z, head_prof(HW - .02, .17, -.10)) for z in (-.38, -.52)], sec, hull, .005)
    zloft('Head folded armour shell', [(-.46, head_prof(HW, .215, -.095)), (-.66, head_prof(HW, .215, -.095)), (-.705, head_prof(HW - .012, .195, -.083))],
          paint, hull, .008)
    zloft('Head neck collar', [(z, head_prof(HW + .012, .227, -.107)) for z in (-.475, -.505)], sec, hull, .004)
    slab('Face plate', rounded(.36, .175, .035), ((HX, .066, -.701), (1, 0, 0), (0, 1, 0), (0, 0, -1)), 0, .016, sec, hull, .004)
    for x in (HX - .094, HX + .094):
        p = Vector((x, .066, -.717))
        turned('Optic tube housing', p, (0, 0, -1), [(0, .080), (.056, .080), (.062, .075), (.068, .066), (.068, .057), (.022, .057)], sec, hull, 40)
        ring('Optic tube clamp band', p + Vector((0, 0, -.024)), (0, 0, 1), .085, .079, .014, oxid, hull, 40)
        turned('Optic machined bezel', p + Vector((0, 0, -.062)), (0, 0, -1),
               [(0, .069), (.005, .069), (.008, .064), (.008, .056), (0, .056), (0, .069)], steel, hull, 40, open_end=True)
        turned('Optic lens', p + Vector((0, 0, -.022)), (0, 0, -1), [(0, .057), (.005, .055), (.010, .041), (.013, .020), (.014, 0.0)], M['blue'], hull, 32)
        ring('Optic iris ring', p + Vector((0, 0, -.030)), (0, 0, 1), .054, .041, .004, dark, hull, 32)
    # Brow visor hood overhangs the optics; it is bolted to the shell top.
    section('Brow visor hood', [(-.60, .213), (-.60, .232), (-.70, .215), (-.79, .158), (-.78, .146), (-.69, .197)], HX - .185, HX + .185, paint, hull, .006)
    bn = Vector((0, .1, .063)).normalized()
    for x in (HX - .15, HX + .15):
        fastener((x, .2235, -.65), bn, hull, .008)
    # Chin lamp bar: amber lens recessed in a framed pocket below the face plate.
    ly = -.05
    slab('Chin lamp back plate', outline(.27, .040, .010), ((HX, ly, -.703), (1, 0, 0), (0, 1, 0), (0, 0, -1)), 0, .006, sec, hull, .002)
    for s in (-1, 1):
        box('Chin lamp frame sill', (HX, ly + s * .0165, -.713), (.27, .008, .008), sec, hull, .002)
        box('Chin lamp frame jamb', (HX + s * .1305, ly, -.713), (.009, .025, .008), sec, hull, .002)
    box('Chin lamp lens', (HX, ly, -.7105), (.252, .025, .003), M['amber'], hull, .001)
    for s in (-1, 1):
        slab('Head cheek armour', [(-.66, -.06), (-.49, -.07), (-.49, .13), (-.62, .14), (-.69, .10)], ((HX + s * (HW + .002), 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0)),
             0, s * .012, paint, hull, .003)
        for z, y in ((-.53, .09), (-.62, -.02)):
            fastener((HX + s * (HW + .014), y, z), (s, 0, 0), hull, .0075)
    box('Nose lower apron', (TX, -.16, -.655), (.40, .07, .03), sec, hull, .006)

    # --- Side rails carry the hips; the left rail is welded to the torso wall,
    # the right one is joined to it through the gun well floor and rear member.
    for side in (-1, 1):
        inner = .403 if side < 0 else RAIL_IN
        zloft('Side rail backing', [(z, rail_profile(side, inset=.010, inner=inner)) for z in (.675, -.628)], sec, hull, .003)
        for z0, z1, title in ((.685, .363, 'rear'), (.357, -.177, 'middle'), (-.183, -.640, 'front')):
            levels = [(z0, rail_profile(side, inner=inner)), (z1, rail_profile(side, inner=inner))]
            if title == 'front':
                levels = [(z0, rail_profile(side, inner=inner)), (-.60, rail_profile(side, inner=inner)), (z1, rail_profile(side, top=RT - .022, inner=inner))]
            zloft('Side rail armour ' + title, levels, paint, hull, .006)
        for z in (-.30, -.05, .20):
            fastener((side * (RAIL_OUT + .001), RB + .052, z), (side, 0, 0), hull, .0075)
        for end in (-1, 1):
            hip = Vector((side * HIP.x, HIP.y, end * HIP.z))
            # Shoulder / haunch pod on the rail: the hip slew drive sits on top.
            cx = side * (.516 if side > 0 else .502); hw = .084 if side > 0 else .098
            pod = rounded(2 * hw, .23, .035, 3, cx, hip.z)
            prism('Hip pod seat flange', rounded(2 * hw + .012, .242, .04, 3, cx, hip.z), RT - .012, RT + .006, sec, hull, .003)
            prism('Hip pod armour', pod, RT - .004, RT + .075, paint, hull, .007, top=rounded(2 * hw - .036, .19, .02, 3, cx, hip.z))
            dx = side * (.516 if side > 0 else .50)
            turned('Hip slew drive flange', (dx, RT + .075, hip.z), (0, 1, 0), [(0, .064), (.008, .064), (.010, .058), (.010, 0.0)], oxid, hull, 32)
            turned('Hip slew drive drum', (dx, RT + .083, hip.z), (0, 1, 0), [(0, .052), (.020, .052), (.024, .046), (.028, .034), (.028, 0.0)], sec, hull, 32)
            turned('Hip drive domed cap', (dx, RT + .111, hip.z), (0, 1, 0), [(0, .026), (.006, .024), (.011, .015), (.013, 0.0)], steel, hull, 24)
            for i in range(4):
                a = i * math.tau / 4 + math.pi / 4
                small_bolt((dx + math.cos(a) * .058, RT + .085, hip.z + math.sin(a) * .058), (0, 1, 0), hull, .0055)
            # Round access cover on the pod's outer wall.
            turned('Hip pod access cover', (side * (RAIL_OUT + .0), RT + .03, hip.z), (side, 0, 0), [(0, .038), (.004, .038), (.007, .033), (.010, .031), (.010, 0.0)], steel, hull, 20)
            # Under the rail: bearing flange, spindle and dust boot above the thigh ball.
            turned('Hip bearing flange', (hip.x, RB, hip.z), (0, -1, 0), [(0, .044), (.010, .044), (.014, .038), (.016, .030), (.016, 0.0)], steel, hull, 24)
            cylinder('Hip spindle', (hip.x, RB - .014, hip.z), (hip.x, hip.y + .054, hip.z), .020, steel, hull, 16, .001)
            turned('Hip spindle dust boot', (hip.x, RB - .014, hip.z), (0, -1, 0),
                   [(0, .034), (.009, .030), (.016, .036), (.024, .029), (.032, .034), (.040, .027), (.046, .024), (0, .024), (0, .034)], M['rubber'], hull, 16, open_end=True)

    # --- Gun well: folded floor and chin tray joining the right rail to the torso.
    x0, x1 = TX + TW + .001, RAIL_IN - .001
    section('Gun well folded floor', [(.690, .045), (.08, .045), (-.12, -.165), (-.30, -.165), (-.30, -.20), (-.12, -.20), (.07, .010), (.690, .010)], x0, x1, sec, hull, .006)
    box('Gun well rear cross member', ((x0 + x1) / 2, .045, .675), (x1 - x0, .09, .04), paint, hull, .006)
    for x in (x0 + .03, x1 - .03):
        fastener((x, .046, .40), (0, 1, 0), hull, .008)
        fastener((x, -.165, -.21), (0, 1, 0), hull, .008)
    # Trunnion cheeks: inner cheek on the torso wall, outer cheek on the rail.
    for xa, xb, base in ((x0, .181, .10), (.463, .498, RT)):
        cheek = [(PIVOT.z - .15, base - .03), (PIVOT.z + .16, base - .03), (PIVOT.z + .10, PIVOT.y - .03)] + \
            arc(PIVOT.z, PIVOT.y, .062, -math.pi * .15, math.pi * 1.15, 12) + [(PIVOT.z - .10, PIVOT.y - .03)]
        slab('Trunnion cheek plate', [(v, u) for u, v in cheek], ((xa, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0)), 0, xb - xa, paint, hull, .004)
        outside = -1 if xa < .3 else 1
        face = xa if outside < 0 else xb
        ring('Trunnion bearing boss', (face + outside * .006, PIVOT.y, PIVOT.z), (1, 0, 0), .050, .026, .012, oxid, hull, 32)
        for i in range(4):
            a = i * math.tau / 4 + math.pi / 4
            small_bolt((face + outside * .012, PIVOT.y + math.sin(a) * .038, PIVOT.z + math.cos(a) * .038), (outside, 0, 0), hull, .0055)
    cylinder('Trunnion pin inner', (x0 - .010, PIVOT.y, PIVOT.z), (.183, PIVOT.y, PIVOT.z), .014, steel, hull, 16, .001)
    cylinder('Trunnion pin outer', (.458, PIVOT.y, PIVOT.z), (.504, PIVOT.y, PIVOT.z), .014, steel, hull, 16, .001)

    # --- Rear bulkhead with a recessed radiator and a recovery eye.
    rz = .668
    slab('Rear bulkhead plate', [(TX + x, y) for x, y in [(-.20, -.19), (.20, -.19), (.245, -.07), (.245, .09), (.15, .185), (-.15, .185), (-.245, .09), (-.245, -.07)]],
         ((0, 0, rz), (1, 0, 0), (0, 1, 0), (0, 0, 1)), 0, .014, sec, hull, .004)
    box('Rear radiator recess floor', (TX, .035, rz + .0155), (.32, .13, .003), dark, hull, .0005)
    for s in (-1, 1):
        box('Rear radiator jamb', (TX + s * .172, .035, rz + .026), (.024, .15, .024), paint, hull, .003)
    for y in (-.035, .105):
        box('Rear radiator lintel', (TX, y + (.004 if y > 0 else -.004), rz + .026), (.368, .022, .024), paint, hull, .003)
    for i in range(6):
        oriented('Rear radiator louvre', (TX, -.012 + i * .019, rz + .025), (.318, .016, .004), Matrix.Rotation(-.55, 3, 'X'), sec, hull, .001)
    box('Rear recovery eye clevis', (TX, -.12, rz + .035), (.10, .06, .05), sec, hull, .006)
    ring('Rear recovery eye', (TX, -.12, rz + .075), (1, 0, 0), .034, .020, .018, steel, hull, 24)
    for x in (TX - .22, TX + .22):
        fastener((x, -.12, rz + .015), (0, 0, 1), hull, .008)

    # --- Antenna on the rail's rear corner.
    base = Vector((.545, RT, .66))
    turned('Antenna base', base, (0, 1, 0), [(0, .026), (.010, .026), (.014, .018), (.024, .016), (.028, .010)], sec, hull, 20)
    coil('Antenna spring', base + Vector((0, .07, 0)), .04, .010, .0024, 3.5, M['spring'], hull, 6, 12)
    cylinder('Antenna mast', base + Vector((0, .026, 0)), base + Vector((0, .62, 0)), .0045, M['gun'], hull, 8, 0)
    sphere('Antenna tip', base + Vector((0, .62, 0)), .008, M['oxidized'], hull, 10, 5)
    return hull


# ------------------------------------------------------------------ legs
def build_leg(root, label, side, end, stance):
    """Rest pose: every segment hangs along -Y from its pivot (runtime contract)."""
    paint, sec, steel, oxid, dark, rub = M['paint'], M['secondary'], M['steel'], M['oxidized'], M['dark'], M['rubber']
    hip = Vector((side * HIP.x, HIP.y, end * HIP.z))
    knee = hip - Vector((0, THIGH, 0))
    ankle = knee - Vector((0, SHIN, 0))
    up = stance['thigh_up']            # thigh local Z sign that faces the sky in the stance

    # ---------------- thigh (local frame = world at rest, origin at the hip)
    thigh = part('Thigh' + label, tuple(hip), root)
    def T(x, y, z): return hip + Vector((x, y, z * up))
    sphere('Hip ball', hip, .054, steel, thigh, 18, 9)
    turned('Thigh neck', T(0, -.040, 0), (0, -1, 0), [(0, .032), (.045, .034), (.062, .046), (.070, .056)], sec, thigh, 24)
    zloft_y = lambda name, levels, mat, bev: mesh_loft_y(name, hip, levels, mat, thigh, bev, up)
    zloft_y('Thigh root casting', [(-.100, chamfered(.060, .066, .016)), (-.150, chamfered(.060, .066, .016))], sec, .006)
    zloft_y('Thigh box-section beam', [(-.145, chamfered(.052, .058, .014)), (-.30, chamfered(.050, .056, .014)), (-.40, chamfered(.046, .052, .013))], sec, .005)
    # Clamshell armour: folded channels over the top and bottom faces; the beam
    # shows only in the narrow side reveal between them.
    hw, z0, z1, t = .064, .036, .088, .008
    prof = [(-hw, z0), (-hw, z1 - .013), (-hw + .013, z1), (hw - .013, z1), (hw, z1 - .013), (hw, z0), (hw - t, z0), (hw - t, z1 - .016),
            (hw - .017, z1 - t), (-hw + .017, z1 - t), (-hw + t, z1 - .016), (-hw + t, z0)]
    for zs, title in ((1, 'top'), (-1, 'belly')):
        pr = [(x, z * zs) for x, z in prof]
        zloft_y('Thigh folded armour ' + title, [(-.140, [(x * .9, z * .92) for x, z in pr]), (-.155, pr), (-.34, pr), (-.36, [(x * .88, z * .92) for x, z in pr])], paint, .004)
    for y in (-.19, -.30):
        for x in (-.038, .038):
            fastener(T(x, y, z1), (0, 0, up), thigh, .008)
    # Knee clevis: fork cheeks with rounded ends, a cross web and drive drums.
    outline_c = [(-.060, -.335), (.060, -.335), (.072, -.43)] + [(math.cos(a) * .076, -.46 + math.sin(a) * .076) for a in [i * math.pi / 10 for i in range(0, -11, -1)]] + [(-.072, -.43)]
    for s in (-1, 1):
        slab('Knee clevis cheek', outline_c, ((hip.x + s * .062, hip.y, hip.z), (0, 0, up), (0, 1, 0), (1, 0, 0)), 0, s * .018, sec, thigh, .004)
    zloft_y('Knee clevis web', [(-.330, chamfered(.080, .060, .014)), (-.375, chamfered(.080, .060, .014))], sec, .004)
    for s in (-1, 1):
        at = T(s * .080, -.46, 0)
        turned('Knee drive ring-gear drum', at, (s, 0, 0), [(0, .086), (.012, .086), (.016, .081), (.024, .081), (.028, .070), (.032, .036), (.032, 0.0)], oxid, thigh, 28)
        turned('Knee drive domed cap', at + Vector((s * .032, 0, 0)), (s, 0, 0), [(0, .034), (.005, .032), (.011, .020), (.013, 0.0)], steel, thigh, 20)
        for i in range(4):
            a = i * math.tau / 4 + math.pi / 4
            small_bolt(at + Vector((s * .030, math.cos(a) * .054, math.sin(a) * .054)), (s, 0, 0), thigh, .0058)
    cylinder('Knee pin', T(-.080, -.46, 0), T(.080, -.46, 0), .018, steel, thigh, 16, .001)
    tube('Thigh hydraulic line', [T(.060, -.10, .02), T(.062, -.16, .012), T(.062, -.30, .012), T(.070, -.38, .0)], .008, rub, thigh)
    for y in (-.20, -.27):
        box('Hose clamp', T(.062, y, .012), (.014, .014, .022), steel, thigh, .002)

    # ---------------- shin (origin at the knee); outboard = side * X, front = -Z
    shin = part('Shin' + label, tuple(knee), root)
    def S(x, y, z): return knee + Vector((x * side, y, z))
    turned('Shin knee eye', S(0, 0, -.028), (0, 0, 1), [(0, .050), (.056, .050)], sec, shin, 32)
    zloft_s = lambda name, levels, mat, bev: mesh_loft_y(name, knee, [(y, [(x * side, z) for x, z in prof]) for y, prof in levels], mat, shin, bev, 1)
    zloft_s('Shin tapered beam', [(-.030, chamfered(.036, .040, .011)), (-.10, chamfered(.043, .047, .013)), (-.24, chamfered(.038, .042, .012)), (-.265, chamfered(.036, .040, .011))], sec, .005)
    # Shin guard: folded red plate over the outboard and front faces.
    guard = [(.043, .052), (.043, -.043), (.036, -.054), (-.034, -.054), (-.034, -.047), (.031, -.047), (.036, -.039), (.036, .052)]
    zloft_s('Shin folded guard', [(-.065, [(x * .92 + .003, z * .92) for x, z in guard]), (-.080, [(x + .006, z) for x, z in guard]), (-.215, [(x + .004, z) for x, z in guard]),
                                  (-.230, [(x * .92, z * .92) for x, z in guard])], paint, .003)
    for y in (-.11, -.19):
        fastener(S(.0495, y, .0), (side, 0, 0), shin, .0068)
    # Damper strut on the rear face, both eyes on shin lugs (static suspension).
    cylinder('Damper body', S(0, -.07, .060), S(0, -.18, .060), .018, oxid, shin, 20, .002)
    cylinder('Damper rod', S(0, -.18, .060), S(0, -.245, .060), .009, steel, shin, 12, .001)
    for y in (-.065, -.25):
        box('Damper eye lug', S(0, y, .048), (.032, .018, .030), sec, shin, .003)
    # Kingpin: the shin ends in a round bearing housing; the fork below it
    # swivels about the shin axis (the runtime steers each wheel along its own
    # travel, #75) and carries the single-sided inboard arm and the mudguard.
    fx = -.079                          # inboard arm mid-plane (tyre half-width .045 + clearance)
    zloft_s('Kingpin housing', [(-.240, chamfered(.036, .040, .011)), (-.252, [(x * 1.25, z * 1.2) for x, z in chamfered(.036, .040, .011)])], sec, .004)
    turned('Kingpin bearing cap', S(0, -.252, 0), (0, -1, 0), [(0, .058), (.006, .058), (.009, .052), (.009, 0.0)], steel, shin, 28)
    fork = part('Fork' + label, tuple(ankle), root)
    turned('Fork swivel crown', S(0, -.262, 0), (0, -1, 0), [(0, .056), (.004, .096), (.022, .096), (.028, .088), (.028, 0.0)], sec, fork, 36)
    for a in range(6):
        ang = a * math.tau / 6 + math.pi / 6
        fastener(S(math.cos(ang) * .074, -.262, math.sin(ang) * .074), (0, 1, 0), fork, .0055)
    arm = [(-.042, -.265), (.042, -.265), (.044, -.40)] + [(math.cos(a) * .044, -.48 + math.sin(a) * .044) for a in [i * math.pi / 10 for i in range(0, -11, -1)]] + [(-.044, -.40)]
    slab('Single-sided fork arm', arm, ((knee.x + side * (fx - .011), knee.y, knee.z), (0, 0, 1), (0, 1, 0), (side, 0, 0)), 0, .022, paint, fork, .004)
    cylinder('Stub axle', S(fx + .011, -.48, 0), S(-.028, -.48, 0), .017, steel, fork, 20, .001)
    turned('Axle retaining nut', S(fx - .011, -.48, 0), (-side, 0, 0), [(0, .022), (.008, .022), (.011, .016), (.011, 0.0)], steel, fork, 6)
    fastener(S(fx - .011, -.33, 0), (-side, 0, 0), fork, .006)
    # Guard hoop: outside the tyre's bounding sphere (r .1376) at r .150-.162, so
    # the shin can tilt about the upright wheel without touching it.
    hoop = [(math.cos(a) * .162, math.sin(a) * .162) for a in [math.radians(40 + i * 10) for i in range(10)]]
    hoop += [(math.cos(a) * .150, math.sin(a) * .150) for a in [math.radians(130 - i * 10) for i in range(10)]]
    slab('Mudguard hoop', [(-u, v) for u, v in hoop], ((ankle.x + side * (fx + .011), ankle.y, ankle.z), (0, 0, 1), (0, 1, 0), (side, 0, 0)), 0, .058 - (fx + .011), paint, fork, .003)

    # ---------------- wheel (spins about hull X at the ankle)
    wheel = part('Wheel' + label, tuple(ankle), root)
    build_wheel(ankle, side, wheel)
    return thigh, shin, fork, wheel


def mesh_loft_y(name, origin, levels, mat, group, bevel, up):
    """Loft along a limb's local -Y through (y, [(x, z)]) sections."""
    n = len(levels[0][1])
    verts = [tuple(origin + Vector((x, y, z * up))) for y, prof in levels for x, z in prof]
    faces = [tuple(reversed(range(n))), tuple(range((len(levels) - 1) * n, len(levels) * n))]
    for k in range(len(levels) - 1):
        faces += [(k * n + i, k * n + (i + 1) % n, (k + 1) * n + (i + 1) % n, (k + 1) * n + i) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def build_wheel(c, side, group):
    """Axle along X; outboard face toward side * X. Outer radius WHEEL_R."""
    rub, steel, oxid, sec, paint = M['rubber'], M['steel'], M['oxidized'], M['secondary'], M['paint']
    W = WHEEL_W; h = W / 2; bead = .086; crown = .119
    def ax(a): return side * a       # axial coordinate, + = outboard
    # Carcass: beads, rounded shoulders, flat crown (lathed about X).
    prof = []
    for i in range(9):
        a = -h + W * i / 8
        edge = max(0.0, h - abs(a))
        r = crown if edge >= .018 else bead + .012 + (crown - bead - .012) * math.sin(edge / .018 * math.pi / 2) ** .6
        prof.append((ax(a), r))
    prof = [(ax(-h + .004), bead - .002)] + prof + [(ax(h - .004), bead - .002)]
    turned('Skate tyre carcass', c, (1, 0, 0), sorted(prof, key=lambda p: p[0]), rub, group, 36, open_end=True)
    # Tread: staggered blocks either side of a centre groove, following the crown.
    pitches = 14
    for k in range(pitches):
        for s, off in ((-1, 0.0), (1, .5)):
            a = (k + off) * math.tau / pitches
            rot = Matrix.Rotation(a, 3, 'X')
            p = c + rot @ Vector((s * .021, crown + .0055, 0))
            lug('Tread block', p, (.034, .011, math.tau * crown / pitches * .62), rot @ Matrix.Rotation(s * .18, 3, 'Y'), rub, group)
    # Moulded ochre band on the outboard sidewall.
    def shoulder(edge): return bead + .012 + (crown - bead - .012) * math.sin(min(edge, .018) / .018 * math.pi / 2) ** .6
    band = [(ax(h - e), shoulder(e) + .0016) for e in (.0025, .006, .010)]
    band += [(ax(h - e), shoulder(e) - .002) for e in (.010, .0025)]
    turned('Ochre sidewall band', c, (1, 0, 0), band + band[:1], M['ochre_band'], group, 36, open_end=True)
    # Rim: rolled flanges and barrel, dished centre with five spoke windows.
    turned('Rim barrel', c + Vector((ax(-h - .002), 0, 0)), (side, 0, 0),
           [(0, bead + .004), (.006, bead + .006), (.010, bead - .004), (W - .006, bead - .006), (W - .002, bead + .006), (W + .004, bead + .004),
            (W + .004, bead - .012), (.004, bead - .014), (0, bead + .004)], steel, group, 36, open_end=True)
    dish = c + Vector((ax(h - .018), 0, 0))
    ring('Dish outer ring', dish, (1, 0, 0), bead - .010, .062, .012, oxid, group, 30)
    ring('Dish hub disc', dish, (1, 0, 0), .040, .016, .016, oxid, group, 24)
    for k in range(5):
        a = k * math.tau / 5
        rot = Matrix.Rotation(a, 3, 'X')
        beam('Forged dish spoke', dish + rot @ Vector((0, .036, 0)), dish + rot @ Vector((0, .066, 0)), .010, .018, oxid, group, .003)
    turned('Hub centre', dish + Vector((ax(.006), 0, 0)), (side, 0, 0), [(0, .040), (.008, .038), (.012, .030), (.012, 0.0)], sec, group, 24)
    for k in range(5):
        a = k * math.tau / 5 + math.pi / 5
        hex_nut(dish + Vector((ax(.016), math.cos(a) * .027, math.sin(a) * .027)), (side, 0, 0), group, .006, .005)
    turned('Domed hub cap', dish + Vector((ax(.018), 0, 0)), (side, 0, 0), [(0, .017), (.004, .016), (.009, .011), (.011, 0.0)], steel, group, 24)
    # Inboard: bearing housing toward the stub axle and fork.
    turned('Wheel bearing housing', c + Vector((ax(-h + .004), 0, 0)), (-side, 0, 0), [(0, .052), (.006, .050), (.010, .040), (.018, .034), (.018, .019)], sec, group, 24)


# ------------------------------------------------------------------ gun
def build_gun(root):
    frame, mount, rotor = minigun(PIVOT, 2, BARREL_SPACING, root, M['secondary'], barrel_r=BARREL_R)
    p = PIVOT
    # Armoured cowl over the receiver in hull enamel, bolted to it.
    section('Gun receiver armour cowl', [(p.z + .07, p.y + .118), (p.z + .07, p.y + .134), (p.z - .28, p.y + .140), (p.z - .345, p.y + .098),
                                         (p.z - .33, p.y + .088), (p.z - .29, p.y + .12)], p.x - .098, p.x + .098, M['paint'], mount, .005)
    for dx in (-.07, .07):
        for dz in (-.20, .04):
            fastener((p.x + dx, p.y + .141, p.z + dz), (0, 1, 0), mount, .0065)
    # Muzzle brakes with real bores: the lathe returns inside to a dark floor.
    muzzle_z = p.z - 1.3
    R = BARREL_R
    for i in range(2):
        a = i * math.pi
        c = Vector((p.x + math.cos(a) * BARREL_SPACING, p.y + .05 + math.sin(a) * BARREL_SPACING, muzzle_z + .10))
        turned('Muzzle brake', c, (0, 0, -1), [(0, R * 1.02), (.012, R * 1.2), (.084, R * 1.2), (.093, R * 1.08), (.100, R * .98), (.100, R * .62), (.024, R * .62)],
               M['gun'], rotor, 24)
        cylinder('Muzzle bore floor', c + Vector((0, 0, -.025)), c + Vector((0, 0, -.023)), R * .62, M['dark'], rotor, 16, 0)
        for z in (.040, .064):
            box('Muzzle brake top port', c + Vector((0, R * 1.14, -z)), (R * 1.1, .008, .013), M['dark'], rotor, .001)
    return frame, mount, rotor


# ------------------------------------------------------------------ runtime replica: stance IK
def solve_knee(hip, ankle, upper, lower, bend):
    d = (ankle - hip).normalized()
    dist = min(max((ankle - hip).length, abs(upper - lower) + .001), upper + lower - .001)
    along = (upper * upper - lower * lower + dist * dist) / (2 * dist)
    out = (bend - d * bend.dot(d)).normalized()
    return hip + d * along + out * math.sqrt(max(0.0, upper * upper - along * along))


def segment_basis(start, end):
    y = -(end - start).normalized()
    x = Vector((1, 0, 0)); x = (x - y * x.dot(y)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()


C3 = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def set_node(obj, basis, origin):
    m = (C3 @ basis @ C3.inverted()).to_4x4(); m.translation = gv(origin); obj.matrix_basis = m


def leg_solution(side, end, crouch=0.0, kick=0.0):
    hip = Vector((side * HIP.x, HIP.y, end * HIP.z))
    wheel = Vector((side * abs(BOT['footholds'][0][0]), 0, end * abs(BOT['footholds'][0][1]))) / nmk.SCALE
    if end > 0:
        wheel += Vector((side * KICK_OUT, 0, KICK_BACK)) * kick
    wheel.y = -RIDE + crouch + WHEEL_R
    v = wheel - hip
    ankle = hip + v * min(1.0, (THIGH + SHIN - .001) / v.length)
    knee = solve_knee(hip, ankle, THIGH, SHIN, Vector((KNEE_BEND.x * side, KNEE_BEND.y, KNEE_BEND.z)))
    return hip, knee, ankle


def pose(legs, gun_mount, crouch=0.0, kick=0.0, pitch=0.0, spin=0.0, steer=0.0):
    """NimbleVisual._pose_skater: the fork swivels about the shin axis by steer
    (radians) and the wheel spins in the fork."""
    for label, side, end in LABELS:
        thigh, shin, fork, wheel = legs[label]
        hip, knee, ankle = leg_solution(side, end, crouch, kick)
        set_node(thigh, segment_basis(hip, knee), hip)
        shin_basis = segment_basis(knee, ankle)
        set_node(shin, shin_basis, knee)
        fork_basis = shin_basis @ Matrix.Rotation(steer, 3, 'Y')
        set_node(fork, fork_basis, ankle)
        set_node(wheel, fork_basis @ Matrix.Rotation(spin, 3, 'X'), ankle)
    set_node(gun_mount, Matrix.Rotation(math.radians(pitch), 3, 'X'), PIVOT)
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ review
def review(root):
    """The kit's studio views (same lights, cameras and floor), with a CPU fallback:
    parallel generators share the GPU, and a CUDA out-of-memory must not lose the
    review. Kept local because the shared kit is owned by the integrator."""
    try:
        nmk.review(root, CHASSIS)
        return
    except RuntimeError as error:
        print('SKATER_REVIEW_GPU_FAILED', error)
    scene = bpy.context.scene
    scene.cycles.device = 'CPU'
    try:
        bpy.context.preferences.addons['cycles'].preferences.compute_device_type = 'NONE'
    except Exception:
        pass
    cam = scene.camera; ride = RIDE; centre = (0, ride * .6, 0)
    views = {'hero': ((2.4, ride + 1.2, -3.0), 2.9), 'rear': ((-2.2, ride + 1.0, 3.0), 2.9), 'side': ((4.0, ride * .6, 0), 2.8),
             'top': ((0.01, ride + 4.0, 0), 2.6), 'closeup': ((1.1, ride + .45, -1.4), 1.25)}
    for name, (at, ortho) in views.items():
        cam.location = gv(at)
        target = centre if name != 'closeup' else (0, ride, -.2)
        cam.rotation_euler = (gv(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam.data.type = 'ORTHO'; cam.data.ortho_scale = ortho
        scene.render.filepath = str(nmk.PREVIEW / ('%s_%s.png' % (CHASSIS, name)))
        bpy.ops.render.render(write_still=True)
    print('NIMBLE_REVIEW', CHASSIS, str(nmk.PREVIEW), 'cpu')


# ------------------------------------------------------------------ diagnostics
def profile(root):
    """Triangles per assembly and per part name (evaluated, before joining)."""
    dg = bpy.context.evaluated_depsgraph_get(); groups = {}; parts = {}
    for group, objs in kit.groups.items():
        for o in objs:
            m = o.evaluated_get(dg).to_mesh(); m.calc_loop_triangles(); n = len(m.loop_triangles); o.evaluated_get(dg).to_mesh_clear()
            groups[group.name] = groups.get(group.name, 0) + n
            key = o.name.split('.')[0]; parts[key] = parts.get(key, 0) + n
    print('SKATER_PROFILE_TOTAL', sum(groups.values()))
    print('SKATER_PROFILE_GROUPS', sorted(groups.items(), key=lambda kv: -kv[1]))
    print('SKATER_PROFILE_PARTS', sorted(parts.items(), key=lambda kv: -kv[1])[:45])


def diagnose(root, moving, poses):
    """Contact locations: hull triangle centroids overlapping each moving assembly."""
    hull = [o for o in nmk.descendants(root) if o.type == 'MESH' and not any(o in nmk.descendants(g) for g in moving)]
    def tris(objs):
        out = []
        dg = bpy.context.evaluated_depsgraph_get()
        for o in objs:
            m = o.evaluated_get(dg).to_mesh()
            for p in m.polygons:
                out.append(sum((o.matrix_world @ m.vertices[i].co for i in p.vertices), Vector()) / len(p.vertices))
            o.evaluated_get(dg).to_mesh_clear()
        return out
    hull_tree = nmk._tree(hull); hull_c = tris(hull)
    rest = {g: g.matrix_basis.copy() for g in moving}
    for label, fn in poses.items():
        for t in (0.0, .5, 1.0):
            fn(t)
            for g in moving:
                objs = [o for o in nmk.descendants(g) if o.type == 'MESH']
                pairs = nmk._tree(objs).overlap(hull_tree)
                if pairs:
                    pts = sorted({(round(hull_c[j].x, 2), round(hull_c[j].z, 2), round(-hull_c[j].y, 2)) for _, j in pairs})
                    print('SKATER_CONTACT', label, t, g.name, len(pairs), pts[:6])
        for g in moving: g.matrix_basis = rest[g]
    bpy.context.view_layer.update()


# ------------------------------------------------------------------ build
def main():
    nmk.setup(PREFIX, PALETTE)
    # Ordnance steel gets drawn-tube streaks, abrasion and heat grime (WEAPON_FEEL).
    M['gun']['atlas_streak'] = (260.0, 5.0, 260.0); M['gun']['atlas_scratch'] = .60; M['gun']['atlas_grime'] = .22
    # The tyre's ochre sidewall stripe is a coloured rubber compound, not enamel:
    # the concept's ochre with a rubber finish, baked with the hardware family.
    M['ochre_band'] = kit.material(PREFIX + '_RubberOchreBand', PALETTE['hazard'][0], .0, .74)
    root = part('NimbleSkater')
    build_hull(root)
    legs = {}
    for label, side, end in LABELS:
        hip, knee, ankle = leg_solution(side, end)
        up = 1.0 if segment_basis(hip, knee).col[2].y > 0 else -1.0
        legs[label] = build_leg(root, label, side, end, {'thigh_up': up})
    frame, mount, rotor = build_gun(root)
    moving = [g for label, _, _ in LABELS for g in legs[label]] + [mount]
    step = math.tau / 18
    poses = {
        'stance_to_crouch': lambda t: pose(legs, mount, crouch=CROUCH * t, spin=step * t),
        'rear_kick': lambda t: pose(legs, mount, kick=t, spin=step * t),
        'rear_kick_crouched': lambda t: pose(legs, mount, crouch=CROUCH, kick=t, spin=step * t),
        'gun_pitch': lambda t: pose(legs, mount, crouch=CROUCH * .5, pitch=-35 + 57 * t),
        'steer': lambda t: pose(legs, mount, steer=math.radians(-80 + 160 * t), spin=step * t),
        'steer_crouched_kick': lambda t: pose(legs, mount, crouch=CROUCH, kick=t, steer=math.radians(-80 + 160 * t)),
    }
    if '--profile' in sys.argv:
        profile(root)
    render = not nmk.NO_RENDER
    nmk.NO_RENDER = True
    nmk.complete(root, CHASSIS, PREFIX, moving, poses=poses, face_wear=FACE_WEAR)
    if '--diagnose' in sys.argv:
        diagnose(root, moving, poses)
    if render:
        # The GLB keeps the rest pose; review the in-game stance instead.
        pose(legs, mount)
        review(root)


main()
