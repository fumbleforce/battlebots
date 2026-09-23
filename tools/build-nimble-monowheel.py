"""HELLWHEEL • 07 monowheel (#61), rebuilt at Atlas MX fidelity.

blender --background --python tools/build-nimble-monowheel.py [-- --quick] [--no-bake] [--no-render]

Construction brief (source metres = game metres / 3; hull frame X right, Y up,
-Z forward; origin = centre of the 0.9 x 0.5 x 1.0 collision box, 0.7 above
the ground). Method: docs/art/STYLIZED_INDUSTRIAL_ASSETS.md.

Fixed constraints (data/nimble_bots.json monowheel_07, data/mvp_parts.json):
- Wheel: lug tips at radius .45, tread width .30, centre (0, -.22, 0); it
  touches the ground at ride height. Node 'Wheel' spins about local X, so
  everything on it is lathed or evenly patterned: lugged carcass, rim barrel
  with drop centre, beadlocks, two six-spoke spiders with real windows onto a
  finned rotor drum, bolted hub centres around a static axle.
- Gun: kit.minigun at data gun_pivot / 3 = (-.32, .30, .30), four barrels,
  muzzle 1.3 ahead of the pivot. Its trunnion runs in a bolted bearing seat on
  the cooling pack's left face. The gun sweeps pitch -35..+20 degrees through
  X < -.23, so every left-side hull part stays inboard of X = -.225.
- Moving assemblies Wheel and GunMount; static axle hardware belongs to Hull.

Primary masses: (1) the lugged tyre, (2) a folded U-channel crown fender
(backing arc over the tyre, cheeks folded down on both sides) carrying (3) the
red head in front and (4) the dark cooling pack behind, (5) two side fork
spiders (front and rear legs into the fender cheeks, lower hydraulic struts
onto the sidewall fender rings) meeting at finned static hub housings.
Medium: segmented red / hazard armour on the sidewall fender rings, hazard
fork plate, head armour (pierced optic plate, sensor pod, "07" cheek, roof
cap and hatch), the right-shoulder four-tube rocket pod on a slewing arm,
flame warning plate on brackets, damper, antenna, rear louvre shroud.
Small: seated button fasteners with hex sockets, hex lug nuts, hinge/clevis
eyes, hoses. Enamel is dielectric oxide red / charcoal / hazard yellow from
the concept; bare metal is high metallic; tyre rubber is matte.

Every armour panel sits over a backing (fender channel, ring band, head core,
cooling pack) with narrow seams. Static parts clear the spinning tyre by
.028 under the fender (inner radius .478 over lug tips .45); ring bands start
at X .160 against wheel hardware at X <= .162 but r <= .32 < .335. The only
closer gaps are coaxial bearings: rotor drum around the static axle (5 mm)
and the gun trunnion dome inside its seat (6 mm). The kit's minigun feed
chute is moved outboard for this left mount (see gun_dress).
--diag (development) prints per-part triangles, per-object contacts and gaps.
Review views: kit hero/rear/side/top/closeup against the concept.
"""
import bpy, math, sys, json
from pathlib import Path
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nimble_model_kit as nk
from nimble_model_kit import setup, section, oriented, beam, hub, lens, vent, stencil_text, coil, rounded, outline, minigun, complete, src, DATA, PARTS, SCALE, M
import atlas_model_kit as ak
from atlas_model_kit import part, mesh, prism, box, cylinder, ring, turned, square_bore_face, tube

CHASSIS = 'monowheel_07'
PREFIX = 'Nimble07'
BOT = DATA[CHASSIS]
WR = BOT['wheel']['radius'] / SCALE          # lug tip radius .45
WW = BOT['wheel']['width'] / SCALE           # tread width .30
WY = BOT['wheel']['centre_y'] / SCALE        # wheel centre height -.22
PIVOT = src(BOT['gun_pivot'])                # (-.32, .30, .30)

# Palette from the concept: weathered oxide-red enamel, charcoal frame enamel,
# ochre hazard yellow with black bands, dark worn steel, rust, matte rubber.
PALETTE = {
    'primary': ((.54, .15, .09), .08, .62),
    'secondary': ((.165, .158, .150), .08, .60),
    'steel': ((.56, .55, .53), .92, .36),
    'oxidized': ((.36, .25, .17), .78, .60),
    'dark': ((.028, .026, .024), .40, .55),
    'rubber': ((.072, .067, .063), .0, .86),
    'gun': ((.23, .22, .21), .85, .48),
    'hazard': ((.82, .57, .10), .08, .58),
    'stencil': ((.84, .80, .72), .05, .55),
    'spring': ((.50, .46, .40), .88, .40),
    'lenses': {'orange': ((1.0, .34, .03), 2.4), 'blue': ((.20, .45, 1.0), 2.2)},
}
# Stripes along a world diagonal read diagonally on side, front and top faces.
STRIPES = {'width': .075, 'colour': (.035, .033, .030), 'axis': (.577, .577, .577)}

# Tyre section.
T_W = .29            # carcass width (lugs stay inside |x| .144)
R_TIP = WR
R_CROWN = .41
R_BEAD = .30
SHOULDER = .05
PITCHES = 18
LUG_RISE = R_TIP - R_CROWN + .006
# Fixed side structure (outboard of the tyre).
RING_X = (.160, .172, .184)      # sidewall ring band: backing inner face, armour face, armour outer
RING_R = (.335, .44)
MEMBER_X = (.182, .214)          # fork legs and stays
HOOD_IN, HOOD_OUT = .478, .515   # crown fender channel radii
CHEEK_X = (.190, .205)


# ------------------------------------------------------------------ local helpers
def arc_pt(r, phi, x=0.0):
    """Point at radius r and angle phi (degrees, 0 = forward, 90 = top) about the axle."""
    a = math.radians(phi)
    return Vector((x, WY + r * math.sin(a), -r * math.cos(a)))


def radial(phi):
    a = math.radians(phi)
    return Vector((0, math.sin(a), -math.cos(a)))


def tangent(phi):
    a = math.radians(phi)
    return Vector((0, math.cos(a), math.sin(a)))


def radial_frame(phi):
    return Matrix((Vector((1, 0, 0)), radial(phi), tangent(phi))).transposed()


def arc_sweep(name, sec, phi0, phi1, mat, group, bevel=.003, step=4.0):
    """Closed (x, r) cross-section swept about the axle from phi0 to phi1: folded fenders, ring bands."""
    n = max(2, math.ceil(abs(phi1 - phi0) / step)); m = len(sec)
    verts = [tuple(arc_pt(r, phi0 + (phi1 - phi0) * k / n, x)) for k in range(n + 1) for x, r in sec]
    faces = [tuple(reversed(range(m))), tuple(range(n * m, n * m + m))]
    faces += [(k * m + i, k * m + (i + 1) % m, (k + 1) * m + (i + 1) % m, (k + 1) * m + i) for k in range(n) for i in range(m)]
    return mesh(name, verts, faces, mat, group, bevel)


