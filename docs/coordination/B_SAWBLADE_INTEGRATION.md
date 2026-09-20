# Sawblade Tank integration — B, 20 September 2026

Branch: `codex/b-sawblade-integration`, base `9e54dcc`.

Scope: export the existing Blender source to a portable runtime model, assemble
its modules in garage/gameplay, and expose all eleven root custom properties.
Owned paths: bot assets, presentation, garage/profile and bot loadout validation.
Shared handoff: optional validated `cosmetics.sawblade` record; existing part IDs
remain authoritative. Saw/hammer/ramp map to saw/hammer/lifter. Drive appearance
supports tracks and wheels; armor covers/exhaust/paint are cosmetic, not additional
damage protection or performance. Existing loadouts remain readable.

Validation planned: portable import/baseline, independent module and malformed
loadout tests, profile persistence/history, garage preview, and rendered inspection.
The source blend and unrelated local project/import edits must be preserved.

First increment: portable GLB plus sampled authored hammer/tread tracks, shared
four-channel shader, garage vehicle/module/color controls, profile save/history,
and gameplay presentation. Hammer primary uses the existing rebound primary
action; authored frames 1–9 align with windup, 9–12 hold impact, 12–33 return
over authoritative cooldown. No client animation applies damage.

Godot 4.7.2 baseline and sawblade, legacy preview, repair, recovery, catalogue
text and history checks pass. Model rendered in Compatibility. Walking legs are
the user's additional requested second increment, including physical climbing;
not implemented by this first commit. Final content identity/online handoff must
cover the new appearance contract and walking drive together.

## Completed walking/geometry increment

The user's follow-up explicitly requests physical obstacle climbing. Canonical
drive ID `walker` costs 32 kg/35 installed power, with 4 m/s top speed and grip 11.
It requires the Sawblade vehicle. Four bounded contact rays support a 0.95 m ride
height, steps up to 0.45 m and walkable normals above 0.65 up-dot. Spring/damping
and bounded stance torque act on the authoritative rigid body; unsupported and
inverted bodies fall normally. Actual gravity includes lunar scaling.

Legs are generated runtime mechanical geometry, not edits to the Blender source.
They use diagonal stepping, planted terrain contacts, two-bone IK, broad feet,
joint housings, tapered armor and hydraulic rods. Moving contact transforms are
followed. Animation is presentation; ray support and the chassis collider are
the physical model, not individually simulated rigid-body limbs.

`SawbladeGeometry` publishes pure authored dimensions for matching server saw,
hammer and ramp hit queries. The hammer preserves quarter-frame baked hinge and
actuator samples. No animation callback awards damage. Rear-pack collision is
added to the bot body. Classic weapon geometry remains unchanged.

### Garage mapping

| Blender root property | Garage control |
| --- | --- |
| weapon | Parts / Weapon: Saw, Hammer, Ramp (lifter) |
| drive | Parts / Drive: Tracks (traction), Four wheels (standard/agile), new Four walking legs |
| armor_side/top/front/rear | Vehicle / respective armor cover slot |
| exhaust | Vehicle / Exhaust: none, small, medium dual, large dual |
| paint_primary/secondary/metal/rubber | Paint / respective channel, presets or Custom Color |

Armor covers/exhaust are cosmetic; Parts / Armor still supplies protection and
budget cost. Model/Stats tabs preserve a large preview and accessible comparisons.
The first local build and new builds use Sawblade Tank; Controller/Duelist and
saved records remain. Unsupported spinners are unavailable until Classic bot is
selected. Source `.blend` remains under its `.gdignore`; runtime GLB needs no Blender.

### Compatibility and validation

Catalogue revision 5 changes the content hash. Known revision-four saves migrate
without losing IDs/cosmetics; unknown or broken saves still require repair. The
optional `cosmetics.sawblade` record has exactly five bounded module integers and
four opaque finite RGBA arrays. No arbitrary paths or new command/view/wire fields.
Protocol/build remain 4/mvp-ab-12; strict content hashes separate catalogues.
**A must update the hosted worker/export to this catalogue before these clients
can use hosted multiplayer. This task does not deploy A's hosted service.**

`tools/check-sawblade.ps1 -GodotPath <4.7.2 executable>` passes baseline, authored
module/paint/save/undo/contact checks, classic saw/hammer physics, garage/profile
regressions and actual two-client ENet at 0/80 ms injected latency. The walking
fixture climbs two 0.35 m steps, reaches body Y 1.65 m, checks IK foot placement,
blocks a 3 m wall, falls when inverted and supports lunar gravity. Network
fixtures climb a raised block and replicate primary hammer phases. Peak local
corrections were about 0.075 m (0 ms) and 0.098 m (80 ms), settling within 0.35 m.
These are local automated results, not human internet or all-obstacle acceptance.

Rendered Compatibility inspection covers hammer/wheels, walking legs, platforms
and 720p garage at 150% text. Physics stays Jolt/60 Hz; only isolated non-network
fixtures run accelerated. Leg handling/balance and unusual contact geometries
remain playtest work, not a claim of full-game release acceptance.

Windows Client PCK export and execution of the Sawblade acceptance scene directly
from that pack pass, including runtime GLB, palette shader and JSON animation data.

Integrated the newer shared Turntable preview, featured main/lobby selection,
unsaved Test Drive and terrain camera updates. Authored previews use the shared
rotation controls/status and keep preview feet attached to the rotating display.
After rebase, the full Sawblade suite, featured_vehicle_test, garage_showcase_test,
featured_vehicle_menu_test and both garage_test_drive scenes pass. Rebase conflicts
were additive coordination-doc entries; both developers' records were retained.
