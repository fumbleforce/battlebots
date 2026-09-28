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
GRAIN_SLOTS = {'wood', 'deck', 'paint'}  # Box UVs follow the board's length.
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
        self.geo = defaultdict(lambda: {'v': [], 'f': [], 'uv': [], 'c': [], 'p': []})
        self.hulls = []
        # Breakable models: faces carry a part id; each part is also exported as
        # its own mesh (<model>__p<id>) so the game can break it into those parts.
        self.part = None

    def add(self, slot, verts, faces, uvs=None, tint=None, frost=0.0, color=None):
        g = self.geo[slot]
        off = len(g['v'])
        g['v'].extend(tuple(v) for v in verts)
        t = R.random() if tint is None else tint
        for i, f in enumerate(faces):
            g['f'].append(tuple(off + k for k in f))
            g['uv'].append(uvs[i] if uvs is not None else None)
            g['c'].append(color or (t, 1.0, frost))
            g['p'].append(self.part)

    def solid(self, slot, points, tint=None, frost=0.0, hull=False, grain=None, origin=None, v0=0.0):
        """Convex solid. With grain (a direction) its faces get UVs projected
        along it from origin, so solids sharing a grain and origin (a wall's
        panels, a beam's segments with running v0) carry the wood unbroken."""
        verts, faces = convex(points)
        uvs = grain_uvs(verts, faces, grain, origin or V(0, 0, 0), v0) if grain is not None else None
        self.add(slot, verts, faces, uvs, tint=tint, frost=frost)
        verts = [Vector(v) for v in verts]
        if hull:
            self.hulls.append(verts)
        return verts

    def box(self, slot, xf, size, centre=(0, 0, 0), tint=None, hull=False):
        cx, cy, cz = centre
        sx, sy, sz = (s * .5 for s in size)
        pts = [xf @ V(cx + a * sx, cy + b * sy, cz + c * sz) for a in (-1, 1) for b in (-1, 1) for c in (-1, 1)]
        return self.solid(slot, pts, tint=tint, hull=hull)

    def beam(self, slot, a, b, r0, r1=None, sides=6, tint=None, hull=False, spin=0.0, v0=0.0):
        """Faceted tapered prism from a to b (already placed), grain along its
        axis; chain segments with v0 = the run's length so far."""
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
        return self.solid(slot, pts, tint=tint, hull=hull, grain=d, origin=a, v0=v0)

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

GRAIN_U = .31  # UV per metre across the grain: one scan plank ~0.8 m, as on the hull.


def grain_uvs(verts, faces, grain, origin, v0):
    """Per-face UVs with the scan's planks along grain (v) and u across it in
    the face's plane; None for a face the grain runs into (box_uv covers it)."""
    out = []
    for f in faces:
        p = [Vector(verts[i]) for i in f]
        n = (p[1] - p[0]).cross(p[2] - p[0])
        g = Vector(grain).normalized()
        if n.length < 1e-9 or abs(n.normalized().dot(g)) > .7:
            out.append(None)
            continue
        n.normalize()
        g = (g - n * g.dot(n)).normalized()
        across = n.cross(g)
        out.append([((q - origin).dot(across) * GRAIN_U, (v0 + (q - origin).dot(g)) * PLANK_V) for q in p])
    return out


def rail(m, slot, points, size, tint=None, lift=0.0, flat=True):
    """A continuous square-section rail through points (flat top when flat),
    raised by lift so it rests on what it follows; grain runs unbroken."""
    run = 0.0
    for a, b in zip(points, points[1:]):
        m.beam(slot, a + V(0, lift, 0), b + V(0, lift, 0), size * .7071, sides=4, tint=tint,
               spin=math.pi / 4 if flat else 0.0, v0=run)
        run += (b - a).length


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


# Carvel planking: the strakes lie flush and share their edges, one continuous
# skin. Strake UVs (the wood scan's planks run along v): each strake shows one of
# the scan's nine planks seam to seam (seams at these pixels of its 1024 tile,
# the game samples it at 0.45 per UV unit), so the scan's seams fall exactly on
# the strakes' edges, and v is the same for every strake at a station, so the
# scan's nail rows line up down the hull like the fastenings on a frame.
SCAN_SEAMS = [62, 172, 286, 403, 516, 631, 746, 861, 973, 1086]
PLANK_V = .6  # Stretches the grain along the plank.
PLANK_STEP = .5  # Metres between stations along the hull (the bow curves fast).


def scan_plank(j):
    """UV u range of the scan's plank j, seam to seam."""
    return SCAN_SEAMS[j % 9] / 1024 / .45, SCAN_SEAMS[j % 9 + 1] / 1024 / .45


def stations(lo, hi, lo_u, hi_u):
    """Shared stations along the hull: every strake samples the same s grid, so
    neighbours meet vertex to vertex; only the ends (ragged at a break) differ."""
    step = PLANK_STEP / L_SHIP
    mid = [g * step for g in range(int(lo / step) + 1, int(math.ceil(hi / step))) if lo < g * step < hi]
    return [lo] + mid + [hi], [lo_u] + mid + [hi_u]


