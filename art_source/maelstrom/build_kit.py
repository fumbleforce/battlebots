"""Frozen Maelstrom kit (#102): rocks, ice, the wrecks of two fleets, the eye
vortex and drifting floes. Reproducible; run from the repository root:

    blender -b --python-exit-code 1 --python art_source/maelstrom/build_kit.py

Geometry is authored in Godot metres (X right, Y up, -Z forward/bow) and turned
into Blender's Z-up frame only when meshes are created; the glTF exporter turns
it back. Every model is one object whose material slots name the game material
(`wood`, `paint`, `banner`, ...). Fleet-specific slots (paint, trim, sail,
banner, cloth) are recoloured per fleet in the game, so one mesh serves both.
`banner` and `sail` faces carry 0..1 UVs for the shader-drawn emblems; every
other face gets metre-scale box UVs. Collision hulls are exported beside the
art from the same vertices: data/maelstrom_hulls.json.

Everything is deliberately faceted and flat shaded: no soft edges.
"""
import bpy, bmesh, math, random, json
from pathlib import Path
from mathutils import Vector, Matrix
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[2]
GLB = ROOT / 'battlebots/assets/models/maelstrom/maelstrom_kit.glb'
HULLS = ROOT / 'battlebots/data/maelstrom_hulls.json'
BLEND = ROOT / 'art_source/maelstrom/maelstrom_kit.blend'
R = random.Random(1022026)
UV_SLOTS = {'banner', 'sail'}
# Model name prefix -> slots given a displaced, weathered surface.
DISPLACE = {'rock_': {'rock'}, 'ice_shards': {'ice'}}
SMOOTH_SLOTS = {'sail', 'banner'}
# Preview colours only; the game assigns its own shaders by slot name.
PREVIEW = {'wood': (.16, .10, .06), 'deck': (.33, .24, .15), 'paint': (.55, .06, .05), 'trim': (.85, .62, .18),
           'iron': (.12, .12, .13), 'sail': (.78, .72, .6), 'banner': (.6, .05, .05), 'rope': (.3, .24, .15),
           'cloth': (.55, .06, .05), 'skin': (.55, .62, .68), 'rock': (.07, .075, .085), 'ice': (.45, .75, .9),
           'glass': (.02, .03, .04), 'lantern': (1, .7, .3), 'snow': (.9, .95, 1)}


def V(*a):
    return Vector(a[0]) if len(a) == 1 else Vector(a)


# --- Geometry helpers -------------------------------------------------------

def convex(points):
    """Convex hull of points: (verts, triangles) with outward winding.
    Incremental hull in plain Python: bmesh.ops.convex_hull corrupted memory
    on near-flat inputs in Blender 4.0 and crashed the build."""
    unique = list({tuple(round(c, 4) for c in p): None for p in points})
    if len(unique) < 4:
        return [], []
    jitter = random.Random(len(unique))
    pts = [Vector(tuple(c + jitter.uniform(-2e-4, 2e-4) for c in p)) for p in unique]
    # Initial tetrahedron from extreme, non-degenerate points.
    a = min(range(len(pts)), key=lambda i: pts[i].x)
    b = max(range(len(pts)), key=lambda i: (pts[i] - pts[a]).length)
    c = max(range(len(pts)), key=lambda i: ((pts[b] - pts[a]).cross(pts[i] - pts[a])).length)
    n = (pts[b] - pts[a]).cross(pts[c] - pts[a])
    d = max(range(len(pts)), key=lambda i: abs(n.dot(pts[i] - pts[a])))
    if n.length < 1e-9 or abs(n.dot(pts[d] - pts[a])) < 1e-9:
        return [], []
    inside = (pts[a] + pts[b] + pts[c] + pts[d]) / 4
    faces = []

    def make(i, j, k):
        nn = (pts[j] - pts[i]).cross(pts[k] - pts[i])
        return (i, j, k) if nn.dot(pts[i] - inside) > 0 else (i, k, j)
    for f in ((a, b, c), (a, b, d), (a, c, d), (b, c, d)):
        faces.append(make(*f))
    scale = max((p - inside).length for p in pts)
    eps = 1e-7 * max(scale, 1.0)
    for pi in range(len(pts)):
        if pi in (a, b, c, d):
            continue
        p = pts[pi]
        visible = []
        for f in faces:
            nn = (pts[f[1]] - pts[f[0]]).cross(pts[f[2]] - pts[f[0]])
            if nn.dot(p - pts[f[0]]) > eps * nn.length:
                visible.append(f)
        if not visible:
            continue
        edges = set()
        for f in visible:
            for e in ((f[0], f[1]), (f[1], f[2]), (f[2], f[0])):
                edges.add(e)
        vis = set(visible)
        faces = [f for f in faces if f not in vis]
        for e in edges:
            if (e[1], e[0]) not in edges:
                faces.append((e[0], e[1], pi))
    used = sorted({i for f in faces for i in f})
    remap = {old: new for new, old in enumerate(used)}
    return [tuple(pts[i]) for i in used], [tuple(remap[i] for i in f) for f in faces]


class Model:
    def __init__(self, name):
        self.name = name
        self.geo = defaultdict(lambda: {'v': [], 'f': [], 'uv': [], 'c': []})
        self.hulls = []

    def add(self, slot, verts, faces, uvs=None, tint=None, frost=0.0, color=None):
        g = self.geo[slot]
        off = len(g['v'])
        g['v'].extend(tuple(v) for v in verts)
        t = R.random() if tint is None else tint
        for i, f in enumerate(faces):
            g['f'].append(tuple(off + k for k in f))
            g['uv'].append(uvs[i] if uvs is not None else None)
            g['c'].append(color or (t, 1.0, frost))

    def solid(self, slot, points, tint=None, frost=0.0, hull=False):
        verts, faces = convex(points)
        self.add(slot, verts, faces, tint=tint, frost=frost)
        verts = [Vector(v) for v in verts]
        if hull:
            self.hulls.append(verts)
        return verts

    def box(self, slot, xf, size, centre=(0, 0, 0), tint=None, hull=False):
        cx, cy, cz = centre
        sx, sy, sz = (s * .5 for s in size)
        pts = [xf @ V(cx + a * sx, cy + b * sy, cz + c * sz) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]
        return self.solid(slot, pts, tint=tint, hull=hull)

    def beam(self, slot, a, b, r0, r1=None, sides=6, tint=None, hull=False, spin=0.0):
        """Faceted tapered prism from a to b (already placed)."""
        a = V(a); b = V(b); r1 = r0 if r1 is None else r1
        d = (b - a)
        if d.length < 1e-4:
            return []
        d.normalize()
        side = d.cross(V(0, 1, 0))
        if side.length < .01:
            side = d.cross(V(1, 0, 0))
        side.normalize(); up = d.cross(side).normalized()
        pts = []
        for end, r in ((a, r0), (b, r1)):
            for j in range(sides):
                ang = spin + j * math.tau / sides
                pts.append(end + (side * math.cos(ang) + up * math.sin(ang)) * r)
        return self.solid(slot, pts, tint=tint, hull=hull)

    def spike(self, slot, base, tip, r, sides=5, tint=None, hull=False):
        base = V(base); tip = V(tip); d = (tip - base).normalized()
        side = d.cross(V(0, 1, 0))
        if side.length < .01:
            side = d.cross(V(1, 0, 0))
        side.normalize(); up = d.cross(side).normalized()
        a0 = R.random() * math.tau
        pts = [tip] + [base + (side * math.cos(a0 + j * math.tau / sides) + up * math.sin(a0 + j * math.tau / sides)) * r * R.uniform(.7, 1.1) for j in range(sides)]
        return self.solid(slot, pts, tint=tint, hull=hull)

    def sheet(self, slot, fn, nu, nv, keep=lambda i, j, k: True, tint=None, uv=True, extent=None):
        """Grid surface fn(u, v) -> point, as triangles. extent[i] shortens
        vertex column i (a torn, jagged hem); triangles failing keep are torn out."""
        extent = extent or [1.0] * (nu + 1)
        verts = [fn(i / nu, j / nv * extent[i]) for j in range(nv + 1) for i in range(nu + 1)]
        # Cloth UVs are metres from the top-left corner; the size rides in the
        # vertex colour (size / 10 m) so shader-drawn emblems keep proportion.
        w = (Vector(fn(1, 0)) - Vector(fn(0, 0))).length
        h = (Vector(fn(0, 1)) - Vector(fn(0, 0))).length
        tex = [(i / nu * w, j / nv * extent[i] * h) for j in range(nv + 1) for i in range(nu + 1)]
        faces = []; uvs = []
        for j in range(nv):
            for i in range(nu):
                a = j * (nu + 1) + i
                quad = (a, a + 1, a + nu + 2, a + nu + 1)
                for k, tri in enumerate(((quad[0], quad[1], quad[2]), (quad[0], quad[2], quad[3]))):
                    if keep(i, j, k):
                        faces.append(tri)
                        uvs.append([tex[q] for q in tri])
        self.add(slot, verts, faces, uvs if uv else None, tint=tint, color=(min(w / 10, 1), min(h / 10, 1), 0.0) if uv else None)

