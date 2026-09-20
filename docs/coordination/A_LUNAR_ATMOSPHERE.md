# Godot lunar atmosphere — Dev A, 20 September 2026

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
