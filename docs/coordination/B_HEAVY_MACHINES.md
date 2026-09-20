# Three-times-larger heavy machines — B

Branch `codex/b-heavy-machines`, based on main `de4fd0e`.
User request: machines three times as large, with heavier battle-machine driving.

Canonical chassis dimensions grow by exactly three on every axis; keep body and
collision transforms unscaled. `BotScale.from_size(size)` maps the canonical hull
height back to the original 0.5m authoring dimensions. Authored Sawblade dimensions
already follow size and must not be scaled twice. Catalogue revision seven rejects
incompatible servers and migrates known revision-six saves without part changes.
Installed mass/power budgets and drive-package top speeds remain design stats.
The user clarified that these are extremely powerful machines with strong torque;
hard acceleration and decisive turns accompany physical inertia and neutral coast.

B owns catalogue/migration, physical drive and replay, collision/weapon geometry,
walker support, camera, bot visuals/garage framing and regression fixtures. Narrow
shared integration is explicitly reserved for AuthorityWorld spawn clearance,
MvpSession practice spacing, BotWorldMarkers height and their affected fixtures.
No arena expansion, match rules or wire field changes are planned. This documented
handoff keeps A's producers/consumers compatible with the newly sized machines.

Validate independent live Jolt handling, scale/collision/contact, weapon geometry,
camera/garage, spawn clearance and accepted network replay. Baseline and required
affected checks must pass before direct-main integration. Matching hosted workers
are required before online acceptance; this B increment must hand A the new content
identity explicitly, and must not restart the single-Machine host during play.

## Spawn and marker integration

The narrow A-consumer handoff updates only `AuthorityWorld`, practice placement
in `MvpSession` and `BotWorldMarkers`. Authored arena markers and the 50m floor
remain unchanged. `AuthorityWorld.clear_spawn_pose` retains marker lane/facing,
pulling the two outer five-player slots inward enough for the enlarged hulls to
clear the octagonal corner walls by 0.25m. It uses the actual oriented hull support
against all eight wall planes. Existing six-meter team lane spacing clears even
the widest 5.4m hull. A spawn's fallback `last_floor` starts at its cleared pose.

Spawn height clears the full physical footprint, including the lunar height-map
cell vertices beneath it, with 0.05m spare height. Walkers use their physical 2.85m
ride height. Practice centers its two bots around the arena center, separates
their hull ends by six meters, and applies the same terrain clearance. Restart
keeps those new poses. Detached badges sit 4.2m above the body pose, with stems
starting at 3.45m to clear the tallest authored rear pack; the public BotView
schema and fixed-screen-size health bars are unchanged.

Focused Godot 4.7.2/Jolt validation passed:

- `heavy_spawn_test.gd`: physical shape queries for main hull and authored rear
  pack, using the widest hulls plus walkers in Foundry and Moon, across duel,
  existing 2v2/5v5/eight-player FFA and public practice. No terrain, wall or peer
  intersection; independent full-hull wall-plane checks; body transforms unscaled.
- `five_v_five_rules.tscn`: original separation, settled-position, facing, reset
  and match-rule checks pass with physical-height spawn mapping.
- `practice_session_test.gd`: restart and a real public-command hammer hit pass
  after dimension-derived approach placement (target 263.34/300, three events).
- `world_markers_test.gd` and `world_markers_game_test.gd`: marker identity,
  health, accessibility, movement and authored rear-pack clearance pass.
- `ffa_session.tscn`, real-time profile zero: four/eight-player matches, exact
  health replication, reconnect/rematch and physical spinner contact pass. The
  contact fixture now separates hulls by their actual lengths plus a scaled gap;
  no distance, health or networking threshold was relaxed.

These local checks do not establish a matching deployed hosted-server release.

## Enlarged network fixture follow-up

`contact_reconciliation`, `horizontal_spinner_session`, `hammer_session`,
`saw_session`, `wall_contact` and `sawblade_session` now place actual-size hulls
at floor height. Contact setups derive longitudinal separation from hull lengths;
the lateral disc contact and saw reach scale by three. Ram speed remains 8m/s
with the original 1.9m free approach gap. Wall coordinates remain arena-relative.
The walker obstacle and required climb height scale by three; it starts 0.6m
ahead of the hull. Existing .25m/10-degree/250ms, exact damage, cadence, recovery,
movement and bounded-observation gates remain unchanged.

Contact, horizontal spinner, hammer and saw pass at profiles zero and 80ms.
At 80ms, worst contact settling was 183.3ms, with lifter 166.7ms and spinner
133.3ms. North/chamfer wall tests pass at their explicit 80ms profile, each with
121 physical-contact samples, .016m peak error and 0ms release settling.
Sawblade walker sessions pass at zero/80ms with maximum corrections .112/.199m.
The separate actual-ENet Moon handshake/reset/reconnect test also passes.

