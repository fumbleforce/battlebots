"""POGO • 03 — hopping gun head on a coil-over damper and a braced tripod (#61).

Run: blender --background --python tools/build-nimble-pogo.py -- [--quick] [--no-bake] [--no-render]

Construction brief (docs/art/STYLIZED_INDUSTRIAL_ASSETS.md)
-----------------------------------------------------------
Fixed constraints (source metres = game metres / 3, hull frame X right, Y up,
-Z forward, origin = centre of the 1.1 x 0.5 x 1.0 hull collision box):
- Ride height 1.2: tripod pad soles at Y=-1.2 with the Hub at rest Y=-0.85;
  pads centred on the published footholds (0,-.5), (±.433,.25).
- Hub stroke -0.20..+0.24 (runtime clamp). The Coil node spans from its origin
  (the head's lower spring seat, Y=-.262) down to the hub seat at hub_y + .06,
  authored at unit length along -Y and scaled by the runtime.
- Gun pivot (-.55,.12,.25), shared minigun frame, pitch -35..+20 degrees.

Primary masses: the chamfered head block (0.80 x 0.43 x 0.74), the red coil
over its dark damper, and the yellow tri-lobed hub with three splayed legs.
Medium: the dark visor module with two tall eye windows, the jutting chin
with grille and lamp slit, the gun pedestal, two shoulder arms carrying lamp
pods, hatch, grilles, leg clevises, knuckles and foot shoes. Small: button
fasteners on their plane, stencil, antennas, seams.

Construction decisions:
- The head is one lofted shell (broad 45° plan corners + forehead/chin folds,
  small machining bevel). Panel seams, the visor pocket, vent apertures and
  the damper well are cut into it (exact booleans), so recesses have walls and
  floors instead of pasted dark rectangles.
- The damper telescopes: the static dark body (Hull) hangs from the spring
  seat and continues up a bore inside the head; the chrome rod (Hub) slides in
  it. Stroke check: rod top = hub_y + .63, so at full extension it is still
  .06 m inside the body above the gland (Y=-.48) and at full compression it
  stops .04 m under the body top (.055 m under the well roof); the hub bump
  stop clears the gland wiper by .017 m.
- The coil wire is authored pre-stretched in Y by 1/L_rest, so it is round at
  rest and only squashes/stretches with the runtime stroke. Its flat end turns
  land exactly on both seats at every length.
- The gun trunnion plugs into a raised pedestal welded onto the head's upper
  left shoulder. Both shoulder arms are placed from the gun's measured sweep:
  the left arm sits aft and low so -35° depression clears it.
- The tripod is rigid: clevis cheeks on the hub carry pinned thighs, knee
  knuckles, shins, ankle pins and slate shoes; a slim brace strut ties each
  shin back to the hub.

Palette (from the concept image, not Atlas): weathered mustard enamel, dark
charcoal gunmetal enamel for structure/visor, red enamelled spring steel,
machined steel, warm oxidised dark metal, amber lamps.
Review views: hero, rear, side, top and close-up studio renders plus the
sampled hub-stroke and gun-pitch clearance audit.
"""
import bpy, bmesh, math, sys
from pathlib import Path
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import atlas_model_kit as kit
import nimble_model_kit as nk
from atlas_model_kit import part, mesh, loft, box, cylinder, ring, turned, gv
from nimble_model_kit import outline, rounded, oriented, vent, stencil_text, minigun, src, DATA, SCALE

BOT = DATA['pogo_03']
RIDE = BOT['ride_height'] / SCALE            # 1.2
HUB_REST = -RIDE + .35                       # -0.85
SEAT = .06                                   # nimble_visual POGO_SEAT
STROKE = (-.20, .24)                         # nimble_visual POGO_EXTEND / POGO_COMPRESS
COIL_TOP = -.262
COIL_REST = COIL_TOP - (HUB_REST + SEAT)     # 0.528
GUN_PIVOT = src(BOT['gun_pivot'])            # (-0.55, 0.12, 0.25)
Y = Vector((0, 1, 0))

PALETTE = {
    # Mustard safety enamel sampled from the concept's lit mid-tones; dielectric.
    'primary': ((.80, .53, .085), .08, .62),
    # Charcoal gunmetal enamel of the visor, clevises and structure.
    'secondary': ((.165, .170, .175), .10, .56),
    'hazard': ((.62, .12, .06), .10, .50),
    'steel': ((.56, .57, .57), .92, .34),
    # Warm, grimy dark metal (the concept's rusty hardware).
    'oxidized': ((.30, .265, .22), .78, .58),
    'dark': ((.028, .030, .033), .40, .55),
    'rubber': ((.05, .05, .055), .0, .86),
    'gun': ((.21, .215, .22), .86, .46),
    'stencil': ((.88, .86, .78), .05, .50),
    # Glossy red enamel over spring steel.
    'spring': ((.60, .105, .055), .30, .40),
    'lenses': {'amber': ((1.0, .56, .12), 7.0)},
}


# ------------------------------------------------------------------ local helpers
def extrude(name, pts, w0, w1, o, u, v, n, mat, group, bevel=.008):
    """Closed prism of a 2D profile (a, b) -> o + u*a + v*b, extruded along n."""
    o, u, v, n = Vector(o), Vector(u), Vector(v), Vector(n)
    k = len(pts)
    verts = [tuple(o + u * a + v * b + n * w) for w in (w0, w1) for a, b in pts]
    faces = [tuple(reversed(range(k))), tuple(range(k, 2 * k))] + [(i, (i + 1) % k, (i + 1) % k + k, i + k) for i in range(k)]
    return mesh(name, verts, faces, mat, group, bevel)