def deck_board(m, xf, lo, hi, x0, x1, sheer, plank, tint):
    """One deck board from lo to hi across x0..x1 (fractions of the half
    width inside the hull), 12 cm thick, one scan plank wide."""
    run, _ = stations(lo, hi, lo, hi)
    u0, u1 = scan_plank(plank)
    top = []
    for s in run:
        w = max(beam_at(s) * .92 - .02, 0.0)
        y = deck_at(s, sheer) - .06 + .12
        z = (.5 - s) * L_SHIP
        top.append((V(x0 * w, y, z), V(x1 * w, y, z), z * PLANK_V))
    down = V(0, -.12, 0)
    quads = []
    for (l0, r0, v0), (l1, r1, v1) in zip(top, top[1:]):
        if (r0 - l0).length < .03 and (r1 - l1).length < .03:
            continue
        quads.append(([l0, r0, r1, l1], [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]))
        quads.append(([r0, r0 + down, r1 + down, r1], [(u1, v0), (u1, v0 + .05), (u1, v1 + .05), (u1, v1)]))
        quads.append(([l1, l1 + down, l0 + down, l0], [(u0, v1), (u0, v1 + .05), (u0, v0 + .05), (u0, v0)]))
    for (l, r, v), flip in ((top[0], False), (top[-1], True)):  # end grain
        q = [l, l + down, r + down, r]
        uv = [(u0, v), (u0, v + .05), (u1, v + .05), (u1, v)]
        quads.append((q[::-1], uv[::-1]) if flip else (q, uv))
    for corners, uv in quads:
        m.add('deck', [xf @ c for c in corners], [(0, 1, 2, 3)], [uv], tint=tint)


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
            n = max(2, int((hi - lo) * L_SHIP / 1.3) + 1)  # collision outline samples
            # Splintered ends: the upper edge runs a little past the lower edge.
            lo_u = lo - (R.uniform(0, .02) if broken_lo else 0); hi_u = hi + (R.uniform(0, .025) if broken_hi else 0)
            # The collision outline keeps the old clinker lip (collision unchanged).
            clinker = .09 if wale else .05
            verts = []; outline = []; uv = []
            u0, u1 = scan_plank(k * 4 + (side > 0) * 2)
            lower, upper = stations(lo, hi, lo_u, hi_u)
            for s_lo, s_hi in zip(lower, upper):
                verts.append(xf @ hull_point(s_lo, q0, side, sheer))
                verts.append(xf @ hull_point(s_hi, q1, side, sheer))
                uv += [(u0, s_lo * L_SHIP * PLANK_V), (u1, s_hi * L_SHIP * PLANK_V)]
            for i in range(n + 1):
                t = i / n
                outline.append(xf @ hull_point(lo + (hi - lo) * t, q0, side, sheer, clinker))
                outline.append(xf @ hull_point(lo_u + (hi_u - lo_u) * t, q1, side, sheer, .0))
            faces = []
            for i in range(len(lower) - 1):
                a = i * 2
                faces.append((a, a + 2, a + 3, a + 1) if side > 0 else (a, a + 1, a + 3, a + 2))
            m.add(slot, verts, faces, [[uv[i] for i in f] for f in faces], tint=R.random() * .6 + (.4 if wale else 0))
            if q1 <= hull_q + 1e-6:
                hull_pts += outline[::2] + outline[1::2]
    # Keel, following the hull's rising forefoot, and at an unbroken bow the
    # stem post up to the bulwark: both close the seam where the sides meet.
    tint = R.random()
    keel, _ = stations(s0, s1, s0, s1)
    rail(m, 'wood', [xf @ hull_point(s, 0, 0) for s in keel], .5, tint=tint, flat=False)
    if s1 >= 1.0 and not broken_hi:
        rail(m, 'wood', [xf @ hull_point(1.0, top_q * i / 12, 0) for i in range(13)], .5, tint=tint, flat=False)
    # The wale: a heavy rubbing strake standing proud of the skin.
    q_wale = 1 - 4.0 / STRAKES
    for side in (-1, 1):
        lo = s0 + (.04 if broken_lo else 0); hi = s1 - (.05 if broken_hi else 0)
        run, _ = stations(lo, hi, lo, hi)
        rail(m, 'wood', [xf @ hull_point(s, q_wale, side, sheer, .09) for s in run], .18, tint=.9)
    # Gunwale caps: one continuous rail seated flat on the bulwark's top edge.
    # (It was straight 2.5 m segments; their random draws are kept so the rest
    # of the kit is unchanged.)
    for side in (-1, 1):
        n = max(2, int((s1 - s0) * L_SHIP / 2.5))
        lo = s0 + (.06 if broken_lo else 0); hi = s1 - (.05 if broken_hi else 0)
        run, _ = stations(lo, hi, lo, hi)
        tints = []
        for i in range(n):
            a = lo + (hi - lo) * i / n; b = lo + (hi - lo) * (i + 1) / n
            tints.append(R.random())
            if R.random() < .5:
                icicles(m, xf @ hull_point(a, top_q - .01, side, sheer, .2), xf @ hull_point(b, top_q - .01, side, sheer, .2), 3, 1.4)
        rail(m, 'wood', [xf @ hull_point(s, top_q, side, sheer) for s in run], .24, tint=tints[0], lift=.1)
    # Deck: planks along the ship, laid on the hull's stations so they follow
    # its sheer and fill out to the walls as the beam swells and narrows; the
    # ragged runs are only at the breaks. (The random draws are the ones the
    # old straight boards made, so everything after them is unchanged.)
    boards = 16
    for b in range(boards):
        u = (b + .5) / boards * 2 - 1
        lo = s0 + (R.uniform(.01, .09) if broken_lo else .01); hi = s1 - (R.uniform(.01, .1) if broken_hi else .01)
        short = R.random() < .12
        tint = R.random() if not short and beam_at(lo) * .93 >= .6 and beam_at(hi) * .93 >= .6 else .5
        if short:
            if broken_hi:
                hi -= .07 + .03 * (b % 3)  # a board torn short at the break
            elif broken_lo:
                lo += .07 + .03 * (b % 3)
        deck_board(m, xf, lo, hi, u - 1 / boards, u + 1 / boards, sheer, b * 5 + 3, tint)
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
                    # Laid in the hull's own frame (along the planks, up the
                    # side, out of the skin) so the port sits flush wherever
                    # the hull flares or curves toward the ends.
                    c = hull_point(s, .8, side, sheer)
                    e = .004
                    along = (hull_point(s - e, .8, side, sheer) - hull_point(s + e, .8, side, sheer)).normalized()
                    up = (hull_point(s, .8 + e, side, sheer) - hull_point(s, .8 - e, side, sheer)).normalized()
                    fr = along.cross(up).normalized()
                    if fr.x * side < 0:
                        fr = -fr
                    up = fr.cross(along).normalized() * (1 if up.y > 0 else -1)
                    at = lambda dy, dz, dd: xf @ (c + up * dy + along * dz + fr * dd)
                    m.solid('glass', [at(dy, dz, dd) for dy in (-.45, .45) for dz in (-.5, .5) for dd in (-.03, .03)])
                    for dy, dz, sy, sz in ((-.55, 0, .12, 1.2), (.55, 0, .12, 1.2), (0, -.6, 1.1, .12), (0, .6, 1.1, .12)):
                        m.solid('trim', [at(dy + a * sy * .5, dz + b * sz * .5, dd) for a in (-1, 1) for b in (-1, 1) for dd in (-.02, .09)])
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