def plate(name, pts, normal, depth, mat, group, b=.003):
    """Planar outline extruded symmetrically along its normal."""
    vec = Vector(normal).normalized() * depth * .5; n = len(pts)
    verts = [tuple(Vector(p) + vec * s) for s in (-1, 1) for p in pts]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, b)


def cut_rect(u0, u1, v0, v1, c):
    return [(u0 + c, v0), (u1 - c, v0), (u1, v0 + c), (u1, v1 - c), (u1 - c, v1), (u0 + c, v1), (u0, v1 - c), (u0, v0 + c)]


def on_x(x, pts):
    """(z, y) outline onto the plane X = x."""
    return [(x, y, z) for z, y in pts]


def on_z(z, pts):
    """(x, y) outline onto the plane Z = z."""
    return [(x, y, z) for x, y in pts]


def radial_outline(phi, r0, r1, hw, c, x):
    """Chamfered strip along a radius (fork members and their plates)."""
    return [tuple(arc_pt(r, phi, x) + tangent(phi) * o) for r, o in
            ((r0, -hw + c), (r0 + c, -hw), (r1 - c, -hw), (r1, -hw + c), (r1, hw - c), (r1 - c, hw), (r0 + c, hw), (r0, hw - c))]


def y_arc(z, r):
    return WY + math.sqrt(max(0.0, r * r - z * z))


def bolt(at, axis, group, r=.008, n=12, washer=True):
    """Seated button fastener: washer against the plate, domed crown, hex socket with a dark floor."""
    p = Vector(at); d = Vector(axis).normalized()
    if washer:
        cylinder('Fastener seated washer', p - d * .003, p + d * .001, r * 1.34, M['oxidized'], group, n, 0)
    # The underside is hidden against the washer/plate and the socket is open to its dark floor.
    turned('Rounded machined button fastener', p, d, [(0, r), (.004, r), (.010, r * .70), (.010, r * .36), (.005, r * .36)],
           M['steel'], group, n, hex_socket=True, open_end=True)
    t, bit = ak._frame(d)[1:]
    floor = [tuple(p + d * .0052 + (t * math.cos(a) + bit * math.sin(a)) * r * .37) for a in (i * math.tau / 6 for i in range(6))]
    mesh('Recessed fastener socket floor', floor, [tuple(range(6))], M['dark'], group)


def hex_nut(at, axis, group, r=.0105, height=.012):
    """Flanged hex lug nut with a chamfered crown and threaded stud end."""
    p = Vector(at); d, t, bit = ak._frame(axis)
    verts = []
    for dep, k in ((.003, 1.0), (height - .002, 1.0), (height, .82)):
        for i in range(6):
            a = i * math.tau / 6 + math.pi / 6
            verts.append(tuple(p + d * dep + (t * math.cos(a) + bit * math.sin(a)) * r * k))
    faces = [tuple(reversed(range(6))), tuple(range(12, 18))]
    for j in range(2):
        for i in range(6): faces.append((j * 6 + i, j * 6 + (i + 1) % 6, (j + 1) * 6 + (i + 1) % 6, (j + 1) * 6 + i))
    mesh('Hex wheel lug nut', verts, faces, M['steel'], group, .001)
    turned('Threaded stud end', p + d * height, d, [(0, r * .42), (.004, r * .40), (.0065, 0)], M['oxidized'], group, 6)


def spring(name, a, b, radius, wire, turns, mat, group, n=6, steps=12):
    """Helical compression spring between two points (any axis), closed ground ends."""
    a = Vector(a); b = Vector(b); axis = (b - a); length = axis.length; d, t, bit = ak._frame(axis)
    verts = []; faces = []; total = int(turns * steps)
    for i in range(total + 1):
        s = i / total; ang = s * turns * math.tau
        pitch_s = min(1.0, max(0.0, (s - .06) / .88))
        c = a + d * pitch_s * length + (t * math.cos(ang) + bit * math.sin(ang)) * radius
        tan = (d * length / (turns * math.tau * radius) + (-t * math.sin(ang) + bit * math.cos(ang))).normalized()
        nrm = (t * math.cos(ang) + bit * math.sin(ang)); bn = tan.cross(nrm).normalized(); nrm = bn.cross(tan)
        for k in range(n):
            q = k * math.tau / n
            verts.append(tuple(c + (nrm * math.cos(q) + bn * math.sin(q)) * wire))
    for i in range(total):
        for k in range(n):
            a0 = i * n + k; a1 = i * n + (k + 1) % n
            faces.append((a0, a1, a1 + n, a0 + n))
    faces += [tuple(reversed(range(n))), tuple(range(total * n, total * n + n))]
    obj = mesh(name, verts, faces, mat, group)
    for f in obj.data.polygons: f.use_smooth = True
    return obj


# ------------------------------------------------------------------ wheel (moving)
def ax(a):
    """Axial position across the carcass: a=0 at +X sidewall, a=T_W at -X."""
    return T_W * .5 - a


def carcass_radius(a):
    edge = max(0.0, min(a, T_W - a))
    if edge >= SHOULDER: return R_CROWN
    k = edge / SHOULDER
    return R_BEAD + .03 + (R_CROWN - R_BEAD - .03) * math.sin(k * math.pi / 2) ** .55


def lug(group, s0, s1, a0, a1, skew, name, na=3, ns=2):
    """Tread block following the carcass between arc positions s (rad) and axial a; chevron skew."""
    top, bot = [], []
    for j in range(na + 1):
        a = a0 + (a1 - a0) * j / na
        shift = skew * (a - a0) / max(1e-6, (a1 - a0))
        base = carcass_radius(min(max(a, 0.0), T_W)) - .006
        edge = max(0.0, min(a, T_W - a))
        tip = min(R_TIP - max(0.0, .045 - edge) * .55, base + LUG_RISE)
        for i in range(ns + 1):
            s = s0 + (s1 - s0) * i / ns + shift
            mid = (s0 + s1) * .5 + shift; s_top = mid + (s - mid) * .90
            top.append((ax(a), WY + tip * math.cos(s_top), tip * math.sin(s_top)))
            bot.append((ax(a), WY + base * math.cos(s), base * math.sin(s)))
    cols = ns + 1; n = len(top); verts = top + bot; faces = []
    for j in range(na):
        for i in range(ns):
            q = (j * cols + i, j * cols + i + 1, (j + 1) * cols + i + 1, (j + 1) * cols + i)
            faces.append(q); faces.append(tuple(reversed([k + n for k in q])))
    for j in range(na):
        faces.append((j * cols, (j + 1) * cols, (j + 1) * cols + n, j * cols + n))
        faces.append((j * cols + ns + n, (j + 1) * cols + ns + n, (j + 1) * cols + ns, j * cols + ns))
    last = na * cols
    for i in range(ns):
        faces.append((i + 1, i, i + n, i + 1 + n))
        faces.append((last + i, last + i + 1, last + i + 1 + n, last + i + n))
    return mesh(name, verts, faces, M['rubber'], group, .0035)


