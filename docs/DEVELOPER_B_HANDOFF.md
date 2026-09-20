# Developer B — combat, bots, customisation and controls

## Garage options — 20 September 2026 user update

Garage/Customize now fill available height before paging. All existing options are
selectable; the sole offered chassis is the authored Sawblade body. Body edits
preserve the other parts and appearance; unsupported-model selection locks and
weapon substitution are removed. Canonical spinners render with the authored body.
Legacy saves retain their IDs/equipment; catalogue revision 6 requires matching
hosted content. See [behavior, migration and validation](coordination/B_GARAGE_OPTIONS.md).

## Camera/input lifecycle acceptance — 20 September 2026

Independent practice/source replacement and real ENet duel scenes verify current
camera anchors/exclusions, camera clearance through round transitions, cancellation
and release-before-rearm. Headless checks and native duel execution pass; baseline
passes. No runtime or shared API change. The prior intermittent baseline shutdown
access violation remains unresolved. See [evidence](coordination/B_CAMERA_ROUND_LIFECYCLE.md).

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

## Unsaved-build test drive — 20 September 2026

`codex/b-garage-test-drive`, from `e0ce7c4`, adds TEST DRIVE to Garage and Customize
through B's separate GarageTestDriveEntry. The menu owner installs it before text
scaling, avoiding concurrent edits to the active Sawblade task's customization
source. The existing real practice authority consumes a detached validated draft
and current arena selection. Restart keeps that build; BACK TO BUILD restores the
originating screen. No save/reload or undo-history change occurs.

Entry rejects invalid builds, existing sessions and settings/recovery modals.
The hidden workshop is disabled during gameplay so undo/navigation shortcuts
cannot edit drafts or navigate behind the test. Normal Practice still returns to
main. Independent component and real-game scenes, native 720p views through150%
text, baseline, practice-menu and real lobby/navigation regressions pass. See
[scope and evidence](coordination/B_GARAGE_TEST_DRIVE.md).

## Featured vehicle selection — 20 September 2026

`codex/b-featured-vehicle` starts from `9e54dcc` and integrates A's lunar arena
update through `dfd5e64`. Main and lobby consume B's
session-free FeaturedVehicle control: named local builds, Previous/Next, live
canonical chassis/weapon preview, and optional rotating pedestal with Pause/Resume.
The old main image/info and lobby dropdown/arena card are removed. Arena identity
and rules remain in the lobby; general session/navigation ownership stays with A.

Selection updates the local profile only. Lobby Apply submits through the existing
session API; status distinguishes drafts from host-confirmed builds and existing
phase/pending locks guard callbacks. Paint-only acknowledgement now compares paint,
not just name/parts. Invalid choices remain visible for repair without fabricating
a model or submitting a legal build. No wire or persistence schema changes.

See [intent, API and validation](coordination/B_FEATURED_VEHICLE.md). Canonical
primitive visuals remain a developing-game asset limitation; this feature does
not claim authored bot art or human hosted-1v1 acceptance.

## B menu text accessibility — 20 September 2026

`codex/b-menu-text-accessibility` starts from `d6e154e`, rebased onto A's
`fe9f2f0` with the newer no-scrolling menu feedback. The saved shared
100/125/150% text setting now reaches Garage, Customize, catalogue, preview/stat
comparisons, file recovery and camera/input settings. Fonts retain the requested
factor across rebuilt rows, repeated application and returning to 100%; wrapping
and keyboard-accessible pages keep controls reachable at 720p through 4K.
Garage uses two builds per page and Loadout/Stats tabs; catalogue and Customize
page choices, rules and detailed stats. Mass/power and Save stay visible.
Preview reasons/recovery text also page. Controls has three binding groups;
Camera uses a responsive inline form. No ScrollContainers remain in B menus.
Camera/input drafts, binding capture, Cancel and Save retain existing behavior.

A handoff: menu_game calls `preview.settings_panel.apply_text_scale` and lets its
responsive Center use the actual window instead of scaling a fixed1600x900 frame.
Existing Form/MarginContainer paths and transactions integrate with A's new
themed settings hub. No wire, input-action or preference-schema changes.

