# Baseline contracts — v1

These are local typed GDScript interfaces, not a wire protocol or complete game API.
A owns implementation definitions under scripts/core; B consumes them via adapters.
Paths below are relative to the Godot project.

## BotCommand
`scripts/core/bot_command.gd`: sequence >= 0, throttle and steering in [-1, 1],
brake, primary_held, primary_pressed, secondary_held, recovery_pressed.
Positive throttle drives chassis -Z. Positive steering means a right turn
(negative Godot yaw), including while reversing. Held actions are levels;
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
Health-zone details, match views, registry/garage validation and serialization are
future coordinated additions, not empty APIs to implement against today.

### Additive MVP implementation on A's branch

Existing fields/methods retain their meanings. BotView now also defaults `owner_id`,
`team`, `server_tick`, `zones`, `weapon_cooldown`, `recovery_cooldown`,
`immobilized_remaining` (seconds; zero means inactive), and `failure_reason`.
B's existing mock inherits neutral defaults; its existing consumers need no edits.
`MvpBot` exposes real values, fresh per read. Camera anchor/exclusions are unchanged.

`ContentRegistry.validate(draft) -> LoadoutValidation` returns `valid`, specific
`reasons`, canonical `stats`, and a detached normalized `loadout`. `starter(false)`
is Striker; `starter(true)` is Controller. Draft shape: `schema_version: 1`, `name`,
`parts` (chassis/drive/weapon/armor/utility IDs), `cosmetics: {paint: id}`,
`content_hash: registry.content_hash`. All current parts fit their category socket;
the two MVP weapon IDs are `vertical_spinner` and `lifter`.

`LoadoutStore.save(Array) -> Error` stores up to twelve uniquely named legal builds;
`load_saved()` returns `loadouts`, `invalid` (index to reasons), `errors`, and
`restored_backup`. Invalid/unknown builds remain visible for repair, never silently
substituted. Local store defaults to `user://loadouts.json`.

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
by the record but have no gameplay effect yet. B's mock rotates a visual and
provides sample HUD values; it intentionally ignores input. Both satisfy the same
interface. The preview only knows BotSource, never a concrete physics node path.
CameraAnchor exists on both sources. Networking must not serialize Node/RID handles.

## Coordinates, timing and collision
Meters, kilograms, Y-up, -Z-forward, radians in logic, degrees in editor/UI.
Physics: 60 Hz. World layer index 1 (mask 1), Bots index 2 (mask 2),
HitZones index 3 (mask 4). Cosmetic visuals have no collision.
Arena floor surface is Y=0, X/Z bounds +/-25.
Team spawn markers are under SpawnPoints; names Team1_1..5 and Team2_1..5.
For 2v2 use indices 2 and 4 (X=-6/+6). Spawn Y=0.5 is body-center clearance.
The baseline has no FFA markers or perimeter walls; B adds them in the first task.
Spawn a future bot root with care: the bot fixture already offsets its body
upward by 0.5, so do not apply that clearance twice when integrating spawn logic.

## Registered input actions
drive_forward=W, drive_reverse=S, steer_left=A, steer_right=D, brake=Space,
primary=LMB, secondary=RMB, recover=R, camera_toggle=C,
camera_recenter=MMB, camera_zoom_in/out=wheel, ping=Q, scoreboard=Tab, pause=Escape.
Only driving/weapon intent collection and Escape navigation are wired in the preview.
B submits neutral input when the window is unfocused. Full menu capture/rebinding
is B's future work. New InputMap entries go through A's project.godot ownership.

## Extension policy
Update typed definition, mock, consumer, contract notes and checks together.
A change to an existing field's meaning is a breaking change; coordinate it before
editing. PROTOCOL_VERSION=1 is reserved configuration, not a compatibility promise
for networking that does not yet exist.