def mast(m, xf, base, height, lean=(0, 0), yard_at=.7, sail=True, banner=True, nest=True, broken=True, parts=False):
    """A broken mast with a yard, torn sail, crow's nest and pennant. With parts,
    it breaks apart as: 0 the stump, 1 the upper mast with nest and pennant,
    2 the yard with its sail."""
    base = V(base)
    top = base + V(lean[0] * height, height, lean[1] * height)
    axis = (top - base).normalized()
    split = base.lerp(top, .35)
    if parts: m.part = 0
    m.beam('wood', xf @ base, xf @ split, .62, .55, sides=8)
    if parts: m.part = 1
    m.beam('wood', xf @ split, xf @ top, .55, .42, sides=8)
    if broken:
        for j in range(5):  # splintered top
            a = j * math.tau / 5
            p = top + V(math.cos(a) * .3, 0, math.sin(a) * .3)
            m.spike('wood', xf @ (p - axis * .3), xf @ (p + axis * R.uniform(.6, 1.8) + V(R.uniform(-.2, .2), 0, R.uniform(-.2, .2))), .16, sides=3)
    for y in (.25, .5, .85):  # iron hoops
        if parts: m.part = 0 if y < .35 else 1
        c = base.lerp(top, y)
        m.beam('iron', xf @ (c - axis * .1), xf @ (c + axis * .1), .68 - y * .2, sides=8)
    if parts: m.part = 2
    yard_c = base.lerp(top, yard_at)
    span = 9.5 * R.uniform(.85, 1.1)
    tilt = R.uniform(-.25, .25)
    yl = yard_c + V(-span, tilt * span, 0); yr = yard_c + V(span, -tilt * span, 0)
    m.beam('wood', xf @ yl, xf @ yr, .3, sides=6)
    icicles(m, xf @ yl, xf @ yr, 10, 1.6)
    if sail:
        cloth(m, 'sail', xf @ (yl + V(.4, -.3, .3)), xf @ (yr + V(-.4, -.3, .3)), height * yard_at * .62, bulge=1.3, tear=.45,
              wind=xf.to_3x3() @ V(0, 0, 1.2), nu=12, nv=12)
    if parts: m.part = 1
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
    if parts: m.part = None
    return [xf @ (base + V(x, 0, z)) for x in (-.7, .7) for z in (-.7, .7)] + [xf @ (top + V(x, 0, z)) for x in (-.5, .5) for z in (-.5, .5)]


def rigging(m, a, b, sag=.6):
    a = V(a); b = V(b); prev = a
    for i in range(1, 7):
        t = i / 6
        p = a.lerp(b, t) - V(0, sag * math.sin(math.pi * t), 0)
        m.beam('rope', prev, p, .05, sides=3)
        prev = p


# --- Crew ------------------------------------------------------------------