Independent Customize, Garage/catalogue, controls and composed-game scenes pass;
rendered 150% screens inspected at 720p, with layout checks through 4K. Composed
checks verify live preview, Cancel, persistence and newly opened screens. Baseline
and affected existing garage/control/general-settings and SETTINGS HUB checks pass.
Native composed Camera/Controls150%720p screens were inspected. Subagents
implemented Garage/catalogue and controls in parallel. See
[scope and evidence](coordination/B_MENU_TEXT_ACCESSIBILITY.md). Remaining garage
work includes authored bot art and a direct unsaved-build test-drive entry; full
combat/control and human 1v1 acceptance remain open.

## Saved-file recovery — 20 September 2026

`codex/b-garage-recovery` starts from main `e24ab02`. Garage and Customize now
offer Saved File: reload disk builds without losing edited/new drafts or history,
and review/confirm a readable backup when primary is missing or unreadable.
Retained copies cannot overwrite refreshed slots; existing duplicate-name and
capacity checks apply. Restore binds confirmation to exact source bytes, keeps
the backup, and archives an unreadable primary to the displayed unique path.
Cancel does not write. Without a usable backup, files remain untouched.

Intent was published to A before implementation. Local APIs are in CONTRACTS.md;
no A runtime or wire changes. Subagents implemented isolated store tests and
reviewed the profile/modal. That review caught and resolved modal directional
focus escape, initial garage focus and redo-at-baseline loss. Storage and actual
garage/customize recovery scenes pass headless; rendered D3D12 review/result
screens fit 1280x720. Baseline and profile/history/repair/comparison/customization
regressions pass. See [recovery evidence](coordination/B_GARAGE_RECOVERY.md).
Text scaling is delivered above; authored bot art and full 1v1 acceptance remain.

## Saved-build repair — 20 September 2026

`codex/b-garage-repair` starts from main `331e073`. Save now replaces/appends one
valid build while retaining unrelated malformed or unknown records. Several bad
entries can be repaired independently; unsaved edits to siblings are not written.
External changes to the loaded file reject the write instead of overwriting it.
Explicit Revalidate updates only draft envelope/catalogue metadata, preserves
selected part IDs and paint, supports Undo and writes nothing until Save.

A: additive local LoadoutStore API is documented in CONTRACTS.md; strict full-list
save, gameplay validation and wire schema are unchanged. Subagent implemented
storage and its independent scene; primary integrated actual Customize repair.
See [repair evidence](coordination/B_GARAGE_REPAIR.md). Saved-file recovery now
has the explicit workflow described above; ambiguous overwrites remain refused.

## Garage comparisons — 20 September 2026

`codex/b-garage-comparison` starts from main `682824b`. Customize now compares
equipped/proposed canonical part stats before Equip, with signed neutral deltas.
Mass and power budgets stay visible above scrollable core, speed, armor, grip,
battery, cooling, recovery and plate-integrity rows. Invalid fully identifiable
builds show known mass/power; other derived values remain unavailable. Proposed
validation errors are explicit, and invalid drafts remain editable for repair.
The 3D preview remains the equipped draft; highlighting a candidate never equips.

A: no catalogue, wire, schema, network, general-menu or combat changes. Scope was
published in [the comparison record](coordination/B_GARAGE_COMPARISON.md) before
implementation. A subagent supplied the pure model and independent acceptance
scenes; the primary integrated/reviewed the screen. Repair and recovery follow in
the increments above; authored bot art remains B work.

## Live garage preview — 20 September 2026

Branch `codex/b-garage-preview`, from main `2a9e70a`, adds a lit cosmetic viewport
to Garage and Customize. It renders the equipped draft, not the highlighted
catalogue candidate. All five weapons reuse existing primitive presentation;
chassis dimensions and paint follow the validated draft. Invalid builds clear the
previous model and show reasons. Drag/arrows rotate, wheel/+/- zoom, Home or the
reset button restores the view. There is no combat/physics/session in the preview.

