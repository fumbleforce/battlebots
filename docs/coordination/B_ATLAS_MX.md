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

Status: second candidate implemented and locally verified; user visual approval
and final main-branch integration remain pending. No hosted readiness claim.

## B runtime and shared consumer contract

Atlas is an additional fifth preset (`ContentRegistry.atlas()`, part `atlas_mx`).
The previous four presets and legacy saved chassis remain. It accepts the existing
six primary weapons and ordinary armor/utilities within the unchanged 120 kg /
100 power limits. Its authored tracked drive requires `traction`; incompatible
drive changes remain visible invalid drafts. Its auxiliary socket accepts the
existing minigun; duplicate primary/auxiliary miniguns remain invalid.

`AtlasGeometry` separates the source collision envelope from the shared weapon
authoring frame. Catalogue dimensions are `[7.02,1.5,7.8]`, retaining the existing
uniform scale of three; actual collision dimensions are `[7.32,3.42,7.8]`, with
local vertical limits `[-1.74,1.68]`. Track probes use the real floor depth. Body
mass, acceleration, braking, recoil and recovery still use the existing mechanics.
The model root is at body origin, Y up, -Z forward. Garage art uses scale one.

**Documented A/B integration:** B publishes `MvpBot.collision_bounds()` and
`ground_clearance()`. A's `AuthorityWorld.clear_spawn_pose()` consumes clearance
instead of assuming every nonwalking hull is 1.5 m tall. The helper preserves
the existing `WalkerDrive.RIDE_HEIGHT` calculation for Scorpion/Sawblade walkers.
Actual Atlas bounds also drive B contact clamping and damage zones, so lower
side-track impacts damage the drive rather than becoming underside core hits.
No other A simulation/network/menu behavior is changed by this contract.

Runtime asset: `res://assets/models/atlas_runtime/atlas_mx.glb`. Eleven exported
`Mount*` transforms cover front, both roof rails, auxiliary, rear, both sides and
four supported corner sockets. Side mounts are at source `(±1.207,-0.02,0)`;
`MountCornerLeftFront/LeftRear/RightFront/RightRear` use `(±0.944,0.545,±0.96)`,
with negative Z at the front. Imported transforms are checked against the asset
manifest for all eleven named mounts.
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
The revised source palette uses sRGB primary `(0.92,0.615,0.05)` and secondary
`(0.16,0.183,0.195)`, stored as linear colors in the existing appearance record.
Its base paint uses texture roughness around 0.66 and secondary around 0.61;
the custom-paint path consumes the same roughness map and preserves exposed chips.

Catalogue revision 10 currently hashes to
`623a35b272a0d70feb57b7d4f0d0f298234b9608ab7ac4414945bec8404bd0ed`.
It includes upstream schema 2 and independent Nitro/charged-jump slots. Atlas
equips both by default; old schema-one saved builds retain both perks disabled.
Published revision-nine hash
`e8d254c8f6d2636fc2c1db7b329a78b04727f5061261a9dd8f437e9021b64bda`
migrates with its existing perk selections preserved. The unpublished first Atlas
preview hash is recognized too, so locally saved review builds remain usable.
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

## Post-rebase integration

The branch rebased onto `origin/main` at `8b1b1c3`, preserving the newly published
Nitro/charged-jump implementation and captured garage thumbnails. Atlas now uses
schema 2 with all seven slots. Revision-nine existing saves migrate without
changing selected perks, and genuine five-slot revision-eight saves migrate with
both abilities disabled, preserving the upstream migration policy.

Actual native mesh-bound measurements prompted the physical-envelope update
above. The collision bottom is now 1.74 m below origin, covering the real tread
shoes; A spawn wall clearance and B damage/autoaim consume the published physical
bounds. Normal weapon positions retain the established assembly frame.

Post-rebase executed checks: Atlas catalogue, extended Atlas grounded modules,
upstream perk abilities, content smoke, menu profile, garage unlocked options and
Sawblade all PASS. The extended grounded fixture additionally drives Atlas under
Nitro to above 8.5 m/s, then charges/releases its actual rigid-body jump with
upward speed above 5 m/s, using ordinary commands. Run it with
`--headless --path battlebots --fixed-fps 120 --quit-after 10000
res://tests/simulation/atlas_grounded_modules.tscn`. Upstream perk regression uses
`--headless --path battlebots --fixed-fps 120 --script
res://tests/simulation/perk_abilities.gd`.

The first post-rebase Scorpion garage attempt encountered the newly introduced
thumbnail renderer class before an editor rescan; it did not pass. The clean
rerun is recorded below. The user's first visual review requested changes to
socket mounting, side-panel construction and material response; the second
candidate addresses those requests and still requires explicit visual approval.

## Second candidate: final runtime verification

The final exported base bounds are source `[-1.2176,-0.578425,-1.256427]` to
`[1.2176,0.559,1.256427]`. The collision envelope now includes the raised corner
caps: source size `[2.44,1.14,2.60]` centered at Y `-0.01`, preserving the existing
source floor depth `0.58`. This last height adjustment changes neither the
catalogue hash nor the canonical weapon frame.