def rot(yaw=0.0, pitch=0.0, roll=0.0, at=(0, 0, 0)):
    """Godot-frame transform: yaw about Y, pitch about X, roll about Z."""
    return Matrix.Translation(V(at)) @ Matrix.Rotation(yaw, 4, 'Y') @ Matrix.Rotation(pitch, 4, 'X') @ Matrix.Rotation(roll, 4, 'Z')


def icicles(m, a, b, count, length, frost=1.0):
    """A fringe of icicles hanging under the segment a..b."""
    a = V(a); b = V(b)
    for i in range(count):
        p = a.lerp(b, (i + R.random()) / count)
        l = length * R.uniform(.35, 1.0)
        m.spike('ice', p + V(0, .05, 0), p - V(R.uniform(-.05, .05), l, R.uniform(-.05, .05)), l * .12 + .03, sides=4)


# --- The galleon ------------------------------------------------------------
L_SHIP = 46.0
B_SHIP = 6.4
D_SHIP = 8.0
STRAKES = 13


def beam_at(s):
    if s < .5:
        return B_SHIP * (.78 + .22 * math.sin(s / .5 * math.pi / 2))
    return B_SHIP * max(0.0, 1 - ((s - .5) / .5) ** 2.2) ** .5


def deck_at(s, sheer=True):
    return D_SHIP + (2.2 * (2 * s - 1) ** 2 if sheer else 0.0)


def keel_at(s):
    return max(0.0, (s - .78) / .22) ** 2 * D_SHIP * .8 + max(0.0, (.05 - s) / .05) * .8


def hull_point(s, q, side, sheer=True, out=0.0):
    k = keel_at(s); d = deck_at(s, sheer)
    w = beam_at(s) * (max(q, 0.0) ** .42) * (1 - .08 * max(0.0, (q - .82) / .18)) if q <= 1 else beam_at(s) * .92 * (1 - .05 * (q - 1))
    y = k + q * (d - k)
    return V(side * (w + out), y, (.5 - s) * L_SHIP)


def galleon(m, xf, s0, s1, broken_lo, broken_hi, sheer=True, ports=True, ribs_lo=True, ribs_hi=True, hull_q=1.0):
    """Planked section between s0 (sternward) and s1 (bowward). Broken ends are
    ragged, plank by plank, with the frames standing out of the break.
    Returns the outer points for the collision hull (up to hull_q of the depth)."""
    hull_pts = []
    top_q = 1.14  # bulwark above the deck
    for k in range(STRAKES + 2):
        q0 = k / STRAKES; q1 = min((k + 1) / STRAKES, top_q)
        if q0 >= top_q:
            break
        slot = 'paint' if q0 >= 1 - 3.0 / STRAKES else 'wood'
        wale = abs(q0 - (1 - 4.0 / STRAKES)) < 1e-6
        for side in (-1, 1):
            lo = s0 + (R.uniform(0, .07) if broken_lo else 0)
            hi = s1 - (R.uniform(0, .08) if broken_hi else 0)
            if broken_hi and R.random() < .18 and q0 > .3:
                hi -= R.uniform(.05, .12)  # a missing plank run near the break
            if hi - lo < .02:
                continue
            n = max(2, int((hi - lo) * L_SHIP / 1.3) + 1)
            # Splintered ends: the upper edge runs a little past the lower edge.
            lo_u = lo - (R.uniform(0, .02) if broken_lo else 0); hi_u = hi + (R.uniform(0, .025) if broken_hi else 0)
            clinker = .09 if wale else .05
            verts = []
            for i in range(n + 1):
                t = i / n
                verts.append(xf @ hull_point(lo + (hi - lo) * t, q0, side, sheer, clinker))
                verts.append(xf @ hull_point(lo_u + (hi_u - lo_u) * t, q1, side, sheer, .0))
            faces = []
            for i in range(n):
                a = i * 2
                faces.append((a, a + 2, a + 3, a + 1) if side > 0 else (a, a + 1, a + 3, a + 2))
            m.add(slot, verts, faces, tint=R.random() * .6 + (.4 if wale else 0))
            if q1 <= hull_q + 1e-6:
                hull_pts += verts[::2] + verts[1::2]
    # Keel and gunwale caps.
    m.beam('wood', xf @ hull_point(s0, 0, 0), xf @ hull_point(s1, 0, 0), .35, sides=4)
    for side in (-1, 1):
        n = max(2, int((s1 - s0) * L_SHIP / 2.5))
        lo = s0 + (.06 if broken_lo else 0); hi = s1 - (.05 if broken_hi else 0)
        for i in range(n):
            a = lo + (hi - lo) * i / n; b = lo + (hi - lo) * (i + 1) / n
            m.beam('trim' if i % 3 == 0 else 'wood', xf @ hull_point(a, top_q, side, sheer, .08), xf @ hull_point(b, top_q, side, sheer, .08), .14, sides=4)
            if R.random() < .5:
                icicles(m, xf @ hull_point(a, top_q - .01, side, sheer, .2), xf @ hull_point(b, top_q - .01, side, sheer, .2), 3, 1.4)
    # Deck: planks along the ship, ragged and holed near the breaks.
    boards = 16
    for b in range(boards):
        u = (b + .5) / boards * 2 - 1
        lo = s0 + (R.uniform(.01, .09) if broken_lo else .01); hi = s1 - (R.uniform(.01, .1) if broken_hi else .01)
        if R.random() < .12:
            continue
        pts = []
        for s in (lo, hi):
            w = beam_at(s) * .93
            if w < .6:
                continue
            y = deck_at(s, sheer) - .06
            for du in (-.5, .5):
                x = (u + du * 2 / boards) * w
                for dy in (0, .12):
                    pts.append(xf @ V(x, y + dy, (.5 - s) * L_SHIP))
        if len(pts) == 8:
            m.solid('deck', pts)
    # Deck beams at the break and frames (ribs) standing out of it.
    for end, active, sign in ((s0, broken_lo and ribs_lo, 1), (s1, broken_hi and ribs_hi, -1)):
        if not active:
            continue
        for r_i in range(3):
            s = end + sign * (.012 + r_i * .03)
            top = R.uniform(.55, 1.12)
            for side in (-1, 1):
                if R.random() < .2:
                    continue
                qs = [q / 8 * top for q in range(9)]
                for qa, qb in zip(qs, qs[1:]):
                    m.beam('wood', xf @ hull_point(s, qa, side, True, -.12), xf @ hull_point(s, qb, side, True, -.12), .22, .2, sides=4)
            m.beam('wood', xf @ hull_point(s, .98, -1, True, -.25), xf @ hull_point(s, .98, 1, True, -.25), .2, sides=4)
    # Gun ports: dark openings with fleet-trim frames.
    if ports:
        s = s0 + .05
        while s < s1 - .05:
            if beam_at(s) > 3:
                for side in (-1, 1):
                    c = hull_point(s, .8, side, sheer, .08)
                    fr = V(side, 0, 0)
                    port = [xf @ (c + V(0, dy, dz) + fr * dd) for dy in (-.45, .45) for dz in (-.5, .5) for dd in (0, .04)]
                    m.solid('glass', port)
                    for dy, dz, sy, sz in ((-.55, 0, .12, 1.2), (.55, 0, .12, 1.2), (0, -.6, 1.1, .12), (0, .6, 1.1, .12)):
                        m.solid('trim', [xf @ (c + V(0, dy + a * sy * .5, dz + b * sz * .5) + fr * dd) for a in (-1, 1) for b in (-1, 1) for dd in (0, .1)])
            s += 3.4 / L_SHIP
    return hull_pts


