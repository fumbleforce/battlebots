# Frozen Maelstrom kit

Reproducible Blender 4.0 source for the Frozen Maelstrom arena (#102). From the
repository root:

    blender -b --python-exit-code 1 --python art_source/maelstrom/build_kit.py
    godot --headless --path battlebots --editor --import

It writes `battlebots/assets/models/maelstrom/maelstrom_kit.glb` (one object per
model: crags, seracs, the five wreck types with crew and debris, the eye vortex,
pack-ice floes), `battlebots/data/maelstrom_hulls.json` (convex collision hulls
per model, from the same vertices) and the editable `maelstrom_kit.blend`.

Geometry is authored in Godot metres (X right, Y up, -Z bow) and converted to
Blender's frame only when meshes are made. Material slots name the game material
(`wood`, `deck`, `paint`, `trim`, `iron`, `rope`, `sail`, `banner`, `cloth`,
`skin`, `rock`, `ice`, `glass`, `lantern`); the game recolours the fleet slots
per fleet. `sail` / `banner` faces carry metre UVs and their size in vertex
colour so the shader draws emblems in proportion. Crag and serac surfaces are
subdivided and displaced for a weathered surface; everything else stays crisp.

Layout, radii and relief live in `battlebots/data/maelstrom_arena.json`; the ice,
cliffs, frozen sea, rubble and far ice walls are built at load by
`scripts/arena/maelstrom_visuals.gd`. Surface detail reuses the project's CC0
Poly Haven scans (rock face, wood, metal; see
`battlebots/assets/textures/woodland/CREDITS.md`). Review captures:

    godot --path battlebots --script res://tests/presentation/maelstrom_arena_test.gd -- --capture [--view=name]

Captures go to ignored `battlebots/exports/maelstrom-review/`; the `card` view
also writes the arena-select image `ui/menus/art/arena_maelstrom.jpg`.