def sector(r0, r1, a0, a1, steps):
    pts = [(r1 * math.cos(a0 + (a1 - a0) * i / steps), r1 * math.sin(a0 + (a1 - a0) * i / steps)) for i in range(steps + 1)]
    pts += [(r0 * math.cos(a1 - (a1 - a0) * i / steps), r0 * math.sin(a1 - (a1 - a0) * i / steps)) for i in range(steps + 1)]
    return pts


def build_wheel(wheel):
    c = Vector((0, WY, 0))
    # Denser loops through the shoulders, where the section curves; the flat crown needs few.
    stations = [0, .004, .010, .018, .028, .040, .052, .09, .145, .20, .238, .25, .262, .272, .28, .286, .29]
    profile = [(ax(a), carcass_radius(a)) for a in stations]
    turned('Lugged tyre carcass', c, (1, 0, 0), [(ax(0), R_BEAD - .004)] + profile + [(ax(T_W), R_BEAD - .004)], M['rubber'], wheel, 64, open_end=True)
    for s in (-1, 1):
        ring('Moulded bead protector rib', c + Vector((s * (T_W * .5 - .004), 0, 0)), (1, 0, 0), R_BEAD + .044, R_BEAD + .036, .008, M['rubber'], wheel, 40)
    pitch = math.tau / PITCHES
    for k in range(PITCHES):
        s = k * pitch
        lug(wheel, s, s + pitch * .44, .006, T_W * .5 - .007, pitch * .22, 'Tread lug block')
        lug(wheel, s + pitch * .5, s + pitch * .94, T_W * .5 + .007, T_W - .006, -pitch * .22, 'Tread lug block')
        lug(wheel, s + pitch * .30, s + pitch * .64, T_W * .5 - .03, T_W * .5 + .03, 0, 'Tread centre tie bar', 1, 1)
    # Steel wheel: rolled flanges, drop-centre barrel, beadlocks on both faces.
    rim = [(.149, .318), (.141, .321), (.133, .297), (.085, .289), (.055, .262), (-.055, .262), (-.085, .289), (-.133, .297),
           (-.141, .321), (-.149, .318), (-.149, .284), (-.06, .250), (.06, .250), (.149, .284)]
    # Bare dark steel rim (as on the concept), painted spiders.
    turned('Rim barrel with drop centre', c, (1, 0, 0), rim + rim[:1], M['gun'], wheel, 56, open_end=True)
    for s in (-1, 1):
        ring('Clamping beadlock ring', c + Vector((s * .1455, 0, 0)), (1, 0, 0), R_BEAD + .034, R_BEAD - .014, .011, M['gun'], wheel, 64)
        for i in range(8):
            a = (i + .5) * math.tau / 8
            bolt(c + Vector((s * .151, math.cos(a) * (R_BEAD + .010), math.sin(a) * (R_BEAD + .010))), (s, 0, 0), wheel, .0072, washer=False)
        # Six-spoke spider: outer mounting ring into the rim, hub disc, forged spokes with real windows.
        x = s * .105
        ring('Spider outer mounting ring', c + Vector((x, 0, 0)), (1, 0, 0), .272, .228, .022, M['secondary'], wheel, 56)
        ring('Spider hub disc', c + Vector((x, 0, 0)), (1, 0, 0), .142, .056, .028, M['secondary'], wheel, 40)
        for k in range(6):
            cang = k * math.tau / 6 + (math.tau / 12 if s > 0 else 0)
            pts = sector(.134, .236, cang - .20, cang + .20, 4)
            verts = [(x + dx, WY + u, v) for dx in (-.013, .013) for u, v in pts]
            n = len(pts)
            faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
            mesh('Forged wheel spoke', verts, faces, M['secondary'], wheel, .004)
        ring('Raised hub centre', c + Vector((s * .117, 0, 0)), (1, 0, 0), .118, .056, .026, M['oxidized'], wheel, 40)
        for i in range(6):
            a = i * math.tau / 6
            hex_nut(c + Vector((s * .130, math.cos(a) * .088, math.sin(a) * .088)), (s, 0, 0), wheel)
        ring('Hub bearing retaining collar', c + Vector((s * .134, 0, 0)), (1, 0, 0), .070, .052, .012, M['steel'], wheel, 32)
    # Finned rotor drum between the spiders, seen through the spoke windows.
    ring('Hub motor rotor drum', c, (1, 0, 0), .188, .050, .17, M['gun'], wheel, 40)
    for x in (-.04, .04):
        ring('Rotor cooling fin', c + Vector((x, 0, 0)), (1, 0, 0), .206, .186, .008, M['oxidized'], wheel, 40)