def face_prism(name, pts_xy, z0, z1, mat, group, bevel=.004):
    """Profile in the X/Y plane extruded along Z (front/rear facing parts)."""
    return extrude(name, pts_xy, z0, z1, (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), mat, group, bevel)


def rrect(w, h, r, n=3, cx=0.0, cy=0.0):
    return rounded(w, h, r, n, cx, cy)


def capsule(c1, r1, c2, r2, n=8):
    """2D hull of two circles (tapered link profile), counter-clockwise."""
    c1, c2 = Vector(c1), Vector(c2)
    d = c2 - c1; L = d.length; base = math.atan2(d.y, d.x)
    a = math.acos(max(-1, min(1, (r1 - r2) / L)))
    pts = []
    for i in range(n + 1):
        t = base - a + 2 * a * i / n
        pts.append((c2.x + math.cos(t) * r2, c2.y + math.sin(t) * r2))
    for i in range(n + 1):
        t = base + a + (2 * math.pi - 2 * a) * i / n
        pts.append((c1.x + math.cos(t) * r1, c1.y + math.sin(t) * r1))
    return pts


def link(name, a, ra, b, rb, width, mat, group, bevel=.006, n=8):
    """Tapered capsule link between points a and b, extruded across its plane."""
    a, b = Vector(a), Vector(b); d = b - a
    nrm = d.cross(Y); nrm = nrm.normalized() if nrm.length > 1e-6 else Vector((0, 0, 1))
    u = d.normalized(); v = nrm.cross(u).normalized()
    return extrude(name, capsule((0, 0), ra, (d.length, 0), rb, n), -width / 2, width / 2, a, u, v, nrm, mat, group, bevel)


def lathe(name, p, axis, profile, mat, group, n=32, closed=True):
    """Lathed ring section; a closed profile makes a hollow tube with a bore."""
    p = Vector(p); d, t, b = kit._frame(axis)
    k = len(profile); verts = []
    for dep, r in profile:
        for i in range(n):
            ang = i * math.tau / n
            verts.append(tuple(p + d * dep + (t * math.cos(ang) + b * math.sin(ang)) * r))
    faces = []
    for j in range(k if closed else k - 1):
        j2 = (j + 1) % k
        for i in range(n):
            faces.append((j * n + i, j * n + (i + 1) % n, j2 * n + (i + 1) % n, j2 * n + i))
    obj = mesh(name, verts, faces, mat, group)
    for f in obj.data.polygons:
        f.use_smooth = True
    return obj


def pbolt(at, axis, group, r=.008, low=False):
    """kit.bolt at 12 segments: washer on the plane, domed crown, hex socket."""
    p = Vector(at); d = Vector(axis).normalized(); h = .45 if low else 1.0
    if low: p = p - d * .002
    cylinder('Fastener recessed steel washer', p - d * .003, p + d * .001, r * 1.34, M['oxidized'], group, 12, 0)
    turned('Rounded machined button fastener', p, d, [(.000, r), (.003 * h, r), (.008 * h, r * .88), (.011 * h, r * .62), (.011 * h, r * .35), (.005 * h, r * .35)],
           M['steel'], group, 12, hex_socket=True)
    cylinder('Recessed fastener socket floor', p + d * .0048 * h, p + d * .0051 * h, r * .35, M['dark'], group, 6, 0)


def phub(name, p, axis, r, width, group, n=24):
    """nimble_model_kit.hub at 24 segments (bearing housing, collars, domed caps)."""
    d = Vector(axis).normalized(); p = Vector(p)
    cylinder(name + ' bearing housing', p - d * width / 2, p + d * width / 2, r, M['secondary'], group, n, .004)
    for s in (-1, 1):
        turned(name + ' machined collar', p + d * s * width / 2, d * s,
               [(0, r * .86), (.006, r * .86), (.012, r * .74), (.016, r * .52), (.020, r * .40), (.020, r * .22)], M['steel'], group, n)
        turned(name + ' domed cap', p + d * s * (width / 2 + .012), d * s, [(0, r * .3), (.008, r * .26), (.013, r * .12), (.014, 0.0)], M['oxidized'], group, 16)


def grille(name, c, u, v, n, w, h, depth, bars, group):
    """Barred grille in an aperture: dark floor, walls and bars (n points out)."""
    c, u, v, n = Vector(c), Vector(u), Vector(v), Vector(n)
    rot = Matrix((u, v, n)).transposed()
    oriented(name + ' floor', c - n * depth, (w, h, .006), rot, M['dark'], group, .001)
    for s in (-1, 1):
        oriented(name + ' wall', c + u * s * (w / 2 + .003) - n * depth / 2, (.006, h + .012, depth), rot, M['secondary'], group, .001)
        oriented(name + ' wall', c + v * s * (h / 2 + .003) - n * depth / 2, (w + .012, .006, depth), rot, M['secondary'], group, .001)
    for i in range(bars):
        oriented(name + ' bar', c + u * (-w / 2 + w * (i + .5) / bars) - n * (depth * .5 + .004), (.011, h, depth - .008), rot, M['secondary'], group, .002)


