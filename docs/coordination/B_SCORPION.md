# Orange modular Scorpion — B implementation and release handoff

20 September 2026. Branch `codex/b-scorpion` in
`C:/Users/jorge/battlebots-scorpion`, integrated over main `32341d1` and its
completed heavy movement, Full HD garage and sampled-audio work. The user
explicitly requests the reference orange hexagonal Scorpion, interchangeable
hammer and working minigun, detailed materials, mechanical walking, authored
practice NPCs and explosive destruction. Their later reference correction,
supplied hammer/footfall recordings and thick diesel smoke are part of this work.
The ranged weapon request supersedes the historical ranged-weapon exclusion.

## Delivered behavior

The Blender source and portable GLBs contain a six-sector inward-tapered chassis,
rounded bevels, radial hip sockets, six articulated armored limbs, hydraulic
links, a forged chamfered hammer with hazard inserts, and a detailed rotary
minigun. The final chrome hammer stage extends 0.66 game meters. The wrist and
server sweep use the same pure hinge/extension transform. Six physical support
probes and the collision hull follow the new footprint; alternating planted
tripods follow the real arena terrain. Art uses one BotScale conversion.

The diesel engine has a vented cover, filler/coolant details and two hollow
exhaust stacks. Imported outlet transforms drive dark, softly lit world-space
smoke: 256 particles per Scorpion, 3.6-second life, low idle emission and dense
load-dependent emission while translating or turning. Stopping eases the load
down; an eliminated engine leaves its old smoke to dissipate. Reset, teleport
and rollback clear old observations. Workshop previews have no exhaust.

The user's hammer sample replaces the existing confirmed-hit recording. The
footfall is cropped to a 0.5-second impact and plays once at the mean contact
position of a newly planted tripod, with two spatial voices per Scorpion.
Spawn, idle, reset and terrain-disabled preview do not synthesize steps. See
[audio preparation and checks](B_SCORPION_AUDIO.md).

The HX-6 preset is 118 kg / 95 power with hammer and removable `minigun_pod`.
The primary weapon slot also supports the canonical alternatives, including
minigun. Primary and auxiliary gun selections cannot occupy the same physical
socket together. The garage adds HX-6 without replacing existing builds, keeps
the full assembly framed, and saves/migrates known revision-seven loadouts.
The alternate saw/lifter/spinners have a visibly supported lowered tool socket;
their authoritative query offsets match the model so they can reach normal
grounded wheeled opponents. Hammer and minigun mounts are unchanged.

Actual held secondary input operates the auxiliary gun independently of the
primary hammer; synthetic cancellation cannot fire it. The authoritative gun
spools for 0.6 seconds, fires at 12 Hz over 24 m, consumes battery/heat and
publishes accepted hit/miss endpoints. A bounded elevation servo follows a
hostile hull on the forward firing line; steering still aims horizontally.
World and friendly bodies block shots. Flash, rotating barrels, tracers and
ejected cases follow accepted snapshots, with no client-awarded damage. The gun
also owns a spatial spool motor and bounded firing reports on the Effects bus;
see [minigun audio validation](B_SCORPION_MINIGUN_AUDIO.md). Menu/settings/recovery
visibility gates weapon and footfall audio without changing A's generic pools.

Practice spawns three separate authored machines: stationary Bulwark calibration
target, mobile Rammer spinner and Watchdog gun sentry. Their pilots use normal
commands. Confirmed destruction releases real detachable armor, wheels and
weapons within the existing eight-piece-per-bot/global debris budgets. After
six seconds a wreck respawns only when its home space is clear. Restart repairs
all four bots and preserves identities; the first `practice_target()` remains
stable. PvP receives no practice director.

## Ownership and shared changes

B owns bot assets, assembly, catalogue/garage, combat, gait and weapon
presentation. Narrow user-authorized A integration covers offline practice
lifecycle, the supplied audio, and one static box-projected Foundry reflection
probe. The arena and workshop use 4x MSAA. Existing A menus, generic audio
pools, network rules and unrelated original-checkout edits are preserved.