def cloth(m, slot, top_l, top_r, height, bulge=.8, tear=.25, notch=0.0, wind=V(0, 0, 0), nu=16, nv=16, droop=0.0):
    """A torn sail or banner hanging from top_l..top_r, frozen stiff: a jagged
    sawtooth hem, a swallowtail notch and triangular rips."""
    top_l = V(top_l); top_r = V(top_r)
    across = top_r - top_l
    normal = across.cross(V(0, -1, 0)).normalized()
    extent = []
    for i in range(nu + 1):
        u = i / nu
        hem = 1 - R.uniform(0, tear) - (tear * .5 if i % 2 else 0) - (R.uniform(.2, .45) if R.random() < tear * .5 else 0)
        extent.append(max(.2, hem - notch * (1 - abs(2 * u - 1))))
    holes = {(R.randrange(1, nu - 1), R.randrange(1, nv - 1), R.randrange(2)) for _ in range(int(nu * nv * tear * .3))}
    slash = (R.uniform(.25, .75), R.uniform(-.8, .8))

    def fn(u, v):
        p = top_l + across * u + V(0, -height * v, 0)
        p += normal * bulge * math.sin(math.pi * u) * math.sin(math.pi * min(v, 1) * .9)
        p += wind * v * v + V(0, -droop * math.sin(math.pi * u) * v, 0)
        return p

    def keep(i, j, k):
        u = (i + .5) / nu; v = (j + .5) / nv
        if (i, j, k) in holes:
            return False
        if tear > .3 and v > .25 and abs((u - slash[0]) - slash[1] * (v - .5) * .5) < .045:
            return False
        return True
    m.sheet(slot, fn, nu, nv, keep, extent=extent)
    # Ice weighs down the hem.
    for i in range(0, nu + 1, 2):
        if R.random() < .45:
            p = fn(i / nu, extent[i])
            m.spike('ice', p + V(0, .15, 0), p - V(0, R.uniform(.5, 1.6), 0), .07, sides=4)

def mast(m, xf, base, height, lean=(0, 0), yard_at=.7, sail=True, banner=True, nest=True, broken=True):
    """A broken mast with a yard, torn sail, crow's nest and pennant."""
    base = V(base)
    top = base + V(lean[0] * height, height, lean[1] * height)
    axis = (top - base).normalized()
    m.beam('wood', xf @ base, xf @ top, .62, .42, sides=8)
    if broken:
        for j in range(5):  # splintered top
            a = j * math.tau / 5
            p = top + V(math.cos(a) * .3, 0, math.sin(a) * .3)
            m.spike('wood', xf @ (p - axis * .3), xf @ (p + axis * R.uniform(.6, 1.8) + V(R.uniform(-.2, .2), 0, R.uniform(-.2, .2))), .16, sides=3)
    for y in (.25, .5, .85):  # iron hoops
        c = base.lerp(top, y)
        m.beam('iron', xf @ (c - axis * .1), xf @ (c + axis * .1), .68 - y * .2, sides=8)
    yard_c = base.lerp(top, yard_at)
    span = 9.5 * R.uniform(.85, 1.1)
    tilt = R.uniform(-.25, .25)
    yl = yard_c + V(-span, tilt * span, 0); yr = yard_c + V(span, -tilt * span, 0)
    m.beam('wood', xf @ yl, xf @ yr, .3, sides=6)
    icicles(m, xf @ yl, xf @ yr, 10, 1.6)
    if sail:
        cloth(m, 'sail', xf @ (yl + V(.4, -.3, .3)), xf @ (yr + V(-.4, -.3, .3)), height * yard_at * .62, bulge=1.3, tear=.45,
              wind=xf.to_3x3() @ V(0, 0, 1.2), nu=12, nv=12)
    if nest:
        c = base.lerp(top, min(yard_at + .14, .95))
        ring = [xf @ (c + V(math.cos(a) * 1.7, dy, math.sin(a) * 1.7)) for a in [j * math.tau / 8 for j in range(8)] for dy in (-.15, .15)]
        m.solid('wood', ring)
        for j in range(8):
            a = j * math.tau / 8
            m.beam('wood', xf @ (c + V(math.cos(a) * 1.7, 0, math.sin(a) * 1.7)), xf @ (c + V(math.cos(a) * 1.75, 1.0, math.sin(a) * 1.75)), .07, sides=4)
        icicles(m, xf @ (c + V(-1.7, -.2, 0)), xf @ (c + V(1.7, -.2, 0)), 6, 1.2)
    if banner:
        head = top - axis * .5
        pole = head + V(0, 0, 0)
        cloth(m, 'banner', xf @ pole, xf @ (pole + V(0, 0, 1.6)), 7.5, bulge=.25, tear=.2, notch=.28,
              wind=xf.to_3x3() @ V(3.5, 1.2, 0), nu=6, nv=18)
    return [xf @ (base + V(x, 0, z)) for x in (-.7, .7) for z in (-.7, .7)] + [xf @ (top + V(x, 0, z)) for x in (-.5, .5) for z in (-.5, .5)]


def rigging(m, a, b, sag=.6):
    a = V(a); b = V(b); prev = a
    for i in range(1, 7):
        t = i / 6
        p = a.lerp(b, t) - V(0, sag * math.sin(math.pi * t), 0)
        m.beam('rope', prev, p, .05, sides=3)
        prev = p


# --- Crew ------------------------------------------------------------------

