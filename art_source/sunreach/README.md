# Sunreach Ruins

Playable 240 m painterly grassland basin inspired by the user-supplied landscape.
The western waterfall, two flanking streams with timber bridges, central broken
ruin, scattered cover, cliff terraces, grass and tree clusters follow its main
landmarks. Routes and 15 m bridge decks accommodate the existing giant robots.

Rebuild from the repository root with the pinned Blender:

    blender -b --python-exit-code 1 --python art_source/sunreach/build_arena.py
    godot --headless --path battlebots --editor --import

`sunreach.blend` is the editable source; `build_arena.py` reproduces it and exports
`assets/models/sunreach/sunreach.glb`, height samples, structure hulls and input
fingerprints in `data/sunreach/`. Layout and gameplay dimensions are authored in
`data/sunreach/layout.json`; start positions remain in `data/arena_spawns.json`.
Meshes are grouped by material and spatial cell for culling and imported LODs.
Physics never loads the visual asset. Shallow streams are traversable; bridges
provide level crossings. Ruins are permanent cover; existing robot damage,
detachment, weapons and movement remain unchanged.

New masonry, bridges, vegetation, terrain and arrangement: generated project
art. Rock silhouettes and graded surface detail reuse the project's CC0 Poly
Haven granite/rock and pine-bark assets: see
[Woodland credits](../../battlebots/assets/textures/woodland/CREDITS.md) and
[rock-source credits](../woodland/CREDITS.md). No Nintendo assets are included.

Review staging: overview from the southern rim looking north, both bridges and
central ruin visible, waterfall NW and arch NE. Chase view looks north along the
main lane; bridge view looks NW along the western crossing, both abutments in
frame. Sunlight enters from the SW. All screenshots are real Godot renders.

    xvfb-run -a godot --path battlebots --script res://tests/presentation/sunreach_arena_test.gd -- --capture
    godot --headless --path battlebots --script res://tests/simulation/sunreach_bridges.gd
    xvfb-run -a godot --path battlebots --script res://tools/stress_woodland.gd -- --arena=sunreach --size=1920x1080 --bots=12 --seconds=30

Captures go to ignored `battlebots/exports/sunreach-review/`; the overview also
updates the shipped arena-selection image. Do not replace it with concept art.
