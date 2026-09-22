"""Compact Atlas side armor, authored through the generator's geometry helpers.

Coordinates use Godot metres: X right, Y up, -Z forward. This module neither
imports Blender nor writes assets; the caller owns grouping, baking and export.
"""


def add_side_skirts(side, group, *, plate, box, bolt, cylinder,
                    paint, secondary, steel, dark):
    """Add one stationary skirt and its supports; ``side`` is -1 or +1.

    The shoulder roof meets the upper edge at Y=.413 (2 mm assembly seam).
    Main armor occupies |X|=1.1695..1.2065. Its deepest central edge is Y=-.15;
    the fixed addon marker (side*1.207, -.02, 0) sits over solid hatch armor.
    All external hardware remains inside |X|=1.2175. Moving parts must remain
    inside |X|=1.165 wherever their Y/Z envelopes overlap this skirt.

    Return the principal armor/support objects for optional caller inspection.
    Helpers register every object, including fasteners, in ``group`` as usual.
    """
    if side not in (-1, 1):
        raise ValueError("Atlas side must be -1 or +1")

    label = "Left" if side < 0 else "Right"
    center_x, depth, outer_x = 1.188, .037, 1.2065
    created = []

    def panel(name, zy, material=paint, bevel=.004):
        obj = plate(label + " " + name,
                    [(side * center_x, y, z) for z, y in zy],
                    (side, 0, 0), depth, material, group, bevel)
        created.append(obj)
        return obj

    def block(name, x, y, z, size, material, bevel=.002):
        obj = box(label + " " + name, (side * x, y, z), size,
                  material, group, b=bevel)
        created.append(obj)
        return obj

    # The front service wing is a real open grille, assembled from four flush
    # frame strips. Their narrow joints follow its horizontal stamped folds;
    # the dark floor and louvers are behind the outer armor plane, not decals.
    panel("skirt grille upper frame", [(-.680, .368), (-.637, .411),
          (-.318, .411), (-.318, .305), (-.680, .305)], bevel=.0015)
    panel("skirt grille lower frame", [(-.680, .194), (-.318, .194),
          (-.318, .055), (-.620, .055), (-.680, .115)], bevel=.0015)
    panel("skirt grille forward jamb", [(-.680, .305), (-.604, .305),
          (-.604, .194), (-.680, .194)], bevel=.0015)
    panel("skirt grille aft jamb", [(-.390, .305), (-.318, .305),
          (-.318, .194), (-.390, .194)], bevel=.0015)
    block("recessed skirt grille floor", 1.1835, .2495, -.497,
          (.005, .115, .218), dark, .001)
    for index, y in enumerate((.216, .239, .262, .285)):
        block("recessed skirt louver %d" % index, 1.1935, y, -.497,
              (.014, .012, .214), secondary, .0025)

    # A broad central hatch replaces the old isolated quadrilateral. Its lower
    # sacrificial strip is flush with the enamel rather than an overlay slab.
    panel("central side service hatch", [(-.312, .411), (.312, .411),
          (.312, -.058), (-.312, -.058)])
    panel("flush lower skirt impact strip", [(-.312, -.064), (.312, -.064),
          (.312, -.105), (.267, -.150), (-.267, -.150), (-.312, -.105)],
          secondary, .003)
    panel("rear side access wing", [(.318, .411), (.637, .411),
          (.680, .368), (.680, .115), (.620, .055), (.318, .055)])

    # Crown extent is outer_x + .011 = 1.2175 for the supplied button fastener.
    for z, y in ((-.638, .356), (-.355, .103), (.638, .356), (.355, .103),
                 (-.266, .363), (.266, .363), (-.232, -.106), (.232, -.106)):
        bolt((side * outer_x, y, z), (side, 0, 0), group, r=.011)

    # Small real hinge barrels bridge the 6 mm front hatch seam. Their backing
    # leaves meet both adjacent panel faces, and the end pins stay recessed.
    for index, y in enumerate((.107, .261)):
        block("side hatch hinge leaf %d" % index, 1.209, y, -.315,
              (.006, .039, .040), secondary, .0015)
        for start, end in ((-.018, -.002), (.002, .018)):
            obj = cylinder(label + " side hatch hinge barrel",
                           (side * 1.212, y + start, -.315),
                           (side * 1.212, y + end, -.315),
                           .0055, secondary, group, n=16, bevel=.0007)
            created.append(obj)
        obj = cylinder(label + " side hatch hinge pin",
                       (side * 1.212, y - .019, -.315),
                       (side * 1.212, y + .019, -.315),
                       .002, steel, group, n=12, bevel=.0005)
        created.append(obj)

    # Recessed latch hardware sits in a shallow raised tray. The steel crossbar
    # remains lower than the tray rim, giving a readable physical recess.
    block("rear wing latch well", 1.208, .243, .497,
          (.003, .073, .102), dark, .003)
    for y in (.2095, .2765):
        block("rear wing latch horizontal rim", 1.211, y, .497,
              (.008, .006, .102), secondary, .001)
    for z in (.449, .545):
        block("rear wing latch vertical rim", 1.211, .243, z,
              (.008, .061, .006), secondary, .001)
    obj = cylinder(label + " recessed rear wing latch crossbar",
                   (side * 1.211, .243, .449),
                   (side * 1.211, .243, .545),
                   .0035, steel, group, n=16, bevel=.001)
    created.append(obj)

    # Actual structure spans the track interior; it does not rely on a floating
    # exterior plate. Beam top=.039 is below the return roller's bottom=.080;
    # the beam bottom=.001 is well above the lower rollers' top=-.210.
    # The end overlaps the armor's inner face by 5 mm to form a welded seat.
    for z in (-.25, .25):
        block("skirt cross-frame bracket", (.720 + 1.1745) * .5, .020, z,
              (1.1745 - .720, .038, .056), secondary, .004)
        obj = plate(label + " skirt bracket root gusset",
                    [(side * .729, .020, z), (side * .953, .020, z),
                     (side * .729, -.055, z)],
                    (0, 0, 1), .030, secondary, group, .003)
        created.append(obj)

    return created