def figure(m, xf, pose='stand', scale=1.0):
    """A frozen soldier: iron limbs, fleet tabard, iron helm; shields and
    pennons carry the fleet's emblem."""
    s = scale

    def P(x, y, z):
        return xf @ V(x * s, y * s, z * s)
    if pose == 'fallen':
        body = rot(0, -math.pi / 2 + .1, R.uniform(-.3, .3), (0, .2, 0))
        xf = xf @ body
    if pose == 'kneel':
        m.beam('iron', P(-.15, .0, .1), P(-.15, .5, -.3), .1, sides=4)
        m.beam('iron', P(-.15, .5, -.3), P(-.15, .55, .15), .1, sides=4)
        m.beam('iron', P(.15, 0, -.35), P(.15, .55, -.3), .1, sides=4)
        m.beam('iron', P(.15, .55, -.3), P(.15, .6, .1), .1, sides=4)
        hip = .62
    else:
        for x in (-.14, .14):
            m.beam('iron', P(x, 0, 0), P(x, .9, 0), .1, .12, sides=4)
        hip = .92
    torso = [P(x, hip + y, z) for x in (-.26, .26) for y in (0, .62) for z in (-.14, .14)]
    m.solid('cloth', torso + [P(0, hip - .25, -.16), P(0, hip - .25, .16)])  # tabard
    m.solid('iron', [P(x, hip + y, z) for x in (-.3, .3) for y in (.55, .72) for z in (-.17, .17)])  # pauldrons
    head = V(0, hip + .9, 0)
    m.solid('skin', [P(x, head.y + y, z) for x in (-.11, .11) for y in (-.12, .12) for z in (-.12, .1)])
    m.solid('iron', [P(x, head.y + y, z) for x in (-.14, .14) for y in (.04, .18) for z in (-.15, .14)] + [P(0, head.y + .32, 0)])  # peaked helm
    sh = hip + .6
    if pose in ('stand', 'fallen'):
        m.beam('iron', P(-.3, sh, 0), P(-.36, sh - .6, -.15), .07, sides=4)
        m.beam('iron', P(.3, sh, 0), P(.45, sh - .3, -.35), .07, sides=4)
        m.beam('wood', P(.46, -.1 if pose == 'stand' else .1, -.4), P(.46, 2.4, -.4), .03, sides=3)  # spear
        m.spike('iron', P(.46, 2.4, -.4), P(.46, 2.75, -.4), .06, sides=3)
    elif pose == 'reach':
        m.beam('iron', P(-.3, sh, 0), P(-.4, sh + .6, -.3), .07, sides=4)
        m.beam('iron', P(.3, sh, 0), P(.35, sh + .7, -.2), .07, sides=4)
    else:  # kneel behind a shield
        m.beam('iron', P(-.3, sh, 0), P(-.2, sh - .2, -.4), .07, sides=4)
        m.beam('iron', P(.3, sh, 0), P(.35, sh - .5, -.3), .07, sides=4)
        c = V(0, hip + .1, -.45)
        m.sheet('banner', lambda u, v: P(c.x + (u - .5) * .9, c.y + (.5 - v) * 1.1, c.z - .08 * math.sin(math.pi * u)), 4, 4)
    for x in (-.2, .2):  # frost beard
        m.spike('ice', P(x, sh - .05, -.15), P(x, sh - .4, -.18), .04, sides=3)


def crew_on(m, xf, spots):
    for (x, y, z, yaw, pose) in spots:
        figure(m, xf @ rot(yaw, 0, 0, (x, y, z)), pose)


# --- Debris ----------------------------------------------------------------

def barrel(m, xf, lying=False):
    at = rot(R.random() * math.tau, math.pi / 2 if lying else 0, 0, (0, .45 if lying else 0, 0))
    ring = []
    for y, r in ((0, .38), (.45, .46), (.9, .38)):
        for j in range(8):
            a = j * math.tau / 8
            ring.append(xf @ at @ V(math.cos(a) * r, y - (.45 if lying else 0), math.sin(a) * r))
    m.solid('wood', ring)
    for y in (.12, .78):
        m.beam('iron', xf @ at @ V(0, y - .03 - (.45 if lying else 0), 0), xf @ at @ V(0, y + .03 - (.45 if lying else 0), 0), .45, sides=8)


def cannon(m, xf):
    m.box('wood', xf, (1.1, .5, 1.6), (0, .25, 0))
    m.beam('iron', xf @ V(0, .75, .8), xf @ V(0, .85, -1.6), .32, .22, sides=8)
    for z in (-.55, .55):
        for x in (-.6, .6):
            m.beam('wood', xf @ V(x, .25, z), xf @ V(x + .12 * (1 if x > 0 else -1), .25, z), .25, sides=6)


def debris_field(m, xf, count, radius, y=0.0):
    for i in range(count):
        a = R.random() * math.tau; r = R.uniform(.3, 1) * radius
        at = xf @ rot(R.random() * math.tau, 0, 0, (math.cos(a) * r, y, math.sin(a) * r))
        kind = R.random()
        if kind < .3:
            barrel(m, at, R.random() < .5)
        elif kind < .5:
            m.box('wood', at @ rot(0, 0, R.uniform(-.3, .3)), (1, .8, .8), (0, .3, 0))
        elif kind < .8:  # broken planks, jutting out of the ice
            l = R.uniform(2, 5)
            m.box('deck', at @ rot(0, R.uniform(-.9, -.2), 0), (.35, .1, l), (0, 0, l * .4))
        else:
            m.beam('wood', at @ V(0, 0, 0), at @ V(R.uniform(-1, 1), R.uniform(.5, 2.5), R.uniform(-2, 2)), .15, .06, sides=4)


def ice_collar(m, xf, points, count, height=1.6, hull=None):
    """Upthrust ice slabs where a wreck broke through the sheet."""
    pts = [V(p) for p in points]
    for i in range(count):
        p = R.choice(pts)
        out = V(p.x, 0, p.z)
        out = out.normalized() if out.length > .1 else V(1, 0, 0)
        c = p + out * R.uniform(.2, 1.5)
        c.y = R.uniform(-.4, .1)
        w = R.uniform(1, 2.6); h = R.uniform(.6, height); t = R.uniform(.25, .5)
        tilt = rot(math.atan2(out.x, out.z), -R.uniform(.3, 1.0), R.uniform(-.3, .3), tuple(c))
        slab = [xf @ tilt @ V(x * w * .5 * R.uniform(.7, 1), y * h, z * t) for x in (-1, 1) for y in (0, 1) for z in (-1, 1)]
        slab.append(xf @ tilt @ V(R.uniform(-.3, .3) * w, h * 1.3, 0))
        verts = m.solid('ice', slab)
        if hull is not None:
            hull.extend(verts)


# --- Models ----------------------------------------------------------------
MODELS = []


def model(fn):
    MODELS.append(fn)
    return fn


