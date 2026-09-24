# Rendering and load performance

Written 2026-09-23 during the Woodland optimisation pass (#34), after the user
reported 2 FPS when the giant boss hit. It records what worked, what to measure,
what to avoid, and what is still open. Numbers are from an RTX 3080 (Godot 4.7.2,
Forward+, Vulkan); treat them as relative guides, not budgets.

## Where things stand

- Woodland, 12-bot all-weapon brawl plus the Warden at 2560×1440: ~13.6 ms GPU
  median (uncontended). Static views: ~11–15 ms.
- Load: the Woodland scene builds in ~2.3 s of CPU, then its first drawn frame
  costs ~2 s of lazy shader/pipeline setup (see "Loading"). Loading screens and
  warm-up are tracked in #70.

## How to measure (do this before and after every change)

- **Windowed without a desktop window:** `xvfb-run -a -s "-screen 0 1920x1080x24" godot ...`
  renders on the real GPU (Vulkan) invisibly, so load and first-draw timings
  and captures work from a terminal session.

- **Stress, not static.** `tools/stress_woodland.gd` fights 12 bots with every
  turret, melee weapon, nitro and jumps next to the boss, reports frame/GPU/CPU/
  physics percentiles and peak effect counts, names new nodes in any stalled
  frame, and ends with paired on/off attribution of features. Static fixtures
  alone missed the combat-light collapse.
- **Static attribution.** `tools/profile_woodland.gd` hides one node group or
  toggles one environment/shadow feature at a time on fixed views.
  `tests/presentation/woodland_arena_test.gd -- --capture --benchmark
  --size=2560x1440` gives per-view GPU minima and captures for visual checks.
- **Use paired minima.** Measure on / off / on and compare minimum GPU time over
  ~20 frames. Other Godot processes (other sessions, a running game) share the
  GPU; averages then lie. Check `nvidia-smi` first; never kill someone else's
  process to get a clean number.
- **Split a stall** into process time and draw time (`frame_post_draw`) before
  guessing. `--verbose` shows shader variants being set up inside a frame.
- **Judge visuals from the gameplay camera** (chase view) with before/after
  captures of the same view. An optimisation the user can see is a regression.

## What worked

| Change | Why it helped | Typical win |
|---|---|---|
| Hide pooled dynamic lights while their energy is 0 | Dark but visible `OmniLight3D`s still cost clustered-light and shadow work every frame. | 5.3 → 0.3 ms in a brawl |
| Cap effect scale on giant bots | Effects scaled with a 3.5× bot became screen-filling overdraw. | removed the 2 FPS collapse |
| Terrain in chunks with distance LODs and a separate shadow-only proxy | A single dense terrain mesh draws every triangle in every shadow cascade. | 17.5 M → 4 M triangles/frame |
| Per-instance nodes for imported meshes with LODs | Godot mesh LOD and culling work per instance; one arena-wide MultiMesh keeps full detail everywhere. | large triangle cuts |
| `mesh_lod_threshold = 2.0` | Default LOD switching is conservative; 2.0 was invisible from the chase camera. | fewer triangles |
| Only structural pieces cast sun shadows | Bolts, rims, cloth and crowds are unreadable in shadow but cost every cascade. | ~1–2 ms |
| Shorter shadow distance, two cascades, filtered shadows instead of PCSS | Cascade count and blocker searches dominate shadow cost. | ~1.2 ms + ~0.6 ms |
| Visibility ranges per scatter group, thinned far copies | Chunked MultiMeshes with ranges cull small props cheaply. | draws and triangles |
| Shader work moved to the vertex stage or skipped when weight is small | Terrain layers sampled only where they contribute; macro noise per vertex. | ~1 ms terrain |
| Bake deterministic load-time data | Heights, scatter poses and collision hulls computed identically every load were seconds of GDScript. | load ~9 s → ~2 s |
| Load bot models in the background from the menus and keep them (`bot_model_warmup.gd`, #70) | Leaving a match freed the last reference, so every Woodland start reloaded the giant's Atlas MX GLBs on the main thread. | Woodland practice build 1.9–2.1 s → 0.45–0.65 s |
| Derive normals from neighbouring grid vertices | Re-sampling noise four extra times per vertex was most of the valley build. | 144 → 40 ms |

## Reminders

- Every arena needs a stress run with many bots and all weapons, not just a
  pretty static capture. Combat effects, lights and the boss are where frames die.
- Pooled effects (lights, particles, decals) must be hidden or disabled while idle.
  Keep effect scale capped for giant bots.
- Decide shadow casters deliberately. New decorative geometry should default to
  not casting.
- Baked caches need a drift test that regenerates and compares (the Woodland test
  does this for heights, scatter and hulls) and a documented bake command.
- Collision or placement data changes are gameplay: bump `WireCodec.BUILD`.
- Keep headless servers free of presentation work; they should not load render
  meshes or textures just to build collision.
- Commit only after before/after captures from the chase camera and a stress run.
- Record the measured numbers on the issue so the next pass has a baseline.

## Warnings (things that looked like wins, or cost us)

- **Do not "optimise" by pulling detail in close to the camera.** Scatter ranges of
  55–60 m left the ground empty in front of a giant tank; the chase camera sits well
  behind the bot. The user rejected it as "2013 style". Cull far, not near.
- **Do not trust a single-run average** or a run while another Godot process uses
  the GPU; attribution flipped sign under contention.
- **Do not replace another owner's scene nodes to change behaviour.** Swapping a
  shared effects node crashed a visual test; configure it through its API instead.
- **Do not merge imported LOD meshes into one big MultiMesh** and expect LODs to work.
- **Do not hand-edit `.import` files**; a clean pinned import rewrites them and it
  blocked a hosted release.
- **Warm caches do not remove first-use shader setup.** Each distinct material
  shader still builds its variants the first time it draws (~2 s for Woodland).
  Hide it behind a loading screen; don't mistake it for a runtime stall.
- **Measure before rewriting shaders.** Stubbing every procedural noise call in
  the Woodland shaders changed GPU time by less than run-to-run noise; the cost
  was geometry, shadows and overdraw, not ALU.
- **Occlusion culling needs occludable pieces.** Box occluders on all eight
  palisade faces culled almost nothing (the valley, mountains and forest sectors
  are a few huge objects never fully hidden) and doubled render CPU time. Only
  revisit if distant scenery is split into small chunks.
- **Know what a cost scales with before cutting detail.** Halving the near
  terrain grid removed only ~0.1 M triangles; the terrain's cost is its pixel
  shading, so coarser geometry would lose detail for nothing. Bot models already
  import with generated LODs and shadow meshes; their shadows cost ~0.2 ms in a
  brawl.
- **Beware many unique shaders.** Every distinct ShaderMaterial shader adds
  first-draw setup and pipeline variants; prefer shared shaders with uniforms.

## Ideas not yet done

- Loading screen plus material warm-up (render arena, bot and effect materials
  once behind the overlay or in the menus); threaded resource loading (#70).
- Build heavy presentation over several frames instead of in one `_ready`.
- Fewer, larger scatter chunks or GPU-driven scatter to cut draw calls
  (~5 k draws in a brawl).
- Cheaper combat particles (fewer, larger, shared materials) — owned with the
  weapon-feel work; measure with the stress tool.
- A graphics-quality preset that lowers shadow distance, SSIL/SSR and scatter
  density for weaker GPUs.
- Export with the Godot shader baker enabled for client presets once verified on
  Windows/D3D12.