# ------------------------------------------------------------------ static hull
def build_axle_side(hull, s):
    """Finned static hub housing, fork spider and the sidewall fender ring on one side (s = -1 left, +1 right)."""
    c = Vector((0, WY, 0)); X = Vector((s, 0, 0))
    turned('Static hub motor housing', c + X * .156, X, [(0, .066), (.014, .066), (.016, .092), (.021, .112), (.090, .112), (.094, .104), (.100, .090), (.100, 0)],
           M['secondary'], hull, 40)
    for k in range(1):
        ring('Hub housing cooling fin', c + X * (.234 + .016 * k), (1, 0, 0), .128, .110, .007, M['secondary'], hull, 32)
    turned('Domed hub bearing cap', c + X * .256, X, [(0, .060), (.008, .059), (.018, .049), (.026, .030), (.028, 0)], M['steel'], hull, 28)
    for i in range(4):
        a = (i + .5) * math.tau / 4
        bolt(c + X * .256 + Vector((0, math.cos(a) * .076, math.sin(a) * .076)), X, hull, .0065, washer=False)
    # Fork spider: front and rear legs into the fender cheeks, lower stays onto the ring band.
    xm = s * (MEMBER_X[0] + MEMBER_X[1]) * .5; w = MEMBER_X[1] - MEMBER_X[0]
    for phi, title in ((62, 'front'), (118, 'rear')):
        beam('Fork %s leg' % title, (xm, WY, 0), arc_pt(.470, phi, xm), w, .10, M['secondary'], hull, .004)
    # Lower radial struts: hydraulic barrels from the hub housing to clevises on the ring band.
    xs = s * .199
    for phi in (-30, 210):
        cylinder('Ring strut barrel', arc_pt(.105, phi, xs), arc_pt(.245, phi, xs), .016, M['oxidized'], hull, 14, .002)
        cylinder('Ring strut gland', arc_pt(.240, phi, xs), arc_pt(.252, phi, xs), .019, M['gun'], hull, 14, .001)
        cylinder('Ring strut chromed rod', arc_pt(.25, phi, xs), arc_pt(.335, phi, xs), .0075, M['steel'], hull, 10, 0)
        oriented('Ring strut clevis', arc_pt(.345, phi, s * .192), (.028, .03, .034), radial_frame(phi), M['secondary'], hull, .003)
        cylinder('Ring strut eye pin', arc_pt(.342, phi, s * .176), arc_pt(.342, phi, s * .210), .0065, M['steel'], hull, 10, .001)
    # Leg plates; the left pair is thinner and shorter, inside the minigun's sweep (X > -.225).
    depth = .008 if s > 0 else .006
    face = s * (MEMBER_X[1] + depth / 2)
    for phi, title in ((62, 'front'), (118, 'rear')):
        hazard = (s > 0) == (phi < 90)
        plate('Fork %s leg %s plate' % (title, 'hazard' if hazard else 'armour'), radial_outline(phi, .135, .44 if s > 0 else .40, .046, .014, face), X, depth,
              M['hazard'] if hazard else M['paint'], hull, .002)
        for r in ((.165, .41) if s > 0 else (.165,)):
            bolt(arc_pt(r, phi, s * (MEMBER_X[1] + depth)), X, hull, .0065, washer=s > 0)
    # Sidewall fender ring: backing band with segmented armour, carried by the members and hangers.
    band = [(s * RING_X[0], RING_R[0]), (s * RING_X[1], RING_R[0]), (s * RING_X[1], RING_R[1]), (s * RING_X[0], RING_R[1])]
    armour = [(s * (RING_X[1] - .001), RING_R[0] + .008), (s * RING_X[2], RING_R[0] + .012), (s * RING_X[2], RING_R[1] - .012), (s * (RING_X[1] - .001), RING_R[1] - .006)]
    for p0, p1 in ((72, -50), (108, 230)):
        arc_sweep('Sidewall fender ring backing band', band, p0, p1, M['secondary'], hull, .002, 6.5)
    seam = .35   # degrees each side: about 5 mm assembly seams at the band's mid radius
    segments = ((71, 41, 'paint'), (41, 3, 'hazard'), (3, -49, 'paint'), (109, 139, 'paint'), (139, 177, 'hazard'), (177, 229, 'paint'))
    for p0, p1, key in segments:
        sgn = 1 if p1 > p0 else -1
        arc_sweep('Sidewall fender armour segment', armour, p0 + sgn * seam, p1 - sgn * seam, M[key], hull, .002, 6.5)
        phi = p0 + (p1 - p0) * .15
        if abs(phi - 62) > 7 and abs(phi - 118) > 7:
            bolt(arc_pt(.388, phi, s * RING_X[2]), X, hull, .0065, washer=False)
    for phi in (67, 113):
        oriented('Fender ring hanger bracket', arc_pt(.447, phi, s * .176), (.030, .036, .040), radial_frame(phi), M['secondary'], hull, .003)
    # Static axle through the wheel bore.
    return c


def build_hood(hull):
    """Folded U-channel crown fender over the tyre, with armour skins, hazard lip and bumpers."""
    sec = [(-CHEEK_X[1], .452), (-CHEEK_X[1], HOOD_OUT - .012), (-CHEEK_X[1] + .012, HOOD_OUT), (CHEEK_X[1] - .012, HOOD_OUT), (CHEEK_X[1], HOOD_OUT - .012),
           (CHEEK_X[1], .452), (CHEEK_X[0], .452), (CHEEK_X[0], HOOD_IN), (-CHEEK_X[0], HOOD_IN), (-CHEEK_X[0], .452)]
    arc_sweep('Crown fender folded channel', sec, 29, 151, M['secondary'], hull, .004)
    for s in (-1, 1):
        a, b = sorted((s * .0025, s * .198))
        skin = [(a, HOOD_OUT - .002), (b, HOOD_OUT - .002), (b, HOOD_OUT + .013), (b - .008, HOOD_OUT + .019), (a + .004, HOOD_OUT + .019), (a, HOOD_OUT + .015)]
        if s < 0:
            skin = [(a, HOOD_OUT - .002), (b, HOOD_OUT - .002), (b, HOOD_OUT + .015), (b - .004, HOOD_OUT + .019), (a + .008, HOOD_OUT + .019), (a, HOOD_OUT + .013)]
        arc_sweep('Crown fender leading armour', skin, 36.6, 64, M['paint'], hull, .003, 3)
    edge = [(-.198, HOOD_OUT - .002), (.198, HOOD_OUT - .002), (.198, HOOD_OUT + .013), (.190, HOOD_OUT + .019), (-.190, HOOD_OUT + .019), (-.198, HOOD_OUT + .013)]
    arc_sweep('Crown fender hazard leading edge', edge, 30.2, 36.0, M['hazard'], hull, .002, 2)
    # Painted warning chevrons pointing forward on the right skin (flush, 1 mm proud).
    for phi in (47.5, 53.5):
        o = arc_pt(HOOD_OUT + .0195, phi, .105); u = Vector((1, 0, 0)); v = -tangent(phi)
        pts = [(-.034, -.012), (0, .010), (.034, -.012), (.034, .002), (0, .024), (-.034, .002)]
        plate('Painted warning chevron', [tuple(o + u * a + v * b) for a, b in pts], radial(phi), .0015, M['pod_yellow'], hull, 0)
    for phi in (40, 60):
        for x in (-.165, .165):
            bolt(arc_pt(HOOD_OUT + .019, phi, x), radial(phi), hull, .0075)
    for s in (-1, 1):
        cheek = [(s * CHEEK_X[1] - s * .001, .458), (s * (CHEEK_X[1] + .011), .461), (s * (CHEEK_X[1] + .011), .505), (s * CHEEK_X[1] - s * .001, .508)]
        arc_sweep('Crown fender cheek armour', cheek, 31, 88.7, M['paint'], hull, .002)
        arc_sweep('Crown fender cheek armour', cheek, 89.3, 149, M['paint'], hull, .002)
        for phi in ((38, 98, 140) if s > 0 else (38,)):
            bolt(arc_pt(.483, phi, s * (CHEEK_X[1] + .011)), (s, 0, 0), hull, .0062)
    # Leading and trailing bumpers close the channel ends.
    for p0, p1, phi in ((26.5, 29.4, 26.5), (150.6, 153.5, 153.5)):
        bar = [(-.212, .466), (.212, .466), (.212, .526), (.200, .534), (-.200, .534), (-.212, .526)]
        arc_sweep('Crown fender impact bumper', bar, p0, p1, M['secondary'], hull, .004, 3)
        out = -tangent(phi) if phi < 90 else tangent(phi)
        if phi < 90:
            for x in (-.12, .12):
                bolt(arc_pt(.50, phi, x) + out * .001, out, hull, .0075)