def spire(m, base, height, radius, lean, sides=7, bury=3.0, hull=True, squash=1.0, yaw=0.0):
    """A fractured basalt crag: a stack of jostled, faceted blocks with ledges,
    icicles hanging under each ledge. Collision is the crag's convex envelope."""
    base = V(base)

    def centre(t):
        return base + V(lean[0] * height * t, -bury + (height + bury) * t, lean[1] * height * t)

    def radius_at(t):
        return radius * (1 - t) ** .85 + .25

    def offset(a, r):
        # A blade-like crag: squash one axis, then turn it.
        x = math.cos(a) * r * squash; z = math.sin(a) * r
        return V(x * math.cos(yaw) - z * math.sin(yaw), 0, x * math.sin(yaw) + z * math.cos(yaw))
    envelope = []
    for t in (0, .25, .55, .82, 1):
        a0 = R.random() * math.tau
        for j in range(sides if t < 1 else 2):
            a = a0 + j * math.tau / sides
            envelope.append(centre(t) + offset(a, radius_at(t) * R.uniform(.75, 1.1)))
    if hull:
        m.hulls.append(envelope)
    blocks = max(3, int((height + bury) / 3.4))
    for k in range(blocks):
        t0 = k / blocks; t1 = min(1.0, (k + 1.25) / blocks)
        shift = V(R.uniform(-1, 1), 0, R.uniform(-1, 1)) * radius_at(t0) * .08
        pts = []
        a0 = R.random() * math.tau
        for t, ring, spread in ((t0, sides + 2, (.78, 1.0)), (t1, sides, (.55, .95))):
            for j in range(ring):
                a = a0 + j * math.tau / ring + R.uniform(-.2, .2)
                pts.append(centre(t) + shift + offset(a, radius_at(t) * R.uniform(*spread)) + V(0, R.uniform(-.25, .25) * radius_at(t), 0))
        if t1 >= 1.0:
            pts.append(centre(1.0) + V(0, R.uniform(.5, 2.0), 0))
        m.solid('rock', pts, tint=R.random())
        # Icicles under the block's ledge.
        if 0 < k and centre(t0).y > 1.0:
            for j in range(R.randrange(2, 6)):
                a = R.random() * math.tau
                p = centre(t0) + shift + offset(a, radius_at(t0) * .98)
                l = R.uniform(.6, 2.8)
                m.spike('ice', p, p - V(0, l, 0), .12 + l * .05, sides=4)
    return envelope

@model
def rock_spire_a():
    m = Model('rock_spire_a')
    spire(m, (0, 0, 0), 34, 9.5, (.12, .05))
    spire(m, (7, 0, 3), 18, 5, (.35, .1))
    spire(m, (-5, 0, 5), 13, 4.5, (-.3, .25))
    spire(m, (-2, 0, -7), 9, 4, (-.1, -.45))
    for i in range(10):
        a = R.random() * math.tau; r = R.uniform(8, 11)
        m.spike('ice', (math.cos(a) * r, -.5, math.sin(a) * r), (math.cos(a) * (r + R.uniform(1, 3)), R.uniform(2, 5), math.sin(a) * (r + R.uniform(1, 3))), R.uniform(.6, 1.2))
    return m


@model
def rock_spire_b():
    m = Model('rock_spire_b')
    # Two crossing blades of fractured black basalt.
    spire(m, (0, 0, 0), 27, 10, (.2, 0), squash=.3, yaw=.3)
    spire(m, (1, 0, 1), 21, 8, (-.25, .1), squash=.32, yaw=1.7)
    spire(m, (5, 0, -6), 8, 5, (.2, -.2))
    for i in range(8):
        a = R.random() * math.tau; r = R.uniform(6, 10)
        m.spike('ice', (math.cos(a) * r, -.5, math.sin(a) * r), (math.cos(a) * r * 1.2, R.uniform(2, 4.5), math.sin(a) * r * 1.2), R.uniform(.5, 1))
    return m


@model
def rock_crag():
    m = Model('rock_crag')
    # A broken, tilted massif: low slabs rising to a sheer, toothed face.
    for x, h, r in ((-7, 4, 7), (0, 7, 7.5), (6, 10, 6.5)):
        spire(m, (x, 0, 0), h, r, (.08, 0), sides=8, squash=.8, yaw=.2)
    for i in range(6):
        x = R.uniform(4, 10); z = R.uniform(-6, 6)
        spire(m, (x, 6 + x * .3, z), R.uniform(4, 9), R.uniform(1.4, 2.4), (R.uniform(-.2, .2), R.uniform(-.2, .2)), bury=2, hull=True)
    return m

def shard_cluster(m, count, spread, hmin, hmax, fan=None):
    """Seracs: broken slabs of glacier ice thrust up through the sheet, leaning,
    their tops snapped into steps; icicles drip from the overhanging side."""
    for i in range(count):
        a = (fan + R.uniform(-.6, .6)) if fan is not None else R.random() * math.tau
        r = R.uniform(0, spread)
        base = V(math.cos(a) * r, -1.5, math.sin(a) * r)
        h = R.uniform(hmin, hmax)
        lean = V(math.cos(a), 0, math.sin(a)) * R.uniform(.12, .45)
        yaw = a + math.pi / 2 + R.uniform(-.4, .4)
        along = V(math.cos(yaw), 0, math.sin(yaw))
        across = V(-along.z, 0, along.x)
        width = R.uniform(2.5, 5.5) * (.5 + .5 * h / hmax)
        thick = R.uniform(1.0, 2.2)
        pieces = R.randrange(2, 4)
        envelope = []
        for k in range(pieces):
            u0 = -width / 2 + width * k / pieces; u1 = -width / 2 + width * (k + 1) / pieces
            top0 = h * R.uniform(.55, 1.0); top1 = h * R.uniform(.55, 1.0)
            pts = []
            for u, top in ((u0, top0), (u1, top1)):
                for w in (-thick / 2, thick / 2):
                    foot = base + along * u + across * w
                    pts.append(foot)
                    pts.append(foot + V(0, top, 0) + lean * top + across * R.uniform(-.2, .2))
            envelope += m.solid('ice', pts, tint=R.random())
            if R.random() < .7:
                tip = base + along * (u0 + u1) / 2 + lean * max(top0, top1) + V(0, max(top0, top1) * .9, 0) + across * thick * .5
                for j in range(3):
                    p = tip + along * R.uniform(-.8, .8)
                    l = R.uniform(.8, 3.0)
                    m.spike('ice', p, p - V(0, l, 0), .12 + l * .05, sides=4)
        m.hulls.append(envelope)

@model
def ice_shards_a():
    m = Model('ice_shards_a')
    shard_cluster(m, 7, 4.5, 4, 13)
    return m


@model
def ice_shards_b():
    m = Model('ice_shards_b')
    shard_cluster(m, 6, 6, 3, 11, fan=0.0)
    return m


# Crew spots are (x, y, z, yaw, pose) in the section's local frame.
@model
def wreck_bow():
    m = Model('wreck_bow')
    xf = rot(0, math.radians(16), math.radians(7), (0, -4.2, 6))
    pts = galleon(m, xf, .55, 1.0, True, False)
    # Bowsprit, beakhead and figurehead.
    tip = hull_point(1, 1, 0)
    m.beam('wood', xf @ (tip + V(0, -.3, 2)), xf @ (tip + V(0, 4.5, -13)), .5, .22, sides=6)
    m.beam('wood', xf @ (tip + V(0, 1.2, -5)), xf @ (tip + V(0, 1.7, -5.6)), .9, sides=6)
    fig = xf @ rot(0, -.5, 0, tuple(tip + V(0, -1.0, -.6)))
    m.solid('trim', [fig @ V(x, y, z) for x in (-.5, .5) for y in (0, 2.4) for z in (-.5, .3)] + [fig @ V(0, 3.1, -.2)])
    for side in (-1, 1):  # gilded wings on the figurehead
        m.solid('trim', [fig @ V(side * a, b, c) for a, b, c in ((.4, 1.8, 0), (2.6, 3.4, .6), (1.8, 1.0, .4), (.4, .8, .1), (2.2, 3.0, .9))])
    rigging(m, xf @ (tip + V(0, 4.3, -12.6)), xf @ hull_point(.8, 1.1, 0) + V(0, 14, 0), .8)
    # Foremast, snapped above its crow's nest.
    mp = mast(m, xf, hull_point(.82, 1, 0), 15, lean=(.03, .06), yard_at=.62)
    for side in (-1, 1):
        for s in (.7, .76, .82):
            rigging(m, xf @ hull_point(s, 1.14, side, True, .1), xf @ (hull_point(.82, 1, 0) + V(0, 14.5, .6)), .6)
    crew_on(m, xf, [(-2.2, deck_at(.68) + .05, (.5 - .68) * L_SHIP, .3, 'stand'), (1.8, deck_at(.72), (.5 - .72) * L_SHIP, 2.8, 'kneel'),
                    (.2, deck_at(.62), (.5 - .62) * L_SHIP, 1.2, 'fallen'), (-1.2, deck_at(.9), (.5 - .9) * L_SHIP, 3.0, 'reach'),
                    (2.4, deck_at(.86), (.5 - .86) * L_SHIP, -.4, 'stand')])
    pts = [p for p in pts if p.y > -1.5]
    ice_collar(m, Matrix(), [p for p in pts if p.y < 1.5] or pts, 22, hull=pts)
    m.hulls.append(pts)
    m.hulls.append(mp)
    debris_field(m, rot(0, 0, 0, (0, 0, 12)), 14, 9)
    crew_on(m, Matrix(), [(5, 0, 10, 2.0, 'fallen'), (-6, 0, 13, .5, 'kneel')])
    return m