def _cutter(verts, faces):
    data = bpy.data.meshes.new('Cutter'); data.from_pydata([gv(p) for p in verts], [], faces); data.update()
    bm = bmesh.new(); bm.from_mesh(data); bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(data); bm.free()
    obj = bpy.data.objects.new('Cutter', data); bpy.context.collection.objects.link(obj)
    for f in data.polygons: f.use_smooth = False
    return obj


def cut_box(center, size, rot=None):
    c = Vector(center); s = Vector(size) * .5; rot = rot or Matrix.Identity(3)
    verts = [tuple(c + rot @ Vector((x * s.x, y * s.y, z * s.z))) for x, y, z in
             [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    return _cutter(verts, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)])


def cut_prism(pts, axis_o, u, v, n, w0, w1):
    o, u, v, n = Vector(axis_o), Vector(u), Vector(v), Vector(n); k = len(pts)
    verts = [tuple(o + u * a + v * b + n * w) for w in (w0, w1) for a, b in pts]
    faces = [tuple(reversed(range(k))), tuple(range(k, 2 * k))] + [(i, (i + 1) % k, (i + 1) % k + k, i + k) for i in range(k)]
    return _cutter(verts, faces)


def cut_band(outer, inner, y0, y1):
    """Annular prism between two plan outlines with equal point counts (seam rings)."""
    k = len(outer)
    verts = [(x, y, z) for y in (y0, y1) for x, z in outer] + [(x, y, z) for y in (y0, y1) for x, z in inner]
    faces = []
    for i in range(k):
        j = (i + 1) % k
        faces += [(i, j, k + j, k + i), (2 * k + i, 3 * k + i, 3 * k + j, 2 * k + j),
                  (i, 2 * k + i, 2 * k + j, j), (k + i, k + j, 3 * k + j, 3 * k + i)]
    return _cutter(verts, faces)


def cut_cyl(a, b, r, n=32):
    a, b = Vector(a), Vector(b); d, t, bb = kit._frame(b - a)
    verts = [tuple(p + (t * math.cos(i * math.tau / n) + bb * math.sin(i * math.tau / n)) * r) for p in (a, b) for i in range(n)]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return _cutter(verts, faces)


def cut(obj, cutters):
    """Exact boolean difference applied beneath the bevel/normal modifiers."""
    coll = bpy.data.collections.new('Cutters'); bpy.context.scene.collection.children.link(coll)
    for c in cutters:
        for users in list(c.users_collection): users.objects.unlink(c)
        coll.objects.link(c)
    mod = obj.modifiers.new('Machined recesses', 'BOOLEAN')
    mod.operation = 'DIFFERENCE'; mod.solver = 'EXACT'; mod.operand_type = 'COLLECTION'; mod.collection = coll
    try:
        obj.modifiers.move(len(obj.modifiers) - 1, 0)
    except Exception:
        with bpy.context.temp_override(object=obj, active_object=obj):
            bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for c in cutters:
        data = c.data; bpy.data.objects.remove(c, do_unlink=True); bpy.data.meshes.remove(data)
    bpy.data.collections.remove(coll)
    for f in obj.data.polygons: f.use_smooth = True
    # The exact boolean leaves a material_index attribute behind; with it the
    # joined assembly baked black occlusion over every cut part (Primary AO
    # mean .10 vs .49 without). Every cut part has one base material here (the
    # bevel adds the edge slot later), so the attribute carries no information.
    if 'material_index' in obj.data.attributes:
        obj.data.attributes.remove(obj.data.attributes['material_index'])
    return obj


def spring_coil(name, top, rest, radius, wire, turns, mat, group, n=14, steps=40):
    """Closed-end helical spring, round at `rest` length, authored at unit length.

    The runtime scales the Coil node in Y to the current length, so the wire
    section and centreline are divided by the rest length here: it renders
    round at rest and its flat end turns sit on both seats at every length.
    """
    top = Vector(top); total = int(turns * steps)
    # Pitch density: zero on the flat end turns, one on the active turns.
    def density(u):
        def ss(x): x = max(0.0, min(1.0, x)); return x * x * (3 - 2 * x)
        return ss(u / 1.1) * ss((turns - u) / 1.1)
    us = [turns * i / total for i in range(total + 1)]
    acc = [0.0]
    for i in range(total):
        acc.append(acc[-1] + (density(us[i]) + density(us[i + 1])) * .5 * (us[i + 1] - us[i]))
    span = rest - 2 * wire
    centres = [Vector((math.cos(u * math.tau) * radius, -wire - span * acc[i] / acc[-1], math.sin(u * math.tau) * radius)) for i, u in enumerate(us)]
    verts = []; faces = []
    for i, u in enumerate(us):
        a = u * math.tau; c = centres[i]
        tangent = (centres[min(i + 1, total)] - centres[max(i - 1, 0)]).normalized()
        normal = Vector((math.cos(a), 0, math.sin(a))); binormal = tangent.cross(normal).normalized(); normal = binormal.cross(tangent)
        for k in range(n):
            b = k * math.tau / n
            q = c + (normal * math.cos(b) + binormal * math.sin(b)) * wire
            verts.append((top.x + q.x, top.y + q.y / rest, top.z + q.z))
    for i in range(total):
        for k in range(n):
            a0 = i * n + k; a1 = i * n + (k + 1) % n
            faces.append((a0, a1, a1 + n, a0 + n))
    faces += [tuple(reversed(range(n))), tuple(range(total * n, total * n + n))]
    obj = mesh(name, verts, faces, mat, group)
    for f in obj.data.polygons: f.use_smooth = True
    return obj