At 150ms, horizontal spinner, hammer and saw pass (horizontal settling 166.7ms;
hammer maximum error .004m; saw cadence and presentation gates unchanged).
The contact spinner case exposed a reproducible residual: .289m vertical error
at the end of its 45-frame observation, while angular error remained below two
degrees. The initial .21m ground-probe margin incorrectly retained ground state
through the launch. Restoring an absolute .07m margin corrected airborne flags,
but the residual still reached .312m with client vertical velocity repeatedly
clipped to zero at corrections. This was retained as a failed 150ms contact gate
while the primary drive/replay investigation resolved the cause. The existing
`BATTLEBOTS_CONTACT_TRACE=1` mode now records weapon positions, velocities and
ground flags. Failure evidence is `%TEMP%/heavy-contact-150-trace.log` and
`%TEMP%/heavy-contact-150-probe07.log`; no gate was loosened or failure retried away.

The primary fix sweeps the replayed hull's resulting orientation from the
authoritative snapshot origin. Previously the sweep used the old tilted hull,
blocking downward center motion even while rotation toward upright cleared the
floor. The corrected 150ms contact run passes with spinner settling 150ms,
impulse 183.3ms, lifter 166.7ms, ram 150ms and recovery 0ms. Follow-up contact80
also passes (worst 183.3ms; spinner 133.3ms). North/chamfer wall80 retains its
121 physical-contact samples, .016m peak and 0ms settling on both walls, with
the original finite-bounds and reverse-drive checks intact. Final trace/logs:
`%TEMP%/heavy-contact-150-finalbasis.log`, `heavy-contact-80-finalbasis.log` and
`heavy-wall-80-finalbasis.log`. Heavy-spawn and public practice-reset/hammer-hit
tests also pass after the drive/replay correction.

## Physical presentation and workshop framing

Primitive weapons and WalkerLegs now assemble in canonical authoring coordinates,
then apply BotScale.from_size exactly once. This retains Sawblade's reciprocal
art-scale compensation and preserves the actual world weapon radii, mounts and
limb lengths. Walker foot transforms retain world scale; terrain reach, stepping
clearance and world-space movement thresholds follow the physical dimensions.
Authored Sawblade body, wheels, tracks and authored weapon geometry already derive
from the supplied hull size and receive no second multiplier.

GarageBotPreview supplies catalogue size / BotScale.FACTOR, preserving the existing
plinth, inspection camera, rotating featured vehicle and canonical walker stance.
The runtime camera consumes the existing anchor's bot_scale metadata. Physical
anchor/contact-clearance scale remains three, while the authored camera boom grows
by two: 12m default, 8-18m zoom, 1m increments. Rebinding preserves relative player
zoom; sensitivity, inversion, recenter settings and arena bounds are unchanged.

Destruction cloud, shockwave, sparks, fragments, trajectories and light range grow
with the body without increasing effect counts. Component damage supplies
set_geometry_scale() for noncompounding plume sizing and motion; damage thresholds
and particle counts are unchanged.

Godot 4.7.2 validation passed:

- heavy_visual_scale_test: headless and native D3D12. All five primitive and authored
  weapon assemblies, walker feet and mounts grow exactly threefold; workshop models
  remain canonical; camera bounds/zoom/rebinding and complete robot framing pass.
  Explosion dimensions/trajectories and unchanged particle budgets pass; MultiMesh
  transform assertions run natively because the dummy renderer returns identities.
- all_body_weapons_test: headless and native, including original authoring fixtures
  and enlarged hulls. Composed world radii replace the obsolete unit-root assumption.
- walker_test: headless and native. The course uses two 1.05m steps and a 9m blocking
  wall; traversal time grows with course length instead of relaxing clearance gates.
  Final platform height 4.950m, peak 4.978m, z=-8.605m. Original 8cm ride-height and
  foot-penetration/contact tolerances remain; inversion and lunar stance pass.
- Headless camera_arena, camera_contact, camera_settings, camera_terrain,
  camera_round_lifecycle and camera_duel_lifecycle fixtures pass. Terrain coverage
  uses the actual enlarged hull/default boom. Its dedicated tight-ceiling scenario
  sets a proportional exported camera probe to retain deliberately insufficient
  clearance; the ordinary runtime probe remains 0.25m.
- Headless garage_preview, garage_showcase, featured_vehicle, sawblade,
  component_mesh_mapping, component_damage, destruction_visual and
  destruction_runtime fixtures pass.

Native 1280x720 captures at %TEMP%/heavy-gameplay.png and heavy-garage.png were
visually inspected: the complete larger robot fits the closer gameplay camera in
unchanged Foundry geometry; the workshop walker fits its original plinth/view.
These are focused correctness/framing checks, not a rendered performance budget
certification or hosted-release acceptance.

## Handling, combat and complete duel evidence

Live drive and replay share 8m/s² reference acceleration (scaled by installed
mass), 4/s throttle and steering response, 1.65rad/s low-speed yaw target,
4.5rad/s² yaw acceleration, 1.1m/s² neutral coast and 9m/s² braking. Grip and
drive-package top speeds remain canonical. The motor torque cap grows with the
square of geometry scale, matching the enlarged Jolt inertia so the actual body
can deliver the strong requested pivot acceleration. Recovery torque remains
proportionate to inertia too. Ground-probe depth
uses half hull height plus an absolute 0.07m contact tolerance.

