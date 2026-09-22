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

Status: fourth visual revision in progress. The user accepted the direction of
the shape but rejected the third candidate's simple/plastic material style.
Approval and final integration remain pending. No hosted claim.

Third-revision scope: slate-grey single-layer tread shoes with visible moving
connecting bands; darker orange enamel and brighter chamfer edges; correct
roller/carrier clearances; shorter track guards with centered corner sockets and
no black corner overplates. B owns the source asset and its narrow runtime
animation/material consumers. Preserve existing weapon mechanics and loadout
contracts. Re-export and inspect actual native Godot close-ups before approval.

## B runtime and shared consumer contract

Atlas is an additional fifth preset (`ContentRegistry.atlas()`, part `atlas_mx`).
The previous four presets and legacy saved chassis remain. It accepts the existing
six primary weapons and ordinary armor/utilities within the unchanged 120 kg /
100 power limits. Its authored tracked drive requires `traction`; incompatible
drive changes remain visible invalid drafts. Its auxiliary socket accepts the
existing minigun; duplicate primary/auxiliary miniguns remain invalid.

`AtlasGeometry` separates the source collision envelope from the shared weapon
authoring frame. Catalogue dimensions are `[7.02,1.5,7.8]`, retaining the existing
uniform scale of three; actual collision dimensions are `[7.32,3.33,7.8]`, with
local vertical limits `[-1.665,1.665]`. Track probes use the real floor depth. Body
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
`MountCornerLeftFront/LeftRear/RightFront/RightRear` use `(±0.93,0.545,±0.69)`,
with negative Z at the front. Imported transforms are checked against the asset
manifest for all eleven named mounts.
The front adapter joins the authored receiver to the existing primary weapon
frame. The default lifter uses `atlas_lifter.glb` under the existing animated
mechanism at source `(0,-0.12,-1.10)`; its contact mechanics are unchanged. Other
primary weapons retain their existing runtime mechanisms. The donor minigun is
translated by `(-0.18,0.27,0.42)` source meters, identically in presentation,
elevation aiming, breech occlusion ray and muzzle evidence.

Both drives animate forty actual tread shoes and forty separate connector frames
along the exported capsule loop. Each connector carries two slate strips between
its neighboring shoes. Wheel pivots rotate separately using source radii 0.388 m
for main wheels, 0.120 m for lower rollers and 0.105 m for return rollers.
Real equipped meshes join the existing component
damage/destruction groups. Authored optional groups make side/top/front/rear armor
and the three exhaust selections visible. They remain cosmetic; protection and
weight come from the canonical armor/utility slots.

Four existing appearance channels persist without a new payload schema. Default
Atlas colors preserve imported PBR materials. Custom enamel changes preserve
normal/roughness textures and exposed steel chips; metal/rubber are independent.
The Original action and its swatch resolve the selected chassis's authored color.
The revised source palette uses sRGB primary `(0.86,0.51,0.055)` and secondary
`(0.205,0.225,0.235)`, stored as linear colors in the existing appearance record.
Its base paint uses texture roughness around 0.66 and secondary around 0.61;
the custom-paint path consumes the same roughness map and preserves exposed chips.
The clean `Atlas_PaintPrimaryEdge` chamfer material follows primary paint with
the authored linear-color lift `min(channel * 1.15 + 0.025, 1)`, keeping edges
slightly brighter in custom colors. Its imported roughness and metallic response
are preserved. Original colors retain every imported material without overrides;
the steel appearance channel remains independent of primary paint.

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

The user rejected the second native candidate and requested shorter corner
guards, centered sockets, simpler connected slate tracks, brighter painted
chamfers, a richer yellow/slate palette and correction of the wheel/armor overlap.
The evidence above remains the historical second-candidate record.

## Third candidate: runtime and verification

The current runtime contract above reflects the third source export. Its measured
base bounds are source `[-1.2176,-0.554118,-1.234171]` to
`[1.2176,0.5486,1.234171]`. Source collision size is `[2.44,1.11,2.60]` centered
at zero, with source floor depth `0.555` and game clearance `1.665`. The canonical
weapon scale, part stats and catalogue hash remain unchanged.

Eighty independent `TrackConnector_{L|R}_{00..39}` frames animate halfway between
the eighty shoes along the existing capsule. Their shared imported mesh contains
two slate straps. Connector phases are discovered from the imported rest poses;
they preserve their authored basis, move with the appropriate left/right drive,
and participate in existing drive damage/destruction groups. Lower wheel rotation
now uses the revised 0.120 m roller radius. Primary painted chamfers preserve the
specified brighter color after repainting and retain their imported material
response; selecting Original leaves imported materials unchanged.

Executed with the pinned Godot 4.7.2 executable after the completed third export:

```powershell
& ./tools/check-baseline.ps1 -GodotPath $atlasGodot
& $atlasGodot --path battlebots --max-fps 60 --quit-after 500 res://tests/presentation/atlas_assembly_test.tscn
& $atlasGodot --headless --path battlebots --fixed-fps 120 --quit-after 10000 res://tests/simulation/atlas_grounded_modules.tscn
```