A: no router, session, world, audio, input map, content hash or shared-schema
changes. B intent was published before implementation. The new automated scene
is in the presentation runner; `scenes/dev/b_garage_preview.tscn` is an independent
manual F6 sandbox. See [scope and evidence](coordination/B_GARAGE_PREVIEW.md).
Older concept-image-only descriptions below are historical. Comparisons and
repair/recovery and text scaling are implemented above; authored bot art remains.

## Garage history — 20 September 2026

`codex/b-garage-history` starts at main `2b42812`. Parts, paint and committed name
edits now have per-build undo/redo in Customize, including keyboard shortcuts.
History survives menu navigation and Save; undo changes the draft only. Invalid
drafts remain repairable. Raw startup reload clears history; the user-facing
Saved File reload now preserves it as described above. No shared schema or
A-owned runtime changes. Baseline, independent history, profile and customization
checks passed; rendered 720p layout inspected. See
[scope and evidence](coordination/B_GARAGE_HISTORY.md). The full 1v1 acceptance
and current A deployment/menu work remain tracked separately.

## Current user-defined ownership

B owns combat, bot models/weapons, bot-customisation menus and player controls.
A owns general menus, networking, game rules, game world and audio. Arena/world,
general lobby/HUD/results integration and audio are now A responsibilities.
CombatState/CombatWorld, bot assembly/catalogue and driving are now B
responsibilities, alongside garage/customisation and input/camera controls.
See TEAM_WORKFLOW.md for shared interfaces. Older entries below retain historical
authorship and validation; their ownership labels do not override this split.

## Results follow-up — 19 September 2026

Current branch: `codex/b-results-followup`, based on integrated A `3f0e80f`.
The default menu game now opens detailed final/per-round server statistics with
FFA placements, rematch and explicit leave. See
[scope and validation](coordination/B_RESULTS_FOLLOWUP.md). Shared contracts are
unchanged; spectating and remaining garage/presentation work are still open.
Baseline, results checks and the real two-peer full-match/rematch check passed.
The network fixture exited successfully but reported two ObjectDB instances
leaked during shutdown; teardown cleanup remains to investigate. Rendered results
were inspected at 1280x720. No human LAN acceptance is claimed.
The earlier branch/build descriptions below are historical.

Owner: Developer B. Active branch: `codex/b-menu-kit`.
Dependency base: B match HUD `d983612`, built on A/B integration `bdb42ef`. Earlier camera/HUD/settings work
was published on `codex/b-arena-camera` through `40aa6b1`.