Executed with the pinned executable above, from the repository root:

```powershell
& ./tools/check-baseline.ps1 -GodotPath $atlasGodot
& $atlasGodot --path battlebots --max-fps 60 --quit-after 500 res://tests/presentation/atlas_assembly_test.tscn
& $atlasGodot --headless --path battlebots --quit-after 5000 res://tests/presentation/scorpion_garage_test.tscn
& $atlasGodot --headless --path battlebots --script res://tests/simulation/atlas_catalogue.gd
& $atlasGodot --headless --path battlebots --script res://tests/presentation/menu_profile_test.gd
& $atlasGodot --headless --path battlebots --quit-after 500 res://tests/presentation/garage_unlocked_options_test.tscn
& $atlasGodot --headless --path battlebots --fixed-fps 120 --quit-after 10000 res://tests/simulation/atlas_grounded_modules.tscn
```

Every command printed its PASS marker and exited zero without engine/script
errors. The required baseline and grounded modules were repeated after the final
collision-height adjustment and both passed. Logs are under `%TEMP%` with names
`atlas-v2-baseline.log`, `atlas-v2-native-assembly.log`,
`atlas-v2-scorpion-garage.log`, `atlas-v2-catalogue.log`, `atlas-v2-profile.log`,
`atlas-v2-garage.log`, and `atlas-v2-grounded.log`.

Native assembly used D3D12 Forward+ on the RTX 3080. It checked all eleven
imported mount transforms against the exported manifest, actual lifter assembly,
track animation, optional modules, per-build paint isolation and preserved PBR
maps. The primary enamel's imported roughness map remains above 0.5. The new
garage thumbnail pipeline captured Atlas into its 256-by-160 viewport; the test
verified visible model pixels and that all visible default hull/track/lifter mesh
bounds remain in frame. Current presets, save/reload and chassis-specific Original
colors passed, as did the existing Scorpion garage presentation regression.

The final grounded check again covered natural Foundry/Moon spawn/reset,
preserved walking-drive height, physical damage zones, acceleration/braking,
Nitro and charged jump. Confirmed primary hits were saw 6, lifter 1, vertical
spinner 3, horizontal spinner 4, hammer 1 and minigun 17; auxiliary minigun had 17.

An earlier verification attempt overlapped editor import with native assembly;
Godot reported an import MD5 error and the native process observed a temporarily
missing texture cache. That attempt was rejected, and the clean evidence above
comes from sequential import/baseline followed by native execution. No cache
failure was waived. `git diff --check` is clean apart from line-ending notices.

The final hidden-shell clearance revision was then imported independently with
`--headless --path battlebots --editor --import --quit`; its first import passed
without errors (`%TEMP%/atlas-v2-last-import.log`). Native assembly was repeated
afterward and again printed `ATLAS ASSEMBLY PASS`, checking the final exported
GLB and captured thumbnail. This last source change does not alter the published
physical bounds or gameplay parameters.

Runtime verification does not establish the requested visual approval or hosted
release acceptance. Both remain open; the catalogue revision requires A's matching
client/server release and external duel/rematch verification.

## Visual revision and final native evidence

The rejected candidate had poorly seated corner sockets, an incoherent side
assembly and excessive gloss. The revised sockets sit on extended supported
fenders; the thick slotted casting, inset gasket and structural carrier share
one outline and four inset through-bolts. The upper return roller sits behind
the carrier. Paint now has a matte roughness response, restrained irregular wear
and separate exposed-steel highlights. These changes are visible in actual Godot
captures, not only the Blender studio renders.

Final static geometric review found and removed a concealed 9 mm shell/track-pin
overlap by narrowing only the inner shell. A Blender triangle-intersection check
on three previously intersecting upper-strand links then returned zero shell
intersections. Visible armor, mounts and published physical bounds are unchanged.
This check is scoped to the corrected shell/track contacts, not every possible
animated surface contact.

Final Godot 4.7.2 Forward+ captures are under
`battlebots/exports/atlas-review-v2-final`: hero, rear, side, top, mounting detail,
production Foundry practice and the actual garage. The garage capture reports
no clipped mesh bounds. The run exited zero with the known seven-texture RID
shutdown warning. The tracked [native report](evidence/b-atlas-native-2026-09-22.json)
records 72,071 base triangles and 95 visible mesh instances. This exceeds the
older provisional 20k–40k target; automatic imported LODs are enabled.

Its bounded RTX 3080 sample used 120 warmed uncapped frames at 1800-by-1350 with
4x MSAA and four practice bots: median 3.536 ms, p95 8.386 ms, maximum 9.222 ms,
203 visible draw calls and 386,159 visible primitives. Engine video-memory usage
was 1,861.94 MiB. This is a short static-camera native sample without HUD or
networking, not a ten-bot, lower-hardware or long-session performance acceptance.

The user has been shown the second native candidate and asked for explicit
approval. No approval has been received at this checkpoint.