def build_head(hull):
    """Head: charcoal core under red armour; pierced optic plate, sensor pod, lamps, "07" cheek, roof cap."""
    xc, zc = .0175, -.075
    y0, y1 = .335, .59
    prism('Head structural core', rounded(.415, .37, .035, 4, xc, zc), y0, y1, M['secondary'], hull, .004)
    # Neck: charcoal casting seated on the crown fender under the head.
    zs = [-.235 + .34 * i / 8 for i in range(9)]
    prof = [(zs[0], .338)] + [(zs[-1], .338)] + [(z, y_arc(z, HOOD_OUT - .004)) for z in reversed(zs)]
    section('Head neck casting', prof, -.165, .195, M['secondary'], hull, .004)
    for x in (-.09, .12):
        cylinder('Neck front ram barrel', (x, y_arc(-.245, HOOD_OUT) - .01, -.245), (x, .30, -.245), .014, M['oxidized'], hull, 16, .002)
        cylinder('Neck front ram rod', (x, .30, -.245), (x, .338, -.245), .008, M['steel'], hull, 12, .001)
    cylinder('Neck tilt drive housing', (.19, .292, -.06), (.232, .292, -.06), .040, M['secondary'], hull, 24, .003)
    turned('Neck tilt drive cap', (.232, .292, -.06), (1, 0, 0), [(0, .032), (.006, .031), (.012, .022), (.014, 0)], M['steel'], hull, 24)
    # Roof: chamfered red cap overhanging the side armour, a bolted hatch and a sensor dome.
    roof = y1 + .026
    prism('Head roof armour cap', rounded(.44, .40, .05, 4, xc, zc), y1 - .005, roof, M['paint'], hull, .003,
          top=rounded(.38, .34, .03, 4, xc, zc))
    nk.shell('Head roof hatch', .17, .19, .025, roof - .002, roof + .008, M['secondary'], hull, top=(.94, .94), at=(-.05, -.04), bevel=.003)
    for dx in (-.063, .063):
        for dz in (-.072, .072):
            bolt((-.05 + dx, roof + .008, -.04 + dz), (0, 1, 0), hull, .0065)
    turned('Head sensor dome collar', (.12, roof - .002, .04), (0, 1, 0), [(0, .048), (.012, .048), (.016, .042), (.016, 0)], M['gun'], hull, 32)
    turned('Head sensor dome', (.12, roof + .014, .04), (0, 1, 0), [(0, .036), (.012, .034), (.022, .024), (.028, .010), (.029, 0)], M['dark'], hull, 32)
    section('Head brow visor', [(-.262, .552), (-.296, .574), (-.298, .586), (-.262, .596)], -.192, .234, M['paint'], hull, .003)
    # Side armour: the right cheek carries the "07" stencil; the left stays clear of the gun sweep.
    plate('Head right cheek backing frame', on_x(.2265, cut_rect(-.270, .113, .336, .590, .026)), (1, 0, 0), .009, M['secondary'], hull, .002)
    plate('Head right cheek armour', on_x(.2295, cut_rect(-.262, .105, .342, .582, .022)), (1, 0, 0), .015, M['paint'], hull, .003)
    stencil_text('07', (.2375 + .0006, .462, -.078), '+x', .125, hull)
    for z, y in ((-.24, .36), (-.24, .565), (.085, .36), (.085, .565)):
        bolt((.237, y, z), (1, 0, 0), hull, .0065)
    plate('Head left cheek armour', on_x(-.195, cut_rect(-.262, .105, .342, .582, .022)), (-1, 0, 0), .015, M['paint'], hull, .003)
    for z, y in ((-.24, .565), (.085, .565)):
        bolt((-.2025, y, z), (-1, 0, 0), hull, .006, washer=False)
    # Front: optic plate pierced around the main optic (a real bore), sensor pod panel and chin.
    oc = Vector((-.075, .47, -.2625))
    square_bore_face('Head optic frame plate', oc, .117, .112, .097, .015, M['secondary'], hull, 40)
    turned('Main optic armoured housing', (oc.x, oc.y, -.25), (0, 0, -1),
           [(0, .094), (.042, .094), (.050, .088), (.056, .076), (.057, .064), (.052, .058), (.012, .058), (.010, 0)], M['gun'], hull, 40)
    lens('Main optic', (oc.x, oc.y, -.275), (0, 0, -1), .049, M['orange'], hull, pocket=False)
    plate('Head sensor armour panel', on_z(-.2625, cut_rect(.047, .237, .40, .582, .018)), (0, 0, -1), .015, M['paint'], hull, .003)
    box('Head sensor pod', (.130, .49, -.2745), (.080, .165, .016), M['secondary'], hull, .004)
    for y in (.527, .453):
        lens('Status lens', (.130, y, -.286), (0, 0, -1), .021, M['blue'], hull)
    plate('Head chin plate', on_z(-.2625, cut_rect(.047, .237, .342, .397, .012)), (0, 0, -1), .015, M['secondary'], hull, .003)
    for x in (.100, .178):
        lens('Chin lamp', (x, .370, -.276), (0, 0, -1), .016, M['orange'], hull)
    for x, y in ((.215, .565), (.066, .565)):
        bolt((x, y, -.27), (0, 0, -1), hull, .006, washer=False)