Ongoing work is tracked in [Worker B's to-do list](DEVELOPER_B_TODO.md), including
priorities, ownership boundaries and dependencies requested from A.

## User-supplied menu kit

F5 now opens scenes/dev/b_menu_game.tscn, using all eight imported menu designs at
ui/menus. The persistent root owns one real session and one input producer;
navigation replaces only the menu Control. MenuRouter and PlayerProfile are added
autoloads. The original project viewport, renderer, physics and input actions stay
unchanged. Authored 1920x1080 menus scale to the 1280x720 game viewport.

Practice/duel/2v2 use canonical selected builds. LAN host/join/team/build/ready use
public session APIs; server loading/countdown opens the actual arena. Garage and
Customize persist through LoadoutStore; all functional parts are free. Settings
opens existing preferences. Supplied images remain labeled concept art. Unsupported
career, ranked/public services, 5v5/FFA, invites and decals are explicit.

A: project.godot entry/autoload wiring is the only shared runtime edit, required by
the user's request to implement this menu. Existing app scenes and command-line
server/host/join paths are preserved. Continue merging protocol-4 independently;
current B peers still require mvp-ab-2/protocol3. See coordination/B_MENU_KIT.md.
Detailed results work was saved separately when the user prioritized this kit.
## B-08a: in-arena match status

MatchHud.render(match_view, practice) displays authoritative phase, round, clock,
team scores and round/final winner or draw. It never advances the match clock or
derives a winner from health/scores. Missing values remain unavailable; Practice
does not show competitive results. The top-center header leaves resource HUD and
diagnostics visible at 1280x720. Independent fixture: scenes/dev/b_match_hud.tscn.

The playable B scene stays in the arena for countdown, intermission and results.
Input remains cancelled outside active/overtime. Escape menus and settings remain
available, and a phase transition does not dismiss an explicitly opened menu.
A can mount the reusable HUD without changing the session contract. Detailed
results statistics, rematch controls and teammate spectating remain B-08 work.

## B-07a: playable lobby and arena

Open scenes/dev/b_lobby_game.tscn (F6). Practice immediately enters actual combat;
or host a 2v2/1v1 match, join from another matching build and ready up. Both players
enter the arena automatically. Escape opens the lobby; Resume returns to play.
The scene uses A's real session and one B input producer, with no mock gameplay.

LobbyPanel renders authoritative roster/build/readiness; LobbyCoordinator binds
public session APIs and emits navigation requests to its owner. It does not own
or free the session. Pending requests disable duplicates and time out visibly.
Starter selection/acknowledgement handles JSON numeric schema conversion.

A: replace the F5 integration menu with this panel/adapter rather than mounting
both. The separate B scene is playable now; F5 routing remains A-owned. One narrow
service fix was necessary: remote team IDs arrive as JSON floats and were rejected
by integer-array membership. The numeric 0/1 guard preserves rejection of invalid
values; carry it onto the contact branch. Full details: coordination/B_LOBBY_PRESENTATION.md.
The current B runtime is mvp-ab-2/protocol 3; A contact is mvp-ab-3/protocol 4.
Contact-camera follow-up: when an opponent covers the camera anchor, the camera now seeks a clear elevated pivot without crossing world geometry. Real Practice combat and a stationary contact/ceiling regression cover it.

## B-06: live connection diagnostics

Read [B-06 intent and evidence](coordination/B_NETWORK_DIAGNOSTICS.md). The preview
now reads SessionBotSource.session into a compact top-right connection panel.
Details shows client last RTT/correction/interpolation/snapshot count or host
rejections/largest snapshot packet, plus build, mode, phase and local engine
physics time. The Details button is keyboard accessible and cancels gameplay
before interaction; it preserves focus through key-up. This is a read-only view.

DiagnosticsLayer is separate from CanvasLayer, so A's menu can hide the ordinary
HUD without hiding connection state. Settings hide the panel. At 1280x720 the
paused panel fits beside A's current 720px menu; coordinate a layout update if
A changes that width. Expanded details are transient, not a saved player setting.

A's diagnostic counters survive leave(), so counters/maxima are explicitly labeled
session-node lifetime. Client metrics appear only in active/overtime and after a
new snapshot count is observed for the connection/match/phase. Offline, connecting,
practice and lobby never reuse prior remote telemetry. Missing, negative, nonfinite
or wrongly typed fields display unavailable. No packet-loss estimate, current
health claim, remote physics timing or automatic reconnect is inferred.

Independent F6 scene: scenes/dev/b_network_diagnostics.tscn, eight synthetic
scenarios. The runner includes widget validation, real two-peer UDP snapshots with
packet starvation/recovery, and rendered scenario/app-layout coverage. Human LAN
performance/feel acceptance still requires both office computers.

## B-04a: cancellation and standalone navigation

Read [the B-04 intention/evidence record](coordination/B_INPUT_MENU.md).
Menus, settings and focus loss now submit brake+secondary cancellation immediately
and on every disabled-control tick. Held drive, weapon and recovery actions must
be released before they can reactivate. An intentional lifter release still fires.
Keep A's SessionBotSource lifecycle gate; this change does not replace it.

The standalone preview has Resume, Camera settings and Return to launcher buttons.
Tab/arrow keys navigate; Enter activates. Escape opens/closes this menu, never
destroys the scene. Return is explicit, idempotent and deferred. A's live menu
continues handling its own Escape/navigation and may hide the preview CanvasLayer.
No changes to A-owned app/core/network/simulation files are needed.

Independent interactive scene: `scenes/dev/b_input_menu.tscn`. It runs A's real
lifter rules against B's input adapter and displays a launch counter, without
pretending to be drive or multiplayer simulation. Tests:

```powershell
./battlebots/tests/presentation/check-presentation.ps1 -GodotPath $GodotPath
```

Baseline, camera/settings, input menu and A's duel/navigation regressions passed.
The menu was also rendered and inspected at 1280x720. B-04b rebinding is described below;
human LAN/contact acceptance remains outstanding.

## B-04b: controls and weapon activation preference

From Camera settings, choose Controls. Bind a keyboard key or mouse button to an
action, choose hold/toggle primary, then Save & back. Edits are drafts until saved;
Cancel discards them and Reset defaults is also a draft. Camera and controls have
separate saves. Escape cancels capture first, then returns to the camera page,
then closes settings. Duplicate bindings, reserved navigation keys, chords and
wheel input on held actions are rejected. UI actions remain fixed; future camera
view/ping/scoreboard actions are explicitly marked planned.

InputPreferences stores validated primitive JSON (schema 1) in
user://presentation_input.cfg. Runtime binding changes preserve controller events
and restore the previous action map on scene exit. Other fixture settings paths
use the same path plus .input; an empty settings_path disables both saves.
Invalid files load complete defaults and a notice. Physically held controls must
be released before they can activate after saving/resuming.

Toggle primary: first press activates; second press deliberately releases, which
fires a charged lifter. Secondary, menu/focus loss and SessionBotSource lifecycle
suppression cancel the latch. B now also consults A's existing input_allowed
callback before sampling; A's source still independently enforces it. No command
or wire changes. Keep that callback pure and retain the source-side guard.

Independent F6 scene: scenes/dev/b_controls.tscn. It uses real lifter rules and its
own user://b_controls_camera.cfg.input file, leaving normal player preferences
alone. The presentation runner includes model persistence/validation, real-combat
toggle safety and GUI capture/navigation/save/reload/rearm/lifecycle tests.

A follow-up: the app's build_hint currently hardcodes LMB/hold text. When refreshing
that A-owned menu, consume preview.input_preferences.label_for(primary/secondary)
and toggle_primary so its instructions reflect saved controls. B's fixture and
camera hints already reflect the selected bindings. Controller remapping remains
B-11; this increment preserves controller events but does not add controller UI.

## B-03 follow-up: camera settings

Press Escape to release the cursor, then click **Camera settings** (or Tab to the
button and press Enter). The modal changes independent X/Y sensitivity, vertical inversion,
automatic recentering and recenter strength live. **Save & resume** persists them;
**Cancel** or Escape restores the values from when the panel opened. Reset is
previewed until saved. Gameplay input stays neutral; the simulation is not paused.

The B-owned `CameraPreferences` adapter writes version 2 to
`user://presentation_camera.cfg` using a temporary file and replacement. It does
not create an autoload or alter A's profile service. Version-1 files load their shared sensitivity into both axes and migrate only on Save. The legacy sensitivity setter still sets both axes; its getter returns X. Unknown file versions fall
back to defaults with a notice; invalid fields use defaults or bounded values;
save failures keep the modal open with an error. Tests use isolated temporary
paths, never the player's preferences. The preview's `settings_path` export can
be overridden for fixtures; an empty path disables loading/saving.

Integration needs no core API or InputMap changes. The panel lives under its own
CanvasLayer and handles Escape before it can fall through to launcher navigation.
Keyboard focus starts on sensitivity; Tab navigates controls. Window focus loss
leaves the modal open and does not recapture the mouse.

Validation: baseline smoke, camera/arena integration, and
`res://tests/presentation/camera_settings_test.gd` passed. The settings test covers
round-trip persistence, replacing an existing file, a fresh scene loading saved
values, live changes, Cancel/defaults, neutral input, save failure and invalid
schema/data. Its rendered `-- --capture` run was inspected at 1280 × 720.

## B-02 follow-up: reusable status HUD

The preview now instances `scenes/ui/bot_status_hud.tscn`, backed by
`scripts/ui/bot_status_hud.gd`. Use `set_context(label)` and `show_view(BotView)`
after the node is ready; `show_view(null)` clears a missing target. It displays
existing core/battery/heat/weapon-charge fractions and weapon/elimination state,
without calculating gameplay outcomes. Both existing sandbox scenes use it.

The baseline smoke check and rendered presentation checks passed, including
invalid fractions and target removal. The 1280 × 720 layout was visually checked.
No A-owned files or shared contracts were changed for this increment. Next is
B-03 (camera settings), not new authoritative state or lobby behavior.

This implements B's first foundation task. It supersedes the baseline notes about
missing walls and a static camera; shared core contracts remain unchanged.

## Delivered

- A 50 × 50-meter floor, three-meter perimeter walls, two-meter corner chamfers,
  symmetric team markings and eighteen spawn markers. Geometry is serialized in
  the arena scene and loads headlessly without visual scripts.
- Team1_1..5 and Team2_1..5 retain their existing names/transforms; use slots 2 and
  4 for 2v2. FFA_1..8 are evenly distributed at radius 20, facing the center.
- A reusable BotOrbitCamera consuming only BotSource. Mouse orbit, 4–9m zoom,
  middle-click recenter, optional gentle auto-recenter after 1.5 seconds of idle
  mouse input while driving, and horizon stabilization independent of bot roll.
- A 0.25m sphere sweep against World/Bots, excluding the source's own RIDs. The
  boom shortens immediately and extends smoothly. Floor/perimeter/chamfer limits
  keep the camera inside even when looking down over the physical walls.
- A diagnostic HUD, cursor capture/release, neutral commands on focus loss, and
  suppression of weapon activation from the click that recaptures the cursor.
- Mock-only WASD movement, a visible front bumper, wheels, and test shortcuts.
  This is presentation testing, not drive physics or collision simulation.

## Run and controls

Open `battlebots/scenes/dev/b_presentation.tscn` and press F6, or select B in F5's
launcher. Click inside the arena if the cursor is released.

| Control | Result |
|---|---|
| Mouse / wheel / MMB | Orbit / zoom / recenter |
| WASD / Space | Move the mock / brake |
| 1 / 2 / 3 | Place mock at center / south wall / southeast corner |
| 4 | Toggle upside-down mock |
| 5 | Toggle automatic recentering |
| Escape | Open menu / resume; use the explicit Return button to leave |

Sensitivity, inversion, recenter speed and automatic recenter are exported on the
OrbitCamera node and exposed through the B-03 settings panel. First-person view,
input remapping, obstruction outlines, combat effects and the full match HUD
remain later tasks.

## Integration for A

The existing A sandbox already instances the same preview and therefore uses the
new camera without editing any A-owned scene. Preserve BotSource's camera_anchor,
camera_exclusions and detached read_view methods. Include every owned physics
RID in camera_exclusions; this prevents clipping behavior when a bot is inverted.

The camera assumes this single arena is centered at the origin, axis-aligned,
with half extent 25 and chamfer 2. For other layouts, configure these exports or
introduce an agreed arena manifest. No new InputMap actions or engine settings
are required. Physics stays at 60 Hz and Jolt remains the backend.

Review wall/chamfer colliders with real drive physics before merging. The floor
has no new collision seams, hazards or gameplay modifiers. The mock intentionally
clamps its visual movement inside the perimeter and never simulates contacts.

## Validation

Run the existing `tools/check-baseline.ps1` with Godot 4.7.2, followed by:

```powershell
& $GodotPath --headless --path battlebots --script res://tests/presentation/camera_arena_test.gd
```

The presentation test checks physical input bindings, all FFA headings/radii,
perimeter and chamfer collision, camera clearance across wall/corner/pitch/yaw
cases, an interior obstruction, zoom/pitch limits, manual/automatic recenter,
horizon stability, neutral input, target deletion, and the A bot's own-collider
exclusion. A rendered D3D12/Forward+ run can save a preview with `-- --capture`.

Godot 4.7.2 import and baseline smoke checks passed. The camera/arena test passed
headlessly and in a rendered run; the saved preview was visually inspected.
Actual human input feel and real drive/network interaction still need joint
playtesting. No multiplayer functionality is claimed by this task.

## Repository state

An existing local `battlebots/project.godot` edit was present before B started.
It was preserved and is excluded from B's commit. No simulation, networking,
bot assembly, shared contracts, data, or application-bootstrap files were edited.
Merge this branch through normal review; do not replace A's evolving scenes.