# ------------------------------------------------------------------ assembly
M = nk.setup('Nimble03', PALETTE)
P, S2, ST, OX, DK, RB, SP, AM = M['paint'], M['secondary'], M['steel'], M['oxidized'], M['dark'], M['rubber'], M['spring'], M['amber']
# Wear: the baker's abrasion noise is in world metres (tuned on the 2.4 m Atlas);
# on this 0.8 m head a high threshold keeps face chips sparse so wear follows
# the edges. Light grime patches match the concept's dirty enamel.
FACE_WEAR = .82
for key in ('paint', 'paint_edge'):
    M[key]['atlas_grime'] = .12

root = part('NimblePogo')
hull = part('Hull', (0, 0, 0), root)

# ---- Head shell: one lofted block, then real recesses are machined into it.
HW, HD, HZ = .80, .74, -.01              # width, depth, plan centre (front z -0.38, rear .36)
FRONT = HZ - HD / 2
Y_BOT, Y_LOW, Y_HIGH, Y_TOP = -.215, -.19, .125, .178
BELT = -.046                             # upper cap / lower body split
cap = loft('Head upper armour cap', [
    (BELT + .003, outline(HW, HD, .075, 0, HZ)),
    (Y_HIGH, outline(HW, HD, .075, 0, HZ)),
    (Y_TOP, outline(HW - .10, HD - .10, .05, 0, HZ))], P, hull, .006)
body = loft('Head lower body', [
    (Y_BOT, outline(HW - .066, HD - .066, .055, 0, HZ)),
    (Y_LOW, outline(HW - .016, HD - .016, .07, 0, HZ)),
    (BELT - .003, outline(HW - .016, HD - .016, .07, 0, HZ))], P, hull, .006)
# Structural backing ring between them: the 6 mm seam shows dark metal, not a void.
belt = kit.prism('Head backing ring', outline(HW - .034, HD - .034, .064, 0, HZ), BELT - .008, BELT + .008, S2, hull, .002)

VIS = dict(x0=-.315, x1=.025, y0=-.035, y1=.122)
vis_w, vis_h = VIS['x1'] - VIS['x0'], VIS['y1'] - VIS['y0']
vis_cx, vis_cy = (VIS['x0'] + VIS['x1']) / 2, (VIS['y0'] + VIS['y1']) / 2
VENTS = [((HW / 2, .045, -.17), .15, .08, .03, 5, (1, 0, 0)),
         ((-HW / 2, .045, -.19), .11, .08, .03, 5, (-1, 0, 0)),
         ((.13, .035, HZ + HD / 2), .20, .09, .03, 6, (0, 0, 1))]
GR = dict(x=-.07, z=.215, w=.26, d=.13)
SEAM, SD = .005, .007


def head_cutters():
    """Recesses machined into the head shells (fresh cutters for each shell)."""
    c = [cut_cyl((0, -.30, 0), (0, .075, 0), .078)]          # damper well
    # Panel seams (5 mm wide, 7 mm deep): visor/number split, rear, sides, roof.
    c.append(cut_box((.055, .04, FRONT), (SEAM, .17, 2 * SD)))
    c.append(cut_box((0, .02, HZ + HD / 2), (SEAM, .40, 2 * SD)))
    for sx in (-1, 1):
        c.append(cut_box((sx * HW / 2, -.03, .105), (2 * SD + .02, .32, SEAM)))
    c.append(cut_box((0, Y_TOP, .085), (.66, 2 * SD, SEAM)))
    c.append(cut_prism(rrect(vis_w + .012, vis_h + .012, .018, 3, vis_cx, vis_cy), (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), FRONT - .02, FRONT + .022))
    for (cc, w, h, dep, _s, f) in VENTS:
        f = Vector(f); across = Vector((1, 0, 0)) if abs(f.x) < .5 else Vector((0, 0, 1))
        size = across * (w + .012) + Y * (h + .012) + Vector((abs(f.x), 0, abs(f.z))) * (2 * dep + .01)
        c.append(cut_box(Vector(cc), (abs(size.x), abs(size.y), abs(size.z))))
    c.append(cut_box((GR['x'], Y_TOP, GR['z']), (GR['w'] + .012, .05, GR['d'] + .012)))
    return c


for shell_obj in (cap, body):
    cut(shell_obj, head_cutters())
cut(belt, [cut_cyl((0, -.30, 0), (0, .075, 0), .078)])

# Visor module seated in its pocket, with two machined eye windows.
VF = FRONT - .032                        # visor face stands 32 mm proud of the face
visor = face_prism('Visor housing', rrect(vis_w, vis_h, .02, 3, vis_cx, vis_cy), VF, FRONT + .018, S2, hull, .007)
EYES = [(-.2175, .0435), (-.0725, .0435)]
EW, EH = .115, .122
cut(visor, [cut_prism(rrect(EW, EH, .018, 3, x, y), (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), VF - .02, VF + .026) for x, y in EYES])
for x, y in EYES:
    face_prism('Eye window floor', rrect(EW, EH, .018, 3, x, y), VF + .026, VF + .030, M['dark'], hull, .001)
    face_prism('Eye lamp tube', rrect(.032, .088, .0159, 4, x, y), VF + .016, VF + .027, AM, hull, .002)
    for sx in (-1, 1):
        face_prism('Eye lamp reflector', rrect(.024, .10, .006, 2, x + sx * .036, y), VF + .02, VF + .027, ST, hull, .002)
