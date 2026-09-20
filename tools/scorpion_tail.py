"""Reference-shaped articulated forging and telescoping Scorpion tail.

Called as build(globals()) by build-scorpion.py. Coordinates are source Godot
metres; the shared ScorpionGeometry resource applies the same four hinge angles
and 0.22 m extension. No scene operators/export side effects live in this module.
"""


def build(ns):
    Vector = ns['Vector']
    Matrix = ns['Matrix']
    math = ns['math']
    bpy = ns['bpy']
    part, mesh, beam = (ns[k] for k in ('part', 'mesh', 'beam'))
    cylinder, ring, bolt, tube, joint = (ns[k] for k in ('cylinder', 'ring', 'bolt', 'tube', 'joint'))
    orange, dark, steel, chrome, rubber, hazard = (ns[k] for k in ('orange', 'dark', 'steel', 'chrome', 'rubber', 'hazard'))
    tail0, tail1, tail2, hammer = (ns[k] for k in ('tail0', 'tail1', 'tail2', 'hammer'))
    pivots = [Vector(p) for p in ((0, .22, .68), (0, .98, .95), (0, 1.73, .28), (0, 1.51, -.88))]
    head_center = Vector((0, 1.25, -1.12))

    def hammer_material(name, striped=False):
        # Dedicated forging maps keep edge wear patchy and physically readable.
        # The narrow/tall face uses metre-proportional hazard coordinates: square
        # UV stripes would compress into vertical pinstripes on this insert.
        np = ns['np']
        u, v, grain = (ns[k] for k in ('u', 'v', 'grain'))
        edge = np.minimum.reduce([u, v, 1 - u, 1 - v])
        rng = np.random.default_rng(9018)

        def smooth_noise(cells):
            # Nonperiodic low-frequency alloy/oxide variation. Trigonometric
            # interference looked like woven fabric across the broad cheeks.
            grid = rng.uniform(-1, 1, (cells, cells))
            samples = np.linspace(0, cells - 1, u.shape[0])
            coords = np.arange(cells)
            rows = np.array([np.interp(samples, coords, row) for row in grid])
            return np.array([np.interp(samples, coords, rows[:, col]) for col in range(u.shape[0])]).T

        mottle = smooth_noise(5) * .60 + smooth_noise(13) * .30 + smooth_noise(37) * .10
        edge_islands = smooth_noise(31)
        broken_edge = edge < (.004 + .012 * (smooth_noise(19) * .5 + .5))
        broken_edge &= (edge_islands > .10) & (grain > .18)
        scuffs = ns['scratches'] & (grain > .48)
        wear = broken_edge | scuffs
        base = (.94, .66, .07) if striped else (.215, .205, .180)
        color = np.ones((*u.shape, 3), dtype=np.float32) * np.array(base, dtype=np.float32)
        color *= (1.0 + mottle[:, :, None] * .16 + (grain[:, :, None] - .5) * .022)
        if striped:
            bands = (((u * .28 + v * .55) / .22) % 1) < .45
            color[bands] = np.array((.085, .079, .065)) * (1 + mottle[bands, None] * .20)
        color[wear] = np.array((.53, .515, .475)) * (.78 + grain[wear, None] * .38)
        # A handful of warm oxide marks occupies valleys, never an all-over rust
        # overlay or a uniform silver border around every bevel.
        oxide = (mottle < -.46) & (grain < .35) & ~wear
        color[oxide] *= np.array((.76, .56, .40))
        mr = np.ones((*u.shape, 3), dtype=np.float32)
        mr[:, :, 1] = .47 + mottle * .06 + (grain - .5) * .02
        mr[:, :, 2] = .78 if striped else .89
        mr[wear, 1] = .28 + grain[wear] * .07
        mr[wear, 2] = .95
        height = (grain - .5) * .003
        height[wear] -= .022
        dx = (np.roll(height, 1, 1) - np.roll(height, -1, 1)) * .65
        dy = (np.roll(height, 1, 0) - np.roll(height, -1, 0)) * .65
        normal = np.stack([.5 + dx, .5 + dy, np.ones_like(grain)], 2)
        images = [ns['save_image'](name + '_base', color),
                  ns['save_image'](name + '_orm', mr, True),
                  ns['save_image'](name + '_normal', normal, True)]
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        nodes, links = mat.node_tree.nodes, mat.node_tree.links
        bs = nodes.get('Principled BSDF')
        for image, kind in zip(images, ('albedo', 'orm', 'normal')):
            image_node = nodes.new('ShaderNodeTexImage')
            image_node.image = image
            if kind == 'albedo': links.new(image_node.outputs['Color'], bs.inputs['Base Color'])
            elif kind == 'orm':
                split = nodes.new('ShaderNodeSeparateColor')
                links.new(image_node.outputs['Color'], split.inputs['Color'])
                links.new(split.outputs['Green'], bs.inputs['Roughness'])
                links.new(split.outputs['Blue'], bs.inputs['Metallic'])
            else:
                normal_node = nodes.new('ShaderNodeNormalMap')
                normal_node.inputs['Strength'].default_value = .25
                links.new(image_node.outputs['Color'], normal_node.inputs['Color'])
                links.new(normal_node.outputs['Normal'], bs.inputs['Normal'])
        return mat

    forging_material = hammer_material('Scorpion_ForgedHammer')
    hammer_hazard = hammer_material('Scorpion_HammerHazard', True)

    # This extra transform carries the moving ram, its clevis and the head.
    # HammerHead retains its independent levelling hinge at a zero local offset.
    extension = part('TailExtension', pivots[3], tail2)
    hammer_world = hammer.matrix_world.copy()
    hammer.parent = extension
    hammer.matrix_parent_inverse = Matrix.Identity(4)
    hammer.matrix_world = hammer_world
    bpy.context.view_layer.update()
    ns['tail_extension'] = extension

    def prism(name, outline, axis, low, high, mat, group, bevel=.008):
        # outline is a world-space ring; extrusion direction need not be vertical.
        axis = Vector(axis)
        verts = [tuple(Vector(p) + axis * d) for d in (low, high) for p in outline]
        n = len(outline)
        faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
        faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        return mesh(name, verts, faces, mat, group, bevel)

    def cheek(name, a, b, side, group, depth=.26, end_fraction=.89):
        direction = (b - a).normalized()
        normal = direction.cross(Vector((1, 0, 0))).normalized()
        length = (b - a).length
        # Long chamfers at the shoulders, narrowed pin ends and a proud centre
        # make the plates read as cast machinery instead of rectangular rails.
        contour = [(.12, -.28), (.18, -.50), (end_fraction - .10, -.50),
                   (end_fraction, -.26), (end_fraction, .27),
                   (end_fraction - .095, .48), (.20, .50), (.12, .24)]
        points = [a + direction * (t * length) + normal * (h * depth) for t, h in contour]
        low, high = sorted((side * .119, side * .186))
        prism(name, points, (1, 0, 0), low, high, orange, group, .012)
        for fraction in (.23, .49, end_fraction - .12):
            for offset in (-.084, .084):
                bolt(a + direction * (fraction * length) + normal * offset
                     + Vector((side * .188, 0, 0)), (side, 0, 0), group, .012)
        # One small flush access recess, surrounded by the orange load-bearing
        # cheek. Its asymmetrical ends echo the reference's machined service cut.
        center = a.lerp(b, .49) + Vector((side * .190, 0, 0))
        slot = [center + direction * t + normal * h for t, h in
                ((-.075, -.025), (.064, -.025), (.077, .008), (.056, .03), (-.064, .03), (-.077, .006))]
        prism('Recessed tail inspection slot', slot, (side, 0, 0), 0, .003, dark, group, .003)

    # The mounting saddle and paired structural cheeks wrap a real dark bearing.
    cylinder('Tail saddle transverse bearing', (-.255, .22, .68), (.255, .22, .68), .19, dark, tail0, 32, bevel=.012)
    for side in (-1, 1):
        beam('Tail socket orange clevis', (side * .22, .12, .51), (side * .22, .31, .79), .07, .23, orange, tail0)

    for index, (group, a, b) in enumerate(zip((tail0, tail1, tail2), pivots, pivots[1:])):
        direction = (b - a).normalized()
        normal = direction.cross(Vector((1, 0, 0))).normalized()
        length = (b - a).length
        end_fraction = .89 if index < 2 else .66
        beam('Dark boxed tail backbone', a + direction * .07,
             a + direction * (length * end_fraction), .195, .18, dark, group)
        for side in (-1, 1):
            cheek('Cast orange tail cheek %d' % index, a, b, side, group,
                  depth=.285 if index == 0 else .255, end_fraction=end_fraction)
        joint(a, group, .173 if index == 0 else .161, .47)
        # Concise, plausible hydraulic plumbing lies inside the orange cheeks.
        # Two large actuators support the rising arch; the fore section instead
        # owns the clearly exposed telescopic stage below.
        if index < 2:
            for side in (-1, 1):
                offset = Vector((side * .087, 0, 0)) + normal * .139
                barrel_start = a + direction * .17 + offset
                barrel_end = a.lerp(b, .61) + offset
                rod_end = b - direction * .13 + offset
                cylinder('Protected hydraulic barrel', barrel_start, barrel_end, .053, dark, group, 24, bevel=.006)
                ring('Hydraulic dust gland', barrel_end, direction, .058, .031, .036, steel, group, 24)
                cylinder('Exposed arch actuator piston', barrel_end, rod_end, .029, chrome, group, 20, bevel=.002)
            tube('Protected tail hydraulic supply', [a + normal * .12, a.lerp(b, .25) + normal * .19,
                 a.lerp(b, .72) + normal * .18, b + normal * .12], .018, rubber, group)

    a, b = pivots[2], pivots[3]
    axis = (b - a).normalized()
    # The fixed actuator has a broad gland and distinct wiper seals. The moving
    # shaft extends from behind it, exposing genuine extra chrome on each stroke.
    fixed_end = a + axis * .86
    cylinder('Fixed telescopic cylinder body', a + axis * .50, fixed_end, .120, dark, tail2, 32, bevel=.012)
    ring('Telescopic gland locking flange', fixed_end, axis, .139, .084, .071, steel, tail2, 32)
    ring('Black ram dust wiper', fixed_end + axis * .047, axis, .108, .079, .025, rubber, tail2, 32)
    for offset in (-.028, .019):
        ring('Gland machined retaining groove', fixed_end + axis * offset, axis, .142, .126, .008, dark, tail2, 32)
    tangent = Vector((1, 0, 0))
    bitangent = axis.cross(tangent).normalized()
    for index in range(6):
        angle = index * math.tau / 6
        at = fixed_end + axis * .038 + (tangent * math.cos(angle) + bitangent * math.sin(angle)) * .119
        bolt(at, axis, tail2, .010)
    cylinder('Sliding chrome outer piston', a + axis * .58, b - axis * .095, .079, chrome, extension, 32, bevel=.004)
    ring('Moving piston shoulder', b - axis * .095, axis, .086, .057, .042, dark, extension, 32)
    cylinder('Nested hardened inner ram', b - axis * .13, b + axis * .042, .056, steel, extension, 24, bevel=.003)
    ring('Rod attachment retention ring', b + axis * .018, axis, .077, .051, .042, dark, extension, 24)
    # A clear centre ridge and short protected hose keep the forearm recognisable
    # even when the reflective nested shaft is caught in a dark environment.
    tube('Telescopic hydraulic feed', [a + Vector((.095, .07, 0)),
         a + axis * .28 + Vector((.108, .09, 0)), a + axis * .69 + Vector((.103, .075, 0))], .015, rubber, tail2)

    # Compact wrist bearing joins directly into the forging's sloped crown.
    cylinder('Hammer integral wrist axle', b - Vector((.175, 0, 0)), b + Vector((.175, 0, 0)), .103, dark, hammer, 28, bevel=.005)
    for side in (-1, 1):
        ring('Recessed hammer wrist bearing', b + Vector((side * .182, 0, 0)), (1, 0, 0), .094, .068, .022, steel, hammer, 24)
        bolt(b + Vector((side * .191, 0, 0)), (side, 0, 0), hammer, .021)
    beam('Hammer forged neck', b, head_center + Vector((0, .18, .07)), .255, .24, dark, hammer)

    # A single continuous forging. The long eight-sided silhouette, skewed crown,
    # tapered back and broad front shoulder bevel are geometry, not a cube with
    # yellow plates or a separate pallet-like strike shoe bolted underneath.
    outline = [(-.19, -.38), (.19, -.38), (.31, -.26), (.31, .24),
               (.21, .35), (-.18, .38), (-.31, .25), (-.31, -.24)]
    rings = [(-.250, .82, .90), (-.160, 1.0, 1.0), (.180, .97, .96), (.250, .80, .84)]
    verts = [tuple(head_center + Vector((x * sx, y * sy, z)))
             for z, sx, sy in rings for x, y in outline]
    count = len(outline)
    faces = [tuple(reversed(range(count))), tuple(range((len(rings) - 1) * count, len(rings) * count))]
    for layer in range(len(rings) - 1):
        for i in range(count):
            faces.append((layer * count + i, layer * count + (i + 1) % count,
                          (layer + 1) * count + (i + 1) % count, (layer + 1) * count + i))
    forging = mesh('Continuous chamfered hammer forging', verts, faces, forging_material, hammer, .010)
    forging.data.materials.append(steel)
    # Only the integral contact face is polished by impacts; adjacent bevels keep
    # dark forged steel. No bright rim outlines every face of the tool.
    forging.data.polygons[2 + count].material_index = len(forging.data.materials) - 1

    def front_inset(name, width, height, z, material, depth):
        x = width * .5
        y = height * .5
        c = .025
        contour = [(-x + c, -y), (x - c, -y), (x, -y + c), (x, y - c),
                   (x - c, y), (-x + c, y), (-x, y - c), (-x, -y + c)]
        points = [head_center + Vector((px, py, z)) for px, py in contour]
        return prism(name, points, (0, 0, -1), 0, depth, material, hammer, .002)

    front_inset('Recess for inset hammer safety marking', .314, .585, -.251, rubber, .002)
    front_inset('Inset worn diagonal hazard strip', .280, .550, -.254, hammer_hazard, .002)

    def embedded_fastener(at, normal, radius=.018):
        at, normal = Vector(at), Vector(normal).normalized()
        cylinder('Embedded hammer fastener counterbore', at - normal * .008, at, radius * 1.42, rubber, hammer, 12, bevel=0)
        cylinder('Flush forged-head hex bolt', at - normal * .003, at + normal * .002, radius, steel, hammer, 6, bevel=0)
        cylinder('Recessed hex drive', at + normal * .0021, at + normal * .0025, radius * .44, rubber, hammer, 6, bevel=0)

    for x, y in ((-.178, -.25), (.178, -.25), (-.217, -.10), (.217, -.10),
                 (-.217, .15), (.207, .15), (-.13, .284), (.13, .266)):
        embedded_fastener(head_center + Vector((x, y, -.252)), (0, 0, -1), .013)
    # The side cheeks are dark heavy forgings, with sparse inset fasteners and
    # a diagonal seam across their broad flat surfaces, like the reference.
    for side in (-1, 1):
        cheek_contour = [head_center + Vector((side * .304, y, z)) for y, z in
                         ((-.19, -.12), (.17, -.12), (.22, -.04), (.15, .13), (-.20, .13), (-.26, .02))]
        prism('Forged hammer side cheek', cheek_contour, (side, 0, 0), 0, .008, forging_material, hammer, .006)
        for y, z in ((-.16, -.055), (.13, -.045), (-.15, .087), (.11, .088)):
            embedded_fastener(head_center + Vector((side * .314, y, z)), (side, 0, 0), .014)
    # Integrated crown shoulder, slightly skewed, retains one service plug.
    embedded_fastener(head_center + Vector((-.10, .377, .015)), (0, 1, 0), .034)
    return {
        'hammer_center': list(head_center), 'hammer_size': [.62, .76, .50],
        'tail_extension': {'node': 'TailExtension', 'axis': list(axis), 'travel': .22,
                           'law': 'smoothstep(0.15,0.85,hammer_fraction)',
                           'parent': 'TailFore', 'head_parent': 'TailExtension'},
        'hammer_angles': [-.90, -.15, .50, .55],
        'hammer_surface': 'Continuous skew-crown octagonal forging, patchy metallic edge wear, integral impact face and 45-degree inset hazard bands',
    }