# They starved and froze over days: nobody is upright any more. Every pose lies
# on the ice: curled on the side, face down reaching out, on the back, or
# folded forward onto the knees with the face pressed to the ice.
POSES = {
    # Knees drawn up, arms locked round the shins, face on the knees (lain on its side: 'curl').
    'huddle': {'hip': (0, .28, .05), 'knee_l': (-.16, .72, -.33), 'knee_r': (.16, .72, -.33), 'foot_l': (-.16, .06, -.46),
               'foot_r': (.16, .06, -.46), 'chest': (0, .82, -.12), 'head': (0, .98, -.36), 'elbow_l': (-.36, .66, -.36),
               'elbow_r': (.36, .66, -.36), 'hand_l': (.1, .58, -.52), 'hand_r': (-.1, .6, -.5)},
    # Folded forward on the knees, face and forearms flat on the ice.
    'fold': {'hip': (0, .5, .32), 'knee_l': (-.16, .1, -.08), 'knee_r': (.16, .1, -.08), 'foot_l': (-.15, .06, .5),
             'foot_r': (.15, .06, .5), 'chest': (0, .38, -.34), 'head': (0, .16, -.66), 'elbow_l': (-.3, .1, -.62),
             'elbow_r': (.3, .1, -.64), 'hand_l': (-.28, .05, -.96), 'hand_r': (.26, .05, -.98)},
    # Stretched out, arms along the sides (laid on the back: 'supine').
    'lie': {'hip': (0, .92, 0), 'knee_l': (-.14, .48, .03), 'knee_r': (.15, .48, .02), 'foot_l': (-.18, 0, 0),
            'foot_r': (.18, 0, 0), 'chest': (0, 1.48, 0), 'head': (0, 1.68, -.03), 'elbow_l': (-.34, 1.2, .06),
            'elbow_r': (.34, 1.2, .06), 'hand_l': (-.38, .94, .04), 'hand_r': (.38, .94, .04)},
    # Arms reaching on past the head (laid face down: 'prone').
    'reach': {'hip': (0, .92, 0), 'knee_l': (-.15, .48, .03), 'knee_r': (.13, .5, .04), 'foot_l': (-.2, 0, 0),
              'foot_r': (.16, 0, .02), 'chest': (0, 1.48, 0), 'head': (0, 1.66, -.04), 'elbow_l': (-.32, 1.78, -.05),
              'elbow_r': (.3, 1.74, -.02), 'hand_l': (-.3, 2.04, -.06), 'hand_r': (.24, 2.0, -.02)},
}
POSE_ALIASES = {'stand': 'prone', 'lean': 'fold', 'kneel': 'fold', 'slump': 'fold', 'prayer': 'fold', 'reach': 'curl',
                'fallen': 'supine', 'huddle': 'curl'}


def figure(m, xf, pose='curl', scale=1.0):
    """A soldier who withered where they lay: thin iron-clad limbs, fleet
    tabard, iron helm, rimed with ice. A dropped shield beside some carries the
    fleet's emblem."""
    pose = POSE_ALIASES.get(pose, pose)
    base = {'curl': 'huddle', 'prone': 'reach', 'supine': 'lie'}.get(pose, pose)
    ground = xf  # the ice under them, before the body is laid down
    if pose == 'curl':
        xf = xf @ rot(0, 0, math.pi / 2 * R.choice([-1, 1]), (0, .3, 0))
    elif pose == 'prone':
        xf = xf @ rot(0, -math.pi / 2, R.uniform(-.1, .1), (0, .2, .9))
    elif pose == 'supine':
        xf = xf @ rot(0, math.pi / 2, R.uniform(-.1, .1), (0, .2, -.9))
    J = {k: V(v) * scale for k, v in POSES[base].items()}
    if pose == 'curl':
        J['hand_r'] = V(.15, 1.08, -.18) * scale
        J['elbow_r'] = V(.3, .98, -.12) * scale
    J = {k: v + V(R.uniform(-.03, .03), 0, R.uniform(-.03, .03)) for k, v in J.items()}
    thin = .75  # wasted limbs

    def P(v):
        return xf @ v
    side = V(1, 0, 0)
    up = (J['chest'] - J['hip']).normalized()
    fwd = side.cross(up).normalized()
    for s in ('l', 'r'):
        hip = J['hip'] + side * (-.12 if s == 'l' else .12)
        m.beam('iron', P(hip), P(J['knee_' + s]), .1 * thin, .09 * thin, sides=5)
        m.beam('iron', P(J['knee_' + s]), P(J['foot_' + s]), .09 * thin, .07 * thin, sides=5)
        m.solid('iron', [P(J['foot_' + s] + V(x, y, z)) for x in (-.06, .06) for y in (-.04, .06) for z in (-.15, .08)])
    torso = [J['hip'] + side * x + fwd * z for x in (-.18, .18) for z in (-.12, .12)]
    torso += [J['chest'] + side * x + fwd * z for x in (-.23, .23) for z in (-.13, .13)]
    torso += [J['hip'] - up * .22 + fwd * z for z in (-.14, .14)]
    m.solid('cloth', [P(p) for p in torso])  # tabard
    m.solid('iron', [P(J['chest'] + side * x + up * y + fwd * z) for x in (-.28, .28) for y in (-.07, .07) for z in (-.15, .15)])  # pauldrons
    h = J['head']
    m.solid('skin', [P(h + V(x, y, z)) for x in (-.1, .1) for y in (-.12, .12) for z in (-.11, .09)])
    m.solid('iron', [P(h + V(x, y, z)) for x in (-.13, .13) for y in (.04, .18) for z in (-.14, .13)] + [P(h + V(0, .28, 0))])  # helm
    for s in ('l', 'r'):
        shoulder = J['chest'] + side * (-.27 if s == 'l' else .27)
        m.beam('iron', P(shoulder), P(J['elbow_' + s]), .07 * thin, .06 * thin, sides=5)
        m.beam('iron', P(J['elbow_' + s]), P(J['hand_' + s]), .06 * thin, .05 * thin, sides=5)
        # Ice drips from the elbows, straight down whatever the pose.
        l = R.uniform(.08, .25)
        m.spike('ice', P(J['elbow_' + s]), P(J['elbow_' + s]) - V(0, l, 0), .03, sides=3)
    if R.random() < .45:
        # A dropped shield lying flat on the ice beside them.
        c = V(R.choice([-.9, .9]), .03, R.uniform(-.4, .4)) * scale
        flat = rot(0, -math.pi / 2, 0, tuple(c))
        m.sheet('banner', lambda u, v: ground @ flat @ V((u - .5) * .9, (.5 - v) * 1.1, .05 * math.sin(math.pi * u)), 4, 4)

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


ICE_ROOT = 7.0  # Metres an ice slab's root reaches down (the cone falls ~0.4 m/m).


