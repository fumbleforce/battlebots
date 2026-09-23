"""Shared construction, bake, export and review for the nimble bots (#61).

Import after bpy inside one bot generator (tools/build-nimble-<bot>.py); run
each bot in its own Blender process. Coordinates are Godot metres in the bot's
source hull frame (X right, Y up, -Z forward); the runtime applies the factor
three once. Follow docs/art/STYLIZED_INDUSTRIAL_ASSETS.md: joined shells over
backing structure, real recesses, lathed/seated hardware, baked portable PBR.

Node contract consumed by battlebots/scripts/presentation/nimble_visual.gd:
- Hull (static). Limbs: Thigh<L>, Shin<L>, Foot<L> / Wheel<L> hang along -Y
  from their pivot (runtime points local -Y at the next joint); leg labels are
  L/R (biped) or FL/FR/BL/BR (quadruped).
- Arm: hammer arm pivot, geometry along -Z, rotates about local X.
- Wheel: monowheel tyre about local X. Coil (unit length along -Y) and Hub (pogo).
- GunFrame at (gun pivot - GUN_PIVOT) -> GunMount at GUN_PIVOT -> GunBarrels
  (spins about local Z through the barrel axis) and Muzzle.
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import atlas_model_kit as kit
from atlas_model_kit import part, mesh, prism, loft, box, cylinder, ring, turned, bolt, tube, gv, descendants, finalize, export_model

RUNTIME = ROOT / 'battlebots/assets/models/nimble_runtime'
PREVIEW = ROOT / 'battlebots/exports/nimble-preview'
DATA = json.loads((ROOT / 'battlebots/data/nimble_bots.json').read_text())['bots']
PARTS = {p['id']: p for p in json.loads((ROOT / 'battlebots/data/mvp_parts.json').read_text())['parts']}
SCALE = 3.0
GUN_PIVOT = Vector((0.66, 0.22, -0.42))
GUN_MUZZLE = Vector((0.66, 0.27, -1.72))
QUICK = '--quick' in sys.argv
NO_BAKE = '--no-bake' in sys.argv
NO_RENDER = '--no-render' in sys.argv
M = {}


def src(values):
    return Vector(values) / SCALE


def setup(prefix, palette, camo=None, stripes=None):
    """Fresh scene with this bot's own material classes, taken from its concept.

    palette maps each class to (sRGB colour, metallic, roughness). Required:
    primary, secondary (enamels), steel (machined), oxidized (worn dark metal),
    dark (recess floors), rubber, gun (ordnance steel), hazard (hazard enamel
    base), stencil, spring. Atlas values are only a calibration reference for
    how enamel, bare metal and rubber differ; the colours come from the concept.
    camo = {"colours": [sRGB...], "stops": [...], "scale": s} paints the primary
    enamel in world-space bands; stripes = {"width": m, "colour": sRGB,
    "axis": (x, y, z)} stripes the hazard enamel.
    """
    for path in (RUNTIME, PREVIEW):
        path.mkdir(parents=True, exist_ok=True)
    (PREVIEW / '.gdignore').write_text('')
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    kit.groups.clear()
    M.clear()
    m = kit.material
    def cls(name, key):
        colour, metal, rough = palette[key]
        return m(prefix + name, colour, metal, rough)
    # Baker families come from names: *PaintPrimary* / *PaintSecondary* are
    # enamel; lens/lamp/stencil keep their authored emission; the rest is hardware.
    M['paint'] = cls('_PaintPrimary', 'primary')
    M['paint_edge'] = cls('_PaintPrimaryEdge', 'primary')
    M['secondary'] = cls('_PaintSecondary', 'secondary')
    M['hazard'] = cls('_PaintSecondaryHazard', 'hazard')
    for key, name in (('steel', '_MachinedSteel'), ('oxidized', '_OxidizedMetal'), ('dark', '_Recess'),
                      ('rubber', '_Rubber'), ('gun', '_GunMetal'), ('spring', '_SpringSteel')):
        M[key] = cls(name, key)
    M['stencil'] = cls('_Stencil', 'stencil')
    if camo:
        for key in ('paint', 'paint_edge'):
            M[key]['atlas_camo'] = [list(c) for c in camo['colours']]
            M[key]['atlas_camo_stops'] = list(camo['stops'])
            M[key]['atlas_camo_scale'] = float(camo['scale'])
    if stripes:
        M['hazard']['atlas_stripes'] = float(stripes['width'])
        M['hazard']['atlas_stripe_color'] = list(stripes['colour'])
        M['hazard']['atlas_stripe_axis'] = list(stripes['axis'])
    for key, (colour, strength) in palette.get('lenses', {}).items():
        M[key] = m(prefix + '_Lens' + key.capitalize(), colour, .05, .28, emission=strength)
    # atlas_model_kit helpers (bevel edge material, bolts) read these module globals.
    kit.paint = M['paint']; kit.paint_edge = M['paint_edge']
    kit.steel = M['steel']; kit.oxidized = M['oxidized']; kit.dark = M['dark']
    return M


# ------------------------------------------------------------------ construction
def outline(w, d, c, dx=0.0, dz=0.0):
    """Plan-view rectangle with corner cuts c (must stay below half of w and d)."""
    x, z = w / 2, d / 2
    c = min(c, x * .95, z * .95)
    return [(dx + a, dz + b) for a, b in [(-x + c, -z), (x - c, -z), (x, -z + c), (x, z - c), (x - c, z), (-x + c, z), (-x, z - c), (-x, -z + c)]]


def rounded(w, d, r, n=4, dx=0.0, dz=0.0):
    """Plan-view rectangle with broad rounded corners (n segments per corner)."""
    x, z = w / 2 - r, d / 2 - r
    points = []
    for cx, cz, start in ((x, -z, -90), (x, z, 0), (-x, z, 90), (-x, -z, 180)):
        for i in range(n + 1):
            a = math.radians(start + 90 * i / n)
            points.append((dx + cx + math.cos(a) * r, dz + cz + math.sin(a) * r))
    return points


def shell(name, w, d, c, y0, y1, mat, group, top=(1.0, 1.0), at=(0.0, 0.0), top_shift=(0.0, 0.0), bevel=.012):
    base = outline(w, d, c, *at)
    lid = outline(w * top[0], d * top[1], c * min(top), at[0] + top_shift[0], at[1] + top_shift[1])
    return prism(name, base, y0, y1, mat, group, bevel, lid)


def section(name, profile, x0, x1, mat, group, bevel=.010):
    """Closed prism extruded along X from a (z, y) side profile: folded armour, wedges."""
    n = len(profile)
    verts = [(x0, y, z) for z, y in profile] + [(x1, y, z) for z, y in profile]
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    return mesh(name, verts, faces, mat, group, bevel)


def oriented(name, center, size, rotation, mat, group, bevel=.008):
    c = Vector(center); s = Vector(size) * .5
    corners = [c + rotation @ Vector((x * s.x, y * s.y, z * s.z)) for x, y, z in
               [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
    return mesh(name, [tuple(p) for p in corners], [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)], mat, group, bevel)


def frame(a, b):
    d = (Vector(b) - Vector(a)).normalized()
    side = Vector((1, 0, 0)) if abs(d.x) < .9 else Vector((0, 0, 1))
    up = d.cross(side).normalized(); side = up.cross(d).normalized()
    return Matrix((side, d, up)).transposed()


def beam(name, a, b, w, h, mat, group, bevel=.010):
    a = Vector(a); b = Vector(b)
    return oriented(name, (a + b) / 2, (w, (b - a).length, h), frame(a, b), mat, group, bevel)


def hub(name, p, axis, r, width, group, cap=True):
    """Bearing housing with machined collars and a domed, recessed centre."""
    d = Vector(axis).normalized(); p = Vector(p)
    cylinder(name + ' bearing housing', p - d * width / 2, p + d * width / 2, r, M['secondary'], group, 32, .004)
    for s in (-1, 1):
        turned(name + ' machined collar', p + d * s * width / 2, d * s,
               [(0, r * .86), (.006, r * .86), (.012, r * .74), (.016, r * .52), (.020, r * .40), (.020, r * .22)], M['steel'], group, 32)
        if cap:
            turned(name + ' domed cap', p + d * s * (width / 2 + .012), d * s, [(0, r * .3), (.008, r * .26), (.013, r * .12), (.014, 0.0)], M['oxidized'], group, 24)


def lens(name, p, axis, r, mat, group, pocket=True):
    """Inset lens in a protective pocket with a bezel ring."""
    d = Vector(axis).normalized(); p = Vector(p)
    if pocket:
        turned(name + ' pocket', p - d * .022, d, [(0, r * 1.55), (.03, r * 1.55), (.034, r * 1.3), (.012, r * 1.18)], M['secondary'], group, 32)
    turned(name + ' bezel', p - d * .008, d, [(0, r * 1.2), (.012, r * 1.2), (.016, r * 1.05), (.010, r * 1.0)], M['steel'], group, 32)
    turned(name, p - d * .004, d, [(0, r), (.004, r * .95), (.008, r * .7), (.010, r * .3), (.0105, 0.0)], mat, group, 32)


def vent(name, center, w, h, depth, slats, group, face=(0, 0, -1)):
    """A real recessed louvre: aperture walls, dark floor and angled slats (on a -Z or ±X face)."""
    c = Vector(center); f = Vector(face).normalized()
    across = Vector((1, 0, 0)) if abs(f.x) < .5 else Vector((0, 0, 1))
    up = Vector((0, 1, 0))
    rot = Matrix((across, up, f)).transposed()
    wall = .006
    oriented(name + ' floor', c - f * depth, (w, h, .006), rot, M['dark'], group, .001)
    for s in (-1, 1):
        oriented(name + ' side wall', c + across * s * (w / 2 + wall / 2) - f * depth / 2, (wall, h + 2 * wall, depth), rot, M['secondary'], group, .001)
        oriented(name + ' lip', c + up * s * (h / 2 + wall / 2) - f * depth / 2, (w + 2 * wall, wall, depth), rot, M['secondary'], group, .001)
    for i in range(slats):
        y = -h / 2 + h * (i + .5) / slats
        oriented(name + ' slat', c + up * y - f * depth * .45, (w - .004, .006, depth * .9), rot @ Matrix.Rotation(-.55, 3, 'X'), M['secondary'], group, .001)


STENCIL_EULER = {'+x': (90, 0, 90), '-x': (90, 0, -90), 'front': (90, 0, 180), 'top': (0, 0, 0)}


def stencil_text(text, at, face, size, group, mat=None):
    """Raised stencil numerals on a hull face: '+x', '-x', 'front' (-Z) or 'top'."""
    curve = bpy.data.curves.new('Stencil ' + text, 'FONT'); curve.body = text; curve.size = size
    curve.extrude = .0015; curve.align_x = 'CENTER'; curve.align_y = 'CENTER'
    obj = bpy.data.objects.new('Stencil ' + text, curve); bpy.context.collection.objects.link(obj)
    obj.rotation_euler = tuple(math.radians(a) for a in STENCIL_EULER[face])
    obj.location = gv(at)
    bpy.context.view_layer.objects.active = obj; bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True)
    bpy.ops.object.convert(target='MESH'); obj = bpy.context.object
    obj.data.materials.clear(); obj.data.materials.append(mat or M['stencil'])
    uv = obj.data.uv_layers.new(name='UVMap')
    kit.groups[group].append(obj)
    return obj


def coil(name, top, length, radius, wire, turns, mat, group, n=12, steps=40):
    """Helical spring from `top` down `length` along -Y with ground end coils."""
    top = Vector(top); verts = []; faces = []
    total = int(turns * steps)
    for i in range(total + 1):
        t = i / total; a = t * turns * math.tau
        # Closed, flattened end coils like a real compression spring.
        pitch_t = min(1.0, max(0.0, (t - .06) / .88))
        c = top + Vector((math.cos(a) * radius, -pitch_t * length, math.sin(a) * radius))
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


def tyre(name, center, radius, width, lugs, group, rim_ratio=.64, lug_depth=.04, spokes=6):
    """Lathed carcass with shoulders, staggered chevron lugs, dished rim, spoked hub, lug nuts."""
    c = Vector(center); r0 = radius - lug_depth; inner = radius * rim_ratio
    for s in (-1, 1):
        turned(name + ' carcass half', c, (s, 0, 0),
               [(0, r0), (width * .38, r0), (width * .46, r0 - .012), (width * .5, r0 - .03), (width * .5, inner + .012), (width * .47, inner)],
               M['rubber'], group, 64, open_end=True)
    for i in range(lugs):
        a = i * math.tau / lugs
        for s in (-1, 1):
            rot = Matrix.Rotation(a + s * math.pi / lugs * .5, 3, 'X')
            p = c + rot @ Vector((s * width * .24, r0 + lug_depth * .5, 0))
            oriented(name + ' chevron lug', p, (width * .46, lug_depth, math.tau * radius / lugs * .55),
                     rot @ Matrix.Rotation(s * .32, 3, 'Y'), M['rubber'], group, .006)
    turned(name + ' rim barrel', c + Vector((-width * .44, 0, 0)), (1, 0, 0), [(0, inner), (width * .88, inner)], M['secondary'], group, 48, open_end=True)
    for s in (-1, 1):
        turned(name + ' rolled rim', c + Vector((s * width * .44, 0, 0)), (s, 0, 0), [(0, inner - .006), (.012, inner + .004), (.016, inner - .01)], M['steel'], group, 48, open_end=True)
    turned(name + ' dish', c + Vector((-width * .30, 0, 0)), (1, 0, 0), [(0, inner - .008), (.03, inner * .8), (.07, inner * .45), (.08, inner * .3), (.08, 0.0)], M['oxidized'], group, 48)
    for i in range(spokes):
        a = i * math.tau / spokes
        p0 = c + Matrix.Rotation(a, 3, 'X') @ Vector((-width * .2, inner * .32, 0))
        p1 = c + Matrix.Rotation(a, 3, 'X') @ Vector((-width * .3, inner * .9, 0))
        beam(name + ' forged spoke', p0, p1, .03, .045, M['secondary'], group, .006)
    turned(name + ' hub cap', c + Vector((-width * .3 - .005, 0, 0)), (-1, 0, 0), [(0, inner * .3), (.02, inner * .28), (.032, inner * .16), (.036, 0.0)], M['steel'], group, 32)
    for i in range(6):
        a = i * math.tau / 6
        bolt(c + Vector((-width * .3 - .002, math.cos(a) * inner * .22, math.sin(a) * inner * .22)), (-1, 0, 0), group, r=max(.008, inner * .045))


def minigun(pivot, barrels, radius, group_root, housing_mat, barrel_r=.024):
    """Rotary gun on the shared Scorpion gun frame (see module docstring)."""
    pivot = Vector(pivot)
    frame_node = part('GunFrame', tuple(pivot - GUN_PIVOT), group_root)
    mount = part('GunMount', tuple(pivot), frame_node)
    muzzle = pivot + (GUN_MUZZLE - GUN_PIVOT)
    axis_y = muzzle.y
    barrel_end = muzzle.z
    # Receiver: folded housing with a feed chute, trunnions and a motor can.
    section('Gun receiver', [(pivot.z + .18, pivot.y - .08), (pivot.z + .18, pivot.y + .08), (pivot.z + .06, pivot.y + .12),
                             (pivot.z - .30, pivot.y + .12), (pivot.z - .36, pivot.y + .06), (pivot.z - .36, pivot.y - .07),
                             (pivot.z - .30, pivot.y - .10), (pivot.z + .10, pivot.y - .10)], pivot.x - .09, pivot.x + .09, housing_mat, mount, .012)
    turned('Gun motor can', Vector((pivot.x, axis_y, pivot.z + .17)), (0, 0, 1), [(0, .07), (.08, .07), (.09, .055), (.095, .03)], M['secondary'], mount, 32)
    box('Gun feed chute', (pivot.x + .10, pivot.y - .02, pivot.z - .08), (.05, .10, .22), M['secondary'], mount, .006)
    hub('Gun trunnion', pivot, (1, 0, 0), .055, .22, mount)
    rotor = part('GunBarrels', (pivot.x, axis_y, pivot.z - .32), mount)
    length = abs(barrel_end - (pivot.z - .32))
    for i in range(barrels):
        a = i * math.tau / barrels
        off = Vector((math.cos(a) * radius, math.sin(a) * radius, 0))
        turned('Gun barrel', Vector((pivot.x, axis_y, pivot.z - .32)) + off, (0, 0, -1),
               [(0, barrel_r * 1.2), (.04, barrel_r * 1.2), (.05, barrel_r), (length - .01, barrel_r), (length, barrel_r * .9)],
               M['gun'], rotor, 20, open_end=True)
    for z in (pivot.z - .40, (pivot.z - .32 + barrel_end) * .5, barrel_end + .06):
        turned('Gun barrel clamp', Vector((pivot.x, axis_y, z + .02)), (0, 0, -1),
               [(0, radius + barrel_r + .012), (.04, radius + barrel_r + .012), (.045, radius + barrel_r)], M['secondary'], rotor, 32)
    turned('Gun muzzle shroud', Vector((pivot.x, axis_y, barrel_end + .03)), (0, 0, -1),
           [(0, radius + barrel_r + .02), (.03, radius + barrel_r + .02), (.035, radius + barrel_r + .005)], M['steel'], rotor, 32, open_end=True)
    part('Muzzle', tuple(muzzle), mount)
    return frame_node, mount, rotor


# ------------------------------------------------------------------ bake, export, review
def complete(root, chassis, prefix, moving, poses=None, sizes=None, face_wear=.74):
    """Finalize assemblies, audit clearance, bake portable maps, export and render.

    moving: assemblies isolated during the occlusion bake (limbs, wheels, gun,
    arm), so no stationary shadow travels with them. poses: {label: callable(t)}
    that poses the assemblies for t in [0, 1] for the clearance audit.
    """
    for group in [g for g in list(kit.groups) if g in descendants(root)]:
        finalize(group)
    audit = clearance(root, moving, poses or {})
    print('NIMBLE_CLEARANCE', chassis, json.dumps(audit))
    surface = {'skipped': True}
    if not NO_BAKE:
        from atlas_surface_bake import bake_surface_atlases
        anchor = bpy.data.objects.new(prefix + 'BakeAnchor', None); bpy.context.collection.objects.link(anchor)
        surface = bake_surface_atlases(root, anchor, moving, RUNTIME, quick=QUICK, prefix=prefix, face_wear=face_wear,
                                       families=('Primary', 'Secondary', 'Hardware'),
                                       sizes=sizes or {'Primary': 2048, 'Secondary': 1024, 'Hardware': 2048},
                                       primary_color=tuple(M['paint'].diffuse_color))
        bpy.data.objects.remove(anchor, do_unlink=True)
    tris = 0
    for o in descendants(root):
        if o.type == 'MESH':
            o.data.calc_loop_triangles(); tris += len(o.data.loop_triangles)
    export_model(root, chassis + '.glb', RUNTIME)
    manifest = {'id': chassis, 'runtime': chassis + '.glb', 'generator': 'tools/build-nimble-%s.py' % chassis.split('_')[0],
                'authoring': 'Godot metres in the hull frame, X right Y up -Z forward; runtime factor three applied by NimbleVisual',
                'triangles': tris, 'nodes': sorted(o.name for o in descendants(root) if o.type == 'EMPTY'),
                'clearance': audit, 'surface_atlases': surface, 'approval': 'Pending user visual approval'}
    (RUNTIME / (chassis + '_manifest.json')).write_text(json.dumps(manifest, indent=2) + '\n')
    print('NIMBLE_EXPORT', chassis, tris)
    if not NO_RENDER:
        review(root, chassis)


def _tree(objs):
    verts = []; polys = []
    dg = bpy.context.evaluated_depsgraph_get()
    for o in objs:
        ev = o.evaluated_get(dg); m = ev.to_mesh()
        off = len(verts); verts += [o.matrix_world @ v.co for v in m.vertices]
        polys += [[off + i for i in p.vertices] for p in m.polygons]; ev.to_mesh_clear()
    return BVHTree.FromPolygons(verts, polys) if polys else None


def clearance(root, moving, poses):
    """Sampled triangle overlap of each moving assembly against the hull over its poses."""
    hull = [o for o in descendants(root) if o.type == 'MESH' and not any(o in descendants(g) for g in moving)]
    hull_tree = _tree(hull)
    rest = {g: g.matrix_basis.copy() for g in moving}
    report = {'scope': 'Sampled triangle overlap of moving assemblies against the static hull at 5 poses each; not continuous clearance.', 'contacts': {}}
    for label, pose in poses.items():
        for t in (0.0, .25, .5, .75, 1.0):
            pose(t); bpy.context.view_layer.update()
            for g in moving:
                objs = [o for o in descendants(g) if o.type == 'MESH']
                tree = _tree(objs)
                if tree and hull_tree:
                    count = len(tree.overlap(hull_tree))
                    if count: report['contacts']['%s@%.2f:%s' % (label, t, g.name)] = count
        for g, m in rest.items(): g.matrix_basis = m
    bpy.context.view_layer.update()
    report['clear'] = not report['contacts']
    return report


def review(root, chassis, ride=None):
    """Studio views like the Atlas review: hero, rear, side, top and a close-up."""
    ride = ride if ride is not None else DATA[chassis]['ride_height'] / SCALE
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
    scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.65, .69, .75, 1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value = .25
    cam_data = bpy.data.cameras.new('NimbleCamera'); cam = bpy.data.objects.new('NimbleCamera', cam_data)
    bpy.context.collection.objects.link(cam); scene.camera = cam
    scene.render.engine = 'CYCLES'; scene.cycles.samples = 24 if QUICK else 64; scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences; prefs.compute_device_type = 'OPTIX'; prefs.get_devices()
        for device in prefs.devices: device.use = device.type == 'OPTIX'
        scene.cycles.device = 'GPU'
    except Exception:
        pass
    scene.render.resolution_x = 1400; scene.render.resolution_y = 1100
    scene.view_settings.view_transform = 'AgX'
    root.location = gv((0, ride, 0)); bpy.context.view_layer.update()
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0)); bpy.context.object.data.materials.append(floor)
    centre = (0, ride * .6, 0)
    views = {'hero': ((2.4, ride + 1.2, -3.0), 2.9), 'rear': ((-2.2, ride + 1.0, 3.0), 2.9), 'side': ((4.0, ride * .6, 0), 2.8),
             'top': ((0.01, ride + 4.0, 0), 2.6), 'closeup': ((1.1, ride + .45, -1.4), 1.25)}
    for name, (at, ortho) in views.items():
        cam.location = gv(at)
        target = centre if name != 'closeup' else (0, ride, -.2)
        cam.rotation_euler = (gv(target) - cam.location).to_track_quat('-Z', 'Y').to_euler()
        cam_data.type = 'ORTHO'; cam_data.ortho_scale = ortho
        scene.render.filepath = str(PREVIEW / ('%s_%s.png' % (chassis, name)))
        bpy.ops.render.render(write_still=True)
    print('NIMBLE_REVIEW', chassis, str(PREVIEW))