for x in (VIS['x0'] + .016, VIS['x1'] - .016):
    for y in (VIS['y0'] + .014, VIS['y1'] - .014):
        pbolt((x, y, VF), (0, 0, -1), hull, r=.0075)

# Dark corner guards on the four vertical plan chamfers (bolted top and bottom).
C = .075
for sx in (-1, 1):
    for sz in (-1, 1):
        a = Vector((sx * (HW / 2 - C), 0, HZ + sz * HD / 2)); b = Vector((sx * HW / 2, 0, HZ + sz * (HD / 2 - C)))
        n = Vector((sx, 0, sz)).normalized(); tan = (b - a).normalized()
        y0, y1 = Y_LOW + .012, Y_HIGH - .012
        if sx < 0 and sz > 0:
            y1 = -.012                    # the gun pedestal owns the upper rear-left corner
        m = (a + b) / 2 + Vector((0, (y0 + y1) / 2, 0)) + n * .004
        oriented('Corner guard', m, ((b - a).length - .012, y1 - y0, .014), Matrix((tan, Y, n)).transposed(), S2, hull, .004)
        for yy in (y0 + .025, y1 - .025):
            pbolt(Vector((m.x, yy, m.z)) + n * .007, n, hull, r=.007)

# Dark neck flange under the head carrying the upper spring seat.
lathe('Neck flange', (0, Y_BOT + .006, 0), (0, -1, 0),
      [(0, .080), (0, .255), (.010, .255), (.016, .245), (.020, .215), (.020, .080)], S2, hull, 40)
for k in range(8):
    a = k * math.tau / 8 + math.pi / 8
    pbolt((math.cos(a) * .232, Y_BOT - .0135, math.sin(a) * .232), (0, -1, 0), hull, r=.0065)

# Rear service plate: flush and bolted beside the rear louvre.
face_prism('Rear service plate', rrect(.23, .12, .014, 3, -.165, .04), HZ + HD / 2 - .003, HZ + HD / 2 + .005, S2, hull, .003)
for x in (-.265, -.065):
    for y in (-.005, .085):
        pbolt((x, y, HZ + HD / 2 + .005), (0, 0, 1), hull, r=.0065)

# Vent internals.
for (c, w, h, dep, slats, f) in VENTS:
    vent('Louvre', c, w, h, dep, slats, hull, face=f)

grille('Roof grille', (GR['x'], Y_TOP, GR['z']), (1, 0, 0), (0, 0, 1), (0, 1, 0), GR['w'], GR['d'], .026, 7, hull)

# Roof hatch: thin flush plate with a hinge and seated fasteners.
hatch = outline(.28, .24, .03, .02, -.10)
kit.prism('Roof hatch', hatch, Y_TOP - .002, Y_TOP + .010, S2, hull, .003)
cylinder('Hatch hinge barrel', (-.09, Y_TOP + .012, .028), (.13, Y_TOP + .012, .028), .012, ST, hull, 16, .002)
for x in (-.08, .12):
    box('Hatch hinge leaf', (x, Y_TOP + .007, .015), (.05, .006, .03), S2, hull, .002)
for x in (-.095, .135):
    for z in (-.195, -.005):
        pbolt((x, Y_TOP + .010, z), (0, 1, 0), hull, r=.0075)
cylinder('Hatch grab rail', (-.03, Y_TOP + .03, -.19), (.07, Y_TOP + .03, -.19), .007, ST, hull, 12, 0)
for x in (-.03, .07):
    cylinder('Hatch grab rail foot', (x, Y_TOP + .008, -.19), (x, Y_TOP + .03, -.19), .007, ST, hull, 12, 0)

# Antennas at the rear right: lathed bases seated on the roof.
for (x, z, h) in ((.25, .23, .44), (.16, .27, .28)):
    turned('Antenna base', (x, Y_TOP - .004, z), (0, 1, 0), [(0, .03), (.012, .03), (.02, .024), (.035, .016), (.05, .012)], S2, hull, 24)
    cylinder('Antenna mast', (x, Y_TOP + .05, z), (x, Y_TOP + h, z), .0055, ST, hull, 10, 0)
    turned('Antenna tip', (x, Y_TOP + h, z), (0, 1, 0), [(0, .009), (.006, .010), (.012, .006), (.014, 0.0)], OX, hull, 12)
    for k in range(3):
        cylinder('Antenna collar', (x, Y_TOP + .09 + k * h * .25, z), (x, Y_TOP + .1 + k * h * .25, z), .009, S2, hull, 12, .001)

# Stencil on the numbered panel of the face.
stencil_text('03', (.195, .045, FRONT - .0013), 'front', .15, hull)
for x in (.08, .31):
    for y in (-.022, .105):
        pbolt((x, y, FRONT), (0, 0, -1), hull, r=.0075)
# Lower face: two fasteners either side of the belt seam line.
for x in (-.28, .28):
    pbolt((x, -.13, FRONT), (0, 0, -1), hull, r=.0085)