def ice_collar(m, xf, points, count, height=1.6, hull=None, root=True):
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
        # The wreck sits level on a sloping cone: a root (drawn, not collided)
        # carries each slab down into the ice so none hangs over the downhill side.
        foot = [slab[i] for i in (0, 1, 4, 5)]  # the slab's lower edge
        if root:
            m.solid('ice', foot + [v - V(0, ICE_ROOT, 0) for v in foot], tint=.5)


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
        m.part = i
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
    m.part = None


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
    return m


def lantern(m, xf, at, size=1.0):
    """A ship's stern lantern on an iron bracket: a six-sided cage of iron posts
    round dark, frosted glass, a stepped base, a domed cap and a hanging ring."""
    at = V(at); r = .42 * size; h = 1.1 * size
    m.beam('iron', xf @ (at - V(0, 1.1 * size, .5 * size)), xf @ (at - V(0, .1 * size, 0)), .06, sides=4)
    m.beam('iron', xf @ (at - V(0, .15 * size, 0)), xf @ at, r * 1.05, r * .9, sides=6, spin=math.pi / 6)
    m.beam('glass', xf @ at, xf @ (at + V(0, h, 0)), r * .86, r * .96, sides=6, spin=math.pi / 6)
    for j in range(6):
        ang = math.pi / 6 + j * math.tau / 6
        d = V(math.cos(ang), 0, math.sin(ang))
        m.beam('iron', xf @ (at + d * r * .9), xf @ (at + d * r + V(0, h, 0)), .04 * size, sides=4)
    m.beam('iron', xf @ (at + V(0, h, 0)), xf @ (at + V(0, h + .12 * size, 0)), r * 1.12, r * 1.12, sides=6, spin=math.pi / 6)
    m.beam('trim', xf @ (at + V(0, h + .12 * size, 0)), xf @ (at + V(0, h + .5 * size, 0)), r * .95, r * .15, sides=6, spin=math.pi / 6)
    m.beam('trim', xf @ (at + V(0, h + .5 * size, 0)), xf @ (at + V(0, h + .7 * size, 0)), .05 * size, .05 * size, sides=4)
    for k in range(6):
        a0 = k * math.tau / 6; a1 = (k + 1) * math.tau / 6
        c = at + V(0, h + .82 * size, 0)
        m.beam('iron', xf @ (c + V(math.cos(a0), math.sin(a0), 0) * .12 * size), xf @ (c + V(math.cos(a1), math.sin(a1), 0) * .12 * size), .025 * size, sides=4)
    icicles(m, xf @ (at + V(-r, -.1, 0)), xf @ (at + V(r, -.1, 0)), 3, .5 * size)