@model
def wreck_stern():
    m = Model('wreck_stern')
    xf = rot(0, math.radians(-5), math.radians(-11), (0, -3.4, -5))
    pts = galleon(m, xf, 0.0, .42, False, True)
    # Stern castle: two raised decks and a gilded, windowed transom.
    for lo, hi, top in ((0, .2, 3.2), (0, .1, 6.0)):
        for side in (-1, 1):
            n = 6
            for i in range(n):
                a = lo + (hi - lo) * i / n; b = lo + (hi - lo) * (i + 1) / n
                quad = [hull_point(a, 1.0, side), hull_point(b, 1.0, side), hull_point(b, 1.0, side) + V(0, top, 0), hull_point(a, 1.0, side) + V(0, top, 0)]
                verts = [xf @ (q + V(side * .02, 0, 0)) for q in quad]
                m.add('paint', verts, [(0, 1, 2, 3) if side < 0 else (0, 3, 2, 1)])
                pts += verts
                if i % 2 == 1:
                    c = hull_point((a + b) / 2, 1.0, side) + V(side * .1, top * .55, 0)
                    m.solid('glass', [xf @ (c + V(0, dy, dz)) for dy in (-.6, .6) for dz in (-.45, .45)] + [xf @ (c + V(side * .08, 0, 0))])
                    m.solid('trim', [xf @ (c + V(side * .05, dy, dz)) for dy in (-.8, .8) for dz in (-.6, .6)] + [xf @ (c + V(side * .15, .9, 0))])
        deck_y = deck_at(0) + top
        m.solid('deck', [xf @ V(x * beam_at(s) * .9, deck_y + dy, (.5 - s) * L_SHIP) for x in (-1, 1) for s in (lo, hi) for dy in (0, .15)])
        for side in (-1, 1):
            m.beam('trim', xf @ (hull_point(lo, 1, side) + V(0, top + .9, 0)), xf @ (hull_point(hi, 1, side) + V(0, top + .9, 0)), .1, sides=4)
            icicles(m, xf @ (hull_point(lo, 1, side) + V(side * .2, top, 0)), xf @ (hull_point(hi, 1, side) + V(side * .2, top, 0)), 8, 1.8)
    transom_z = .5 * L_SHIP + .02
    tw = beam_at(0) * .95
    y0 = keel_at(0) + 2.5; y1 = deck_at(0) + 6.0

    def transom(u, v):
        return xf @ V((u - .5) * 2 * tw * (0.8 + .2 * v), y0 + (y1 - y0) * v, transom_z + .6 * v)
    m.sheet('paint', transom, 8, 8, uv=False)
    for row, y in enumerate((deck_at(0) + 1.4, deck_at(0) + 4.4)):
        for j in range(5):
            x = (j - 2) * tw * .38
            c = V(x, y, transom_z + .6 * (y - y0) / (y1 - y0) + .08)
            m.solid('glass', [xf @ (c + V(dx, dy, dz)) for dx in (-.55, .55) for dy in (-.7, .7) for dz in (0, .05)])
            m.solid('trim', [xf @ (c + V(dx, dy, dz)) for dx in (-.7, .7) for dy in (.75, .95) for dz in (0, .25)])
        m.beam('trim', xf @ V(-tw, y - 1.1, transom_z + .5), xf @ V(tw, y - 1.1, transom_z + .5), .18, sides=4)
    # The fleet's crest, carved and painted on the transom (banner UVs).
    c = V(0, deck_at(0) + 2.9, transom_z + .6 * (deck_at(0) + 2.9 - y0) / (y1 - y0) + .15)
    m.sheet('banner', lambda u, v: xf @ (c + V((u - .5) * 3.2, (.5 - v) * 2.6, .1 * math.sin(math.pi * u))), 6, 6)
    for x in (-1.9, 1.9):  # lanterns on iron brackets, long gone dark
        l = V(x * tw / 3, y1 + .2, transom_z + .9)
        m.beam('iron', xf @ (l - V(0, 1.2, .4)), xf @ l, .06, sides=4)
        m.solid('lantern', [xf @ (l + V(dx, dy, dz)) for dx in (-.35, .35) for dy in (0, 1.1) for dz in (-.35, .35)] + [xf @ (l + V(0, 1.5, 0))])
        m.beam('trim', xf @ (l + V(0, 1.1, 0)), xf @ (l + V(0, 1.6, 0)), .38, .05, sides=6)
    # Ensign staff with the fleet's great banner.
    staff_base = V(0, y1, transom_z - .5)
    staff_top = staff_base + V(0, 9, 1.2)
    m.beam('wood', xf @ staff_base, xf @ staff_top, .18, .1, sides=6)
    cloth(m, 'banner', xf @ (staff_top - V(0, .3, 0)), xf @ (staff_top + V(0, -.3, 4.8)), 6.5, bulge=.4, tear=.25, notch=.2,
          wind=xf.to_3x3() @ V(1.5, .5, 1.5), nu=8, nv=10)
    mp = mast(m, xf, hull_point(.3, 1, 0), 21, lean=(-.04, .02), yard_at=.66)
    for side in (-1, 1):
        rigging(m, xf @ hull_point(.22, 1.14, side, True, .1), xf @ (hull_point(.3, 1, 0) + V(0, 20, 0)), .7)
    top_deck = deck_at(0) + 6.0
    crew_on(m, xf, [(-1.5, top_deck, (.5 - .05) * L_SHIP, 3.1, 'stand'), (1.6, top_deck, (.5 - .07) * L_SHIP, 2.4, 'kneel'),
                    (0, deck_at(0) + 3.2, (.5 - .15) * L_SHIP, 3.3, 'reach'), (-2.5, deck_at(.3), (.5 - .3) * L_SHIP, .4, 'fallen'),
                    (2.1, deck_at(.36), (.5 - .36) * L_SHIP, 1.9, 'stand')])
    pts = [p for p in pts if p.y > -1.5]
    ice_collar(m, Matrix(), [p for p in pts if p.y < 1.5] or pts, 22, hull=pts)
    m.hulls.append(pts)
    m.hulls.append(mp)
    debris_field(m, rot(0, 0, 0, (0, 0, -16)), 12, 8)
    return m


