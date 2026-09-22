# Atlas MX modular chassis — B, 22 September 2026

Owner: B. Branch: `codex/b-modular-chassis`, isolated worktree. User requested an
additional base chassis, broad addon suitability, and a major fidelity increase
matching the supplied yellow tracked industrial robot reference. Explicit user
visual approval is required before completion.

Reserved scope: original Blender authoring script/source, portable runtime
meshes/materials, chassis catalogue and garage integration, B assembly/visual
consumers, and focused asset/assembly/drive checks. Preserve all existing bots.
Keep the deck useful: real attachment rails, bolted service covers, accessible
primary/front, auxiliary/top, side, and rear hardpoints. Author in metres, Y up,
-Z forward, then use the existing uniform game-scale presentation contract.

Acceptance: actual model renders at reference-comparable angles; beveled designed
silhouette, modeled continuous track links/rollers, differentiated portable PBR
materials and restrained edge wear; usable exported addon transforms; legal
existing weapon/utility assemblies; imported Godot visual capture; relevant
checks and baseline; user approval. Concept art alone cannot meet acceptance.

Catalogue additions change content identity. B will document the exact final
catalogue hash and migration. A must build/deploy matching hosted workers and
validate external play before this content is described as online-ready. No live
restart is authorized by this asset task, and compatibility rejection stays.

Status: implementation in progress. No visual approval or hosted readiness yet.

## B runtime and shared consumer contract

Atlas is an additional fifth preset (`ContentRegistry.atlas()`, part `atlas_mx`).
The previous four presets and legacy saved chassis remain. It accepts the existing
six primary weapons and ordinary armor/utilities within the unchanged 120 kg /
100 power limits. Its authored tracked drive requires `traction`; incompatible
drive changes remain visible invalid drafts. Its auxiliary socket accepts the
existing minigun; duplicate primary/auxiliary miniguns remain invalid.

`AtlasGeometry` separates the source collision envelope from the shared weapon
authoring frame. Catalogue dimensions are `[7.02,1.5,7.8]`, retaining the existing
uniform scale of three; actual collision dimensions are `[7.02,3.33,7.8]`, with
local vertical limits `[-1.68,1.65]`. Track probes use the real floor depth. Body
mass, acceleration, braking, recoil and recovery still use the existing mechanics.
The model root is at body origin, Y up, -Z forward. Garage art uses scale one.

**Documented A/B integration:** B publishes `MvpBot.collision_bounds()` and
`ground_clearance()`. A's `AuthorityWorld.clear_spawn_pose()` consumes clearance
instead of assuming every nonwalking hull is 1.5 m tall. The helper preserves
the existing `WalkerDrive.RIDE_HEIGHT` calculation for Scorpion/Sawblade walkers.
Actual Atlas bounds also drive B contact clamping and damage zones, so lower
side-track impacts damage the drive rather than becoming underside core hits.
No other A simulation/network/menu behavior is changed by this contract.

Runtime asset: `res://assets/models/atlas_runtime/atlas_mx.glb`. Seven exported
`Mount*` transforms cover front, both roof rails, auxiliary, rear and both sides.
The front adapter joins the authored receiver to the existing primary weapon
frame. The default lifter uses `atlas_lifter.glb` under the existing animated
mechanism at source `(0,-0.12,-1.10)`; its contact mechanics are unchanged. Other
primary weapons retain their existing runtime mechanisms. The donor minigun is
translated by `(-0.18,0.27,0.42)` source meters, identically in presentation,
elevation aiming, breech occlusion ray and muzzle evidence.

Both drives animate forty actual tread shoes along the exported capsule loop;
wheel pivots rotate separately. Real equipped meshes join the existing component
damage/destruction groups. Authored optional groups make side/top/front/rear armor
and the three exhaust selections visible. They remain cosmetic; protection and
weight come from the canonical armor/utility slots.

Four existing appearance channels persist without a new payload schema. Default
Atlas colors preserve imported PBR materials. Custom enamel changes preserve
normal/roughness textures and exposed steel chips; metal/rubber are independent.
The Original action and its swatch resolve the selected chassis's authored color.

Catalogue revision 9 currently hashes to
`3e3bea8546acfb26cc2ba9db84b4a7d018e582bc9303006b88dba7311df09bdd`.
Revision-eight hash
`bf965dc8fdd5456ccddb23873d40f490885006eb70424a6a7c53c3db1fa4bf73`
is recognized for local saved-build migration; selected parts and appearance are
preserved. Live peers still require matching content. This is **not** evidence of
a deployed server; A must run the coordinated release before hosted acceptance.

## Integration verification, before upstream rebase

Pinned executable:
`C:/Users/jorge/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`.
Commands run from the repository root, with that executable represented by
`$atlasGodot` below:

```powershell
& $atlasGodot --headless --path battlebots --script res://tests/simulation/atlas_catalogue.gd
& $atlasGodot --headless --path battlebots --fixed-fps 120 --quit-after 8000 res://tests/simulation/atlas_grounded_modules.tscn
& $atlasGodot --headless --path battlebots --quit-after 400 res://tests/presentation/atlas_assembly_test.tscn
& $atlasGodot --path battlebots --max-fps 60 --quit-after 300 res://tests/presentation/atlas_assembly_test.tscn
& $atlasGodot --headless --path battlebots --script res://tests/simulation/content_smoke.gd
& $atlasGodot --headless --path battlebots --script res://tests/presentation/menu_profile_test.gd
& $atlasGodot --headless --path battlebots --quit-after 500 res://tests/presentation/garage_unlocked_options_test.tscn
& $atlasGodot --headless --path battlebots --fixed-fps 120 --quit-after 1000 res://tests/presentation/sawblade_test.tscn
& $atlasGodot --headless --path battlebots --quit-after 5000 res://tests/presentation/scorpion_garage_test.tscn
& $atlasGodot --headless --path battlebots --fixed-fps 120 --quit-after 2000 res://tests/simulation/minigun_physics.tscn
& $atlasGodot --headless --path battlebots --fixed-fps 120 --quit-after 2000 res://tests/simulation/scorpion_grounded_modules.tscn
```

These checks printed their PASS markers and exited zero. The native assembly
check used D3D12 Forward+ on the RTX 3080. After the final material export, the
native assembly check passed again, including an actual rendered frame containing
custom enamel shaders with non-null color/metal-roughness/normal maps. The required
`tools/check-baseline.ps1 -GodotPath <pinned executable>` then passed cleanly.
Logs: `%TEMP%/atlas-final-native-assembly.log` and
`%TEMP%/atlas-final-baseline.log`.

The Atlas grounded check uses normal commands against a full-health, grounded
wheeled opponent: saw 6, lifter 1, vertical spinner 2, horizontal spinner 4,
hammer 1, primary minigun 17 and auxiliary minigun 17 confirmed hits. It separately
checks unmodified authored spawn and round reset in Foundry/Moon with actual shape
intersection, preserved normal walking-drive spawns, track-zone classification,
powerful acceleration and normal braking. The combat-contact cases deliberately
position opponents; they do not stand in for the independent natural-spawn checks.

An independent static review found and prompted fixes for pivot-track direction,
spawn clearance, actual-height damage zones, and Original paint behavior. Its
second pass caught walker-height preservation before completion. The final static
review reports no remaining actionable integration issue; engine evidence above
was executed separately. Human visual approval, hosted play, and final integration
after fetching the concurrent upstream work remain open.