- `heavy_drive_test.tscn`: actual unscaled Jolt body/collider, acceleration, coast,
  braking, pivot, reversing, missing-command failsafe, 250ms live/replay agreement
  and recovery pass. Final powerful calibration measured 8.529m/s after 1s
  acceleration and 10m/s at 1.4s, 7.151m/s after 1s coasting from 10m/s, 5.639m
  stopping distance and 1.543rad/s after 0.75s pivot. After 0.5s reverse intent the
  bot still travels forward at 5.934m/s, reaching backward cruise within 3s.
  Maximum live/replay steering error was 0.0394m / 0.493 degrees, within the
  unchanged 0.08m / 2-degree acceptance. This supersedes the initially slower
  handling calibration, following the user's explicit powerful-machine direction.
  Independent real-Jolt replay queries additionally verify descent while righting
  a tipped hull, preserved downward velocity while above the floor, actual floor
  clamping and full-hull wall-sweep protection after the orientation correction.
- `content_smoke.gd`: exact dimensions for every chassis and a painted revision-six
  walker save retain parts/name/cosmetics; invalid and unknown hashes still reject.
  Garage unlocked-options, repair and recovery checks pass.
- `scaled_combat.tscn`: independent rendered-mesh probes across all fifteen
  chassis/weapon combinations, grounded/raised/launch lifter tips and outside
  reach checks pass. This exposed an existing authored lifter query floating above
  its visible low blade; its box now includes the actual leading edge. Damage,
  impulse strength and cadence values are unchanged. Horizontal spinner, hammer,
  saw state/visual/physics and combat_physics_smoke pass, including actual flipping,
  pin handling, simultaneous kills and recovery (upright dot 0.9994).
- `tools/check-gameplay.ps1`: NATURAL DUEL PASS in 89.4s with 16 actual hammer
  hits, two round wins, results and an active rematch. Scripted approach/attack
  distances follow the enlarged hull/weapon envelope; normal commands, health,
  cooldowns, damage and match rules remain in force. Repeated after the final
  powerful-drive/torque changes with the same full outcome; evidence is
  `%TEMP%/battlebots-powerful-natural.log`.
- General `session_smoke.gd` profile80 passes with 0.166667m p95 correction for
  the final powerful motor/torque calibration (unchanged 0.25m gate);
  airborne_replay passes with zero position/velocity error and 0.040 degrees
  angular error. App integration and ten-body headless stress pass (0.874ms p95
  frame wall time; this is not rendered performance acceptance).
- Baseline, original drive smoke and combat-impact game presentation pass.
  New heavy-drive, spawn, scaled-combat and heavy-visual fixtures are registered
  in their existing gate scripts. These are focused checks; the full aggregate
  MVP suite was not run for this increment.

Final powerful-drive contact150 also passes: worst settling 183.3ms, spinner
150ms and ram 133.3ms, against the unchanged 250ms / 0.25m / 10-degree gates.
Wall80 retains 121 physical contact samples per wall, 0ms release settling and
0.007m north / 0.010m chamfer peak error. Final evidence is
`%TEMP%/battlebots-powerful-finaltorque-contact-150.log`,
`battlebots-powerful-finaltorque-session-80.log` and
`battlebots-powerful-wall-80.log`. Strong yaw torque is independently compared
against live Jolt in heavy_drive_test; session_smoke's straight-line driving
phase separately covers acceleration/replay.

## Hosted release handoff to A

Revision 7's normalized catalogue SHA256 is
`45bb581a3c4403fd74ce7067150eb480148e70a6e5b8dba9a5977dda95db25be`.
The live `https://battlebots-fumbleforce.fly.dev/healthz` response inspected on
20 September still reports build `mvp-ab-12`, protocol 4 and content hash
`63b655000dc8129c3cd52cb735ecfaec5cbc7cdb1513b43de024383e7473e8a5` (revision 6).
Existing compatibility gates therefore reject the new content against those
workers. No health manifest, protocol or compatibility bypass was introduced.

A must build matching client/server artifacts from the integrated tested commit,
establish a playtest break before the single-Machine restart, retain rollback,
deploy the actual updated workers, compare live health compatibility and run
`tools/check-hosted.mjs --endpoint https://battlebots-fumbleforce.fly.dev
--duel-only --godot <pinned Godot executable>` through results/rematch. No client
package or hosted deployment was produced by this B source increment, and no
external online acceptance is claimed.

## Integration verification

The initial rebase included battle soundtrack `ac2bda4`. The final source at
`f77dd58` also includes completed sampled audio `a972308` and main-menu cleanup
`deebff3`. Documentation insertions were combined, retaining both owners' entries.
GarageBotPreview's new compact APIs and physical-size normalization compose
without conflict. After this final rebase, `tools/check-drive.ps1` passes editor
import, baseline, original drive and powerful enlarged Jolt/replay regressions.
Main-menu fit, featured vehicle, garage showcase/preview and heavy visual scale
checks all pass on the combined source. Source diff whitespace validation passes.
The separate working checkout's unrelated project/import edits remain untouched.
