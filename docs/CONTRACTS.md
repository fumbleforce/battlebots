# Shared contracts — local records and current MVP session API

## Atlas drive configurations — build mvp-ab-27 (#47)

`ContentRegistry.validate` accepts Atlas MX with any drive in
`AtlasGeometry.DRIVE_GEAR`: `traction` (tracks), `standard_wheels` (large
wheels) and `walker` (hydraulic legs); `agile` stays invalid. Physics follow the
drive part as for other bodies (`walker` uses WalkerDrive and its ride height);
Atlas collision, mounts, weapons and turret frames are unchanged. No catalogue,
schema, command or snapshot fields change, but peers must agree on validation,
so clients and workers need the matching gameplay build. Presentation reads the
generated `data/atlas_drive_rig.json` through `AtlasDriveRig`; an Atlas body
pickup still brings its tracks. [Details and validation](coordination/ATLAS_DRIVES.md).

## Reverse steering — build mvp-ab-23 (#43)

`DriveModel.forces` inverts yaw steering when travelling backward along the
chassis's ground-plane forward axis. Below `motor.steering_direction_threshold`
(0.25 m/s), throttle selects reverse/normal steering; neutral retains normal
pivot steering. Live Jolt and replay share this rule, without input adapter or
wire shape changes. Protocol 10/catalogue 13 remain unchanged, but matching
clients/workers require the new gameplay build. [Details and validation](coordination/REVERSE_STEERING.md).

## Perk HUD presentation (#9)

`CombatHud.render` accepts an optional final `perk_parts: Dictionary` with the
viewed entity's current loadout part IDs. MenuGame matches the local source's
entity ID before supplying the parts; absent metadata produces UNAVAILABLE.
Existing BotView Nitro activity, jump charge/cooldown and shared overheating
fields drive explicit status text. No view, command, wire or gameplay fields
change. CombatHud now owns the existing HudJumpGauge, its layout and accessibility.
Idle jump cooldown is labelled IDLE rather than asserting ground eligibility.
See [states and validation](coordination/PERK_HUD.md).

## Shared heat — catalogue 12, protocol 9, build mvp-ab-19 (#41)

This revision supersedes historical battery references below. `CombatState` has
one shared `heat` and `overheated` latch; no battery/capacity/recharge state.
Weapons retain their heat rates. Nitro adds14/s, jump release20, recovery30.
The 100/50 lock gates all heat-generating actions while normal driving stays
available. A committed discrete attack may finish at the cap. Cooling is12/s
(15 with Cooling Pack), once per idle tick, without an inactivity delay.

`BotView.overheated` replaces `battery_fraction`, independently of weapon phase
(e.g. a destroyed weapon or a final committed strike). Local snapshots drop
`battery`/`battery_max`. Packed snapshot slot9 changes from numeric battery to
boolean `overheated`; the remaining indices and40-field count are unchanged.
The decoder rejects legacy numeric slot9. All clients/workers require the new
protocol/build/catalogue; compatibility rejection remains intact.

Local perk prediction restores authoritative heat/latch on each snapshot.
Drive replay gates Nitro/jump by that latch and accumulates predicted perk heat;
it conservatively keeps a received lock until authority clears it, because it
cannot reconstruct concurrent weapon heat/cooling. Force/aim/physics contracts
are unchanged. Pickups preserve shared heat/latch when swapping a part.

Battery Pack is removed from the catalogue. Known revision1–11 saved builds
migrate its utility to Cooling Pack while preserving all other selections, name
and cosmetics. Unknown hashes remain invalid. HUDs show heat and an explicit
cool-to50% warning; garage stats show cooling instead of capacity.
See [implementation and release handoff](coordination/B_HEAT_ONLY.md).

## Atlas turret — catalogue 14, protocol 10, build mvp-ab-24

Utilities `turret_cannon`/`turret_plasma`, their `_dual`/`_quad` upgrades and
`turret_flamer`/`turret_tesla`/`turret_railgun` are Atlas-only and exclude the
primary minigun. Firing applies server-side jolt/rock impulses to the shooter. A shot's barrel is
`(shot_sequence - 1) % barrels`; no extra wire field. `BotCommand` adds `aim_valid` (flag bit 9) plus `aim_yaw` and
`aim_pitch` (world bearing/elevation). The wire command array is
`[sequence, throttle, steering, flags, aim_yaw, aim_pitch]` and rejects
malformed, non-finite or out-of-range aim. Snapshots append `turret_yaw`
(40 fields). Elevation reuses `gun_pitch` and shots reuse the gun shot fields.
`BotView` adds `turret_kind` and `turret_yaw`. The server alone slews the turret
within the audited per-bearing elevation profile and resolves every ray; the
client supplies only aim intent. Revision-10 to revision-13 saves migrate. Hosted peers need
the matching release. See [B turret handoff](coordination/B_ATLAS_TURRET.md).

## Atlas MX — catalogue 10, schema 2, protocol 6, build mvp-ab-14

`ContentRegistry.atlas()` adds the `atlas_mx` chassis with traction drive and the
existing loadout slots. The catalogue hash is
`623a35b272a0d70feb57b7d4f0d0f298234b9608ab7ac4414945bec8404bd0ed`.
Revision-nine saved builds migrate while retaining their selected perks. No
command or snapshot fields change. Hosted peers must have the matching catalogue;
local migration does not relax compatibility rejection.

`MvpBot.collision_bounds()` returns the local physical hull AABB, independently
of the weapon authoring scale. `MvpBot.ground_clearance()` includes authored drive
support depth and preserves the existing walking-drive ride height. A consumes
these in `AuthorityWorld.clear_spawn_pose()` for wall and floor clearance; B uses
the same physical bounds for damage-zone classification and weapon targeting.
Atlas source meters have Y up and -Z forward; the shared runtime factor three is
applied once. Its eleven imported attachment transforms, animation paths and
portable material contract are recorded in [the B asset handoff](coordination/B_ATLAS_MX.md).

## Garage navigation — 22 September 2026

`MenuRouter.SCREENS` has no `shop` entry. Garage and Customize remain the
player-facing build screens; Customize retains the canonical part choices.
The removed Part Catalogue scene and its components have no gameplay or
client/server compatibility role.

## Nitro and charged jump — catalogue 9, protocol 6, build mvp-ab-14

Loadout schema 2 adds independent `nitro` and `suspension` part slots. Each may
select its active perk or an unequipped option; both active perks may coexist.
New starter builds equip both. Known schema-1 saves migrate with both unequipped,
retaining their prior combat selections. Catalogue 9 and the new command/snapshot
fields require matching client and server builds.

`BotCommand` adds `nitro_held`, `jump_held`, and `jump_cancel` in flag bits 6–8.
`jump_cancel` clears charge on focus/menu suppression, stale input or inactive
rounds and never launches. Shift drives Nitro; Space holds the suspension charge
and release launches. Brake moves to B by default. Saved input preferences use
version 2; known version-1 bindings are migrated while preserving other controls.

The authoritative combat state spends 14 battery per second for forward Nitro,
which raises drive speed to 135% and drive force up to 150%. A grounded jump
charges over 1.2 seconds; release spends 20 battery, launches at 3.5–7.5 m/s
scaled for arena gravity, then cools down for 4 seconds. `BotView` and bot
snapshots publish Nitro activity, normalized jump charge and jump cooldown.
Local prediction uses the same perk state and drive model; authoritative snapshots
still correct the body. A's match HUD may display the published jump charge and
cooldown; B's input/physics implementation does not alter A's HUD layout.

`project.godot`, `mvp_session.gd`, `wire_codec.gd` and the loading tip are shared or
A-owned integration surfaces changed for this B feature. A must use catalogue 9,
protocol 6, build `mvp-ab-14` for a matching hosted release. Existing live workers
must continue rejecting incompatible clients until the coordinated deploy.

## Scorpion and practice NPCs — catalogue 8, protocol 5, build mvp-ab-13