Catalogue 8 / protocol 5 / build `mvp-ab-13` add the explicit auxiliary input bit
and accepted gun state/endpoints; see [contracts](../CONTRACTS.md). Primary and
auxiliary weapons currently share the existing weapon integrity zone. This is
an explicit current limitation, not separate damageable hardpoints.

## Validation and release status

Godot is pinned to `4.7.2.stable.official.ed1daf0bf`, Jolt/60 Hz, Y-up/-Z-forward.
Core validation passed against an isolated checkout of checkpoint `ddd3edd` over
main `32341d1`; final cosmetic/audio changes receive their affected native and
lifecycle checks. The full MVP gate initially stopped at the old one-target
practice fixture; that assertion now checks the arena, player and three NPCs.
The resumed gate completed with `MVP PASS`, including all 0/80/150 ms transport,
combat, reconnect, results and existing team/FFA fixtures. Logs are
`%TEMP%/scorpion-mvp-integrated.log` and `%TEMP%/scorpion-mvp-resumed.log`.

Completed focused checks include real six-contact Jolt walking, module swaps,
loadout persistence, exact imported hammer transforms at five stroke fractions,
native full-model framing, minigun hits/misses/occlusion/resources and simultaneous
hammer/gun input. Real ENet Scorpion scenarios pass at 0/80 ms, including
accepted gun pitch/endpoints, held-input rearming and reconnect/round reset.
Garage validation covers actual main-menu, garage, customization and lobby
holders, three resolutions, 100%/150% text and 16 turntable angles; the complete
model stays in frame and its engine stays off.
The additional grounded-module regression settles the six-foot walker opposite
an unmodified wheeled target and damages it using ordinary primary commands
with saw, lifter, vertical spinner and horizontal spinner. The earlier airborne
query fixture alone was insufficient to validate those optional swaps.
Diesel passes headless and native D3D12 checks for moving density, idle/stop,
imported outlet origins, elimination fade, preview silence and reset safeguards.
Supplied audio passes native spatial and mixer/volume tests. Native full-bot
shutdown reports a seven-Texture-RID warning; there are no associated
script/shader failures. Native renders and review media are under
`battlebots/exports/`, while reproducible Blender source/renders are committed
under `battlebots/assets/models/scorpion_source/`.

Final baseline and affected hammer/minigun/saw/horizontal-spinner physics,
grounded-module, articulated-tail and diesel regressions all pass after the
socket and audio integration. Their logs are `%TEMP%/scorpion-final-baseline.log`
and `%TEMP%/scorpion-final-combat.log`. Native grounded-module, extended garage,
footfall, gun audio and composed menu/settings/recovery audio checks pass too.

The final 11.533-second 1920x1080/60 fps review clip is
`battlebots/exports/evidence/scorpion-practice-review.mp4`, with engine-captured
48 kHz stereo audio. Ordinary commands walk toward the untouched 300-core
Bulwark, land a 36-damage hammer strike, then destroy it after 47 gun shots.
The supplied hammer waveform is verified in the native recording at 2.540 s;
the death image shows all eight released authored chunks. No health, damage,
body pose or playback-rate shortcut is used for the review.

Prepare matching artifacts with `tools/prepare-hosted.ps1 -GodotPath <pinned>
-WindowsSmokeServer`. The tool records the source commit, clean/dirty status
and server hashes in `battlebots/exports/hosted-server/build-record.json`, with
the corresponding manifest beside it and Windows client in
`battlebots/exports/hosted-windows/`. It now creates an exports import boundary
before scanning so previous builds and review images are not game resources.

The client and hosted worker must be exported from the same tested commit.
Preparing both artifacts does not update live workers. A must deploy during an
established playtest break, compare live `/healthz` compatibility, and run the
external private/Quick Play duel through results/rematch using
`tools/check-hosted.mjs --duel-only`. No live restart, health-manifest-only
workaround or hosted-play acceptance is claimed by this B asset/combat task.
