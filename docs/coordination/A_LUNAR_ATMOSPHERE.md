# Godot lunar atmosphere — Dev A, 20 September 2026

## Follow-up: dark backdrop and inward-facing floodlights

`codex/a-lunar-backdrop` starts from integrated `393ea31`. The user correctly
identified that sun-facing mountains were still bright and requested floodlights
angled toward the arena. The first pass lowered broad lighting without adequately
separating the geology from the combat space.

CraterRidges and FracturedRock batches now use exclusive render layer 2. The
existing sun keeps its 0.55 energy on the base/floor/bots; a shadowed 0.07 key
with the same orientation illuminates only geology. Both retain all shadow
casters. The backdrop key contributes no GI, sky lighting or fog scattering.
This is deliberate art direction, not a physical claim about sunlight distance.
Physics layers, meshes, materials, gravity and spawn locations are unchanged.

Each tower's housing and six lens faces tilt together toward its actual arena
target. The spotlight originates just ahead of the lenses, with a 28-degree
half-cone, 32 m range and shadows on all eight towers. Floodlight masks exclude
the backdrop. An independent engine inspection measured all eight beam axes
32.326 degrees downward, the cone top 4.326 degrees below the horizon, and all
48 lens normals aligned with their beams (minimum dot product 0.99999994).

Moon arena and lunar asset checks pass first attempt, exit 0, with no errors or
warnings. Final-tree baseline also passes first attempt, exit 0, with no warnings,
errors or crash markers. Native 1440p arena/outpost/reverse captures and complete scene removal
pass on the final production tree, exit 0. Only the previously documented seven
texture-RID shutdown warning remains. The final captures are under ignored
`exports/lunar-backdrop/`; check logs are under `exports/lunar-atmosphere/`.

The first comparison tool changed mesh layers during rendering and triggered
[Godot issue 121989](https://github.com/godotengine/godot/issues/121989) on teardown.
The review tool now captures production settings only in a fresh process, keeping
the same three views. It explicitly draws frames so review can complete while
occluded. The optional full cinematic benchmark was stopped after it stalled
following its second capture; no new benchmark or movement-pass claim is made.
The final production capture, unlike that benchmark, completes scene teardown
and does not report the light-unpairing errors. Older before/after captures remain
historical evidence of the first pass below.

Godot's [light masks](https://docs.godotengine.org/en/4.7/classes/class_light3d.html#class-light3d-property-light-cull-mask)
do not filter GI or volumetrics; the new rim light explicitly disables those
contributions. The existing baked bay indirect lighting remains unchanged.

## First atmosphere pass (integrated as 393ea31)

Branch `codex/a-lunar-atmosphere`, based on current main `69dbbce`. The user
returned from the isolated Unreal experiment to Godot and requested a less bright,
more atmospheric Moon base, especially the surrounding mountains.

## Scope

Only the Moon presentation lighting changes. Ambient fill falls from 0.15 to
0.04; the directional key falls from 1.25 to 0.55, becomes cool neutral, and moves
from 28 to 16 degrees above the horizon for longer shadows. Tower floodlights
retain energy 3.0 and become warm, keeping readable pools on the combat floor
against the cooler crater. Exposure and global fog density remain unchanged;
SSAO, localized dust, reflections and the existing bay indirect bake remain.

No geometry, materials, authoritative terrain, gravity, spawns, bots, controls,
networking or Foundry settings change. The original main checkout has unrelated
HUD work and is untouched. Unreal and the unfinished `codex/a-lunar-fidelity`
geometry/material experiments remain separate; they are not dependencies of this
focused correction.

## Review

`battlebots/tools/review_lunar_atmosphere.gd` captures native 2560x1440 before/after
views from identical arena, outpost and reverse angles, holding the vent/beacon
phase fixed. Output is ignored under `battlebots/exports/lunar-atmosphere/`.
The before variant restores main's previous light values. The after variant uses
the production environment. Captures show darker ridge valleys and cool lit
crests, retained warm floor pools, readable bay panels and a clear black sky.
This is a lighting correction, not reference-level asset fidelity acceptance.

Initial capture on Godot 4.7.2/D3D12 Forward+/RTX3080 exits 0 with the completion
marker. It retains the previously documented seven leaked texture RID shutdown
warning; no script or shader errors.

Baseline, Moon arena (terrain/gravity/spawns/headless exclusion), lunar asset
receivers and Moon ENet session/reconnect checks all pass on their first runs,
exit 0 and no warning/error/crash markers. Existing two-bot cinematic movement
and effect lifecycle fixture also passes, exit 0, with the same seven-RID warning.
Inspected its arena/reverse captures as well as all three comparison views.
Its 1080 frame samples at a 120 FPS cap report p95 10.378 ms and sampled system
GPU memory 5320 MiB; this is incidental fixture evidence, not a full-game budget
or human readability certification. Logs are in ignored
`exports/lunar-atmosphere/checks/` and `movement-check.log`.

The focused lighting correction is ready for main integration. Broader geometry,
material fidelity and human playtest acceptance remain separate work.