`ContentRegistry.scorpion()` supplies the legal 118 kg / 95 power HX-6 preset:
`scorpion_hex`, `walker`, `hammer`, `standard_armor`, `minigun_pod`. The hexagonal
chassis uses six physical suspension samples and six authored limbs in alternating
tripods. Other walkers retain their four supports. The existing primary weapon
slot swaps the hammer for other weapons; utility `minigun_pod` independently adds
the auxiliary gun. Primary `minigun` is also available; one physical gun socket
cannot accept both minigun selections. Parts still use loadout schema 1. Known
revision-seven saves migrate without changing selections; stale online peers reject.

BotCommand adds `auxiliary_held` in flag bit 5. Input gating sets it only for a
real, released-and-rearmed secondary trigger on an auxiliary-equipped bot.
Synthetic `secondary_held` cancellation on pause/focus/reconnect is preserved and
cannot fire the gun. Existing primary/secondary controls retain their semantics
on other builds. A new wire build/protocol separates incompatible readers.

BotView/accepted bot snapshots add `secondary_charge`, `secondary_active`,
`shot_sequence`, `last_shot_from`, `last_shot_to`, `last_shot_tick`, and `gun_pitch`.
Gun pitch is an additional local X rotation about ScorpionGeometry.GUN_PIVOT,
above the imported two-degree-down rest pose. The server adjusts elevation within
bounded mechanical travel to a hostile hull intersecting the chassis-forward
horizontal firing line. Steering remains the horizontal aim. The first actual
world/body obstruction blocks the ray, including allies; clients provide no
target, direction or damage. Misses publish endpoints too. First/reconnect
baselines establish silent visual state rather than replaying earlier fire.

The minigun spools for 0.6 seconds, fires up to 12 shots/second over 24 meters,
and deals 6 raw damage per shot through existing zone/armor rules. Motor and
shot costs share battery/heat with the primary weapon. Both modules currently
share the canonical `weapon` integrity zone. ScorpionGeometry defines the exact
articulated hammer arc for both rendered joints and authoritative sweeps.
The final telescopic stage extends 0.22 source meters (0.66 at game scale) along
the authored forearm, and the wrist keeps the striking head level. The pure
ScorpionStance profile supplies the tapered collision hull, radial visual hips
and six corresponding suspension contacts.
Alternate saw/lifter/spinner tools attach through a lower-front adapter socket
at source offset `(0, -0.55, 0)`. Rendering and authoritative sweeps share this
offset so the tall walker can hit grounded wheeled opponents. The native
hammer/minigun keep their independent reference geometry.

Diesel exhaust and footfalls are cosmetic observations of accepted presentation
state, with no additional wire fields. Both imported exhaust lips drive bounded
world-space smoke (256 particles per bot, 3.6-second lifetime). Translation and
turning load the engine; elimination stops emission while existing smoke fades.
Terrain-disabled garage previews stay silent and smoke-free. Explicit round
resets, teleports and tick rollbacks clear old observation state. Completed
displaced, grounded tripods share one spatial footfall cue with two pooled voices.

Offline `MvpSession.practice()` installs PracticeBotDirector with stationary
Bulwark and mobile Rammer/Watchdog NPCs. `practice_target()` retains the stable
first target. Six-second respawn waits until its space is clear, resets that
bot's normal combat state, and never respawns the player. Practice restart
repairs/repositions all four bots, clears queued intent, and preserves identities.
No NPC director is installed in PvP. Practice world markers now support every NPC;
existing online ambiguous-rival suppression remains. Destruction substitutes
real detachable armor/wheels/weapons into the existing eight-piece explosion
budget, restores them on repair, and never adds gameplay collision.

See [Scorpion scope and release handoff](coordination/B_SCORPION.md). This source
increment requires matching exported hosted workers before online readiness;
no compatibility bypass or live health-manifest-only update is permitted.

## Three-times-larger heavy machines — 20 September 2026

Catalogue revision 7 grows all three canonical hull dimensions by three. The
balanced hull is now Vector3(4.8, 1.5, 6.0). `BotScale.from_size(size)` supplies
the linear authoring multiplier; Jolt body transforms remain unit scale. Weapon
queries, authored/primitive meshes, walker support and recovery follow that size.
DriveModel and live DriveBody share powerful acceleration, coast/brake and yaw
tuning; motor torque scales with enlarged inertia so size does not make turns weak.
The static replay sweep uses the extrapolated hull orientation, allowing a tipped
chassis to descend while rotating upright without bypassing wall translation
checks. No command/view wire fields or damage/cadence values change.

`AuthorityWorld.clear_spawn_pose(bot, authored)` retains marker lane/facing while
clearing the whole hull against the octagon and terrain. Practice derives spacing
from hull lengths. CameraAnchor publishes local `bot_scale` metadata; physical
clearance follows scale 3 and the boom uses scale 2 (12m default, 8–18m zoom).
Garage previews divide catalogue dimensions by BotScale.FACTOR for original
workshop framing. Detached markers clear the enlarged rear pack. Explosion and
smoke dimensions grow without raising effect counts.

Known revision-six saved builds migrate with IDs, names and cosmetics preserved;
unknown hashes remain rejected. New catalogue SHA256 is
`45bb581a3c4403fd74ce7067150eb480148e70a6e5b8dba9a5977dda95db25be`.
A must deploy matching workers before hosted acceptance: the inspected service
still reported revision-six content, and this increment does not deploy it.
See [B scope and validation](coordination/B_HEAVY_MACHINES.md).

## Robot core destruction presentation — 20 September 2026

MvpBot consumes existing accepted BotView state for one explosion on observed
zero-core elimination. Initial terminal/reconnect baselines remain silent. Repair
clears effects and restores original hull overlays; camera anchors and physics
remain intact. Up to two bursts share the twenty-piece debris budget with ordinary
impact fragments and expire within 4.2 seconds. This changes no shared record,
catalogue or network version. See [B destruction](coordination/B_DESTRUCTION_EXPLOSION.md).

## Confirmed impact feedback — 20 September 2026

The normal menu game now consumes confirmed hit events for localized sparks and
short-lived metal fragments, capped at 64 sparks and 20 fragments per client.
Duplicate/stale events and offline/connecting sessions cannot replay effects;
phase changes, practice restart and leave clear them. No collision or damage is
added. Independent rendering/session/native contact checks pass. Human readability,
larger-scene budgets and legacy CLI mounting remain open. See
[scope and evidence](coordination/B_IMPACT_FEEDBACK.md).

## Component damage presentation — 20 September 2026

Weapons and individual drive sides now show snapshot-driven cracked/scorched and
smoking disabled states. Original appearance returns on repair/reset. Authored and
legacy assemblies are covered without physics, health or wire changes. Independent
mapping/state/native runtime checks and baseline pass; follow-distance captures
reviewed. Impact sparks/fragments are covered by the newer increment above; larger-scene budgets and human acceptance remain open.
See [scope and evidence](coordination/B_COMPONENT_DAMAGE.md).

## Garage options — 20 September 2026 user update

Garage/Customize now fill available height before paging. All existing options are
selectable; the sole offered chassis is the authored Sawblade body. Body edits
preserve the other parts and appearance; unsupported-model selection locks and
weapon substitution are removed. Canonical spinners render with the authored body.
Legacy saves retain their IDs/equipment; catalogue revision 6 requires matching
hosted content. See [behavior, migration and validation](coordination/B_GARAGE_OPTIONS.md).

## Camera mouse scaling — 20 September 2026

The B input adapter now uses unscaled screen mouse motion, so viewport stretching
does not change the selected X/Y orbit sensitivity. Independent engine-transform
and real-adapter tests reproduce the former half/double sensitivity and verify
inversion and menu suppression. Camera settings, input/menu and baseline checks
pass. Existing preference files and shared APIs are unchanged. See
[scope and evidence](coordination/B_CAMERA_MOUSE_SCALE.md).

