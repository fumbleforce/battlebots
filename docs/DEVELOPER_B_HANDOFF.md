# Developer B — arena and third-person camera

Owner: Developer B. Active branch: `codex/b-lobby-presentation`.
Dependency base: B diagnostics `85dc14d`, built on A/B integration `bdb42ef`. Earlier camera/HUD/settings work
was published on `codex/b-arena-camera` through `40aa6b1`.

Ongoing work is tracked in [Worker B's to-do list](DEVELOPER_B_TODO.md), including
priorities, ownership boundaries and dependencies requested from A.

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