@model
def wreck_stern():
    m = Model('wreck_stern')
    xf = rot(0, math.radians(-5), math.radians(-11), (0, -3.4, -5))
    pts = galleon(m, xf, 0.0, .42, False, True)
    # Stern castle: two raised decks and a gilded, windowed transom. Each tier
    # is a closed box: thick planked side walls standing on the tier below, a
    # deck laid into them and a bulkhead across its forward end with a doorway.
    wall = .28
    for lo, hi, base, top in ((0, .2, 0.0, 3.2), (0, .1, 3.2, 6.0)):
        for side in (-1, 1):
            n = 6
            for i in range(n):
                a = lo + (hi - lo) * i / n; b = lo + (hi - lo) * (i + 1) / n
                box = []
                for s_ in (a, b):
                    p = hull_point(s_, 1.0, side)
                    for inset in (0.0, wall):
                        for h in (base, top):
                            box.append(xf @ (p + V(-side * inset, h, 0)))
                # Planks run along the ship across all six panels and both tiers.
                pts += m.solid('paint', box, tint=.35, grain=xf.to_3x3() @ V(0, 0, 1), origin=xf @ V(0, 0, 0))
                if i % 2 == 1:
                    # A flat glazed window set into the wall, framed like a port.
                    c = hull_point((a + b) / 2, 1.0, side) + V(0, base + (top - base) * .55, 0)
                    m.solid('glass', [xf @ (c + V(side * dd, dy, dz)) for dy in (-.6, .6) for dz in (-.45, .45) for dd in (-.02, .04)])
                    frame_tint = None
                    for dy, dz, sy, sz in ((-.7, 0, .16, 1.1), (.7, 0, .16, 1.1), (0, -.55, 1.56, .16), (0, .55, 1.56, .16)):
                        m.solid('trim', [xf @ (c + V(side * dd, dy + u * sy * .5, dz + w * sz * .5)) for u in (-1, 1) for w in (-1, 1) for dd in (-.02, .1)],
                                tint=frame_tint)
                        frame_tint = .6
        deck_y = deck_at(0) + top
        w_lo = beam_at(lo) * .92 - wall; w_hi = beam_at(hi) * .92 - wall
        m.solid('deck', [xf @ V(x * w, deck_y - .15 + dy, (.5 - s_) * L_SHIP) for x in (-1, 1) for s_, w in ((lo, w_lo), (hi, w_hi)) for dy in (0, .15)],
                grain=xf.to_3x3() @ V(0, 0, 1), origin=xf @ V(0, 0, 0))
        # Forward bulkhead: vertical boards across the beam from the tier below
        # up to this deck, a doorway in the middle, a few boards split short.
        z = (.5 - hi) * L_SHIP
        y_lo = deck_at(0) + base; y_hi = deck_y
        width = beam_at(hi) * .92
        boards = 12
        for k in range(boards):
            x0 = -width + 2 * width * k / boards; x1 = x0 + 2 * width / boards - .04
            if abs((x0 + x1) / 2) < .8 and base == 0.0:
                m.box('wood', xf, (x1 - x0, .5, .2), ((x0 + x1) / 2, y_hi - .25, z))  # lintel over the door
                continue
            cut = R.uniform(.55, .85) if R.random() < .2 else 1.0
            m.solid('wood', [xf @ V(x, y, z + dz) for x in (x0, x1) for y in (y_lo, y_lo + (y_hi - y_lo) * cut) for dz in (-.1, .1)], tint=R.random(),
                    grain=xf.to_3x3() @ V(0, 1, 0), origin=xf @ V(0, 0, 0))
            if cut < 1.0:  # the split board's jagged top
                m.spike('wood', xf @ V((x0 + x1) / 2, y_lo + (y_hi - y_lo) * cut - .05, z), xf @ V((x0 + x1) / 2 + R.uniform(-.1, .1), y_lo + (y_hi - y_lo) * cut + R.uniform(.3, .7), z), .16, sides=4)
        m.beam('trim', xf @ V(-width, y_hi + .05, z), xf @ V(width, y_hi + .05, z), .14, sides=4)
        for side in (-1, 1):
            m.beam('trim', xf @ (hull_point(lo, 1, side) + V(-side * wall * .5, top + .9, 0)), xf @ (hull_point(hi, 1, side) + V(-side * wall * .5, top + .9, 0)), .1, sides=4)
            for s_ in (lo + (hi - lo) * t for t in (.1, .5, .9)):
                p = hull_point(s_, 1, side) + V(-side * wall * .5, 0, 0)
                m.beam('wood', xf @ (p + V(0, top, 0)), xf @ (p + V(0, top + .9, 0)), .08, sides=4)
            icicles(m, xf @ (hull_point(lo, 1, side) + V(side * .2, top, 0)), xf @ (hull_point(hi, 1, side) + V(side * .2, top, 0)), 8, 1.8)
    # The transom closes the stern flush with the planking and the castle: a
    # solid plate stacked in strips, each as wide as the hull's own section at
    # its height (the castle walls' outer face above the deck).
    transom_z = .5 * L_SHIP
    y0 = keel_at(0) + .3; y1 = deck_at(0) + 6.0

    def transom_half(y):
        k = keel_at(0); d = deck_at(0)
        if y >= d:
            return abs(hull_point(0, 1.0, 1).x)
        return abs(hull_point(0, max((y - k) / (d - k), .03), 1, True, .05).x)
    tw = transom_half(y1)
    # One continuous plate, planked athwartships: each band is one scan plank
    # seam to seam, and its end grain wraps round the edge into the hull side.
    # Collision keeps the original per-strip boxes.
    strips = 14
    back, front = transom_z - .3, transom_z + .12
    for i in range(strips):
        ya = y0 + (y1 - y0) * i / strips; yb = y0 + (y1 - y0) * (i + 1) / strips
        wa = transom_half(ya); wb = transom_half(yb)
        pts += [Vector(v) for v in convex([xf @ V(x * w, y, transom_z + dz) for x in (-1, 1) for y, w in ((ya, wa), (yb, wb)) for dz in (-.3, .12)])[0]]
        u0, u1 = scan_plank(i * 4 + 1)
        P = lambda x, y, z: xf @ V(x, y, z)
        quads = [  # (corners, their uvs): front, back, then each side edge
            ([P(-wa, ya, front), P(wa, ya, front), P(wb, yb, front), P(-wb, yb, front)],
             [(u0, -wa * PLANK_V), (u0, wa * PLANK_V), (u1, wb * PLANK_V), (u1, -wb * PLANK_V)]),
            ([P(wa, ya, back), P(-wa, ya, back), P(-wb, yb, back), P(wb, yb, back)],
             [(u0, wa * PLANK_V), (u0, -wa * PLANK_V), (u1, -wb * PLANK_V), (u1, wb * PLANK_V)])]
        for x in (-1, 1):
            corners = [P(x * wa, ya, back), P(x * wa, ya, front), P(x * wb, yb, front), P(x * wb, yb, back)]
            uv = [(u0, back * PLANK_V), (u0, front * PLANK_V), (u1, front * PLANK_V), (u1, back * PLANK_V)]
            quads.append((corners, uv) if x < 0 else (corners[::-1], uv[::-1]))  # outward winding
        if i == 0:
            quads.append(([P(-wa, ya, back), P(wa, ya, back), P(wa, ya, front), P(-wa, ya, front)], [(u0, 0)] * 4))
        if i == strips - 1:
            quads.append(([P(-wb, yb, front), P(wb, yb, front), P(wb, yb, back), P(-wb, yb, back)], [(u1, 0)] * 4))
        for corners, uv in quads:
            m.add('paint', corners, [(0, 1, 2, 3)], [uv], tint=.3 + .08 * (i % 3))
    face = transom_z + .12
    for row, y in enumerate((deck_at(0) + 1.4, deck_at(0) + 4.4)):
        for j in range(5):
            x = (j - 2) * tw * .38
            c = V(x, y, face)
            m.solid('glass', [xf @ (c + V(dx, dy, dz)) for dx in (-.55, .55) for dy in (-.7, .7) for dz in (0, .05)])
            m.solid('trim', [xf @ (c + V(dx, dy, dz)) for dx in (-.7, .7) for dy in (.75, .95) for dz in (0, .25)])
        w = transom_half(y - 1.1)
        m.beam('trim', xf @ V(-w, y - 1.1, face + .1), xf @ V(w, y - 1.1, face + .1), .18, sides=4)
    # The fleet's crest, carved and painted on the transom (banner UVs).
    c = V(0, deck_at(0) + 2.9, face + .08)
    m.sheet('banner', lambda u, v: xf @ (c + V((u - .5) * 3.2, (.5 - v) * 2.6, .1 * math.sin(math.pi * u))), 6, 6)
    for x in (-1.9, 1.9):  # stern lanterns on iron brackets, long gone dark
        lantern(m, xf, V(x * tw / 3, y1 + .2, face + .8))
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
    return m