# ---- Chin: a jutting folded jaw carrying the grille and the lamp slit.
chin_prof = [(-.20, -.185), (FRONT - .02, -.185), (FRONT - .045, -.21), (FRONT - .045, -.31), (FRONT - .025, -.332), (-.20, -.332)]
chin = nk.section('Chin jaw', chin_prof, -.21, .21, P, hull, .006)
CZ = FRONT - .045
cut(chin, [cut_box((0, -.238, CZ), (.30 + .012, .045 + .012, .07)),
           cut_prism(rrect(.19, .024, .011, 3, 0, -.290), (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), CZ - .02, CZ + .016)])
grille('Chin grille', (0, -.238, CZ), (1, 0, 0), (0, 1, 0), (0, 0, -1), .30, .045, .028, 11, hull)
face_prism('Chin lamp floor', rrect(.19, .024, .011, 3, 0, -.290), CZ + .012, CZ + .016, DK, hull, .001)
face_prism('Chin lamp slit', rrect(.17, .012, .0059, 3, 0, -.290), CZ + .004, CZ + .012, AM, hull, .002)
for x in (-.18, .18):
    pbolt((x, -.290, CZ), (0, 0, -1), hull, r=.008)

# ---- Gun pedestal welded onto the upper-left shoulder; the trunnion plugs in.
px, py, pz = GUN_PIVOT
ped = kit.prism('Gun trunnion pedestal', rounded(.12, .22, .03, 3, -.35, pz), .0, py + .10, P, hull, .008,
                rounded(.10, .18, .025, 3, -.355, pz))
turned('Trunnion bearing boss', (-.405, py, pz), (-1, 0, 0), [(0, .082), (.002, .082), (.004, .074), (.004, .062)], ST, hull, 32)
for k in range(6):
    a = k * math.tau / 6 + math.pi / 6
    pbolt((-.409, py + math.sin(a) * .07, pz + math.cos(a) * .07), (-1, 0, 0), hull, r=.0065, low=True)

# ---- Gun (shared minigun frame; receiver in the head enamel).
frame_node, mount, rotor = minigun(GUN_PIVOT, 3, .036, root, S2, barrel_r=.02)
# Yellow armour cheek on the receiver's outer face ties the gun to the head
# livery (the concept's cannon root); it follows the receiver side profile.
RX = px - .09
cheek = [(pz + .15, py - .065), (pz + .15, py + .06), (pz + .05, py + .095), (pz - .27, py + .095), (pz - .31, py + .05), (pz - .31, py - .06), (pz - .27, py - .08), (pz + .10, py - .08)]
nk.section('Receiver armour cheek', cheek, RX - .014, RX + .002, P, mount, .005)
for dz, dy in ((.11, .03), (.11, -.045), (-.24, .06), (-.24, -.045)):
    pbolt((RX - .014, py + dy, pz + dz), (-1, 0, 0), mount, r=.0065)
box('Receiver data plate', (RX - .0155, py - .005, pz - .10), (.003, .05, .13), OX, mount, .001)

# ---- Shoulder arms and lamp pods. The left arm sits aft/low of the gun sweep.
ARMS = {1: dict(sh=(.40, -.075, .10), pod=(.785, -.13, .03)),
        -1: dict(sh=(-.40, -.125, .165), pod=(-.80, -.285, .07))}
for s, arm in ARMS.items():
    sx, sy, sz = arm['sh']; cx, cy, cz = arm['pod']
    # Mount plate welded to the head side, drum bearing and forged link.
    extrude('Shoulder mount plate', rrect(.15, .14, .02, 3, sz, sy), sx - s * .004, sx + s * .012, (0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0), S2, hull, .004)
    for dz in (-.055, .055):
        for dy in (-.05, .05):
            pbolt((sx + s * .012, sy + dy, sz + dz), (s, 0, 0), hull, r=.0065)
    drum_end = sx + s * .065
    turned('Shoulder drum', (sx + s * .012, sy, sz), (s, 0, 0),
           [(0, .058), (.008, .058), (.012, .052), (.046, .052), (.050, .056), (.053, .056), (.053, .03)], S2, hull, 32)
    ring('Shoulder steel collar', (sx + s * .03, sy, sz), (1, 0, 0), .055, .045, .012, ST, hull, 32)
    a = Vector((drum_end, sy, sz)); podin = Vector((cx - s * .07, cy + .02, cz))
    link('Shoulder forged link', a, .044, podin, .038, .07, S2, hull, .006)
    # Hydraulic actuator under the link: barrel on the head, rod into the pod.
    e0 = Vector((sx + s * .012, sy - .075, sz)); e1 = Vector((cx - s * .075, cy - .075, cz))
    mid = e0.lerp(e1, .55)
    cylinder('Arm actuator barrel', e0.lerp(e1, .12), mid, .019, S2, hull, 16, .002)
    cylinder('Arm actuator rod', mid, e1, .010, ST, hull, 12, 0)
    for e in (e0, e1):
        turned('Actuator eye', e + Vector((0, 0, -.018)), (0, 0, 1), [(0, .018), (.036, .018)], OX, hull, 16)
    # Pod: chamfered loft with a machined lamp window and an access plate.
    W, H, D = .15, .235, .25
    pod = loft('Sensor pod', [(cy - H / 2, outline(W - .03, D - .03, .03, cx, cz)), (cy - H / 2 + .02, outline(W, D, .045, cx, cz)),
                             (cy + H / 2 - .025, outline(W, D, .045, cx, cz)), (cy + H / 2, outline(W - .035, D - .04, .03, cx, cz))], P, hull, .006)
    pf = cz - D / 2
    cut(pod, [cut_prism(rrect(.085, .15, .014, 3, cx, cy - .005), (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), pf - .02, pf + .016),
              cut_box((cx + s * W / 2, cy + .045, cz + .02), (.014, .005, D - .07))])
    bezel = face_prism('Pod lamp bezel', rrect(.085, .15, .014, 3, cx, cy - .005), pf - .004, pf + .016, S2, hull, .004)
    cut(bezel, [cut_prism(rrect(.036, .11, .0179, 4, cx, cy - .005), (0, 0, 0), (1, 0, 0), (0, 1, 0), (0, 0, 1), pf - .02, pf + .008)])
    face_prism('Pod lamp floor', rrect(.036, .11, .0179, 4, cx, cy - .005), pf + .008, pf + .012, DK, hull, .001)
    face_prism('Pod lamp tube', rrect(.022, .09, .0109, 4, cx, cy - .005), pf + .002, pf + .009, AM, hull, .002)
    for y in (cy - .07, cy + .06):
        pbolt((cx - .03, y, pf - .004), (0, 0, -1), hull, r=.006); pbolt((cx + .03, y, pf - .004), (0, 0, -1), hull, r=.006)
    ox = cx + s * W / 2
    extrude('Pod access plate', rrect(.15, .12, .016, 3, cz + .02, cy - .03), ox - s * .003, ox + s * .006, (0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0), S2, hull, .003)
    for dz in (-.05, .09):
        for dy in (-.075, .015):
            pbolt((ox + s * .006, cy + dy, cz + dz), (s, 0, 0), hull, r=.0065)
    # Small sensor block on the pod roof.
    box('Pod sensor block', (cx, cy + H / 2 + .014, cz + .03), (.06, .028, .07), S2, hull, .004)
    face_prism('Pod sensor eye', rrect(.03, .012, .0059, 2, cx, cy + H / 2 + .016), cz - .008, cz - .004, AM, hull, .001)
    turned('Pod link collar', (cx - s * W / 2, cy + .02, cz), (-s, 0, 0), [(0, .05), (.012, .05), (.016, .044), (.016, .0)], ST, hull, 28)

