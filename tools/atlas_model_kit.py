"""Shared Blender modelling helpers for Atlas attachment generators.

Construction helpers (lathed sections, lofts, bolts, rings, pierced faces) and
the approved Atlas material palette, copied from tools/build-atlas-turret.py so
new attachment generators build with the same language. Import after bpy.
Godot metres in the Atlas hull frame: X right, Y up, -Z forward; gv() maps
them into Blender's Z-up frame.
"""
import bpy, bmesh, math, json, struct
from mathutils import Vector, Matrix

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


def palette():
    """The approved Atlas V5 material classes (names keep the paint contract)."""
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
    pilot_lens = material('Atlas_PilotLens', (1.0, .45, .08), .05, .3, emission=4.0)
    arc_lens = material('Atlas_ArcLens', (.55, .7, 1.0), .05, .2, emission=3.5)
    white = material('Atlas_Stencil', (.83, .86, .8), .05, .49)

    names = {k: v for k, v in locals().items() if not k.startswith('_')}
    # Helpers (mesh, bolt) read paint, steel, oxidized and dark as globals.
    globals().update(names)
    return names

def descendants(obj):
    result = [obj]
    for ch in obj.children: result += descendants(ch)
    return result

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

def export_model(obj, filename, runtime):
    bpy.ops.object.select_all(action='DESELECT')
    for item in descendants(obj): item.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = runtime / filename
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_yup=True, export_apply=True, export_extras=True, export_animations=False, export_materials='EXPORT', export_texcoords=True, export_normals=True)
    # Reference the external canonical maps, as the hull GLB does.
    raw = path.read_bytes(); json_len = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_len]); binary = raw[20 + json_len + 8:]
    image_views = {im['bufferView'] for im in document.get('images', []) if 'bufferView' in im}
    for im in document.get('images', []):
        im.pop('bufferView', None); im.pop('mimeType', None); im['uri'] = im['name'] + '.png'
        if not (runtime / im['uri']).exists(): raise RuntimeError('Missing portable material ' + im['uri'])
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