def build_cooling_pack(hull):
    """Charcoal cooling pack behind the head: gun trunnion seat, rear louvre shroud, pod arm, antenna."""
    z0, z1, top = .125, .44, .50
    zs = [z0 + (z1 - z0) * i / 8 for i in range(9)]
    prof = [(z0, top - .03), (z0 + .03, top), (z1 - .04, top), (z1, top - .04)] + [(z, y_arc(z, HOOD_OUT - .004)) for z in reversed(zs)]
    section('Cooling pack casting', prof, -.168, .215, M['secondary'], hull, .004)
    nk.shell('Cooling pack roof armour', .40, .30, .03, top - .004, top + .012, M['paint'], hull, top=(.95, .93), at=(.02, .28), bevel=.003)
    for dx, dz in ((-.16, .16), (.16, .16), (-.16, .40)):
        bolt((.02 + dx, top + .012, dz), (0, 1, 0), hull, .0065)
    # Rear louvre shroud: real aperture walls, dark floor and angled slats.
    vent('Cooling pack rear louvre', (.02, .32, z1 + .028), .30, .13, .028, 6, hull, face=(0, 0, 1))
    vent('Cooling pack side louvre', (.215 + .022, .33, .37), .09, .11, .022, 4, hull, face=(1, 0, 0))
    # Gun trunnion bearing seat: a bolted ring around the trunnion collar, on a yoke cheek plate.
    p = PIVOT
    plate('Gun yoke cheek plate', on_x(-.173, cut_rect(p.z - .115, p.z + .115, p.y - .07, p.y + .13, .03)), (-1, 0, 0), .010, M['paint'], hull, .003)
    ring('Gun trunnion bearing seat', (-.1865, p.y, p.z), (1, 0, 0), .090, .062, .018, M['gun'], hull, 40)
    for i in range(4):
        a = i * math.tau / 4 + math.pi / 4
        bolt((-.1955, p.y + math.cos(a) * .076, p.z + math.sin(a) * .076), (-1, 0, 0), hull, .0055, washer=False)
    # Rear lower armour under the louvre, and a lifting handle on the roof.
    plate('Cooling pack rear armour', on_z(z1 + .006, cut_rect(-.15, .19, .07, .24, .025)), (0, 0, 1), .012, M['paint'], hull, .003)
    for x in (-.13, .17):
        bolt((x, .09, z1 + .012), (0, 0, 1), hull, .0065)
    for x in (-.09, .13):
        cylinder('Roof handle welded seat', (x, top + .010, .21), (x, top + .016, .21), .014, M['steel'], hull, 16, .001)
    tube('Roof lifting handle', [(-.09, top + .012, .21), (-.09, top + .05, .21), (.13, top + .05, .21), (.13, top + .012, .21)], .007, M['secondary'], hull)
    # Antenna: spring-mounted segmented mast on the roof armour.
    ab = Vector((.10, top + .012, .40))
    turned('Antenna base', ab, (0, 1, 0), [(0, .026), (.010, .026), (.014, .018), (.030, .016), (.032, .010)], M['gun'], hull, 20)
    spring('Antenna base spring', ab + Vector((0, .032, 0)), ab + Vector((0, .072, 0)), .012, .0028, 4, M['spring'], hull, 5, 9)
    cylinder('Antenna lower mast', ab + Vector((0, .030, 0)), ab + Vector((0, .25, 0)), .0085, M['secondary'], hull, 12, .001)
    cylinder('Antenna upper mast', ab + Vector((0, .25, 0)), ab + Vector((0, .50, 0)), .005, M['gun'], hull, 10, 0)
    turned('Antenna tip', ab + Vector((0, .50, 0)), (0, 1, 0), [(0, .008), (.008, .008), (.012, .004), (.013, 0)], M['dark'], hull, 12)


def build_rocket_pod(hull):
    """Right-shoulder four-tube rocket pod: box casing frame, pierced face plate, lined tubes, slewing arm."""
    cx, cy, cz = .35, .53, .25
    w, h, d = .18, .16, .28
    zf = cz - d / 2
    box('Rocket pod lower plate', (cx, cy - h / 2 + .007, cz), (w, .014, d), M['secondary'], hull, .003)
    box('Rocket pod upper plate', (cx, cy + h / 2 - .007, cz), (w, .014, d), M['secondary'], hull, .003)
    for s in (-1, 1):
        box('Rocket pod side wall', (cx + s * (w / 2 - .007), cy, cz), (.014, h - .026, d), M['secondary'], hull, .002)
        plate('Rocket pod yellow side panel', on_x(cx + s * (w / 2 + .003), cut_rect(zf + .025, zf + d - .025, cy - h / 2 + .018, cy + h / 2 - .018, .018)),
              (s, 0, 0), .006, M['pod_yellow'], hull, .002)
        for z in (zf + .045, zf + d - .045):
            bolt((cx + s * (w / 2 + .006), cy - h / 2 + .03, z), (s, 0, 0), hull, .0055, washer=False)
    stencil_text('R4', (cx + w / 2 + .0066, cy + .012, cz + .02), '+x', .07, hull, M['stencil_black'])
    nk.shell('Rocket pod roof armour', w - .012, d - .03, .02, cy + h / 2 - .002, cy + h / 2 + .010, M['paint'], hull, top=(.94, .95), at=(cx, cz + .005), bevel=.002)
    box('Rocket pod rear bulkhead', (cx, cy, zf + d - .012), (w - .004, h - .004, .024), M['secondary'], hull, .003)
    for i, (dx, dy) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        tc = Vector((cx + dx * .045, cy + dy * .04, zf))
        square_bore_face('Rocket pod pierced face quadrant', tc + Vector((0, 0, .006)), .045, .04, .029, .012, M['secondary'], hull, 16)
        ring('Launch tube liner', tc + Vector((0, 0, .10)), (0, 0, 1), .031, .026, .18, M['gun'], hull, 16)
        ring('Launch tube painted muzzle rim', tc + Vector((0, 0, -.004)), (0, 0, 1), .038, .027, .010, M['paint'], hull, 20)
        turned('Rocket warhead', tc + Vector((0, 0, .12)), (0, 0, -1), [(0, .022), (.012, .022), (.030, .015), (.042, .005), (.044, 0)], M['oxidized'], hull, 12)
        cylinder('Launch tube dark breech', tc + Vector((0, 0, .188)), tc + Vector((0, 0, .19)), .026, M['dark'], hull, 16, 0)
    # Slewing arm from the cooling pack's right face, a turned slewing ring and feed hoses.
    # Shoulder mount: a block welded to the cooling pack, a cantilever deck and a web gusset under it.
    box('Rocket pod shoulder block', (.245, .40, cz), (.07, .09, .15), M['secondary'], hull, .006)
    box('Rocket pod cantilever deck', (.325, cy - h / 2 - .018, cz), (.15, .032, .11), M['secondary'], hull, .005)
    plate('Rocket pod deck web gusset', on_z(cz, [(.26, .356), (.27, .356), (.385, .415), (.26, .415)]), (0, 0, 1), .024, M['secondary'], hull, .003)
    plate('Rocket pod shoulder armour', on_x(.281, cut_rect(cz - .07, cz + .07, .36, .44, .02)), (1, 0, 0), .008, M['paint'], hull, .002)
    turned('Rocket pod slewing ring', (cx, cy - h / 2 - .003, cz), (0, 1, 0), [(0, .052), (.004, .052), (.006, .046), (.006, 0)], M['gun'], hull, 32)
    for i in range(3):
        a = i * math.tau / 3 + .5
        bolt((cx + math.cos(a) * .058, cy - h / 2 - .002, cz + math.sin(a) * .058), (0, 1, 0), hull, .005, washer=False)
    tube('Rocket pod feed hose', [(.41, cy - h / 2 + .01, zf + d - .02), (.40, cy - h / 2 - .05, zf + d + .03), (.30, .40, .43), (.215, .40, .42)], .010, M['rubber'], hull)