# ---- Under the head: spring seat and damper body (static half of the telescope).
# Seat face stops 3 mm above the coil's top wire (Coil origin).
seat_top = Y_BOT - .012
seat_depth = seat_top - (COIL_TOP + .003)
lathe('Upper spring seat', (0, seat_top, 0), (0, -1, 0),
      [(0, .080), (0, .192), (seat_depth - .008, .196), (seat_depth, .188), (seat_depth, .080)], ST, hull, 40)
SLEEVE_TOP, GLAND = .06, -.48
lathe('Damper body', (0, SLEEVE_TOP, 0), (0, -1, 0),
      [(0, .044), (0, .064), (SLEEVE_TOP - GLAND - .045, .064), (SLEEVE_TOP - GLAND - .04, .071),
       (SLEEVE_TOP - GLAND - .006, .071), (SLEEVE_TOP - GLAND, .064), (SLEEVE_TOP - GLAND, .044)], S2, hull, 32)
lathe('Damper gland nut', (0, GLAND + .04, 0), (0, -1, 0), [(0, .037), (0, .074), (.028, .074), (.034, .068), (.034, .037)], ST, hull, 6)
ring('Damper wiper', (0, GLAND - .002, 0), (0, 1, 0), .046, .0345, .006, RB, hull, 32)

# ---- Coil: helical spring only (runtime scales it along Y).
coil_node = part('Coil', (0, COIL_TOP, 0), root)
spring_coil('Coil spring', (0, COIL_TOP, 0), COIL_REST, .148, .029, 5.4, SP, coil_node)

# ---- Hub: damper rod, hub casting, spring seat and the rigid tripod.
hub_node = part('Hub', (0, HUB_REST, 0), root)
HY = HUB_REST
LEGS = [Vector((f[0], 0, f[1])) / SCALE for f in BOT['footholds']]
angles = [math.atan2(f.z, f.x) for f in LEGS]
def lobe_radius(t):
    d = min(abs((t - a + math.pi) % math.tau - math.pi) for a in angles)
    return .16 + .07 * max(0.0, math.cos(min(d * 2.2, math.pi / 2))) ** 2
hub_plan = [(math.cos(t) * lobe_radius(t), math.sin(t) * lobe_radius(t)) for t in (i * math.tau / 48 for i in range(48))]
hub_top = [(x * .93, z * .93) for x, z in hub_plan]
kit.prism('Hub casting', hub_plan, HY - .075, HY + .035, P, hub_node, .008, hub_top)
kit.prism('Hub casting lower', [(x * .82, z * .82) for x, z in hub_plan], HY - .09, HY - .07, S2, hub_node, .004)
turned('Hub belly dome', (0, HY - .088, 0), (0, -1, 0), [(0, .12), (.012, .115), (.028, .085), (.038, .04), (.040, .0)], OX, hub_node, 32)
# Seat face at hub_y + SEAT - 2 mm, where the coil's bottom wire lands; a
# centring spigot rises inside the coil and carries the rod bump stop.
s0 = HY + .031; face = HY + SEAT - .002 - s0; spig = HY + .08 - s0
lathe('Lower spring seat', (0, s0, 0), (0, 1, 0),
      [(0, .04), (0, .192), (.008, .192), (.012, .188), (face, .184), (face, .118), (face + .004, .110), (spig - .002, .105), (spig, .04)], ST, hub_node, 40)

