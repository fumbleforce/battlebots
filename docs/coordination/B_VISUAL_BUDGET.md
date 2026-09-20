# B visual budget measurement — completed audit

Branch `codex/b-visual-budget`, from main `e9dd2b7`. Measure the assembled bot assets
and newly combined damage/impact visuals in independent scenes. Two bots represent
current 1v1 scope; ten bots exercise the spec's provisional art budget without
implementing deferred multiplayer modes. No gameplay, physics, networking or A
world edits. Native frame times are local measurements, not platform certification.

Parallel geometry audit reports equipped triangle/mesh/material counts for all
20 authored combinations and inspects LOD configuration. Native fixture compares
two/ten intact bots against disabled components and capped impacts after warm-up.
Use measured evidence to identify optimization work; do not declare provisional
targets achieved merely because a scene loads.

## Recorded evidence

Godot 4.7.2 stable, Windows D3D12 Forward+, RTX 4080, 1920 x 1080, VSync disabled.
The [native report](evidence/b-visual-load-2026-09-20.json) records the final capture
run; each scenario warms for 120 frames and samples 240 wall-clock frame intervals.
Foundry is present, but bots are frozen, with no networking/HUD. These short samples
include OS/background contention; they are not full-game FPS or low-end acceptance.

| Bots | State | Median ms | P95 ms | Mean draw calls |
| --- | --- | ---: | ---: | ---: |
| 2 | Intact | 1.792 | 2.854 | 2,526 |
| 2 | Disabled + capped impacts | 2.473 | 3.772 | 2,993 |
| 10 | Intact | 5.399 | 6.644 | 9,951 |
| 10 | Disabled + capped impacts | 6.533 | 7.638 | 11,713 |

An earlier run measured ten damaged bots at median 6.825 ms/P95 8.131 ms, illustrating
run-to-run variation. Captures confirm all ten bots in view. The client stays at
64 sparks/20 fragments, with 36 smoke particles for two fully disabled bots and
180 for ten. Rendering primitive counters include arena and rendering passes;
they must not be interpreted as the assembled bot triangle count.

The [geometry report](evidence/b-geometry-budget-2026-09-20.json) covers all 20
drive/weapon combinations twice: default cosmetics and all optional guards/large
exhaust. Largest sampled assembly is walker/saw with optional modules: 39,056
highest-detail triangles, 427 meshes, 430 surfaces and 12 material resources.
Traction/saw reaches 429 meshes/432 surfaces despite only 26,360 triangles.
The maximum is among these 40 samples, not every cosmetic permutation.

Imported LOD generation and shadow meshes are enabled. The largest sample has
278 ArrayMesh surfaces: 214 have LODs and 141 have at least two. Its 152 procedural
surfaces have no imported LODs. The 25,516-triangle coarsest-per-surface bound is an
inventory calculation, not proof of actual distance-based LOD selection. Hidden
unequipped geometry is reported separately and excluded from visible counts.

## Checks and next work

`bot_geometry_budget_test.tscn` passes headless/native with matching counts.
`bot_visual_load_test.tscn` passes native resource-cap checks and writes its report
to TEMP. Use `-- --capture` for the four scene images. It intentionally has no
hardware-dependent FPS assertion and is not registered in the headless runner.
The geometry audit is registered there. Baseline passes.

Sampled triangle counts fit the provisional 40k upper target, but the complete LOD
and performance gates remain open. Hundreds of mesh instances per bot are the
strongest batching investigation lead; procedural geometry LODs need a separate
design. Do not change models or raise budgets based only on this RTX 4080 run.
The user requested pause after this audit; no optimization was started.