KEEL_RIBS = []  # Frame offsets along the keel (m), exported with the hulls.


@model
def wreck_keel():
    """A capsized hull stripped to its keel and frames: a ribcage arching out of
    the ice. Each side of each frame is its own breakable model
    (keel_rib_N_l / _r, centred on its frame); the keel rides high above."""
    m = Model('wreck_keel')
    length = 30.0
    keel_h = 8.2
    frames = 11
    ribs = []
    for i in range(frames):
        t = i / (frames - 1)
        z = (t - .5) * length
        KEEL_RIBS.append(round(z, 3))
        arch = keel_h - 2.6 * (2 * t - 1) ** 2
        half = 6.0 * (1 - .45 * (2 * t - 1) ** 2)
        broken = R.random() < .25
        for side in (-1, 1):
            if broken and side > 0:
                continue
            # Each side of a frame breaks off on its own.
            rib = Model('keel_rib_%d_%s' % (i, 'l' if side < 0 else 'r'))
            pts = []
            prev = None
            cut = R.uniform(.65, 1.0) if R.random() < .4 else 1.0
            for k in range(8):
                a = k / 7 * cut
                x = side * half * math.sin(a * math.pi / 2) ** .7
                y = arch * math.cos(a * math.pi / 2) - 1.0 * a
                p = V(x, y - .6, R.uniform(-.05, .05))
                if prev is not None:
                    pts += rib.beam('wood', prev, p, .32, .3, sides=4)
                prev = p
            if cut == 1.0:
                rib.spike('wood', prev, prev + V(side * R.uniform(.2, .8), -1.6, 0), .3, sides=4)
            if R.random() < .5:
                icicles(rib, V(0, arch - .9, 0), V(side * half * .5, arch * .7, 0), 4, 1.4)
            rib.hulls.append([V(p.x, max(p.y, -1.2), p.z) for p in pts])
            ribs.append(rib)
    # Keel and keelson, snapped at one end.
    spine = [V(0, keel_h - 2.6 * (2 * t - 1) ** 2 - .2, (t - .5) * length) for t in [i / 10 for i in range(11)]]
    for a, b in zip(spine, spine[1:]):
        m.beam('wood', a, b, .55, sides=4)
    m.hulls.append([p + V(dx, dy, 0) for p in spine[3:8] for dx in (-.6, .6) for dy in (-.6, .6)])
    cloth(m, 'banner', V(-.2, keel_h - .6, -3), V(-.2, keel_h - .6, 1), 5.5, bulge=.3, tear=.3, notch=.25, nu=6, nv=10)
    icicles(m, spine[2], spine[8], 18, 2.2)
    ice_collar(m, Matrix(), [V(s * 6 * (1 - .45 * (2 * t - 1) ** 2), 0, (t - .5) * length) for t in (0, .25, .5, .75, 1) for s in (-1, 1)], 14)
    return [m] + ribs


@model
def ground_props():
    """Frozen crew and wreckage lying on the ice, one model each; the game seats
    them on the terrain around the wrecks."""
    out = []
    for pose in ('curl', 'prone', 'supine', 'fold'):
        for variant in range(2):
            m = Model('crew_%s_%d' % (pose, variant))
            figure(m, Matrix(), pose)
            out.append(m)
    m = Model('debris_plank')
    m.box('deck', rot(0, -.45, .1), (.35, .1, 3.6), (0, 0, 1.3))
    out.append(m)
    m = Model('debris_beam')
    m.beam('wood', V(0, -.4, 0), V(.5, 2.0, 1.1), .16, .07, sides=5)
    out.append(m)
    m = Model('debris_barrel')
    barrel(m, Matrix(), True)
    out.append(m)
    return out

@model
def wreck_mast():
    m = Model('wreck_mast')
    xf = rot(0, math.radians(-7), math.radians(4))
    # Breakable: it comes apart as stump, upper mast, yard and sail, topsail yard
    # and the ice collar round its foot. (Lines to the ice are gone: on the cone
    # they could not reach the ground everywhere.)
    mp = mast(m, xf, V(0, -4, 0), 30, lean=(0, 0), yard_at=.62, parts=True)
    # A second, snapped topsail yard hangs by its lines.
    m.part = 3
    top = xf @ V(0, 22, 0)
    m.beam('wood', top + V(-5, -1, .6), top + V(4, -6, .6), .22, sides=6)
    cloth(m, 'sail', top + V(-4.6, -1.4, .9), top + V(-.5, -3.2, .9), 6, bulge=.6, tear=.55, nu=8, nv=8)
    m.part = 1
    crew_on(m, xf, [(0.6, 18.6 + .1, -.4, 1.0, 'reach')])
    m.part = 4
    base = [xf @ V(x, 0, z) for x in (-.8, .8) for z in (-.8, .8)]
    ice_collar(m, Matrix(), base, 12, height=2.2, hull=mp, root=False)  # masts break apart
    m.part = None
    m.hulls.append(mp)
    return m