turned('Rod bump stop', (0, HY + .08, 0), (0, 1, 0), [(0, .055), (.018, .055), (.026, .045), (.028, .036)], RB, hub_node, 28)
ROD_TOP = HY + .63
rod_len = ROD_TOP - (HY + .08)
turned('Damper rod', (0, HY + .08, 0), (0, 1, 0), [(0, .032), (rod_len - .006, .032), (rod_len, .026), (rod_len, .0)], ST, hub_node, 28)

GROUND = -RIDE
for f in LEGS:
    d = Vector((f.x, 0, f.z)).normalized(); t = Vector((d.z, 0, -d.x))
    def P3(r, y, w=0.0): return d * r + Vector((0, y, 0)) + t * w
    hip, knee, ankle = (.245, HY - .03), (.375, HY + .055), (.50, GROUND + .115)
    # Clevis cheeks cast into the hub lobe.
    for s in (-1, 1):
        extrude('Hip clevis cheek', capsule((.17, HY - .035), .05, hip, .045, 6), s * .047, s * .067, (0, 0, 0), d, Y, t, S2, hub_node, .004)
    phub('Tripod hip', P3(*hip), t, .036, .094, hub_node)
    # Thigh: tapered forged beam, pinned at the hip and knee.
    extrude('Tripod thigh', capsule(hip, .043, knee, .05, 8), -.045, .045, (0, 0, 0), d, Y, t, P, hub_node, .006)
    for w in (-.045, .045):
        pbolt(P3((hip[0] + knee[0]) / 2, (hip[1] + knee[1]) / 2 + .005, w), t * (1 if w > 0 else -1), hub_node, r=.0065)
    phub('Tripod knee', P3(*knee), t, .054, .11, hub_node)
    # Shin: yellow upper leg with a dark ankle yoke.
    extrude('Tripod shin', capsule(knee, .048, ankle, .036, 8), -.038, .038, (0, 0, 0), d, Y, t, P, hub_node, .006)
    shin_dir = (Vector(ankle) - Vector(knee)).normalized()
    ank_top = Vector(ankle) - shin_dir * .10
    for s in (-1, 1):
        extrude('Ankle yoke cheek', capsule(tuple(ank_top), .036, ankle, .034, 6), s * .036, s * .052, (0, 0, 0), d, Y, t, S2, hub_node, .003)
    phub('Tripod ankle', P3(*ankle), t, .030, .072, hub_node)
    # Slate shoe with a rubber sole and cheeks rising to the ankle pin.
    fx, fz = f.x, f.z
    def shoe(w, l, r, s=1.0):
        return [(fx + d.x * a + t.x * b, fz + d.z * a + t.z * b) for a, b in rounded(l * s, w * s, r * s, 3)]
    loft('Foot shoe', [(GROUND + .014, shoe(.17, .21, .03)), (GROUND + .05, shoe(.17, .21, .03)),
                       (GROUND + .072, shoe(.13, .16, .025))], S2, hub_node, .006)
    kit.prism('Foot rubber sole', shoe(.165, .205, .028), GROUND, GROUND + .016, RB, hub_node, .004)
    for s in (-1, 1):
        extrude('Shoe ankle cheek', [(.44, GROUND + .06), (.56, GROUND + .06), (.535, GROUND + .10), (ankle[0] + .02, ankle[1] + .03), (ankle[0] - .02, ankle[1] + .03), (.465, GROUND + .10)],
                s * .037, s * .053, (0, 0, 0), d, Y, t, S2, hub_node, .004)
    for a, b in ((-.066, -.034), (-.066, .034), (.066, -.034), (.066, .034)):
        pbolt(P3(.50 + a, GROUND + .072, b), (0, 1, 0), hub_node, r=.0065)
    # Brace strut from the hub belly to the shin: a slim ram with eyes.
    e0 = P3(.17, HY - .08); e1 = P3(.445, GROUND + .21)
    m = e0.lerp(e1, .55)
    cylinder('Brace strut barrel', e0, m, .016, OX, hub_node, 14, .002)
    cylinder('Brace strut rod', m, e1, .009, ST, hub_node, 12, 0)
    for e in (e0, e1):
        cylinder('Brace strut eye', e - t * .014, e + t * .014, .016, S2, hub_node, 16, .002)


# ------------------------------------------------------------------ complete
def coil_len(hub_y):
    return COIL_TOP - (hub_y + SEAT)

_clearance = nk.clearance
def clearance_at_rest(root_, moving, poses):
    # Pose the Coil at its rest length before the audit captures rest transforms;
    # the GLB keeps this scale (the runtime replaces the whole transform).
    coil_node.scale = (1, 1, COIL_REST); bpy.context.view_layer.update()
    return _clearance(root_, moving, poses)
nk.clearance = clearance_at_rest

def pose_hub(t):
    y = HUB_REST + STROKE[0] + (STROKE[1] - STROKE[0]) * t
    hub_node.location = gv((0, y, 0)); coil_node.scale = (1, 1, coil_len(y))

def pose_gun(t):
    mount.rotation_euler.x = math.radians(-35 + 55 * t)

nk.complete(root, 'pogo_03', 'Nimble03', [coil_node, hub_node, mount], face_wear=FACE_WEAR,
            poses={'hub_stroke': pose_hub, 'gun_pitch': pose_gun})
