"""Constructed Atlas roof and rear closure using the supplied hull helpers.

All coordinates are Godot metres. The caller owns Blender grouping, baking,
export and the adjoining nose/shoulder armor; this module writes no files.
"""

import math


def add_deck_shell(*, box, rounded_plate, plate, cylinder, tube, bolt,
                   panel_bolts, deck_text, paint, secondary, steel,
                   edge_steel, rubber, dark, red, brass):
    """Add a .486 m roof, .498 m service covers and a supported rear closure.

    The roof envelope is 1.392 W x .047 H x 1.46 L, centered at (0,.4625,.06).
    Openings are built from separate structural sections, so the 10 mm rail
    recesses have real floors and overhanging lips instead of dark overlays.
    Published top mount origins at Y=.49 stay unchanged in the caller.
    """
    created = []

    def block(name, at, size, material, bevel=.003):
        obj = box(name, at, size, material, b=bevel)
        created.append(obj)
        return obj

    def face(name, points, normal, depth, material, bevel=.003):
        obj = plate(name, points, normal, depth, material, b=bevel)
        created.append(obj)
        return obj

    # Continuous structural roof backing. Its top is .459; the enamel skin
    # above it is interrupted only by the actual rails and service openings.
    block("Roof continuous monocoque seat", (0, .432, .060),
          (1.348, .026, 1.426), secondary, .003)
    created.append(rounded_plate("Deck structural backing", (0, .449, .06),
                   (1.392, .020, 1.46), .025, secondary, edge=.003))
    for name, xz in (
        ("Roof front cross member", [(-.674, -.670), (.674, -.670),
            (.696, -.648), (.696, -.556), (-.696, -.556), (-.696, -.648)]),
        ("Roof rear cross member", [(-.696, .636), (.696, .636),
            (.696, .768), (.674, .790), (-.674, .790), (-.696, .768)]),
    ):
        face(name, [(x, .4725, z) for x, z in xz], (0, 1, 0), .027, paint)
    for side in (-1, 1):
        block("Roof outer longitudinal seam strip", (side * .6455, .4725, .04),
              (.101, .027, 1.184), paint)
        block("Roof inner service opening frame", (side * .387, .4725, .04),
              (.036, .027, 1.184), paint, .002)

    # Recessed longitudinal T-slots. The .476 floor is 10 mm below the roof;
    # a 6 mm undercut remains below the 4 mm lip. No rail stands above the skin.
    for side in (-1, 1):
        x = side * .500
        block("Recessed addon rail floor", (x, .474, .04),
              (.100, .004, 1.180), dark, .001)
        for edge in (-1, 1):
            block("Addon rail structural wall", (x + edge * .0705, .4705, .04),
                  (.041, .023, 1.180), paint, .002)
            block("Flush addon rail overhanging lip", (x + edge * .0595, .484, .04),
                  (.063, .004, 1.180), paint, .001)
        for z in (-.530, .610):
            block("Flush addon rail end closure", (x, .4725, z),
                  (.100, .027, .040), paint, .002)
            bolt((x, .486, z), r=.010)
        # A removable slider demonstrates the mechanical interface without
        # obstructing the long mounting channel or raising a stacked rail.
        block("Recessed captured rail nut", (x, .478, .405),
              (.077, .004, .047), steel, .001)
        block("Rail nut drive recess", (x, .4803, .405),
              (.015, .001, .019), dark, .001)

    # Two supported access covers. Their broad faces are only 12 mm proud of
    # the enamel roof and use a 6 mm perimeter assembly gap, not a rubber halo.
    block("Service opening shadow floor", (0, .475, .04),
          (.744, .004, 1.184), dark, .002)
    block("Roof transverse hatch seam", (0, .4725, -.055),
          (.738, .027, .014), paint, .002)
    for z in (-.548, .628):
        block("Roof service opening end frame", (0, .4725, z),
              (.738, .027, .010), paint, .002)
    for name, center, length in (("Forward modular service cover", -.3025, .475),
                                 ("Rear modular service cover", .2875, .665)):
        for x in (-.327, .327):
            for z in (center - length * .5 + .044, center + length * .5 - .044):
                block("Internal service cover support", (x, .469, z),
                      (.047, .024, .044), secondary, .002)
                bolt((x, .498, z), r=.011)
        if name.startswith("Forward"):
            created.append(rounded_plate(name, (0, .488, center),
                           (.726, .020, length), .015, secondary, edge=.003))
        else:
            # An actual .48 x .30 cooling aperture in the removable cover.
            # Its frame is segmented around the opening rather than laying a
            # grille on top of an unbroken plate. Louvers stay below the lid.
            for title, xz in (
                ("Rear service cover front frame", [(-.348, -.045), (.348, -.045),
                    (.363, -.030), (.363, .040), (-.363, .040), (-.363, -.030)]),
                ("Rear service cover aft frame", [(-.363, .340), (.363, .340),
                    (.363, .605), (.348, .620), (-.348, .620), (-.363, .605)]),
            ):
                face(title, [(x, .488, z) for x, z in xz],
                     (0, 1, 0), .020, secondary, .0015)
            for side in (-1, 1):
                block("Rear cooling aperture side frame", (side * .3015, .488, .190),
                      (.123, .020, .300), secondary, .0015)
            for z in (.069, .117, .165, .213, .261, .309):
                block("Recessed roof cooling louver", (0, .4875, z),
                      (.484, .015, .025), secondary, .003)
    deck_text("ATLAS  /  MX", (0, .4987, -.280), .033)
    deck_text("SERVICE  02", (0, .4987, .500), .024)

    # Continuous rear transition. Points describe the outside armor surface;
    # extrusion is placed inward so the shoulder/roof junction stays exact.
    rise, run = .182, .322
    norm = math.hypot(rise, run)
    normal = (0, run / norm, rise / norm)

    def rear_slope(name, x0, x1, offset, thickness, material, bevel=.004):
        points = [(x0, .484, .794), (x1, .484, .794),
                  (x1, .302, 1.116), (x0, .302, 1.116)]
        points = [(x - normal[0] * offset, y - normal[1] * offset,
                   z - normal[2] * offset) for x, y, z in points]
        return face(name, points, normal, thickness, material, bevel)

    rear_slope("Rear transition structural backing", -.682, .682,
               .037, .024, secondary)
    rear_slope("Rear transition central access panel", -.355, .355,
               .015, .030, secondary)
    for side in (-1, 1):
        a, b = sorted((side * .361, side * .682))
        rear_slope("Rear transition enamel shoulder", a, b,
                   .015, .030, paint)
        # Follow the backing's inner plane instead of using an axis-aligned
        # box whose far top corner would emerge through the descending armor.
        # At fixed Z the .050 m normal inset requires .050 / normal.y in Y;
        # this stays 1 mm behind the backing's .049 m inner surface. The knee
        # remains joined to the vertical rear backing through its lower body.
        knee_front, knee_rear = 1.048, 1.112
        def knee_top(z):
            return .484 - (z - .794) * rise / run - .050 / normal[1]
        face("Rear transition internal knee",
             [(side * .596, knee_top(knee_front), knee_front),
              (side * .596, knee_top(knee_rear), knee_rear),
              (side * .596, .220, knee_rear),
              (side * .596, .220, knee_front)],
             (1, 0, 0), .100, secondary, .003)
        for x in (side * .397, side * .645):
            z = .835
            y = .484 - (z - .794) * rise / run
            bolt((x, y, z), normal, r=.010)

        # The feet start inside the actual sloped panel. A short forged U-bar
        # rises from these seats, instead of hovering above an unrelated deck.
        z = 1.008
        y = .484 - (z - .794) * rise / run
        points = []
        for x, distance in ((side * .460, .008), (side * .460, .043),
                            (side * .590, .043), (side * .590, .008)):
            points.append((x, y + normal[1] * distance, z + normal[2] * distance))
        for x in (side * .460, side * .590):
            a = (x, y - normal[1] * .002, z - normal[2] * .002)
            b = (x, y + normal[1] * .013, z + normal[2] * .013)
            created.append(cylinder("Rear lifting handle welded seat", a, b,
                           .021, steel, n=24, bevel=.002))
        tube("Rear armor seated lifting handle", points, .0105, secondary)

    # The vertical rear frame starts at the transition with a narrow 4 mm
    # seam. Its radiator is physically open between the structural pieces.
    block("Rear closure structural backing", (0, -.005, 1.074),
          (1.318, .606, .028), secondary, .006)
    block("Rear radiator upper lintel", (0, .2765, 1.103),
          (1.318, .043, .034), paint, .004)
    for side in (-1, 1):
        block("Rear lamp and radiator upright", (side * .5295, .1565, 1.103),
              (.259, .197, .034), paint, .004)
    block("Rear lower service fascia", (0, -.106, 1.103),
          (1.318, .324, .034), paint, .005)
    block("Rear radiator recessed floor", (0, .1565, 1.096),
          (.810, .203, .010), dark, .002)
    for y in (.087, .121, .155, .189, .223):
        block("Rear recessed radiator louver", (0, y, 1.110),
              (.806, .013, .018), secondary, .003)
    for side in (-1, 1):
        block("Rear sealed lamp seat", (side * .5295, .171, 1.122),
              (.146, .079, .012), dark, .008)
        block("Rear lens retaining rim", (side * .5295, .171, 1.129),
              (.124, .058, .006), edge_steel, .006)
        block("Rear recessed red lamp lens", (side * .5295, .171, 1.133),
              (.098, .034, .006), red, .004)

    block("Rear flush removable service door", (0, -.113, 1.118),
          (.750, .246, .016), secondary, .005)
    for x in (-.331, .331):
        for y in (-.195, -.031):
            bolt((x, y, 1.126), (0, 0, 1), r=.011)
    # Small real annular service connectors; the dark floor is behind the
    # brass ring, so neither connector relies on a painted black cap.
    for x in (-.100, .100):
        created.append(cylinder("Rear service connector recessed floor",
                       (x, -.113, 1.126), (x, -.113, 1.129),
                       .012, dark, n=24, bevel=.0005))
        points = [(x + math.cos(i * math.tau / 16) * .014,
                   -.113 + math.sin(i * math.tau / 16) * .014, 1.133)
                  for i in range(17)]
        tube("Rear service connector brass rim", points, .0025, brass)
    block("Rear continuous impact bumper", (0, -.2925, 1.135),
          (1.340, .115, .100), secondary, .018)
    for side in (-1, 1):
        bolt((side * .595, -.289, 1.185), (0, 0, 1), r=.014)
    return created