## Terrain camera clearance — 20 September 2026

An inverted bot could be clear of raised Moon terrain while its camera sphere
remained embedded. The camera now queries supporting ground from chassis height
and raises the pivot only when the candidate sphere and upward path are clear.
Ceilings and walls still constrain the view; no world, drive or BotSource API changes.
Independent lunar poses, ceiling/wall removal, perimeter, existing contact/arena
and settings checks pass, along with Godot 4.7.2 baseline and native visual review.
These are deterministic collision fixtures; human driving feel remains open.
See [reproduction and validation](coordination/B_TERRAIN_CAMERA.md).

## Sawblade Tank and walking drive — catalogue revision 5

B's optional `cosmetics.sawblade` record has armor_side (0–2), armor_top/front/rear
(0–1), exhaust (0–3), and paint_primary/secondary/metal/rubber (four finite linear
RGBA channels in 0–1, alpha exactly 1). All nine keys are required when present.
Weapon IDs remain saw/hammer/lifter; drive traction renders tracks, agile/standard
render wheels, and new canonical `walker` supplies physical leg suspension and
procedural IK. Walker requires this vehicle. Exhaust is cosmetic; armour covers are gameplay pieces since #46.
Existing loadout schema 1 and command/view wire records are unchanged; catalogue
hash changes separate old peers. Local revision-four saves migrate preserving
parts/colors. A's hosted worker needs the matching updated catalogue/export.
DriveBody retains its existing model_config/grounded API; walker contacts are
local physics data, not transmitted foot targets. Input replay remains approximate
at terrain contacts, corrected by authoritative body snapshots. See
[B integration and validation](coordination/B_SAWBLADE_INTEGRATION.md).

The first sections describe local typed GDScript interfaces; the session section
below documents the implemented MVP wire-facing API. This is not the full game API.
A owns networking/session and match/world contracts; B owns combat/bot/control
and customisation implementations. Shared command/view/loadout records are
coordinated producer-consumer interfaces, not blanket A ownership of scripts/core.
The current split in TEAM_WORKFLOW.md supersedes historical authorship below.
Paths below are relative to the Godot project.

## Featured vehicle selection

`FeaturedVehicle.set_compact(enabled)` and `GarageBotPreview.set_compact(enabled)`
are opt-in local presentation APIs, valid before or after ready. Main uses the
compact layout: preview above name/count/previous/next, plus an accessible pause
icon. Routine inspection instructions move to tooltips; invalid-build reasons
stay visible. Selection, caller-owned locks, validation and workshop/lobby defaults
remain unchanged. `MenuRouter.open_practice()` opens arena setup before calling
the existing direct `start_practice()` entry. Workshop test drive remains direct.

`FeaturedVehicle.render(loadouts, selected, editable=true, message="")` accepts
detached local choices and caller-owned selection/status. Its
`selection_requested(index, draft)` signal is intent only: it cannot save a build,
change PlayerProfile or send session requests. Disabled selection is guarded in
the callback as well as the buttons. `apply_text_scale(factor)` preserves full
100/125/150% text; raw invalid records retain preview validation feedback.

Main accepts the signal into `PlayerProfile.active_bot`. Lobby keeps local choice
separate from APPLY BUILD and host confirmation, with existing pending/phase
locks. Paint is included in acknowledgement comparisons. Accepted loadout changes
still clear readiness through the existing server rule. Profile inventory edits
refresh both consumers; selection does not write a save file.

`GarageBotPreview.set_auto_rotate(enabled)` opts into slow shared pedestal/model
rotation. Default Garage/Customize remains manual. Pause/Resume is keyboard
accessible; manual inspection pauses motion, hidden/focused previews suspend it,
and invalid builds remove the model and rotation action. Assembly stays isolated
and cosmetic, using canonical primitive chassis/weapon geometry, not final bot art.
See [featured vehicle handoff](coordination/B_FEATURED_VEHICLE.md).

## Workshop test drive

`GarageTestDriveEntry.install(screen, callback)` adds a B-owned footer entry to a
Garage/Customize screen. `render(draft, allowed)` caches validation of detached
drafts and guards disabled/invalid/hidden activation. The menu owner installs it
before applying the shared text factor; the component never persists or starts a
session itself.

`menu_game.start_practice(return_screen="")` retains existing main-menu behavior
for the default argument. Its internal Garage/Customize callers supply their
origin, require the visible workshop with no existing session or modal, and pass
the validated active draft to existing practice authority. Restart preserves that
admitted build. The pause return action uses BACK TO BUILD and restores origin;
ordinary practice returns to main. Profile state and saved bytes are untouched.
Hidden screen processing stops while driving to prevent background edit shortcuts;
return creates an active screen again. No session/wire/input/save schema changes.

## Transport compatibility

Current transport build is `mvp-ab-12`, protocol 4. Every MvpSession host and
client enables ENet range-coder compression. Older clients must update with the
server; this symmetric setting reduces current game packets below the measured
Fly path limit. BotCommand/BotView and authoritative message fields are unchanged.
The raw transport regression drops datagrams over 1350 bytes and verifies the
current traffic, results, rematch and reconnect. See
[live hosting evidence](coordination/A_FLY_DUEL_LIVE.md).

## Combat and round HUD

`GameplayAudio.observe_bot(view, weapon = "")` consumes a fresh accepted local
BotView and optional family from the audio accessor. It silently establishes a
baseline after missing data, reconnect, identity/round changes or leave.
`CombatAudioStatus` reports positive-to-zero armor edges and family-specific
weapon edges: full spinner speed, charged lifter, running saw or hammer cooldown
completion. These captions do not assert attack affordability or hit success.
Repeated/stale ticks and invalid per-field baselines cannot fabricate events.
Critical core/recovery/armor captions retain the latest of each type together;
positive readiness is rate limited to 750 ms and suppressed during critical
captions. Four spatial impact and three announcement players cap concurrent voices,
including a simultaneous core/recovery/breach warning. The game's caption region
fits the combined warning at 100–150% text without covering HUD/status panels.

Accepted combat-event positions place the four reused `AudioStreamPlayer3D`
impact voices in world space; event validation, ordering and captions remain
unchanged. A single additional non-spatial crowd player reacts to genuine
round/match transitions, never initial/rejoined results or practice. New rounds,
new matches and leave stop old reactions. Crowd uses BBEffects at its own gain
and ducks locally for the duration of major announcements without modifying
user bus settings. Crowd cues emit `cue_played` but do not replace outcome captions.
Contact material is not published; these sounds do not invent material identity.

`MvpSession.audio_views() -> Array[Dictionary]` supplies detached audio records
for current bots: entity_id, tick, position (displayed world position), pose
(physical world transform), velocity, angular, drive_input, turn_input,
grounded, weapon, charge, eliminated and age (seconds). Server/practice records
use authoritative body/combat state, neutral movement during pending resets,
and zero age. Client records require an accepted current-round baseline and
use its physical snapshot even for the predicted local player; age measures
time since acceptance. Presentation must reject stale records beyond 250 ms.
Practice target metadata is included independently of lobby membership. No
BotView or wire fields changed. A owns this accessor and its continuous audio
consumer; B's drive and combat producers remain unchanged.

`ContinuousGameplayAudio.render(records, active)` supplies at most two bots'
spatial drive/sliding/rotor loops plus arena ambience on BBEffects. Only grounded
lateral motion drives the approximate sliding cue. Spinner charge also drives
spin-down pitch; saw power is binary, hammer/lifter have no rotor loop.
`reset()` stops all continuous sound; `duck(seconds)` lowers arena gain locally
without changing user bus settings. Game menus, recovery, results and inactive
rounds suppress these loops; captions/HUD remain the visual source of information.