@model
def wreck_deck():
    """A midships section sunk at one end: its deck is a ramp onto a raised,
    broken platform. Collision follows the deck, not the bulwarks."""
    m = Model('wreck_deck')
    s0, s1 = .3, .64
    length = (s1 - s0) * L_SHIP
    rise = 5.4
    pitch = math.atan2(rise, length)
    # The low (sternward, +Z) end's deck meets the ice; the bow end stands high.
    sink = -(D_SHIP) + .05
    xf = rot(0, pitch, 0, (0, 0, 0)) @ Matrix.Translation(V(0, sink, -(.5 - (s0 + s1) / 2) * L_SHIP))
    # Place so the low end of the deck sits at y = 0.
    low = xf @ V(0, D_SHIP, (.5 - s0) * L_SHIP)
    xf = Matrix.Translation(V(0, -low.y + .02, -low.z + length * .5 * math.cos(pitch))) @ xf
    galleon(m, xf, s0, s1, True, True, sheer=False, ribs_lo=True, ribs_hi=False)
    deck = []
    for s in (s0, s1):
        for x in (-1, 1):
            w = beam_at(s) * .9
            deck.append(xf @ V(x * w, D_SHIP, (.5 - s) * L_SHIP))
            deck.append(xf @ V(x * w, 0, (.5 - s) * L_SHIP))
    m.hulls.append([p if p.y > -2 else V(p.x, -2, p.z) for p in deck])
    # Deck clutter at the sides only, clear of the driving line.
    for s in (.36, .44, .52, .6):
        for side in (-1, 1):
            if R.random() < .6:
                c = xf @ V(side * beam_at(s) * .72, D_SHIP, (.5 - s) * L_SHIP)
                cannon(m, rot(math.pi / 2 * side, pitch, 0, tuple(c)))
    crew_on(m, xf, [(-4.2, D_SHIP, (.5 - .42) * L_SHIP, 1.2, 'kneel'), (4.0, D_SHIP, (.5 - .5) * L_SHIP, -1.5, 'stand'),
                    (-4.4, D_SHIP, (.5 - .58) * L_SHIP, 1.8, 'fallen')])
    stump = xf @ V(0, D_SHIP, (.5 - .47) * L_SHIP)
    m.beam('wood', stump + V(4.8, 0, 0), stump + V(4.8, 3.2, .4), .6, .5, sides=8)  # snapped mast
    cloth(m, 'banner', stump + V(4.8, 3.0, .4), stump + V(4.8, 3.0, 2.2), 4.2, bulge=.2, tear=.3, notch=.3, nu=4, nv=8)
    outline = [xf @ V(x * beam_at(s) * 1.02, 0, (.5 - s) * L_SHIP) for s in (s0, .4, .5, s1) for x in (-1, 1)]
    ice_collar(m, Matrix(), [p for p in outline if p.y < 2.5] or outline, 16)
    debris_field(m, rot(0, 0, 0, (0, 0, 16)), 10, 7)
    return m


@model
def wreck_keel():
    """A capsized hull stripped to its keel and frames: a ribcage arching out of
    the ice. Each frame collides on its own; the keel rides high above."""
    m = Model('wreck_keel')
    length = 30.0
    keel_h = 8.2
    frames = 11
    for i in range(frames):
        t = i / (frames - 1)
        z = (t - .5) * length
        arch = keel_h - 2.6 * (2 * t - 1) ** 2
        half = 6.0 * (1 - .45 * (2 * t - 1) ** 2)
        broken = R.random() < .25
        for side in (-1, 1):
            if broken and side > 0:
                continue
            pts = []
            prev = None
            cut = R.uniform(.65, 1.0) if R.random() < .4 else 1.0
            for k in range(8):
                a = k / 7 * cut
                x = side * half * math.sin(a * math.pi / 2) ** .7
                y = arch * math.cos(a * math.pi / 2) - 1.0 * a
                p = V(x, y - .6, z + R.uniform(-.05, .05))
                if prev is not None:
                    pts += m.beam('wood', prev, p, .32, .3, sides=4)
                prev = p
            if cut == 1.0:
                m.spike('wood', prev, prev + V(side * R.uniform(.2, .8), -1.6, 0), .3, sides=4)
            m.hulls.append([V(p.x, max(p.y, -1.2), p.z) for p in pts])
    # Keel and keelson, snapped at one end.
    spine = [V(0, keel_h - 2.6 * (2 * t - 1) ** 2 - .2, (t - .5) * length) for t in [i / 10 for i in range(11)]]
    for a, b in zip(spine, spine[1:]):
        m.beam('wood', a, b, .55, sides=4)
    m.hulls.append([p + V(dx, dy, 0) for p in spine[3:8] for dx in (-.6, .6) for dy in (-.6, .6)])
    # A few planks still clinging to the frames, painted in the fleet's colours.
    for side in (-1, 1):
        for k in range(3):
            a = .35 + k * .12
            zs = [(t - .5) * length for t in (R.uniform(.1, .3), R.uniform(.6, .85))]
            pts = []
            for z in zs:
                t = z / length + .5
                arch = keel_h - 2.6 * (2 * t - 1) ** 2
                half = 6.0 * (1 - .45 * (2 * t - 1) ** 2)
                for da in (0, .1):
                    aa = a + da
                    pts.append(V(side * (half * math.sin(aa * math.pi / 2) ** .7 + .3), arch * math.cos(aa * math.pi / 2) - aa - .6, z))
            m.solid('paint' if k == 0 else 'wood', pts + [p + V(side * .08, 0, 0) for p in pts])
    cloth(m, 'banner', V(-.2, keel_h - .6, -3), V(-.2, keel_h - .6, 1), 5.5, bulge=.3, tear=.3, notch=.25, nu=6, nv=10)
    icicles(m, spine[2], spine[8], 18, 2.2)
    crew_on(m, Matrix(), [(2.2, 0, 4, 2.6, 'kneel'), (-1.5, 0, -6, .3, 'fallen'), (0.5, 0, 9, 3.4, 'stand')])
    ice_collar(m, Matrix(), [V(s * 6 * (1 - .45 * (2 * t - 1) ** 2), 0, (t - .5) * length) for t in (0, .25, .5, .75, 1) for s in (-1, 1)], 14)
    debris_field(m, Matrix(), 12, 10)
    return m


@model
def wreck_mast():
    m = Model('wreck_mast')
    xf = rot(0, math.radians(-7), math.radians(4))
    mp = mast(m, xf, V(0, -4, 0), 30, lean=(0, 0), yard_at=.62)
    # A second, snapped topsail yard hangs by its lines.
    top = xf @ V(0, 22, 0)
    m.beam('wood', top + V(-5, -1, .6), top + V(4, -6, .6), .22, sides=6)
    cloth(m, 'sail', top + V(-4.6, -1.4, .9), top + V(-.5, -3.2, .9), 6, bulge=.6, tear=.55, nu=8, nv=8)
    for a in (0, 2.1, 4.2):
        rigging(m, xf @ V(0, 21, 0), V(math.cos(a) * 11, -.2, math.sin(a) * 11), 1.4)
    crew_on(m, xf, [(0.6, 18.6 + .1, -.4, 1.0, 'reach')])
    crew_on(m, Matrix(), [(3, 0, 2, 3.8, 'fallen'), (-2.5, 0, -2.5, .7, 'kneel')])
    base = [xf @ V(x, 0, z) for x in (-.8, .8) for z in (-.8, .8)]
    ice_collar(m, Matrix(), base, 12, height=2.2, hull=mp)
    m.hulls.append(mp)
    debris_field(m, Matrix(), 8, 7)
    return m