def flame_outline(cz, cy, size, x):
    pts = [(0, -.5), (.22, -.45), (.33, -.30), (.35, -.10), (.28, .06), (.31, .24), (.20, .13), (.16, .31), (.08, .50), (.03, .26),
           (-.04, .40), (-.09, .17), (-.19, .31), (-.21, .09), (-.31, -.01), (-.35, -.18), (-.30, -.36), (-.18, -.47)]
    return [(x, cy + v * size, cz + u * size) for u, v in pts]


def build_flame_plate(hull):
    """Flame warning plate on two brackets off the cooling pack and fender cheek."""
    zc, yc = .35, .15
    plate('Warning plate backing frame', on_x(.280, cut_rect(zc - .125, zc + .125, yc - .13, yc + .13, .04)), (1, 0, 0), .012, M['secondary'], hull, .003)
    plate('Warning plate red face', on_x(.287, cut_rect(zc - .112, zc + .112, yc - .117, yc + .117, .034)), (1, 0, 0), .008, M['paint'], hull, .002)
    plate('Flame emblem', flame_outline(zc, yc + .005, .19, .2915), (1, 0, 0), .002, M['stencil'], hull, 0)
    plate('Flame emblem core', flame_outline(zc + .004, yc - .03, .085, .2925), (1, 0, 0), .002, M['paint'], hull, 0)
    for z, y in ((zc - .09, yc + .09), (zc + .09, yc + .09), (zc - .09, yc - .09), (zc + .09, yc - .09)):
        bolt((.291, y, z), (1, 0, 0), hull, .0065)
    for y, z in ((.24, .30), (.075, .41)):
        box('Warning plate standoff bracket', (.245, y, z), (.07, .026, .036), M['secondary'], hull, .004)
        cylinder('Standoff bracket pin', (.212, y, z), (.276, y, z), .006, M['steel'], hull, 12, .001)


def build_damper(hull):
    """Right-side coil-over damper from a hub-drum lug to a clevis on the fender cheek."""
    x = .252
    lo = Vector((x, WY + .025, .13)); hi = Vector((x, .152, .268))
    beam('Damper lower lug', (x, WY, .05), lo, .022, .03, M['secondary'], hull, .003)
    box('Damper upper clevis', (x - .016, hi.y, hi.z), (.034, .036, .036), M['secondary'], hull, .003)
    for p in (lo, hi):
        cylinder('Damper eye pin', p - Vector((.016, 0, 0)), p + Vector((.016, 0, 0)), .011, M['steel'], hull, 16, .001)
    d = (hi - lo).normalized()
    cylinder('Damper body', lo + d * .02, lo + d * .20, .017, M['oxidized'], hull, 20, .002)
    cylinder('Damper chromed rod', lo + d * .20, hi - d * .02, .008, M['steel'], hull, 16, .001)
    for t in (.035, .23):
        cylinder('Damper spring seat', lo + d * (t - .004), lo + d * (t + .004), .026, M['gun'], hull, 20, .001)
    spring('Damper coil spring', lo + d * .039, lo + d * .226, .022, .0038, 6.5, M['spring'], hull)


def build_brake(hull):
    """Left hub caliper and its line, kept below the gun sweep."""
    s = -1
    box('Hub brake caliper', (s * .205, WY + .118, -.02), (.05, .03, .09), M['oxidized'], hull, .006)
    for dz in (-.03, .03):
        bolt((s * .2305, WY + .118, -.02 + dz), (s, 0, 0), hull, .006, washer=False)
    tube('Brake line', [(s * .205, WY + .133, .02), (s * .200, WY + .16, .09), tuple(arc_pt(.30, 118, s * .200))], .0055, M['rubber'], hull)


def gun_dress(mount):
    """Local workaround and armour for the kit minigun on a LEFT mount.

    kit.minigun() always hangs its feed chute on the receiver's +X face, which
    is outboard for right-side guns but inboard here, where it swept through
    the crown fender and the trunnion seat. Move it to the outboard (-X) face.
    """
    p = PIVOT
    for o in list(ak.groups[mount]):
        if o.name.startswith('Gun feed chute'):
            ak.groups[mount].remove(o); bpy.data.objects.remove(o, do_unlink=True)
    box('Gun feed chute', (p.x - .115, p.y - .02, p.z - .08), (.05, .10, .22), M['secondary'], mount, .006)
    tube('Gun feed guide', [(p.x - .14, p.y + .02, p.z - .19), (p.x - .15, p.y + .06, p.z - .10), (p.x - .14, p.y + .04, p.z + .02)], .008, M['gun'], mount)
    # Receiver armour: bolted outboard cover and a chamfered roof plate.
    plate('Gun receiver armour cover', on_x(p.x - .095, cut_rect(p.z - .33, p.z + .14, p.y - .085, p.y + .105, .03)), (-1, 0, 0), .010, M['paint'], mount, .003)
    for z in (p.z - .30, p.z + .11):
        for y in (p.y - .06, p.y + .08):
            bolt((p.x - .100, y, z), (-1, 0, 0), mount, .006)
    prism('Gun receiver roof armour', outline(.17, .36, .025, p.x, p.z - .10), p.y + .118, p.y + .134, M['paint'], mount, .003,
          top=outline(.15, .34, .02, p.x, p.z - .10))
    # Barrel sleeve on the receiver nose: the spinning cluster turns inside it.
    ring('Gun barrel sleeve', (p.x, p.y + .05, p.z - .42), (0, 0, 1), .093, .088, .16, M['gun'], mount, 40)
    ring('Gun sleeve retaining band', (p.x, p.y + .05, p.z - .345), (0, 0, 1), .097, .088, .016, M['secondary'], mount, 40)