`CombatHud.apply_accessibility(text_scale, palette, high_contrast)` and the same
`MatchHud` method change local presentation only. Text grows independently from
viewport scaling; the enlarged layout reflows panels and component cells.
`CombatHud.caption_bounds()` returns its reserved logical subtitle rectangle.
`HudPreferences` stores validated 100/125/150% HUD/general-menu text size, standard/deuteranopia/
protanopia/tritanopia palette and high contrast in version-one `user://hud.cfg`.
The settings panel emits detached previews; Cancel restores the original, while
Save publishes only after successful atomic persistence. This does not change
B control settings or network schemas.

`BotWorldMarkers.render(views, local_id, practice, duel)` consumes only detached
published views. It creates depth-tested, fixed-size world badges with distinct
`+ YOU` and `◇ RIVAL`/`◇ TARGET` labels, explicit `/ OUT` state and small stems
connecting them to bot positions. `apply_accessibility(text_scale, palette,
high_contrast)` uses the HUD preference. These are separate A-owned presentation
nodes; bot meshes, paint, physics and camera controls are unchanged.
Classification requires a valid local identity/team and pose; missing local
baseline clears badges, invalid/removed peers cannot retain a stale marker, and
ambiguous extra opponents are suppressed. Only 1v1/practice uses this feature.
The game reads global presentation poses after child interpolation and suppresses
world badges with menus/results/settings/recovery. Rendering respects scene
depth and sits below Canvas HUD layers; it is not an off-screen tracking system.

`MenuTextScale.apply(root, factor)` preserves each text control's base font size
and reapplies a bounded scale without compounding. It covers labels, buttons,
text inputs, rich text and option popups. It does not resize the whole canvas or
choose layout; A's general screens and game/results/reconnect/audio/accessibility
panels expose `apply_text_scale(factor)` and own their layouts.
The game owner propagates live drafts to current panels and newly opened screens,
restores the saved value on Cancel/reconnect cancellation, and loads the same
version-one HUD preference at startup. Existing files need no migration.
B's Garage, Customize, catalogue, preview/comparison/recovery and camera/input
settings now expose `apply_text_scale(factor)` too. The existing screen dispatch
covers B menus; one explicit call in menu_game propagates to CameraSettingsPanel,
which also scales InputSettingsPanel. Rebuilt rows retain the current factor.
Keyboard-accessible pages and wrapping preserve full 100/125/150% fonts without
scrolling. Garage/catalogue choices and comparison stats use fixed pages;
recovery text and invalid-preview reasons use pages too. Controls has three
binding groups; Camera uses an inline responsive form. Existing Form and
MarginContainer paths integrate with A's themed settings hub. menu_game uses the
actual viewport instead of reducing camera/settings through a fixed design-frame
scale. No preference schema changes. See
[B text evidence](coordination/B_MENU_TEXT_ACCESSIBILITY.md).

`MvpSession.bot_views() -> Array[BotView]` returns fresh detached views for the
current world. Server/practice views read the real bot state; clients omit bots
without an accepted snapshot for the current epoch. No world returns an empty
array. This lets UI display unknown peers instead of neutral full-health defaults.
It is a local read API, not a new RPC or wire field.

A's `CombatHud` displays fractions, raw component integrity, weapon phase and
cooldown, recovery availability/cooldown, immobilization seconds, and a chassis
bearing derived from presentation pose (-Z forward, arena -Z treated as north).
Raw zone values are not percentages; no armor maximum is inferred. Zero armor
is breached; zero drive/weapon is disabled; invalid or missing data stays unknown.
Recovery readiness uses the published flag and active match phase; no inversion,
battery-max or recovery-animation state is invented. Timers do not advance locally.

The default menu game reads local/rival views from `bot_views()`, applies current
recovery binding labels, and uses a shared scalable canvas for combat, practice,
diagnostics and captions. The old preview HUD/hints stay available to B's fixtures
but are hidden in this composed game. B preview/control/camera code is unchanged.
`MatchHud.render(view, practice = false, local_team = -1)` accepts an authoritative
team for local round won/lost wording; its neutral behavior remains available.
No protocol/build/catalogue or BotView schema change is needed.

## General game menu and result presentation

A composes the preview's existing pause panel into `scripts/ui/game_menu_page.gd`.
Existing resume/settings/return button references and control cancellation remain
intact; no B preview/input/camera implementation changes are required. General
game-menu and results pages hide arena HUD overlays while open.

`MatchResults.render(view, local_id, local_team = -1)` accepts the authoritative
local BotView team to distinguish victory from defeat. Unknown team keeps a
neutral outcome; never infer team from entity ID. Overview and score-detail tabs
read server-published results and retain the existing rematch/leave signals.
No wire, BotCommand or BotView schema change accompanies these menu refinements.

## Gameplay audio presentation

A's `scripts/audio/gameplay_audio.gd` consumes existing `MvpSession.combat_event`,
`match_view` and local `BotView` without changing combat/network schemas.
`observe_match(view, practice)`, `observe_bot(view)`, `combat_event(event, local_entity)`
and `reset()` drive bounded effect/announcement players. Hit IDs are deduplicated
per match/round; leaving and reopening practice starts a fresh local event epoch.
`caption_changed(text)` supplies short visual equivalents, with announcements
taking priority over impact captions. These cues are procedural first-pass sounds.

`AudioPreferences` loads/saves version-one `user://audio.cfg`; master, music,
effects and announcements are linear gains in [0, 1], plus a global mute flag.
`BBMusic`, `BBEffects` and `BBAnnouncements` route to Master. The menu shell
composes `AudioSettingsPanel` alongside B's existing control settings. Preview
changes affect buses immediately; Cancel/Escape restores original preferences;
Save publishes only after successful persistence. Invalid saves remain open.
No changes to B's controls, combat or bot-customisation paths are required.

## Practice lifecycle

`MvpSession.practice_target() -> BotSource` exposes the current detached-view
source for the stationary practice target; it returns null outside practice.
`restart_practice() -> Error` is a local, non-RPC API, permitted only in the
practice authority. It reuses `AuthorityWorld.reset_round()` to repair and
reposition both bots, preserving world/bot identities, selected loadouts and
monotonic world ticks/command sequence marks. It clears queued commands, submits
neutral braking and emits `match_changed` plus `session_event("practice_restarted", {})`.
Offline, hosted, connecting and connected network sessions reject it unchanged.

The general menu adds a practice-only pause action and read-only target HUD.
Player knockout opens pause focused on Restart; Resume cannot recapture a
knocked-out practice bot. A restart resets local audio event history, because
new practice hits begin again at event ID one. No wire/schema version changes.

## BotCommand
`scripts/core/bot_command.gd`: sequence >= 0, throttle and steering in [-1, 1],
brake, primary_held, primary_pressed, secondary_held, recovery_pressed.
Positive throttle drives chassis -Z. Positive steering means a right turn
(negative Godot yaw) in forward travel or a neutral pivot, and positive yaw in
reverse travel. Near standstill, reverse throttle selects the reversed convention. Held actions are levels;
pressed actions are one-physics-tick edges. Commands are created fresh each tick.
Camera orbit/toggle/zoom/pings remain local until their own service exists.

`is_valid()` rejects non-finite/out-of-range axes and negative sequence numbers.
This is basic local validation only; A must implement authority, sequence-window,
rate-limit and network payload checks separately.

## BotView
`scripts/core/bot_view.gd`: a fresh detached snapshot from read_view(), containing
entity ID, global pose, core/battery/heat/weapon-charge fractions in [0, 1],
weapon state name, recovery availability, and elimination flag.
Treat it as read-only; mutating it never writes simulation state.
Health-zone details, match views and registry/garage validation are now available
through the additive fields and APIs below. Existing baseline fields remain valid.

### Additive MVP implementation on A's branch

Existing fields/methods retain their meanings. BotView now also defaults `owner_id`,
`team`, `server_tick`, `zones`, `weapon_cooldown`, `recovery_cooldown`,
`immobilized_remaining` (seconds; zero means inactive), and `failure_reason`.
B's existing mock inherits neutral defaults; its existing consumers need no edits.
`MvpBot` exposes real values, fresh per read. Camera anchor/exclusions are unchanged.