All three commands printed their PASS markers and exited zero. Native assembly
used D3D12 Forward+ on the RTX 3080. It verified eighty distinct connector frames,
their placement between the actual neighboring shoes, tangent alignment, coverage
of both shoe inner-edge gaps by imported strap mesh bounds (8 mm bevel/chord
tolerance), reverse travel, loop wrapping and return to imported rest transforms.
It also passed the six primary weapon assemblies, eleven mounts, actual thumbnail
capture/framing, Original/custom paint and lifted-edge checks. This is scoped
geometric coverage, not a claim of exhaustive triangle collision checking.

The grounded fixture passed natural Foundry/Moon spawn and reset, previous walker
spawn clearance, revised top/underside zones, acceleration/braking, Nitro and
charged jump. Confirmed primary hits were saw 6, lifter 1, vertical spinner 2,
horizontal spinner 4, hammer 1 and minigun 17; auxiliary minigun confirmed 17.
Logs: `%TEMP%/atlas-v3-baseline.log`, `%TEMP%/atlas-v3-native-assembly.log` and
`%TEMP%/atlas-v3-grounded.log`.

The first editor import reported `get_multiple_md5` errors while importing repeated
texture dependencies and was rejected. That failure is preserved in
`%TEMP%/atlas-v3-initial-import-failure.log`. A separate second import/baseline was
clean, and native/grounded execution followed sequentially; no failing import was
accepted as validation. Final visual captures are a separate review step. User
visual approval and A's coordinated hosted release remain outstanding.

Third-candidate native evidence is preserved in
[the V3 report](evidence/b-atlas-native-v3-2026-09-22.json), including the exact
side close-up and eight captures under `battlebots/exports/atlas-review-v3`.
The [bounded clearance report](evidence/b-atlas-v3-clearance-2026-09-22.json)
and adjacent Blender script record 534 mesh-pair checks against the saved source:
zero unintended intersections, with intentional central axle contacts excluded.
The report specifies scope, exclusion rules and exact source/runtime hashes.

The user found the shape substantially improved but rejected the material style
as too simple/plastic. The next iteration must replace uniform bright edges and
repeated face-mapped scratches with localized exposed-metal wear, primer, varied
physical metal surfaces and contact occlusion. Rounded machined fasteners and
roller surfaces are also required by the supplied close-up comparison. This
checkpoint is not visual acceptance; geometry alone does not satisfy the goal.

## Fourth candidate: physical surfaces and hardware

The source now separates thin metal edge chamfers from larger cast corner rounds.
Wheel rims, dished bearings and axle caps use curved lathed profiles. Button-head
fasteners have actual six-sided recessed sockets, and their washers sit against
the armor or wheel faces. Lower rollers use oxidized steel dishes. The isolated
geometry preview measures 155,467 base triangles and bounds
`[-1.218,-0.554118,-1.234171]` to `[1.218,0.549,1.234171]`; existing collision and
ground-clearance contracts still contain these bounds.

The new `tools/atlas_surface_bake.py` produces unique UV atlases with portable
base color, occlusion/roughness/metallic and tangent normals. Primary enamel and
hardware use 4096px maps; secondary enamel and track steel use 2048px. Physical
edge masks measure distance from actual bevel seams, placing irregular exposed
steel chips and a narrow primer rim onto adjoining faces. Explicit enamel
coverage maps preserve both primer and steel during garage recoloring. The old
constant bright-edge material and repeated per-face scratch maps are removed.

AO traces finite 6cm contacts within each finalized mesh assembly. This avoids
stamping a stationary guard's shadow onto every shared moving track shoe or a
rotating wheel. Runtime lighting supplies shadows between separate assemblies.
Preview generation now writes to an isolated ignored export directory rather
than replacing production textures with reduced-resolution maps.

Bounded helper checks confirmed manifold rounded plates, outward-facing caps,
and six flat socket walls for both wheel axes, deck fasteners and the sloping
nose. The full production bake completed successfully. Standard 8-bit maps retain
encoded values within 0.001969 of the original 16-bit bake, reducing map storage
from 346.60 MB to 61.45 MB. The compressed source is 63.38 MB and is tracked with
Git LFS. Its fourteen maps remain packed, including both coverage masks.

V4 passed the clean Godot 4.7.2 import, baseline and native assembly checks,
including rendered enamel/primer/steel recolor swatches. All fourteen runtime
maps have mipmaps. The [clearance report](evidence/b-atlas-v4-clearance-2026-09-22.json)
records 534 mesh-pair checks, zero unintended intersections and the same 388
intentional central axle contacts as V3. Packed material bytes match runtime
textures. The [native material checkpoint](evidence/b-atlas-native-v4-material-checkpoint-2026-09-22.json)
includes nine views under `battlebots/exports/atlas-review-v4`, including a lower
rear-quarter camera in the unmodified production Foundry. Garage bounds fit.
The scoped front-view sample measured median 3.649 ms / p95 4.579 ms, 213 draws
and 2,493.1 MiB engine video memory; it is not release performance certification.

Initial import failures were rejected: the generated quick preview needed
`.gdignore`, and stale texture UIDs needed reconciliation after replacing the old
maps. Logs are preserved under ignored `exports/atlas-v4-validation`; the accepted
subsequent imports were clean. The generator now creates the preview exclusion.

The user supplied a new armored shell reference and requested cohesive armor
instead of separated raised panels. They explicitly chose to retain the compact
footprint. The next geometry pass joins nose, deck, shoulders and upper side
armor with narrow seams, recessed access panels and supported addon interfaces.
V4 is a verified material/hardware checkpoint, not an approval candidate.
