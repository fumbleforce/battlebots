# Woodland arena (A, #34)

User request, 2026-09-23: a new "Woodland" arena at top visual fidelity from two
supplied concepts (timber palisade stadium in a pine valley; a rutted, varied
battlefield with a central rock island, ramps and bunkers). The user asked for
the interior and walls first, then the surrounding nature. After review they
asked for it to be built for **giant bots and 10+ players**, with far more
terrain interest: varied heights, cliffs and heavy wear.

## Contract

- Arena id `woodland`, scene `scenes/arenas/woodland_arena.tscn`, inheriting the
  shared octagon shell. `ArenaBounds.WOODLAND_HALF = 120`: a 240 m octagon, about
  5.8× Foundry's floor area. `ArenaBounds.IDS` lists every selectable arena.
- Walls use the shell's planes, raised to 16 m collision so jumping bots stay in.
  Spawn markers scale with the shell (team rows at z = ±91 m, FFA ring r = 96 m).
- Authority: `scripts/arena/woodland_ground.gd` builds a seeded 1 m
  `HeightMapShape3D` plus boulder hulls, trunk cylinders, log barricades,
  jump-ramp wedges, bunker boxes and plinth drums. Every feature is point-mirrored
  so both teams face identical ground; spawn pads and the mesa-top practice area
  are level. `AuthorityWorld.clear_spawn_pose` samples terrain for Moon and
  Woodland alike.
- Handshake: `ARENA_RULES = 2`; hosts reject older clients from a Woodland host
  with "Update the game to join the Woodland arena". Build, protocol and
  catalogue hash are unchanged. The hosted worker still hosts Foundry, so no
  hosted release is required.

## Presentation (never collides)

- `woodland_visuals.gd`: palisade with 3 m bumper beams, plank walls, girts,
  braces, banners and lanterns; concrete buttresses with braziers; walkway and
  terraced stands with an animated human-scale crowd; corner floodlight towers;
  a scoreboard; ramp, bunker and plinth dressing. The terrain is rendered at 0.5 m.
  Tank ruts, puddles and scorch marks are cut by the dirt shader.
- `woodland_flora.gd`: seeded pines, grass tufts. `woodland_nature.gd`: valley
  terrain to 1.5 km, forest bands, granite knolls, river, lake, roads and bridge.
  `woodland_sky.gdshader` paints the far mountain ranges and clouds.
- Camera: the B-owned orbit camera has `far = 150`, which clips this arena.
  The visuals extend the active camera's far plane to 1600 m at runtime. The
  proper arena-published view distance is handed to B on #34.

## Validation (x3d, RTX 3080, Godot 4.7.2)

- `tests/presentation/woodland_arena_test.gd` headless and native: contracts,
  mirrored obstacles, level spawn/practice pads, wall height, clear spawn radius,
  terrain spawn height and headless stripping. `-- --capture [--benchmark]`
  writes review views to `exports/arena-review/`.
- Also passing: baseline smoke, arena selection, heavy spawn (all three arenas),
  Moon/Foundry arena, Moon session, practice session, menu fit, session smoke.
- Pre-existing failures on clean `main`, not from this work: practice menu
  "Target HUD fits 720p"; featured vehicle menu standalone compile error.
- Fixture frame times at 1600×900, vsync off: median 8.7–13.3 ms over ten
  views. This is a static arena fixture, not a combat or low-end certification.
- Human visual acceptance by the user is still open.

## Current state (2026-09-23, supersedes details above)

After user review the arena was rebuilt for fidelity; the full method, failures
and a checklist for future arenas are in
[docs/art/ARENA_ENVIRONMENTS.md](../art/ARENA_ENVIRONMENTS.md). Changes to the
contract above: the mesa top is 7.0 m (cliff sectors, ramps ~22°); boulders use
decimated CC0 granite scans whose render mesh is the convex collision hull; the
visuals raise the active camera far plane to 12 km for the mountain ranges (the
orbit-camera handoff to B still stands). Structures, trees, scatter and the crowd
come from Blender scripts in `art_source/woodland/`; materials are CC0 Poly Haven
scans (credits alongside the assets). Deferred gameplay request: #45.