def build():
    setup(PREFIX, PALETTE, stripes=STRIPES)
    M['pod_yellow'] = ak.material(PREFIX + '_PaintSecondaryYellow', PALETTE['hazard'][0], .08, .58)
    M['stencil_black'] = ak.material(PREFIX + '_StencilBlack', STRIPES['colour'], .05, .6)
    # Drawn ordnance steel: lengthwise streaks and heat abrasion on the barrels (WEAPON_FEEL).
    M['gun']['atlas_streak'] = (260.0, 5.0, 260.0); M['gun']['atlas_scratch'] = .62; M['gun']['atlas_grime'] = .2
    root = part('NimbleMonowheel')
    hull = part('Hull', (0, 0, 0), root)
    wheel = part('Wheel', (0, WY, 0), root)
    build_wheel(wheel)
    cylinder('Static axle', (-.20, WY, 0), (.20, WY, 0), .045, M['steel'], hull, 24, .002)
    for s in (-1, 1):
        build_axle_side(hull, s)
    build_hood(hull)
    build_head(hull)
    build_cooling_pack(hull)
    build_rocket_pod(hull)
    build_flame_plate(hull)
    build_damper(hull)
    build_brake(hull)
    frame_node, mount, rotor = minigun(PIVOT, 4, .045, root, M['secondary'], barrel_r=.028)
    gun_dress(mount)
    # Hollow muzzles: a thick crown ring and a dark bore floor in every barrel.
    muzzle_z = PIVOT.z - 1.3; axis_y = PIVOT.y + .05
    for i in range(4):
        a = i * math.tau / 4
        bc = Vector((PIVOT.x + math.cos(a) * .045, axis_y + math.sin(a) * .045, muzzle_z))
        ring('Barrel muzzle crown', bc + Vector((0, 0, .004)), (0, 0, 1), .0236, .0135, .008, M['gun'], rotor, 16)
        cylinder('Barrel bore floor', bc + Vector((0, 0, .03)), bc + Vector((0, 0, .032)), .0236, M['dark'], rotor, 12, 0)
    pitch = math.tau / PITCHES

    def wheel_pitch(t): wheel.rotation_euler = (t * pitch, 0, 0)
    def wheel_turn(t): wheel.rotation_euler = (t * math.tau * .93, 0, 0)
    def gun_pitch(t): mount.rotation_euler = (math.radians(-35 + 55 * t), 0, 0)
    report(root, wheel)
    if '--diag' in sys.argv:
        diagnose(root, [wheel, mount], {'wheel_turn': wheel_turn, 'gun_pitch': gun_pitch})
        return
    complete(root, CHASSIS, PREFIX, [wheel, mount], poses={'wheel_lug_pitch': wheel_pitch, 'wheel_turn': wheel_turn, 'gun_pitch_-35_+20': gun_pitch})


def group_meshes(root):
    return [o for g in ak.descendants(root) for o in ak.groups.get(g, [])]


def diagnose(root, moving, poses):
    """Per-part triangle totals and per-object contacts of each moving assembly (development only)."""
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get(); tally = {}
    for o in group_meshes(root):
        m = o.evaluated_get(dg).to_mesh(); m.calc_loop_triangles()
        key = o.name.split('.')[0]; tally[key] = tally.get(key, 0) + len(m.loop_triangles); o.evaluated_get(dg).to_mesh_clear()
    print('NIMBLE_DIAG_TRIS', json.dumps(sorted(tally.items(), key=lambda kv: -kv[1])[:40]))
    moving_objs = {g: [o for d in ak.descendants(g) for o in ak.groups.get(d, [])] for g in moving}
    static = [o for o in group_meshes(root) if not any(o in v for v in moving_objs.values())]
    def tree(o, delta=Matrix.Identity(4)):
        ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get()); m = ev.to_mesh()
        t = BVHTree.FromPolygons([delta @ o.matrix_world @ v.co for v in m.vertices], [list(p.vertices) for p in m.polygons]); ev.to_mesh_clear(); return t
    rest = {g: g.matrix_basis.copy() for g in moving}
    rest_world = {g: g.matrix_world.copy() for g in moving}
    # Nearest static surface to any moving vertex at rest (the wheel is near lathe-symmetric).
    verts = []; polys = []
    for o in static:
        ev = o.evaluated_get(dg); m = ev.to_mesh(); off = len(verts)
        verts += [o.matrix_world @ v.co for v in m.vertices]; polys += [[off + i for i in p.vertices] for p in m.polygons]; ev.to_mesh_clear()
    static_all = BVHTree.FromPolygons(verts, polys)
    for g, objs in moving_objs.items():
        best = (9.0, '', '')
        for mo in objs:
            ev = mo.evaluated_get(dg); m = ev.to_mesh()
            for v in m.vertices:
                hit = static_all.find_nearest(mo.matrix_world @ v.co)
                if hit[0] is not None and hit[3] < best[0]: best = (hit[3], mo.name.split('.')[0], tuple(round(c, 3) for c in hit[0]))
            ev.to_mesh_clear()
        print('NIMBLE_DIAG_MIN_GAP', g.name, round(best[0], 4), best[1], best[2])
    for label, pose in poses.items():
        for t in (0.0, .25, .5, .75, 1.0):
            pose(t); bpy.context.view_layer.update()
            static_trees = static_trees if t else [(o.name, tree(o)) for o in static]
            for g, objs in moving_objs.items():
                hits = {}
                delta = g.matrix_world @ rest_world[g].inverted()
                for mo in objs:
                    mt = tree(mo, delta)
                    for name, st in static_trees:
                        n = len(mt.overlap(st))
                        if n: hits['%s x %s' % (mo.name.split('.')[0], name.split('.')[0])] = hits.get('%s x %s' % (mo.name.split('.')[0], name.split('.')[0]), 0) + n
                if hits: print('NIMBLE_DIAG_CONTACT', label, t, g.name, json.dumps(hits))
        for g, m in rest.items(): g.matrix_basis = m
    bpy.context.view_layer.update()


def report(root, wheel):
    """Measured contract numbers: lug-tip radius, wheel width, bounds, approximate triangles."""
    dg = bpy.context.evaluated_depsgraph_get()
    rmax = 0.0; xmax = 0.0; lo = Vector((9, 9, 9)); hi = Vector((-9, -9, -9)); tris = 0
    for o in group_meshes(root):
        if o.type != 'MESH': continue
        ev = o.evaluated_get(dg); m = ev.to_mesh(); m.calc_loop_triangles(); tris += len(m.loop_triangles)
        on_wheel = o in ak.groups.get(wheel, [])
        for v in m.vertices:
            p = o.matrix_world @ v.co; g = Vector((p.x, p.z, -p.y))
            lo = Vector(map(min, lo, g)); hi = Vector(map(max, hi, g))
            if on_wheel:
                rmax = max(rmax, math.hypot(g.y - WY, g.z)); xmax = max(xmax, abs(g.x))
        ev.to_mesh_clear()
    print('NIMBLE_MONOWHEEL', json.dumps({'wheel_tip_radius': round(rmax, 4), 'wheel_half_width': round(xmax, 4),
                                          'bounds_min': [round(v, 3) for v in lo], 'bounds_max': [round(v, 3) for v in hi], 'triangles_pre_join': tris}))


build()
