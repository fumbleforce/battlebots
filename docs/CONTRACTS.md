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

## MVP session API — protocol 3 (A branch)

`MvpSession` must have the same relative NodePath on every peer. Instantiate it
under the application/session root, then call `host(port=24567, listen=true)` or
`join(address, port=24567, token="")`; both return a Godot Error. `leave()` closes
the local connection. Preserve `reconnect_token` in memory for a retry, never in
logs or lobby UI. A reconnect rotates the token and preserves the original bot.

Requests: `set_loadout(draft)`, `set_team(0|1)`, `set_ready(bool)`,
`vote_forfeit()`, `vote_rematch()`, `submit_local(BotCommand)`. The session assigns
transport sequence numbers; B's existing per-tick command sequence may continue.
Four connected/ready slots are required. Server alone advances the lifecycle.

Signals:
- `session_event(kind, details)`: hosted, joined, left, results, or error. Error
  details contain a message and optionally operation/code. Results carry match,
  participant state, build and content hash.
- `lobby_changed(view)`: slots (entity_id, peer, team, ready, connected, loadout),
  capacity=4, mode=2v2, phase. Tokens never appear in this view.
- `match_changed(view)`: authoritative MatchState view. Timer updates at 1 Hz;
  phase changes arrive reliably. UI may interpolate a countdown for display only.
- `bot_updated(entity_id, BotView)`: resources and health from 20 Hz snapshots.
  `local_source()` returns the player's BotSource after loading. B's input must
  call `submit_local`, not mutate a client body or call a server bot directly.
- `combat_event(event)`: disposable visual event with match/round/event/attack IDs,
  server tick, attacker/target, zone, effective damage, position and normal.
  Dropping an effect never loses health state. Deduplicate by match/round/event ID.

`connection_state` is offline/connecting/connected/hosting. `diagnostics` reports
RTT in milliseconds, correction distance in meters, rejected-input count, maximum
entity snapshot bytes, and received-snapshot count. UI must not infer request
success solely from pressing ready/join.

Server validates protocol/build/content at handshake, assigns sender ownership,
accepts bounded finite-axis command packets only, limits sequences/queue/rate,
and rejects loadout changes after lock. Input channel 1 is unreliable ordered at
30 packets/s with recent redundancy; channel 2 carries independently decodable
entity snapshots at 20 Hz; control uses reliable channel 0. Node/RID/Object handles
are never serialized. `WireCodec.PROTOCOL` is the actual wire version.

Local drive prediction uses the same DriveModel tire response as the server and
replays up to 250 ms of unacknowledged commands. Authoritative pose/velocity/contact
outcomes replace prediction; small positional visual errors decay, errors >=2 m
snap. This is approximate contact reconciliation, not deterministic Jolt rollback.
Remote visuals interpolate in a 75–150 ms adaptive buffer; extrapolation stops
after 100 ms. `diagnostics.degraded` marks snapshots older than 250 ms and
`interpolation_ms` reports the buffer. MvpBot's stable camera anchor is now under
its separate Presentation node; use camera_anchor(), never hard-code a node path.

NetworkSimulator is opt-in for tests. It delays/drops/duplicates unreliable input
and snapshot sends; reliable control remains real ENet without emulated impairment.
The test profile `BATTLEBOTS_NET_PROFILE=80` uses 40 ms each direction, +/-10 ms
jitter, 1% loss and 2% duplication; profile 150 uses 75 ms, +/-20 ms, 3%/3%.

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
uses A's canonical collision-only Foundry dimensions and primitive rendering;
B's finished arena/camera remains a separate integration step. Do not stack both
arena collision roots in one world. Match results include per-round participant
snapshots and aggregate damage/elimination/assist/component/recovery counters.