`ContentRegistry.validate(draft) -> LoadoutValidation` returns `valid`, specific
`reasons`, canonical `stats`, and a detached normalized `loadout`. `starter(false)`
is Striker; `starter(true)` is Controller. Draft shape: `schema_version: 1`, `name`,
`parts` (chassis/drive/weapon/utility IDs; schema 3 removed armor, see #46 below), `cosmetics: {paint: id}`,
`content_hash: registry.content_hash`. All current parts fit their category socket;
the implemented weapon IDs are `vertical_spinner`, `horizontal_spinner`, `lifter`,
`hammer` and `saw`. `duelist()` adds the compact/agile/hammer/standard-armor/cooling-pack
starter (91 kg/70 power), without changing `starter(bool)`.
Horizontal spinner is 30 kg/40 power, charges over two seconds, uses spinner
energy/heat rates, deals up to 40 raw damage with a 25% charge threshold and
consumes 60% charge per hit. Side-contact sweeps and lateral recoil are authoritative.
Hammer uses a primary press edge, 0.35-second committed windup, 38 raw damage,
and 1.4-second recovery even on a miss. It spends 16 battery at acceptance and
adds 20 heat at impact. A strike reaching heat 100 completes and locks further
activations until 50. Release/secondary do not cancel a committed swing; inactive,
eliminated or destroyed state does. Secondary prevents starting a new strike.
Charge is windup progress; phases are `windup`, `strike`, `cooldown` plus the
existing idle/disabled/overheated states. One target hit per attack ID and round.
The existing snapshot fields suffice. Physical primary press edges are preserved
in both hold/toggle modes; the held latch still governs continuous weapons/lifter.
Saw is 20 kg/30 power. Hold primary to power it immediately (charge 1/phase active),
using 9 battery/14 heat per second. Every full 1/3 second of maintained target
contact deals 6 raw damage to one contacted zone. Separation or loss of power
discards partial contact time. Secondary stops it; zero battery or heat 100 ends
damage eligibility that tick. No authored saw impulse or pin is applied.
Build `mvp-ab-11` requires the octagonal Foundry on both peers; older square-map
clients are rejected by the existing build check. Catalogue revision four and
protocol 4 remain unchanged. Build 9 added reliable state
checkpoints to match transitions and active/countdown heartbeats. Checkpoints use
the existing snapshot format and per-entity tick guard, so newer fast snapshots
cannot be rewound by delayed reliable delivery. Finished-match heartbeats remain
compact. Combat events add `kind`: a canonical weapon ID or `ram`, allowing VFX
and telemetry to distinguish weapon contact from ordinary chassis damage.
All peers need
matching build/content. Known revision-one/two/three saves migrate after validation while
preserving every selected part and cosmetic; unknown/incompatible saves stay invalid.
Catalogue hashes normalize CRLF to LF for matching Windows/Linux content.

Hosted matchmaking adds `MvpSession.join(address, port, reconnect_token, admission_ticket)`;
both tokens default empty, retaining LAN callers. Admission tickets are only
required by allocated public workers. The worker validates player, slot, membership
reservation generation, build/content and ticket expiry against supervisor-owned
configuration before admission. Hosted teams follow reserved slots and cannot be
changed by a client. A valid reconnect token preserves the admitted bot and damage;
revoked/replaced reservations cannot reconnect. These identities/tokens remain
internal, outside public lobby and BotView data.

`PublicServiceClient` owns HTTPS guest/room/queue requests and emits a ready endpoint
assignment. It does not mark a game connected; only the ENet welcome does that.
Quick Play sends `POST /v1/queue` with `{capacity:2}` after health advertises
`queue_capacities` containing numeric two. The service isolates two/four-player
queues; omitted capacity retains legacy four. Other capacities/keys are rejected.
Older health responses still support private games. Authenticated HTTP 401
clears expired credentials, membership and cleanup locks; the player chooses a
new action, with no automatic allocation replay. Cancel still takes precedence
over late replies. See [duel queue coordination](coordination/A_DUEL_QUICK_PLAY.md).
The menu shares the existing lobby/Ready flow after successful admission. See
[hosted coordination](coordination/A_HOSTED_MATCHMAKING.md) for control routes,
worker lifecycle and the current single-Machine playtest boundaries.

`LoadoutStore.save(Array) -> Error` stores up to twelve uniquely named legal builds;
`load_saved()` returns `loadouts`, `invalid` (index to reasons), `errors`, and
`restored_backup`. Invalid/unknown builds remain visible for repair, never silently
substituted. Local store defaults to `user://loadouts.json`.

B's local garage repair API adds `LoadoutStore.save_build(draft, index, expected)`.
`index=-1` appends; otherwise it replaces one saved slot with a valid unique-name
build. `expected` is the last loaded array. A changed disk baseline returns
`ERR_BUSY`; corrupt/backup recovery input returns `ERR_FILE_CORRUPT`. Untouched
invalid/malformed sibling records are preserved, allowing independent repairs.
Strict `save(Array)` still requires an entirely legal list. Neither API changes
wire validation, content identity or the JSON schema. Explicit garage Revalidate
updates draft format/catalogue metadata only, retains part IDs/paint, supports
Undo and does not persist until Save. See coordination/B_GARAGE_REPAIR.md.

Local recovery adds `LoadoutStore.inspect_recovery()` (read-only availability,
reviewed loadouts and an opaque confirmation token) and `restore_backup(token)`
(error and preserved_path). Recovery is offered only for a missing/unreadable
primary with a readable backup envelope; invalid individual records remain.
Changed primary/backup sources reject the confirmation. Successful restore copies
exact backup bytes to primary, keeps the backup and archives any old primary to
a unique `.unreadable-*` sibling. The UI displays that archive path. Opening or
cancelling review writes nothing. No valid backup means no reset/overwrite action.

`PlayerProfile.reload_retaining_drafts()` refreshes saved slots, detaches edited
or new drafts as unsaved copies and preserves their Undo/Redo. Unchanged records
keep history where an exact disk match exists; otherwise history travels with a
detached copy. Detached drafts can only append on Save, so external edits are not
overwritten by stale slot indices. Duplicate-name and twelve-save limits still
apply. `restore_reviewed_backup(token)` reloads this way after successful restore.
Raw `reload()` remains the startup/test reset API. Garage and Customize expose
these actions under Saved File. See coordination/B_GARAGE_RECOVERY.md.

`CombatState.snapshot()` carries detached health zones, resources, weapon/recovery
timers, elimination/failure details and combat counters. `MatchState.snapshot()`
carries match/event IDs, phase, seconds remaining, round, scores, round results and
winner (team 0/1; -1 draw). These are server-local records; the session API follows
in the next increment. Hold LMB to raise the lifter, release fully charged to launch;
RMB lowers it. Spinner RMB brakes spin. R activates eligible physical recovery.

## BotSource
`scripts/core/bot_source.gd`: common Node3D adapter.
- submit_command(command: BotCommand): accepts local intent. Real source validates it.
- read_view() -> BotView: returns a new snapshot.
- camera_anchor() -> Node3D: follow target; caller must handle source destruction.
- camera_exclusions() -> Array[RID]: bodies to exclude from camera collision queries.

A's baseline source wraps a driveable RigidBody3D. It validates commands, copies
drive intent, and brakes after 250 ms without valid input. Combat flags are accepted
by the drive fixture's record; real combat is provided by MvpBot. B's mock accepts
visual-only drive input and provides sample HUD values. Both satisfy the same
interface. The preview only knows BotSource, never a concrete physics node path.
CameraAnchor exists on both sources. Networking must not serialize Node/RID handles.

## Coordinates, timing and collision
Meters, kilograms, Y-up, -Z-forward, radians in logic, degrees in editor/UI.
Physics: 60 Hz. World layer index 1 (mask 1), Bots index 2 (mask 2),
HitZones index 3 (mask 4). Cosmetic visuals have no collision.
Arena floor surface is Y=0, X/Z bounds +/-25. The Foundry is a regular octagon:
diagonal faces satisfy abs(X)+abs(Z) <= 25*sqrt(2), with 3 m wall collision.
The floor collider extends beneath the full 50 m square; diagonal walls exclude
the corner wedges from play. Existing orbit-camera scene `corner_chamfer` is
14.644661 so its above-wall boundary also matches the octagon.
Team spawn markers are under SpawnPoints; names Team1_1..5 and Team2_1..5.
For 2v2 use indices 2 and 4 (X=-6/+6). Marker Y=0.5 is historical authoring data;
`clear_spawn_pose` replaces it with full-footprint terrain clearance plus half
hull height (walker ride height instead for walking drives) and 0.05m spare.
B's integrated arena includes perimeter walls and FFA spawn markers; A's current
session rules support 1v1, 2v2, 5v5 and FFA.
Five-player teams use all five existing team markers; duel/2v2 retain markers
2 and 4. `AuthorityWorld.spawn(..., team_size=2)` takes the team size as an
optional fifth argument; pass 5 for 5v5. Optional sixth argument `mode="teams"`
accepts `"ffa"` to use the existing `FFA_1` through `FFA_8` markers by slot+1.
The published arena includes eight equal perimeter faces (25 m inradius) and
FFA_1..8 markers on a 20-meter ring facing inward.
Spawn poses are world body-center transforms, applied through body.reset_pose;
do not add a second body-height offset when integrating a future bot root.

## Registered input actions
drive_forward=W, drive_reverse=S, steer_left=A, steer_right=D, brake=Space,
primary=LMB, secondary=RMB, recover=R, camera_toggle=C,
camera_recenter=MMB, camera_zoom_in/out=wheel, ping=Q, scoreboard=Tab, pause=Escape.
B collects drive/weapon intent and implements camera controls and menu/settings
capture. Suppressed input brakes and lowers/cancels; held actions require release
before rearming. Escape toggles the standalone menu; explicit Return exits.
Keyboard/mouse rebinding and hold/toggle primary are supplied by B's merged
InputPreferences adapter. Controller remapping remains pending. New InputMap
entries go through A's ownership.

## Extension policy
Update typed definition, mock, consumer, contract notes and checks together.
A change to an existing field's meaning is a breaking change; coordinate it before
editing. WireCodec.PROTOCOL below is the actual transport compatibility version;
do not infer wire support from a baseline configuration constant.

## Session API — protocol 4, build mvp-ab-11

### Client recovery (current local API)

After an established client unexpectedly loses transport, `can_reconnect()`
reports whether a same-session retry is available. `reconnect()` uses only the
remembered endpoint and private rotated token; it never falls back to fresh
admission. `is_reconnecting()` reports an in-flight attempt and
`reconnect_seconds_remaining()` gives the remaining local retry budget, up to
20 seconds from detection. This is not a guarantee of server eligibility: the
server's disconnect deadline, membership and token validation remain authoritative.
The connection-state enum and wire format are unchanged.

`left`/`error` details include `reconnect_available`; unexpected transport loss
preserves recovery, while explicit `leave()`, new join/host/practice, rejection
and expiry clear it. Tokens and endpoint are memory-only. A successful `joined`
event includes `reconnected: true` for token-based recovery; wait for baseline
before returning to play and do not submit a fresh build. The general menu keeps
hosted membership while recovering and releases it only on explicit leave.

### Historical session baseline

The playable a-b-integration checkpoint is still mvp-ab-2/protocol 3. Both peers
must use the same build. Private clock/baseline and snapshot epoch semantics
changed on a-contact-reconciliation. The preceding 5v5 branch adds ten-player
capacity and compact match summaries/detailed results delivery as described below.
BotSource and camera/input APIs remain unchanged.

`MvpSession` must have the same relative NodePath on every peer. Instantiate it
under the application/session root, then call `host(port=24567, listen=true, player_count=4, mode="teams")` or
`join(address, port=24567, token="")`; both return a Godot Error. `leave()` closes
the local connection. Preserve `reconnect_token` in memory for a retry, never in
logs or lobby UI. A reconnect rotates the token and preserves the original bot.

Requests: `set_loadout(draft)`, `set_team(0|1)`, `set_ready(bool)`,
`vote_forfeit()`, `vote_rematch()`, `submit_local(BotCommand)`. The session assigns
transport sequence numbers; B's existing per-tick command sequence may continue.
The host selects 2 (1v1), 4 (2v2) or 10 (5v5) connected/ready slots. Other counts return
ERR_INVALID_PARAMETER before opening a server. The API's omitted count remains 4
for existing consumers; the app defaults to 2. Server alone advances the lifecycle.
With `mode="ffa"`, the selected count is a maximum of 4–8. At least four admitted
players, all connected and ready, start even below that maximum. Load acknowledgments
and rematches use the actual roster. An FFA rematch requires every connected
participant's vote and at least four connected players; disconnected slots are
removed before restarting. Team formats still require their full selected count.
FFA `team` equals the bot's unique entity ID, making all other entities hostile;
`set_team` returns an operation error. Forfeit affects only the requesting bot.

Signals:
- `session_event(kind, details)`: hosted, joined, left, results, or error. Error
  details contain a message and optionally operation/code. Results carry match,
  participant state, build and content hash.
- `lobby_changed(view)`: slots (entity_id, peer, team, ready, connected, loadout),
  capacity=2|4|10 for teams or 4–8 for FFA, mode=1v1|2v2|5v5|ffa, phase.
  `minimum_players` is 4 for FFA and capacity for teams. Tokens never appear here.
- `match_changed(view)`: authoritative MatchState view. Timer updates at 1 Hz;
  phase changes arrive reliably. UI may interpolate a countdown for display only.
  Mode/capacity are included. `rounds` contains round/winner summaries. Detailed
  per-round participant records arrive with `session_event("results", details)`
  as `details.match.rounds[].participants`, alongside aggregate `details.participants`.
  Reliable result delivery occurs once per match; a results-phase reconnect
  baseline includes the full record and restores it without duplicate events.
  FFA includes ordered `placements`: `{entity_id, place, elimination_tick}`
  (-1 tick for survivors), and `winners`: all first-place entity IDs. Equal places
  use competition ranking (1, 1, 3); an entity-ID sort only orders tied rows.
  FFA `winner` is the sole winner's entity ID or -1 for a shared win. Read `winners`
  instead of labelling a shared FFA win a draw. Team winner/scores are unchanged;
  team winners/placements arrays are empty. FFA ignores the team `scores` field.
- `bot_updated(entity_id, BotView)`: resources and health from 20 Hz snapshots.
  `local_source()` returns the player's BotSource after loading. B's input must
  call `submit_local`, not mutate a client body or call a server bot directly.
- `combat_event(event)`: disposable visual event with match/round/event/attack IDs,
  server tick, attacker/target, zone, effective damage, position and normal.
  Dropping an effect never loses health state. Deduplicate by match/round/event ID.

`connection_state` is offline/connecting/connected/hosting/practice. `diagnostics` reports
RTT in milliseconds, correction distance in meters, rejected-input count, maximum
entity snapshot bytes, and received-snapshot count. UI must not infer request
success solely from pressing ready/join.

Server validates protocol/build/content at handshake, assigns sender ownership,
accepts bounded finite-axis command packets only, limits sequences/queue/rate,
and rejects loadout changes after lock. Input channel 1 is unreliable ordered at
30 packets/s with recent redundancy; channel 2 carries independently decodable
entity snapshots at 20 Hz; control uses reliable channel 0. Node/RID/Object handles
are never serialized. `WireCodec.PROTOCOL` is the actual wire version.
Snapshot delivery is unordered at the transport layer; per-entity round/epoch
and tick checks reject stale/duplicate state without dropping another bot's
valid update when packets arrive in a different order.
The bounded 1 Hz clock request/reply uses reliable control so ENet's unreliable
packet throttle cannot indefinitely prevent synchronization after a baseline.
Clock origin uses the lowest-RTT reply among eight recent samples; a clean reply
replaces retransmission bias promptly, and the window resets on a fresh baseline.
Reliable baseline/match payloads are capped at 128 KiB to accommodate ten players
and the five-round cap; ordinary timer messages omit detailed participant history.
`MatchState.begin(player_count=4, match_mode="teams")` uses 240-second rounds for ten players and
180 seconds for duel/2v2, preserving five-second countdown, first-to-two and
five-round draw cap. `match_mode="ffa"` uses one 300-second round and no overtime;
survivors rank by rounded core percentage then effective damage, eliminated bots
by latest elimination tick. Equal elimination ticks share placement regardless
of damage or kills; a complete first-place tie shares the win. Session calls
`advance(delta, combatants, teams, world.tick)` after all same-tick eliminations.
The host CLI accepts `--players=10` or `--mode=ffa --players=4..8`; app default
remains a two-player duel.

Local drive prediction uses the same DriveModel tire response as the server and
advances snapshots to the estimated current simulation tick, bounded to 250 ms,
using recent unacknowledged input. A server tick/echo clock exchange estimates
snapshot age separately from the input backlog. Free-flight replay includes
gravity and full angular rotation. Forward replay translation is swept against
the actual static-world collision shape in the physics callback, starting from
the authoritative snapshot pose. Existing contact normals prevent deeper
penetration. Dynamic contacts and rotational collision outcomes are not replayed.
First/reset snapshots seed exact authoritative pose and velocities before later
snapshots use swept replay.
Authoritative pose/velocity/contact
outcomes replace prediction; small positional visual errors decay, errors >=2 m
snap. Visual offsets accumulate when Jolt applies the correction, avoiding an
offset on the old physical pose; offsets above 0.25 m blend faster than smaller
driving corrections. This is approximate reconciliation, not
deterministic Jolt rollback. Snapshot epochs include match ID and round number;
round changes discard interpolation/replay history and reject old-round packets.
Baselines taken while an authoritative reset is pending carry the planned spawn
and zero prior motion/input, so reconnect cannot restore a previous round's pose.
Remote visuals interpolate in a 75–150 ms adaptive buffer; only surviving bots
in active/overtime extrapolate, stopping after 100 ms. Other phases and eliminated
bots hold the latest pose once interpolation history is exhausted.
`diagnostics.degraded` marks snapshots older than 250 ms and
`interpolation_ms` reports the buffer. MvpBot's stable camera anchor is now under
its separate Presentation node; use camera_anchor(), never hard-code a node path.

NetworkSimulator is opt-in for tests. It delays/drops/duplicates unreliable input
and snapshot sends; reliable control remains real ENet without emulated impairment.
The test profile `BATTLEBOTS_NET_PROFILE=80` uses 40 ms each direction, +/-10 ms
jitter, 1% loss and 2% duplication; profile 150 uses 75 ms, +/-20 ms, 3%/3%.
The independent `tests/network/transport_session.tscn` instead disables this
simulator and routes all four clients through loopback raw UDP relays. Both
reliable control and unreliable traffic receive the same configured impairment,
including a forced initial connection-packet loss. Relay instrumentation is
test-only; printed measured RTT includes scheduling/retransmission overhead and
must not be equated with the injected delay. No public diagnostics fields change.

## B integration example

Add a `SessionBotSource` Node3D near B's preview and set `session_path` to the
MvpSession node. Point the preview's `source_path` at this proxy. It forwards input
to submit_local(), reads the current local bot view, and resolves camera handles
through local_source(). Until a bot exists, it provides an inert default view and
itself as the anchor. B should show loading/lobby from session state, not this
default view. Do not retain an old camera anchor across baseline replacement.

`MvpSession.practice(draft={})` starts local physics against a stationary enemy;
it validates an unsaved draft before assembly and returns Error. `leave()` resets
it before starting another mode. No practice result is awarded. Networking MVP
uses the published B arena through AuthorityWorld and primitive bot rendering;
B's camera/HUD/settings mount through the combined app. Do not stack both
arena collision roots in one world. Match results include per-round participant
snapshots and aggregate damage/elimination/assist/component/recovery counters.

Neutral input for menus/focus loss must set brake and secondary_held so a held
lifter cancels instead of launching on release. All-false is an ordinary released
command. The server's stale/disconnect path supplies cancellation automatically.
`spectator_sources()` returns live teammates in team modes and all live bots in
FFA for B's spectator camera to cycle.

### Combined app checkpoint (mvp-ab-1)

AuthorityWorld now instantiates B's published arena and its spawn markers on every
peer; headless worlds remove presentation nodes. Do not add another arena to the
MVP app. SessionBotSource has an optional `input_allowed: Callable`; returning false
submits brake+secondary cancellation. No gate retains the previous forwarding API.
The app uses this to keep B's unmodified input collector safe during modal/focus
suppression, countdown and elimination. B can later own this gate in its final UI.

## Lunar Outpost arena contract (A, 20 September 2026)

Practice and LAN hosting select `foundry` (default) or `moon` via a final optional
`MvpSession.host(..., selected_arena)` parameter or `practice(draft, selected_arena)`.
Hello advertises optional `arena_rules: 1`. A Moon host rejects peers without that
capability before slot admission. Lobby and baseline add `arena`; absent baseline
arena means Foundry, unknown/non-string values disconnect. RPC signatures, build12
and protocol4 stay unchanged, preserving the deployed Foundry transport.

`AuthorityWorld.arena_id` determines physical terrain and bot gravity_scale.
Moon uses deterministic heightfield collision, four small rock colliders, existing
18 spawn markers and octagonal boundaries, and gravity_scale `1.62/9.8`.
Existing `DriveBody.model_config()` propagates gravity into replay. No BotCommand,
BotView, drive/camera/control implementation or combat contract changes.
Decorative meshes and particles remain client-only. See
[Moon handoff](coordination/A_MOON_ARENA.md) for compatibility and evidence.

## Foundry size and impact response (coordinated A/B, 23 September 2026)

Build `mvp-ab-15` changes gameplay; protocol 6 and catalogue 10 are unchanged.
`ArenaBounds.half_extent(arena_id)` is 50 m for Foundry and 25 m for Moon.
AuthorityWorld supplies each bot's `arena_half_extent` and camera-anchor metadata
with the same key. Cameras consume that geometry when switching local/spectated
anchors; input behavior is unchanged. Spawn clearance and recovery use the same
octagonal planes. Moon resizes its inherited shell before entering physics and
duplicates resources to avoid modifying concurrently loaded Foundry worlds.

MvpBot keeps catalogue mass and motor settings, lowers its center of mass and
adds pitch/roll inertia and angular damping. DriveBody.model_config now includes
local `center_of_mass`; bounded DriveModel replay rotates the hull origin around
that point while Jolt velocity advances the center. No wire fields change.
CombatWorld scales ordinary weapon impulses by 0.65 and the attacker/target mass
ratio (bounded 0.65–1.4); charged lifters omit the 0.65 reduction. Damage and
weapon activation remain unchanged. Matching server/client deployment is required.

## Match item pickups and credits (B with A areas, 23 September 2026, #35)

Build `mvp-ab-16`, protocol 7; catalogue unchanged. `AuthorityWorld.pickups`
(`MatchPickups`) stocks `pickup_points()` (centre and four diagonals at half
the arena radius, derived from `ArenaBounds`; terrain arenas use their ground) when a
match or practice begins; `reset_round()` restocks and `clear_bots()` clears.
Collection runs only while the match is active. Practice NPCs never collect.

`AuthorityWorld.apply_loadout(id, loadout)` is the only way to change a live
bot's match loadout. It validates against a budget-exempt registry
(`ContentRegistry.enforce_budget = false`; lobby validation stays strict).
Perk-only changes update `combat.stats` and `DriveBody` flags in place. Any
other slot replaces the MvpBot node under the same entity id and emits
`loadout_changed(id)`. Consumers must keep looking bots up by id, or through
`session.local_source()`, and never cache MvpBot references across frames.

`MvpSession` adds a reliable `_pickups` RPC and `baseline.pickups`:
`{match_id, revision, items:[{id, point, kind, part, amount, available}],
credits:{entity:int}, loadouts:{entity:loadout}, events:[...]}`. Clients apply
`loadouts` through `apply_loadout` and expose `pickup_view` (without
loadouts/events), `pickups_changed` and `pickup_collected(event)`. A refused touch
(`MatchPickups.refusals`: `{entity, item, kind, part, reason: equipped|incompatible}`, once per
contact) goes only to the owning peer via the reliable `_pickup_refused` RPC and emits
`pickup_refused(event)`. Protocol 10 / `mvp-ab-21`. Results
participants gain `credits: {pickups, performance, total}`, computed by the
server with `MatchPickups.reward`. Clients pay `total` into
`PlayerProfile.wallet` (`CreditWallet`, `user://wallet.cfg`) once per match
id. Practice never pays. The wallet is local and not tamper-proof; server-held
identity (#16) must own it before credits gate shared content.

## Heavy-machine physics configuration (B, #38, 23 September 2026)

Build `mvp-ab-17`, protocol 7 (unchanged wire fields); catalogue unchanged.
Gameplay change: needs A's matching hosted server release before hosted play.

All heft, motor-authority and impact tuning lives in `data/bot_physics.json`,
read through the typed `BotPhysics.settings()` loader (`scripts/core/bot_physics.gd`).
Missing or non-numeric fields fail loading; there are no silent defaults. Server
simulation and client replay read the same file, so changing any value is a
gameplay change requiring a BUILD bump and a matching hosted server release.

- `DriveBody.heft()` multiplies arena gravity (`heft.gravity_multiplier`) on arenas
  at or above `minimum_arena_gravity_scale`; the Moon keeps 1.62 m/s².
  `model_config().gravity` includes heft, and `model_config().max_rise` supplies
  the replay rise cap. `launch_scale()` = sqrt(heft) scales jumps, weapon impulses
  and the rise cap so apex heights hold while hang time shrinks.
- Traction: on its drive the hull uses `contact.track_hull_friction` (the drive
  model owns grip) and the tracks cancel `slope_hold_fraction` of the downhill
  pull up to the grip limit, so tanks park and climb steep hills. Stranded on
  roof/side it grinds with `stranded_hull_friction`. `DriveBody` also applies
  explicit Coulomb friction between touching bots (`bot_contact_friction`).
- Client replay sweep: floor-like contacts under an airborne client body limit
  translation but keep velocity, so a tumbling hull pivoting on a corner keeps
  falling like the server's; walls, and floors once grounded, still cancel it.
- Motor multipliers scale catalogue top speed, acceleration, grip, yaw limit/torque, brakes
  and released-throttle coast (`rolling_resistance_multiplier`, so knocked hulls
  stop instead of sliding) in `model_config()`. Walker lift supports heft weight.
- `CombatWorld` scales weapon impulses by `impacts.*_impulse_multiplier` and
  `launch_scale()`, adds ram knock-back proportional to closing speed above
  `RAM_MIN_CLOSING_SPEED`. The lifter applies no hold force while charging
  (`lifter_hold_acceleration_at_1g` 0); release launches the target with
  `lifter_impulse_multiplier` and adds `lifter_flip_spin_at_1g` × launch_scale
  about the horizontal axis so it flips away. The flipper arm visual lies flat
  while charging and snaps up on release. Damage, cadence and wire fields are unchanged.

## Hit stagger and hammer knockback (B, #32, 23 September 2026)

Build `mvp-ab-20`; protocol and catalogue unchanged. Gameplay change: confirmed hits
stagger the victim's drive, steering and grip (`CombatWorld.STAGGER`,
`CombatState.stagger()/stagger_factor()`, `DriveBody.grip_multiplier`), and hammer
blows knock the target away and upward. Stagger is authority-only and not
replicated. Needs a matching hosted server release before hosted play. Details and
the presentation-only VFX live in `docs/coordination/B_IMPACT_FEEDBACK.md`.

## Chassis core and per-area armour pieces (#46, 23 September 2026)

Protocol 11, build `mvp-ab-25`, catalogue revision 15, loadout schema 3. Needs the
matching hosted server release (automatic on the `main` push).

- **Loadout schema 3.** `ContentRegistry.SLOTS` drops `armor`: `parts` holds
  chassis/drive/weapon/utility/nitro/suspension. Armour packages (`light`,
  `standard_armor`, `heavy`) are removed from the catalogue. `LoadoutStore.migrate`
  upgrades known schema-2 saves (revision 13 and 14 hashes trusted) by erasing `parts.armor`.
- **Armour pieces** are the `cosmetics.sawblade` module choices `armor_side`,
  `armor_top`, `armor_front`, `armor_rear`, now gameplay. The server-owned catalogue
  (`data/mvp_parts.json` `armor_faces` / `armor_pieces`) gives each choice its
  `covers` faces, `integrity` (HP per covered face) and `mass`.
  `ContentRegistry.armor_plates(draft)` / `armor_mass(draft)`; piece mass counts
  toward the 120 kg budget. A draft without `cosmetics.sawblade` has no armour.
  `exhaust` stays cosmetic.
- **Stats.** `validate().stats.plates` maps front/rear/left/right/top/underside to
  armour HP (0 = bare) and `stats.armor_total` sums it; `plate_integrity` and
  `reduction` are removed. Chassis `core` scales with body size (Sawblade 240,
  Scorpion 300, Atlas MX 380).
- **Damage.** `CombatState` has one zone per face. A face hit is absorbed by that
  face's armour up to its remaining HP; the excess and every hit on a bare face go
  100% to the core. Drive/weapon routing is unchanged. `snapshot().plate_max` is the
  plates dictionary.
- **Wire.** `WireCodec.ZONES` adds `top` and `underside` (field count unchanged; the
  zone array is longer). Decoded views take `plate_max` from local canonical stats.
- **Views.** `MvpBot.read_view()` omits faces with no armour fitted, so `BotView.zones`
  reports fitted armour plus drive/weapon components. `CombatHud` and
  `CombatAudioStatus` treat all six faces as armour panels (0 = breached).
- **Garage/Customize.** PARTS > ARMOR lists the per-area piece sections (no package
  section). `GarageComparison.compare_armor()` previews a piece swap.
  `BuildReadout` shows six area values with top/underside inside the core box.

Build `mvp-ab-26` (B, #32): stagger now applies only to projectile hits (minigun,
plasma, flamer, tesla, cannon, railgun) and the saw blade. Hammer, spinners, lifter
and rams no longer stagger; hammer knockback is unchanged. Protocol and catalogue
unchanged. Needs a matching hosted server release.

Build `mvp-ab-27` (#50): wall pin. When a ram opens (closing speed above 4 m/s),
`CombatWorld` remembers the victim's struck face (drive/weapon zones map to
left/right/front) for `impacts.ram_pin_window_seconds`. If the victim touches static
arena geometry on its far side (new `DriveBody.static_contacts`, wall-like normals
only) while that face has no armour HP, it takes one extra `ram` event routed to that
face (all core): `ram_pin_damage_base + ram_pin_damage_per_closing_speed * excess`,
capped at `ram_pin_damage_max` (data/bot_physics.json). Bots now report up to 16
contacts. Protocol and catalogue unchanged. Needs a matching hosted server release.