@model
def icicle_cluster():
    """A breakable clump of great icicles grown up out of the sheet, where spray
    froze as it fell."""
    m = Model('icicle_cluster')
    pts = []
    for i in range(6):
        m.part = i
        a = R.random() * math.tau; r = R.uniform(0, 1.3)
        base = V(math.cos(a) * r, -.4, math.sin(a) * r)
        h = R.uniform(1.8, 5.2) * (1.0 if i else 1.2)
        tip = base + V(math.cos(a) * R.uniform(.2, .9), h, math.sin(a) * R.uniform(.2, .9))
        pts += m.spike('ice', base, tip, R.uniform(.35, .7), sides=5)
    m.part = None
    m.hulls.append(pts)
    return m


@model
def barrel_prop():
    m = Model('barrel')
    for j in range(8):
        m.part = j // 2
        a0 = j * math.tau / 8; a1 = (j + .92) * math.tau / 8
        stave = []
        for a in (a0, a1):
            for y, r in ((0, .38), (.45, .46), (.9, .38)):
                for d in (0, -.05):
                    stave.append(V(math.cos(a) * (r + d), y, math.sin(a) * (r + d)))
        m.solid('wood', stave)
    for k, y in enumerate((.12, .78)):
        m.part = 4 + k
        m.beam('iron', V(0, y - .03, 0), V(0, y + .03, 0), .45, sides=8)
    m.part = 6
    m.beam('wood', V(0, .84, 0), V(0, .87, 0), .4, sides=8)
    m.part = None
    m.hulls.append([V(math.cos(j * math.tau / 8) * .47, y, math.sin(j * math.tau / 8) * .47) for j in range(8) for y in (0, .9)])
    return m


@model
def crate():
    m = Model('crate')
    size = 1.3
    for y in range(4):
        for k, z in enumerate((-1, 1)):
            m.part = k
            m.box('wood', Matrix(), (size, .3, .08), (0, .18 + y * .32, z * size / 2))
            m.part = 2 + k
            m.box('wood', Matrix(), (.08, .3, size), (z * size / 2, .18 + y * .32, 0))
    m.part = 4
    m.box('deck', Matrix(), (size, .08, size), (0, 1.3, 0))
    for k, (x, z) in enumerate(((-1, -1), (-1, 1), (1, -1), (1, 1))):
        m.part = 5 + k
        m.box('iron', Matrix(), (.12, 1.34, .12), (x * size / 2, .67, z * size / 2))
    m.part = None
    m.hulls.append([V(x * size * .52, y, z * size * .52) for x in (-1, 1) for y in (0, 1.36) for z in (-1, 1)])
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

def box_uv(verts, face, grain=False):
    """Metre box UVs. With grain (plank slots) v runs along the face's longer
    extent, so the wood scan's planks follow a board, wall or deck lengthwise."""
    p = [Vector(verts[i]) for i in face]
    n = Vector((0, 0, 0))
    for i in range(len(p)):
        a = p[i]; b = p[(i + 1) % len(p)]
        n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
    ax = max(range(3), key=lambda k: abs(n[k]))
    a, b = [(2, 1), (2, 0), (0, 1)][ax]
    if grain and max(q[a] for q in p) - min(q[a] for q in p) > max(q[b] for q in p) - min(q[b] for q in p):
        a, b = b, a
    return [(q[a], q[b]) for q in p]


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
    built = []
    for fn in MODELS:
        result = fn()
        built += result if isinstance(result, list) else [result]
    for m in built:
        verts = []; faces = []; face_slots = []; uvs = []; cols = []; parts = []
        slots = sorted(m.geo)
        for si, slot in enumerate(slots):
            g = m.geo[slot]
            off = len(verts)
            verts.extend(g['v'])
            for f, uv, c, part in zip(g['f'], g['uv'], g['c'], g['p']):
                parts.append(part)
                faces.append(tuple(off + k for k in f))
                face_slots.append(si)
                uvs.append(uv if uv is not None else box_uv(verts, faces[-1], slot in GRAIN_SLOTS))
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
            for f, si, uv, c, part in zip(faces, face_slots, uvs, cols, parts):
                if not include(slots[si], part) or len(set(f)) < 3:
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
        def assemble(name, keep):
            mesh = build_mesh(name, lambda slot, part: keep(part) and slot not in rough)
            if rough:
                carve(mesh, build_mesh(name + '_raw', lambda slot, part: keep(part) and slot in rough))
            mesh.update()
            return mesh

        def carve(mesh, raw):
            carved = bpy.data.objects.new(raw.name, raw)
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
        mesh = assemble(m.name, lambda part: True)
        ob = bpy.data.objects.new(m.name, mesh)
        bpy.context.scene.collection.objects.link(ob)
        # Breakable models also ship each part on its own (<model>__p<id>).
        for part in sorted({p for p in parts if p is not None}):
            piece = assemble('%s__p%d' % (m.name, part), lambda p, part=part: p == part)
            bpy.context.scene.collection.objects.link(bpy.data.objects.new(piece.name, piece))
        if m.hulls:
            out = []
            for pts in m.hulls:
                hv, _ = convex(pts)
                out.append([[round(c, 3) for c in p] for p in hv])
            hulls[m.name] = out
        print('built', m.name, len(verts), 'verts', len(faces), 'faces', len(m.hulls), 'hulls', flush=True)
    GLB.parent.mkdir(parents=True, exist_ok=True)
    hulls['_keel_ribs'] = KEEL_RIBS
    HULLS.write_text(json.dumps(hulls, separators=(',', ':')) + '\n')
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
    bpy.ops.export_scene.gltf(filepath=str(GLB), export_format='GLB', export_yup=True, export_texcoords=True,
                              export_normals=True, export_materials='EXPORT', export_cameras=False, export_lights=False)
    print('MAELSTROM KIT COMPLETE', flush=True)


build()
