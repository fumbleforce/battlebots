# Woodland ramp-to-bunker jump (#42)

Woodland's four jump ramps now have a nominal **5.5 m** lip, replacing 3.6 m.
The collision wedge and Blender-generated `jump_ramp.gltf`/`.bin` use the same
height. Footprint, placement, bunker geometry, materials, rivets and plate detail
remain as authored. `build_structures.py -- --only jump_ramp` regenerates just
this asset; its default invocation still builds all structures.

Gameplay build **mvp-ab-31** gates the changed collision on clients and workers.
Protocol 11 and catalogue identity are unchanged. The existing build mismatch
rejection also protects LAN play; the arena ID/schema does not change. The
source of collision remains `woodland_ground.gd`; rendered assets never define
server physics. Mass/speed changes from #49 and wall-pin changes from #50 are
retained without modifying drive forces or tuning for this jump.

## Checks and player route

The regression uses a real tracked Atlas in the actual Woodland/Jolt world,
on both `JumpRamp24 → Bunker28` and the mirrored `25 → 29` pair. Start 28 m
behind the ramp centre and 1.5 m toward the bunker side, boost straight up the
ramp, then release throttle/Nitro and brake 1 m past the ramp centre. No jump
button, steering, added impulse or pose/velocity correction is used after the
run starts. Braking for the landing prevents overshooting the small roof.

The same commands with Nitro disabled stop on the ramp. With Nitro, the bot
becomes airborne and lands with its centre over the bunker's upward-facing
roof. After allowing one second for landing bounce, it must stay grounded on
that bunker for two seconds and finish upright at near-zero speed. This is a
controlled route; other approach speeds, armour weights, drive types and edge
lines are not asserted to have identical outcomes. The corresponding route
with the old 3.6 m wedge failed to reach the roof even with Nitro.

Twelve downward triangle intersections on the imported asset are compared with
actual Jolt ray hits on each mirrored ramp. The visible deck must remain within
its existing steel plate/rib/bevel thickness (up to 0.24 m) of the collision
wedge; a stale 3.6 m model fails this check. The physical lip is checked at
5.5 m separately. Baseline, Woodland structure and heavy-spawn checks pass.
The jump cases also pass after rebasing onto #49's mass-scaled speed model.

## Reproduction and evidence

```sh
blender --background --python art_source/woodland/build_structures.py -- --only jump_ramp
godot --headless --path battlebots --editor --import --quit
godot --headless --path battlebots --fixed-fps 60 --script res://tests/simulation/woodland_ramp_jump.gd
godot --path battlebots --max-fps 60 --script res://tests/simulation/woodland_ramp_jump.gd -- --capture
```

The headless case is registered in `tools/check-mvp.ps1`. Native captures go to
ignored `battlebots/exports/ramp-jump-review/`. Validation uses official Godot
4.7.2 and Blender 5.2.2 LTS. Native Forward+ on RTX 3080 reports the known seven
reflection-atlas Texture RIDs on shutdown (#18); script/shader failures remain
errors. [Retained measurements](evidence/woodland-ramp-jump/results.json) and
[native roof capture](evidence/woodland-ramp-jump/roof.png) record the tested route.
Hosted release acceptance is tracked on [#42](https://github.com/fumbleforce/battlebots/issues/42).
