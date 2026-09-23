# Building high-fidelity arenas

Written 2026-09-23 after building the Woodland arena (#34) at the user's request,
through several rounds of blunt user review. It records how the arena was made,
what made it look good, what failed, and what future arenas must plan for. It is
the environment counterpart of [STYLIZED_INDUSTRIAL_ASSETS.md](STYLIZED_INDUSTRIAL_ASSETS.md):
the same rule applies. Real construction, real scanned material and honest
lighting beat procedural noise, however clever.

## The user's bar, in their words

- "Top level fidelity", judged against photoreal concept art, not against the
  previous arenas.
- "Way too small … this should be for GIGANTIC TANKS, up to 10 possibly or more."
- "Extremely boring … see the reference … HIGH detail terrain with clear marks of
  wear and use, varied heights and cliffs."
- "Very PlayStation 3 era" / "more … 2013 style": procedural shaders on boxes,
  spiky card grass, visibly repeating ground and flat-looking models all read as
  old, no matter how many of them there are.
- Fidelity is judged from the **gameplay camera** (low chase camera behind a giant
  tank), not from the flattering overview.

## How the Woodland arena was made

### 1. Gameplay shape first (authoritative, deterministic)

`scripts/arena/woodland_ground.gd` owns everything that collides:

- A 240 m octagon (`ArenaBounds.WOODLAND_HALF = 120`) for 10+ giant bots, walls
  raised to 16 m collision so jumping tanks stay in, spawn markers scaled from
  the shared shell.
- A seeded 1 m `HeightMapShape3D`: rolling ground, a 7 m cliff-ringed central
  mesa with four ramps, raised terraces with ramps, outcrop mounds. Spawn pads and
  the mesa top are forced level; the wall foot is flat.
- Obstacles: scanned granite boulders (the render mesh is also the convex
  collision hull), pine trunks, log barricades, jump-ramp wedges, bunkers, a
  turret plinth.
- **Everything is point-mirrored** so both teams face identical ground (the test
  checks every obstacle has a mirrored partner). Noise that is not symmetric
  (terrace rims, rolling height) was a real bug; average a point with its mirror.
- Pure static functions (`height_at`, `obstacles()`), no global random state, so
  server and every client rebuild the same world. Headless servers strip all
  presentation.

### 2. Construction in Blender, not boxes in GDScript

Every structure is built by a reproducible script in `art_source/woodland/`
(Blender 5.2.2 LTS, installed in the user's home, checksum verified):

| Script | Output |
|---|---|
| `build_palisade.py` | Wall bays and posts: bevelled, slightly warped planks with gaps and broken tops, hewn bumper beams, forged straps with domed bolts, braces, girts. Shared helpers (Godot-frame coordinates, grain-aligned metre UVs, bolts, AO bake). |
| `build_stands.py` | Raised grandstands on trestle bents, treads/risers/benches, sagging canvas canopies; lattice floodlight towers with ladder and aimed lamp housings; scoreboard frame; low-poly seated/standing spectators with per-part material slots. |
| `build_structures.py` | Jump ramps and bunkers that match their collision exactly: riveted plates, rails, hazard lips, steel-clad buttresses. |
| `build_boulders.py` | CC0 granite scans decimated to 2.4–3.6k triangles, full scan detail baked to normal maps with Cycles, albedo graded to cool grey. |
| `build_scatter.py` | Scanned pebbles, mossy rocks (baked normals), grass clumps and ferns. |
| `build_grass_atlas.py` | Dense meadow patches rendered from scanned grass clumps into an alpha atlas. |
| `build_branch_atlas.py` | Conifer branch sprays: the scanned fir cut into layered azimuth wedges, rendered top-down (colour, alpha, normals). |
| `build_conifer_atlas.py` | Whole-tree side cards for distant forest. |
| `prepare_sky.py` | Removes the photographed sun from the HDRI (see lighting). |

Models export as separate `.gltf` + `.bin` with named material slots
(`timber`, `plank`, `iron`, `concrete`, `canvas`, `lamp`, …). The game assigns its
own scanned materials by slot name, so textures are stored once and every piece
shares a consistent material system. Ambient occlusion is baked into vertex colour
with a **short AO distance (0.35 m)**; the default distance darkened open planks
to 25 % and made the wall read black.

### 3. Photoscanned CC0 material instead of procedural noise

All textures and scans are CC0 from Poly Haven, credited in
`assets/textures/woodland/CREDITS.md` and `art_source/woodland/CREDITS.md`
(the repo already had the same precedent for Flamebot).

- Terrain: four scanned layers (muddy tracks, stony mud, forest soil, sparse
  grass) blended by height and by baked masks, plus scanned granite projected on
  steep faces.
- Timber: a weathered-plank scan sampled one board wide along each board's grain
  (knots and nail rows keep their scale), with patina, ground mud and moss. A
  fine grain scan looked like speckle at gameplay distance; bold features win.
- Concrete, steel, rust and bark: triplanar scans, graded (the concrete scan is
  beige and read as khaki until desaturated; rust needed muting).
- Scans are **graded to the arena palette** (grey granite, dark wet brown mud),
  not used raw.

### 4. Ground that shows use

- `tools/bake_woodland_masks.gd` bakes `ground_masks.png` once: R tank-rut
  grooves (gauge and track width from giant tanks, laps around the mesa, lanes
  from spawns, skid loops, faded on slopes), G grass, B wetness, A scorch.
- The terrain is a 0.25 m grid displaced **on the GPU** from the physics heights
  (uploaded as a float texture) plus the rut profile (groove with churned lips)
  and visual lumps. Collision stays the 1 m heightmap; visual offsets stay small.
- **Hex-tile sampling** (Mikkelsen) of every scan removes visible repetition.
- Cliffs: irregular rock beds, ledges and vertical joints displaced along the
  slope in the vertex stage, with normals from the displaced surface.
- Scatter is placed from the same masks and a shared baked "lump" texture, so
  props sit on the rendered surface: ~30 k grass patches, dense scanned debris,
  pebbles on rut lips and around outcrops, ferns and mossy rocks near walls.

### 5. Vegetation

- Grass: crossed cards textured from Blender renders of scanned clumps. Spiky
  procedural blade cards were rejected ("10 spiky leaves").
- Conifers: whorls of drooping, rolled branch cards from the branch atlas around a
  modelled bark trunk, crown occlusion in vertex colour; distant forest uses
  whole-tree side cards. Flat crossed cards alone read as paper up close.

### 6. Lighting and grade

- A CC0 pure-sky HDRI as the sky. **Its photographed sun must be removed**
  (`prepare_sky.py` soft-clamps it) and the `DirectionalLight3D` aimed along the
  exact photographed sun direction. Otherwise sky ambient and reflections count
  the sun twice and bleach everything.
- Soft sun (angular distance 1.2°, four splits), strong wide SSAO, SSIL bounce,
  reduced flat ambient, AgX tonemapping with a mild contrast lift and slightly
  reduced saturation, restrained volumetric fog with no ambient injection.
- Surroundings: 1.5 km forested valley terrain, river, lake, roads, and
  snow-capped mountain geometry out to 7 km, so no painted-sky shortcut is needed.

## Failures worth not repeating

| Symptom the user saw | Real cause | Fix |
|---|---|---|
| Flickering white lights everywhere | `normalize()` of a zero vector in the derivative bump helper produced NaN pixels; bloom and TAA smeared them. First "fixes" (puddle roughness, flames) only hid symptoms. | Guard every normalize in shared shader helpers; find the root cause before tuning materials. |
| Triangle "shards" in the ground | `fract(sin(x)*43758)` hash differs by last-bit float error between neighbouring noise cells on the GPU. | Use an exact integer (PCG) hash of the float bits. Never use the sin hash in production shaders. |
| Blooming sun orb, chrome ruts | Mirror-like puddles in displaced ruts under a low sun. | Puddles are silty water (roughness ≥ 0.3), only on flat ground. |
| Everything washed out | HDRI sun counted twice. | Remove the sun from the HDRI; aim the key light along it. |
| Ground empty 5 m ahead | Scatter visibility ranges (55–60 m) measured from the camera, which sits well behind a giant tank. | Full density to 80–160 m, then a thinned copy to 3× that. Judge from the chase camera. |
| Black timber | AO baked with the default long distance. | Short AO distance; normalise baked AO in the shader. |
| Brick-wall cliffs | Uniform strata bands. | Uneven bed thickness, dipping beds, per-bed joints. |
| Hosted release blocked (#51) | A hand-edited `.import` file was rewritten by a clean Linux import. | Let pinned Godot generate import files from a clean import and commit that result; run the release import check before pushing assets. |
| Wrong result files | Blender `Image.save()` wrote the unmodified source; `hide_render` copied to duplicates; cached materials removed by reset. | Use `save_render` for edited pixels; set flags on copies; clear caches on reset. |

## Checklist for the next arena

1. **Brief and scale.** Agree player count, bot size and camera. Giant tanks need
   ~6× Foundry's floor area, tall walls and features at their scale (a 4.6 m
   cliff disappears next to them).
2. **Gameplay layout before art.** Deterministic collision, mirrored for teams,
   level spawn pads, clear lanes, height variation (plateaus, terraces, ramps).
   Headless strips presentation; a structural test covers contracts, symmetry,
   spawn clearance and wall height.
3. **Reference review at three distances.** Chase camera, mid-arena, overview.
   Add a named capture view for each (the Woodland test has 14, including a
   sun-facing "glare" view, which catches specular problems).
4. **Build structures in Blender** with the shared helpers: bevels, real joints and
   hardware, grain UVs, material slots, short-distance baked AO. Match collision
   exactly where players touch.
5. **Use scanned CC0 material** graded to a palette; credit every source; never
   ship raw procedural noise as the main surface.
6. **Ground tells a story.** Bake masks for wear (tracks, wet, scorch, grass),
   displace on the GPU, hex-tile, and scatter from the same masks at every scale
   (grass, debris, pebbles, rocks).
7. **Vegetation from scans** (branch cards, grass patch atlases), never generic
   procedural cards.
8. **Lighting from a real sky** with the sun removed and the key light aligned;
   SSAO/SSIL, soft shadows, a mild filmic grade.
9. **Performance from the start.** Batch repeated pieces in MultiMeshes, chunk
   scatter into ~24 m cells with visibility ranges, cap crowd polycount (~350
   triangles per spectator), keep valley trees shadowless. Woodland runs at a
   6–16 ms median at 1600×900 on an RTX 3080 (static fixture). Benchmark with
   no other GPU work running; other sessions' render tests cause false spikes.
10. **Release discipline.** Commit Blender scripts plus outputs, import files from
    a clean pinned import, credits; run the Woodland/baseline/spawn tests. Arena
    geometry changes are client-side, but `ARENA_RULES` gates older clients.

## Where things live

- Gameplay: `scripts/arena/woodland_ground.gd`, `scenes/arenas/woodland_arena.tscn`,
  `scripts/core/arena_bounds.gd`, spawn height in `authority_world.gd`.
- Presentation: `scripts/arena/woodland_visuals.gd` (structures, lighting, terrain
  mesh), `woodland_flora.gd` (trees, scatter), `woodland_nature.gd` (valley,
  mountains), shaders `assets/materials/arena/woodland_*.gdshader` with shared
  helpers in `woodland_common.gdshaderinc`.
- Sources: `art_source/woodland/*.py`, `tools/bake_woodland_masks.gd`.
- Test and captures: `tests/presentation/woodland_arena_test.gd`
  (`-- --capture [--benchmark] [--view=name]`, output `exports/arena-review/`).
- Coordination record: [docs/coordination/A_WOODLAND_ARENA.md](../coordination/A_WOODLAND_ARENA.md).