@model
def eye_vortex():
    """The eye, frozen mid-spin: serrated spiral terraces screwing down into the
    dark, and blades of frozen spray curling in over the drop."""
    m = Model('eye_vortex')
    nu, nv = 144, 26
    lip = 13.0

    def fn(u, v):
        a = u * math.tau
        depth = v
        teeth = abs(((a / math.tau * 20 - depth * 5) % 1) * 2 - 1)
        r = lip * (1 - depth) ** .62 + 1.0 + 1.0 * teeth * (1 - depth * .6)
        y = -.6 - depth * 44 - 1.4 * teeth * depth
        return V(math.cos(a) * r, y, math.sin(a) * r)
    verts = [fn(i / nu, j / nv) for j in range(nv + 1) for i in range(nu)]
    faces = []
    for j in range(nv):
        for i in range(nu):
            a = j * nu + i; b = j * nu + (i + 1) % nu
            faces.append((a, a + nu, b + nu, b))
    m.add('ice', verts, faces, tint=.2)
    for i in range(26):
        a = i * math.tau / 34 + R.uniform(-.05, .05)
        r0 = R.uniform(12.5, 14.5)
        h = R.uniform(1.2, 4.0)
        sweep = R.uniform(.25, .5)
        pts = []
        for t in (0, .5, 1):
            aa = a + sweep * t
            rr = r0 - t * t * R.uniform(2, 5)
            y = -2.5 + h * math.sin(t * math.pi * .7)
            for w in (-1, 1):
                pts.append(V(math.cos(aa + w * .025) * rr, y + w * .3, math.sin(aa + w * .025) * rr))
        pts.append(V(math.cos(a + sweep * 1.2) * (r0 - 6), -1 + h * .3, math.sin(a + sweep * 1.2) * (r0 - 6)))
        m.solid('ice', pts, tint=R.random())
    return m


@model
def ice_floe():
    m = Model('ice_floe')
    pts = []
    for j in range(9):
        a = j * math.tau / 9; r = R.uniform(3, 6)
        for y in (-1.2, .5):
            pts.append(V(math.cos(a) * r, y + R.uniform(-.2, .2), math.sin(a) * r))
    m.solid('ice', pts, tint=.6)
    return m


# --- Build and export -------------------------------------------------------

def box_uv(verts, face):
    p = [Vector(verts[i]) for i in face]
    n = Vector((0, 0, 0))
    for i in range(len(p)):
        a = p[i]; b = p[(i + 1) % len(p)]
        n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    ax = max(range(3), key=lambda k: abs(n[k]))
    if ax == 0:
        return [(q.z, q.y) for q in p]
    if ax == 1:
        return [(q.z, q.x) for q in p]
    return [(q.x, q.y) for q in p]


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0
    materials = {}
    for slot, c in PREVIEW.items():
        mat = bpy.data.materials.new('Maelstrom_' + slot)
        mat.use_nodes = True
        mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (*c, 1)
        mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .8
        materials[slot] = mat
    hulls = {}
    for fn in MODELS:
        m = fn()
        verts = []; faces = []; face_slots = []; uvs = []; cols = []
        slots = sorted(m.geo)
        for si, slot in enumerate(slots):
            g = m.geo[slot]
            off = len(verts)
            verts.extend(g['v'])
            for f, uv, c in zip(g['f'], g['uv'], g['c']):
                faces.append(tuple(off + k for k in f))
                face_slots.append(si)
                uvs.append(uv if uv is not None else box_uv(verts, faces[-1]))
                cols.append(c)
        # Realistic crags and seracs: their rock/ice faces are subdivided and
        # displaced with crisp noise (sharp macro form, weathered surface);
        # icicles, wood and cloth stay as authored.
        rough = next((v for k, v in DISPLACE.items() if m.name.startswith(k)), set())

        def build_mesh(name, include):
            # bmesh rather than from_pydata: it refuses duplicate or degenerate
            # faces instead of corrupting the mesh (Blender 4.0 crashed on them).
            bm = bmesh.new()
            bverts = [bm.verts.new((x, -z, y)) for x, y, z in verts]
            uv_layer = bm.loops.layers.uv.new('UVMap')
            color = bm.loops.layers.color.new('Col')
            for f, si, uv, c in zip(faces, face_slots, uvs, cols):
                if not include(slots[si]) or len(set(f)) < 3:
                    continue
                try:
                    face = bm.faces.new([bverts[i] for i in f])
                except ValueError:
                    continue
                face.material_index = si
                face.smooth = slots[si] in SMOOTH_SLOTS or slots[si] in rough
                for k, loop in enumerate(face.loops):
                    # glTF flips V; keep emblem UVs upright (v = 0 at the top).
                    loop[uv_layer].uv = (uv[k][0], 1 - uv[k][1]) if slots[si] in UV_SLOTS else uv[k]
                    loop[color] = (c[0], c[1], c[2], 1)
            bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if not v.link_faces], dist=0.0)
            for v in [v for v in bm.verts if not v.link_faces]:
                bm.verts.remove(v)
            mesh = bpy.data.meshes.new(name)
            bm.to_mesh(mesh)
            bm.free()
            for slot in slots:
                mesh.materials.append(materials[slot])
            return mesh
        mesh = build_mesh(m.name, lambda slot: slot not in rough)
        if rough:
            raw = build_mesh(m.name + '_raw', lambda slot: slot in rough)
            carved = bpy.data.objects.new(m.name + '_raw', raw)
            bpy.context.scene.collection.objects.link(carved)
            sub = carved.modifiers.new('detail', 'SUBSURF')
            sub.subdivision_type = 'SIMPLE'
            sub.levels = sub.render_levels = 3
            for name, kind, size, strength in (('mass', 'CLOUDS', 2.6, .55), ('chips', 'VORONOI', .7, .22)):
                tex = bpy.data.textures.new(m.name + name, kind)
                tex.noise_scale = size
                if kind == 'CLOUDS':
                    tex.noise_depth = 4
                else:
                    tex.distance_metric = 'DISTANCE'
                disp = carved.modifiers.new(name, 'DISPLACE')
                disp.texture = tex
                disp.texture_coords = 'GLOBAL'
                disp.strength = strength
                disp.mid_level = .5
            dec = carved.modifiers.new('budget', 'DECIMATE')
            dec.ratio = .55
            depsgraph = bpy.context.evaluated_depsgraph_get()
            detailed = bpy.data.meshes.new_from_object(carved.evaluated_get(depsgraph))
            bpy.data.objects.remove(carved)
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bm.from_mesh(detailed)
            bm.to_mesh(mesh)
            bm.free()
            mesh.use_auto_smooth = True
            mesh.auto_smooth_angle = math.radians(38)
        mesh.update()
        ob = bpy.data.objects.new(m.name, mesh)
        bpy.context.scene.collection.objects.link(ob)
        if m.hulls:
            out = []
            for pts in m.hulls:
                hv, _ = convex(pts)
                out.append([[round(c, 3) for c in p] for p in hv])
            hulls[m.name] = out
        print('built', m.name, len(verts), 'verts', len(faces), 'faces', len(m.hulls), 'hulls', flush=True)
    GLB.parent.mkdir(parents=True, exist_ok=True)
    HULLS.write_text(json.dumps(hulls, separators=(',', ':')) + '\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
    print('MAELSTROM KIT COMPLETE', flush=True)


build()
