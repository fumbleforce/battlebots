# Project Battlebots — Game Specification

**Version:** 1.0 · **Date:** 19 September 2026 · **Engine:** Godot 4.7.2 stable

**Status:** Proposed design and implementation specification. This document does not represent implemented features. Numerical balance values are initial playtest targets unless explicitly stated otherwise.

## 1. Product definition

A competitive 3D robot-combat game in which players build a compact fighting machine, drive it directly into an enclosed arena, and win through positioning, weapon timing, and teamwork. Machines should feel heavy and mechanically understandable while remaining responsive enough for online competition.

The signature encounter is a teammate lifting an opponent, exposing its underside for a partner's spinning weapon, followed by a desperate self-right and counterattack. A good build creates opportunities; driving and coordination decide whether those opportunities become victories.

### Confirmed requirements and design decisions

| Category | Requirement or decision |
|---|---|
| User requirements | PvP; standard 2v2; additional 5v5 and FFA; a simple 50 × 50 arena; customizable player-controlled battlebots; mouse-controlled third-person camera; WASD movement; Godot 4.7.2 |
| Arena interpretation | 50 × 50 **meters** of playable floor; one Godot unit represents one meter |
| Proposed audience/platform | PC players who enjoy mechanical combat and short competitive matches; Windows client first, headless Linux server |
| Proposed combat style | Accessible simulation: physical motion and impacts, authored weapon damage and impulses |
| Camera decision | Third person is standard; optional first-person chassis camera ships after the core camera is validated |
| Proposed product scope | Small complete multiplayer game with one arena, three modes, modular construction, practice, and cosmetic progression |
| Reference image | Inspiration for low chassis, exposed mechanisms, steel surfaces, vivid paint, enclosed arena staging, and impact sparks; not a specification of exact machines, names, logos, or arena branding |

### Design pillars

1. **Readable mechanical combat.** Players can recognize weapon type, facing, damaged components, and attack readiness.
2. **Meaningful construction.** Weight, armor, traction, weapon, and recovery choices have visible tradeoffs.
3. **Team interaction.** Blocking, lifting, peeling attackers away, and coordinated strikes matter alongside damage.
4. **Competitive consistency.** Server decisions, mirrored arena layout, clear scoring, and identical part access keep outcomes understandable.

### Scope boundaries

The first release excludes freeform CAD construction, arbitrary player scripts or imported meshes, voxel destruction, fluid simulation, flying robots, ranged weapons, campaign content, console/mobile support, split screen, built-in voice chat, and a user-created arena editor. Physics debris is cosmetic. Ranked matchmaking is a later addition; public 2v2 is unranked initially.

## 2. Player experience and game loops

**Moment to moment:** read opponent facing → approach or bait → manage traction and weapon charge → strike, lift, or pin → recover and reposition.

**Match loop:** select build → join lobby → inspect teams → lock build → play rounds → inspect results → rematch or return to garage.

**Long-term loop:** experiment with builds → learn opponents and team combinations → complete play milestones → unlock paint and cosmetic badges. No combat part is locked behind progression or payment.

A first-time player receives a complete starter robot, enters a short practice tutorial, and can reach a multiplayer lobby without building anything. Tutorial steps cover driving, camera orbit, braking, weapon use, damaged-part feedback, and self-righting. The tutorial may be skipped and replayed.

## 3. Game modes and match rules

### Shared rules

- A round starts with a 5-second countdown. Bots cannot drive, charge weapons, or take damage until the server starts the round.
- Loadouts lock before the first round. Repairs and resource refills occur between rounds; mid-match part swaps are disabled.
- There are no repairs, ammunition pickups, respawns, or health regeneration during a round.
- Elimination occurs at zero core integrity, after a completed immobilization count, or on a disconnect timeout.
- Team weapons cannot damage allies or apply authored attack impulses to them. Ordinary physical collisions remain, allowing accidental blocking and physical assistance.
- Destroyed bots lose combat collision and become local visual wrecks, preventing inconsistent obstruction across clients.
- All simultaneous eliminations within the same server physics tick are resolved together before evaluating winners.
- Players eliminated from team modes spectate surviving teammates. FFA spectators may cycle survivors. Spectator cameras remain inside the arena.
- Intermission lasts 15 seconds. Post-match results offer rematch voting for 20 seconds; a rematch requires every connected participant to accept, otherwise players return to the lobby.

| Mode | Players | Format | Round limit | Win condition |
|---|---:|---|---:|---|
| Custom duel (user-requested MVP addition) | 2 | First to 2 round wins | 180 seconds | Eliminate the opponent; otherwise the same judging rules |
| Standard 2v2 | 4 | First to 2 round wins | 180 seconds | Eliminate the opposing team; otherwise judges' decision |
| 5v5 | 10 | First to 2 round wins | 240 seconds | Same team rules with five bots per side |
| FFA | 4–8 | One round | 300 seconds | Last surviving bot; otherwise timeout ranking |

Public 2v2 requires four connected players; matches do not start with empty slots. 5v5 uses full custom lobbies at launch. FFA supports custom lobbies and starts with at least four players. Practice supports one player with stationary or simple driving targets. AI does not fill PvP vacancies.

### Timeout judging and ties

At the timer, compare teams lexicographically:

1. Number of surviving bots.
2. Sum of each survivor's remaining core integrity as a percentage of its own maximum.
3. Total effective enemy damage dealt during the round, including damage to components but excluding overkill and damage to already-disabled parts.

Health percentages are rounded to 0.1 percentage points; damage is recorded in integer units. A complete tie starts 30 seconds of overtime with no repair. If still tied, the round is a draw. A simultaneous team wipe also draws the round. A match ends as a draw if neither team reaches two wins within five played rounds; this bounds repeated ties.

FFA uses the same survivor/core/damage ordering for players remaining at timeout. Earlier eliminations rank below survivors, ordered by elimination tick; simultaneous eliminations share placement. A complete tie for first shares the win. FFA awards no kill-steal scoring bonus: placement is the primary result.

### Immobilization, pins, and recovery

- Low speed alone never triggers elimination. Holding position is legal.
- A bot is immobilized if it has no functional drive pod, or remains upside down without restoring usable wheel contact for 5 seconds. The server then starts a visible 10-second elimination countdown.
- Restoring functional drive contact and moving at least 0.5 meters under the bot's own drive cancels the countdown. Being pushed does not count.
- A bot upside down for at least 2 seconds may activate its recovery system with `R`. Recovery takes 2 seconds and costs 30 battery. All chassis include this system; it has a 20-second cooldown and requires battery recovery if empty.
- Recovery applies a capped physical torque. It cannot teleport through another bot or guarantee escape from a pin. Cooldown and cost apply on activation.
- A pin is continuous weapon-assisted restraint against a wall or ground with target speed below 0.5 m/s. After 5 seconds, the holding weapon releases, withdraws, and cannot engage the same target for 3 seconds. Ordinary pushing remains legal.
- Out-of-bounds is an exceptional fault, not a scoring mechanic. The server returns the bot to its last valid floor position with zero velocity, preserving damage and resources. Repeated faults are logged for investigation.

## 4. Controls and camera

### Default keyboard and mouse

| Input | Action |
|---|---|
| W / S | Drive forward / reverse relative to the chassis |
| A / D | Turn left / right; differential steering allows turning in place |
| Mouse | Orbit camera yaw and pitch independently of chassis facing |
| Left mouse | Primary weapon; hold for spin/saw, press for hammer or flipper |
| Right mouse | Secondary mechanical action when supported: lower/retract lifter; otherwise brake weapon spin |
| Space | Wheel brake |
| R | Activate self-right recovery when eligible |
| C | Toggle third-person / first-person camera |
| Middle mouse | Recenter camera behind chassis |
| Mouse wheel | Third-person distance, 4–9 meters |
| Q | Context ping: opponent, location, or regroup |
| Tab | Hold scoreboard |
| Escape | Menu; online gameplay continues |

WASD uses vehicle steering rather than strafing. Mouse movement does not steer the bot. Reverse steering follows the same turn-direction convention as forward input to keep differential-drive control predictable. Acceleration and turning ramp in rather than changing instantly.

Inputs are remappable. Expose mouse sensitivity, inversion, camera recenter strength, toggle/hold weapon activation, and separate horizontal/vertical sensitivities. Focus loss clears held inputs. Controller support is a post-MVP release requirement with equivalent actions and remapping.

### Third-person behavior

- Default follow distance 6 meters; target anchor 0.6 meters above chassis center; pitch range approximately −15° to 70° relative to the horizontal viewing convention.
- Collision-aware camera boom pulls inward before intersecting walls. Camera casts exclude its own bot and cosmetic debris.
- Follow yaw is independent of chassis roll. Horizon stabilization prevents flips from rotating the view upside down.
- Optional automatic recenter activates after 1.5 seconds without mouse input while driving. Default is enabled at gentle strength.
- Shake and impact zoom are cosmetic, bounded, and independently adjustable down to zero.
- Outline the controlled bot when arena geometry obscures it; opponent outlines never reveal opponents through walls.

### First-person behavior

The camera sits on a standardized chassis sensor mount. It keeps a stabilized horizon, limits local yaw to ±100°, and displays a chassis-forward marker. Local chassis geometry may be hidden only where it clips the near plane. Combat rules and aim do not change between views; switching cannot move the camera through walls. Third person remains the reference view for balancing.

## 5. Robot construction

### Builder model

Use authored chassis sockets and compatible modules, not freeform geometry. Every legal build contains one chassis, one drive package, one primary weapon, one armor package, and one utility. Cosmetic elements have no mass, collision, visibility advantage, or gameplay effects.

All builds share a **120 kg** mass ceiling and a **100-unit installed power** budget. Power budget controls legal construction; battery is the separate runtime resource. Chassis fixes socket locations, collision envelope, core integrity, and recovery mechanism. No part can extend beyond its permitted weapon sweep or deployment envelope.

Target body footprint is 1.5–2.2 meters long and 1.2–1.8 meters wide. These deliberately enlarged game machines make the 50-meter arena practical; they are not a literal engineering simulation of the reference photo.

### Initial part catalogue

All statistics in these tables are authoring seeds, subject to the balancing process in section 16.

| Category | Part | Mass kg | Installed power | Identity |
|---|---|---:|---:|---|
| Chassis | Compact | 25 | 0 | 220 core; tight turning, narrow frontage |
| Chassis | Balanced | 30 | 0 | 260 core; versatile footprint |
| Chassis | Wide | 35 | 0 | 300 core; stable platform, broader target |
| Drive | Agile wheels | 18 | 25 | 12 m/s top speed; lower grip |
| Drive | Standard wheels | 22 | 25 | 10 m/s; balanced grip |
| Drive | Traction wheels | 28 | 30 | 8 m/s; strongest pushing grip |
| Weapon | Vertical spinner | 28 | 40 | Burst damage and upward disruption |
| Weapon | Horizontal spinner | 30 | 40 | Wide reach, strong recoil |
| Weapon | Lifter/flipper | 22 | 30 | Hold to lift; charged release flips |
| Weapon | Hammer | 24 | 35 | Timed overhead strike |
| Weapon | Saw arm | 20 | 30 | Sustained contact damage |
| Armor | Light | 10 | 0 | 10% core reduction; 60 integrity per plate |
| Armor | Standard | 18 | 0 | 25% core reduction; 90 integrity per plate |
| Armor | Heavy | 25 | 0 | 40% core reduction; 120 integrity per plate |
| Utility | Recovery assist | 5 | 10 | Recovery activation 1 second instead of 2 |
| Utility | Cooling pack | 6 | 10 | Heat dissipation +25% |
| Utility | Battery pack | 8 | 5 | Battery capacity 125 instead of 100 |

Armor packages consist of front, rear, left, and right plates. Top and underside retain chassis baseline protection of 5%. A destroyed side plate loses its reduction. Package mass is the total for all four plates, not the mass of one plate.

Drive packages expose four visual wheels but use two logical drive pods, each with 100 integrity. One disabled pod reduces drive force to 50% and maximum steering torque to 60%; input assistance compensates persistent drift. Both disabled pods start the immobilization sequence. The primary weapon has 140 integrity. Disabled weapons cannot activate; recovery remains available.

Unused mass is permitted. Final mass influences acceleration, resistance to impulses, and recovery. Top speed is governed by the drive package, not scaled upward for lighter builds. Grip caps drive force so mass is not an unlimited pushing advantage.

### Legal starter builds

| Build | Components | Mass | Power | Intended play |
|---|---|---:|---:|---|
| Striker | Balanced, standard wheels, vertical spinner, standard armor, recovery assist | 103 kg | 75 | Approach, strike, disengage |
| Controller | Wide, traction wheels, lifter/flipper, standard armor, recovery assist | 108 kg | 70 | Lift and set up a teammate |
| Duelist | Compact, agile wheels, hammer, standard armor, cooling pack | 91 kg | 70 | Flank and punish missed attacks |

### Garage experience

Rotate and zoom a lit 3D preview; select sockets; filter compatible parts; compare current and proposed stats; display mass and power budgets continuously. Explain invalid builds with specific errors and disable readying until fixed. A test-drive button opens the practice arena with the unsaved draft. Save at least 12 named loadouts locally. Undo/redo covers the current editing session.

Before a match, the server rebuilds every loadout from allowed part IDs and validates category counts, compatibility, budgets, and content version. Client-provided masses, stats, scene paths, and collision shapes are never accepted.

## 6. Combat model

### Movement and contact

Robots use rigid-body chassis with suspension/contact probes and applied tire forces. Wheels are animated from contact speed rather than simulated as four networked rigid bodies. Target acceleration is 0 to 10 m/s in approximately 2 seconds for the Striker. Steering torque decreases at high forward speed to avoid weightless cornering. Brake force is limited by grip.

Bots can push, climb low wedges, flip, and tumble. Prevent permanent nose-balancing with authored collision shapes and sensible centers of mass. Use convex chassis colliders and simplified wall geometry. Mechanical mechanisms have bounded travel; a spinning visual mesh does not require thousands of collision contacts per second.

### Weapon starting values

| Weapon | Attack | Damage before armor | Timing / tradeoff |
|---|---|---:|---|
| Vertical spinner | Powered contact | Up to 45 per registered impact | 1.5-second spin-up; charge drops 50% on hit; moderate upward impulse |
| Horizontal spinner | Swept side contact | Up to 40 per registered impact | 2-second spin-up; charge drops 60% on hit; high lateral recoil |
| Lifter/flipper | Raise / launch | 8 per launch | 1-second raise; 3-second launch cooldown; low damage, high control |
| Hammer | Committed overhead arc | 38 per strike | 0.35-second windup; 1.4-second recovery; miss leaves exposure |
| Saw arm | Maintained contact | 18 per second | 6 damage every 1/3 second; weak against mobile targets |

Spinners require at least 25% charge to deal weapon damage, then scale linearly to the listed maximum. Each spinner can damage a given target at most once per 0.3 seconds; continuous contact cannot create a damage event every physics frame. Hammer and flipper use one event per target per activation. Saw uses its fixed cadence. Swept hit queries cover fast movement between ticks. Every event has an attack ID and server tick for deduplication.

### Damage routing

1. Resolve the contacted damage zone using the authoritative swept query or body contact.
2. Compute authored raw weapon damage using weapon readiness. A normal chassis ram only damages at closing speed above 4 m/s: `min(12, 2 × (closing_speed − 4))`, with a 0.5-second pair cooldown. Ram damage applies independently to each struck zone; pushing below the threshold does no damage.
3. A side-armor hit removes raw damage from that plate and applies `raw × (1 − reduction)` to core. Use the plate state at the start of the hit; its reduction disappears on subsequent hits after destruction.
4. A direct top/underside hit applies baseline reduction to core. A direct exposed drive/weapon hit applies 75% raw damage to that component and 25% to core, without side-plate reduction.
5. Clamp actual damage to remaining integrity for scoring. Health never becomes negative. A single contact resolves one zone; overlapping colliders cannot multiply a hit.

Contact direction, weapon charge, and armor matter; random critical hits do not exist. Apply capped attack impulses independently of health damage, and account for ordinary collision impulse when tuning them so effects are not accidentally doubled. Cap launch vertical speed at an initial 8 m/s and angular speed at 12 rad/s; adjust only after testing stable recovery and camera behavior.

### Battery and heat

Base battery is 100; base heat range is 0–100. Driving is always available without battery. Battery recharges at 8 units/second after 1 second without weapon activation or recovery. Cooling continues at 12 heat/second when the weapon is inactive. Overheat at 100 disables the primary weapon until heat falls to 50.

| Action | Battery cost | Heat gained |
|---|---:|---:|
| Spinner powered | 10/second | 12/second |
| Lifter holding/raising | 6/second | 4/second |
| Flipper launch | 20 | 18 |
| Hammer strike | 16 | 20 |
| Saw powered | 9/second | 14/second |
| Recovery | 30 | 0 |

An action requiring more battery than available cannot begin. Continuous actions stop at zero. An empty battery does not prevent recharge while flipped. Cooldown, overheat, and insufficient-battery feedback identify the specific reason an action failed.

### Assists and match statistics

Elimination credit goes to the most recent enemy to deal effective damage within 10 seconds; otherwise classify it as uncredited. Other enemies dealing damage in that interval receive assists. Statistics include effective damage, component disables, eliminations, assists, time spent pinning within legal limits, and recovery activations. None overrides the victory rules.

## 7. Arena specification

**Arena 01: The Foundry.** A flat 50 × 50-meter square with continuous 3-meter-high collision walls, chamfered interior corners, neutral industrial flooring, and spectator dressing outside the combat volume. The floor is one uninterrupted driving surface. Painted seams and decals cannot snag wheels.

Use X/Z ground axes; playable boundaries are −25 to +25 meters. Team spawns sit near Z = −19 and Z = +19, facing center. For 5v5 use X = −12, −6, 0, 6, 12. 2v2 uses X = −6 and +6. FFA uses eight evenly spaced points on a 20-meter-radius circle, assigned randomly by the server. Verify every spawn envelope clears walls and every other bot.

No active hazards, pits, or ring-outs in the initial arena. This keeps the baseline focused on bot combat. Floor graphics suggest a central combat area but do not change movement or damage. A future hazard variant must remain a separate ruleset.

Lighting emphasizes silhouettes and weapon contact. Team colors appear as an outline/badge and small paint accents; players retain their chosen paint. Team recognition also uses icons to avoid relying solely on color. FFA displays distinct player markers and names.

The arena must allow a standard bot to traverse the width in roughly 5–7 seconds after acceleration. If repeated evasive play causes timeouts, tune speed, visibility, and match timing before adding arbitrary damage zones.

## 8. Interface, accessibility, and audio

### Required screens

Boot/loading → main menu → garage / play / practice / settings → lobby → arena loading → countdown → combat → round result → match result.

The Play screen exposes quick-play 2v2 and custom lobbies. Custom hosts select mode, region/server where supported, and public/private visibility. Lobby UI shows slots, teams, readiness, connection quality, and build validity. Friendly team assignment and FFA slot changes invalidate readiness. Players can inspect opponents' chassis and primary weapon before lock, but cannot change loadout once the match starts.

The combat HUD contains core integrity, component diagram, battery, heat, weapon charge/cooldown, team survivors, round score, timer, and a chassis-facing compass marker. A prominent countdown identifies immobilization. Pings expire after 4 seconds and are limited to one per second. Menus expose network status and reconnect progress without covering essential elimination feedback.

Support scalable UI at 1280 × 720 through 4K, text scaling to 150%, color-vision presets, high-contrast markers, subtitles for announcements, independent audio buses, reduced flashing, and complete shake disable. Essential events use visual and audio cues. No information depends only on stereo position.

Audio layers include drive load, wheel skid, weapon spin-up, weapon-ready cues, impact materials, armor breaks, core warning, recovery, crowd response, and round announcements. The pitch of a spinner communicates readiness. Duck ambience during major warnings. Cap concurrent impact voices in 5v5. Captions identify gameplay-relevant announcements.

## 9. Art and content production

Use grounded stylized industrial art: believable metal construction with simplified surfaces and strong color blocks. Bots need distinct front/rear silhouettes, visible weapon states, and readable damage at normal follow distance. Avoid relying on tiny scratches for critical component status.

Damage uses staged meshes/materials, sparks, smoke, and limited detached fragments. Intact, damaged, and disabled states must be recognizable for drive pods and weapons. There is no gameplay mesh fracturing. Cosmetic fragments have short lifetimes, no damage, and no collision with bots.

Initial content inventory: one arena and lighting setup; three chassis; three drive packages; five weapon families; three armor sets fitted to each chassis; three utility visuals; three starter presets; approximately 12 paint colors and six decal shapes; complete HUD/menu icon set; effects and audio for each weapon and damage state.

Art targets: approximately 20k–40k triangles per assembled bot at highest detail, two lower LODs, shared materials and texture atlases where practical, and no more than 20 cosmetic debris pieces alive per client. These are provisional budgets, validated with ten bots in view. Mounts, forward axes, collision envelopes, and animation limits must be documented alongside each asset.

## 10. Godot 4.7.2 implementation architecture

### Engine and project baseline

Pin editor, export templates, server, and client builds to Godot **4.7.2 stable**. The current repository has a starter project in `battlebots/` using the 4.7 feature tag, Forward+, Jolt Physics, and D3D12 on Windows; no gameplay implementation is present at specification time. The requested stable release is listed in the [official Godot archive](https://godotengine.org/download/archive/4.7.2-stable/).

Use typed GDScript for gameplay and Godot Resources for authored data. Keep Jolt as the 3D backend and test its supported behavior before introducing joints; see [Godot's Jolt documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html). Retain Forward+ as the default desktop renderer. A lower graphics preset reduces shadows, particles, and reflections without changing simulation.

The server simulates chassis with `RigidBody3D`; forces and controlled physics-state work belong in physics callbacks and `_integrate_forces`, rather than assigning visual transforms every render frame. See the [RigidBody3D reference](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html). Clients maintain separate visual smoothing and prediction representations.

### Proposed repository structure

```text
battlebots/
  project.godot
  scenes/
    app/           # Bootstrap, frontend, session root
    arenas/        # Foundry, spawn markers, environment
    bots/          # Bot root, chassis, weapon scenes
    ui/            # Garage, lobby, HUD, results, settings
    practice/      # Tutorial and target fixtures
  scripts/
    core/          # IDs, signals, state machine, content registry
    simulation/    # Drive, damage, battery, heat, round rules
    weapons/       # Weapon states and swept hit queries
    networking/    # Input transport, snapshots, reconciliation
    services/      # Lobby, allocation, profile adapters
    presentation/  # Camera, audio, VFX, animation
    ui/
  data/
    chassis/ drives/ weapons/ armor/ utilities/ modes/
  assets/
    models/ materials/ textures/ audio/ effects/
  tests/
    unit/ integration/ network/ fixtures/
docs/
  GAME_SPEC.md
```

### Scene ownership

```text
SessionRoot
├── MatchController
├── NetworkSession
├── Arena
│   ├── StaticCollision
│   ├── SpawnPoints
│   └── EnvironmentVisuals
├── Bots
│   └── BotRoot (stable network entity ID)
│       ├── SimulationBody (RigidBody3D; authoritative server)
│       │   ├── ChassisCollision
│       │   └── GroundProbes
│       ├── DriveController
│       ├── WeaponController
│       ├── DamageModel
│       ├── ResourceController
│       └── VisualRoot (interpolated client presentation)
└── LocalPresentation
    ├── CameraRig
    ├── HUD
    └── Audio/VFX
```

`BotRoot` identifies ownership, while the server retains gameplay authority. Presentation is optional so the same session can run headlessly. Keep persistent services to a small set: settings, local profile, content registry, and session coordinator. Match state belongs to the session, not permanent global singletons.

### Data contracts

| Record | Required fields |
|---|---|
| PartDefinition | Stable ID, revision, category, mass, installed power, compatible socket IDs, presentation resource, stat values |
| BotLoadout | Schema version, name, one part ID per slot, cosmetic IDs, content hash |
| BotRuntimeState | Entity ID, owner ID, server tick, transform, linear/angular velocity, core/zone integrity, resource values, weapon state, recovery state, elimination state |
| InputCommand | Sequence, estimated server tick, throttle, steering, brake, action flags; no client damage/position values |
| MatchRules | Mode ID, capacity, timer, round target, spawn configuration, judging policy |
| MatchResult | Match ID, participants, round results, placements, effective damage and component events, content/build version |

Validate ranges and required fields at every external boundary. Save local loadouts/settings as versioned JSON in `user://`, using write-to-temp and atomic replacement with backup. Unknown parts produce a clear repair prompt and prevent matchmaking; do not silently substitute a competitive build. Ship migration functions with schema changes.

## 11. Multiplayer and online services

### Authority and transport

Use server-authoritative simulation with `ENetMultiplayerPeer` and Godot's high-level RPC layer. Godot provides transport and RPC facilities; matchmaking, allocation, authentication, and rigid-body reconciliation remain project work. See [high-level multiplayer documentation](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html).

For the prototype, support LAN and direct-IP connections to a listen server. Remote listen-server access needs reachable UDP routing. For public release, use dedicated headless Linux servers with the same simulation code. Run one match per process initially. No peer authority transfer or host migration is required; a lost listen host ends its session with an explicit message.

| Stream | Initial frequency | Delivery |
|---|---:|---|
| Server physics | 60 Hz | Local fixed timestep |
| Client input | 30 packets/sec, up to two new 60 Hz commands plus recent redundancy | Unreliable ordered, dedicated input channel |
| Server snapshots | 20 Hz | Unreliable ordered, dedicated snapshot channel |
| Spawn, loadout lock, round transitions, results | Event-driven | Reliable control channel |
| Cosmetic events | Event-driven | Unreliable; disposable |

Snapshots carry authoritative health and weapon state as well as motion, so missing an effect event cannot lose a gameplay change. Reliable events use IDs and round numbers and are idempotent. Initial join/reconnect receives a complete baseline before deltas. Keep packets within a measured safe datagram budget; split entities across independently decodable packets when necessary.

### Prediction and smoothing

- Render remote bots approximately 100 ms behind the latest estimated server time, interpolating timestamped snapshots. Adapt within a bounded 75–150 ms buffer for jitter.
- Predict local drive response immediately with the same input-to-force model. Reconcile position, velocity, and orientation to server snapshots and acknowledged input sequence.
- Local weapon anticipation may animate immediately, but only server events confirm hits, damage, flips, and eliminations.
- Jolt simulation is not assumed to be bit-identical across peers. Replaying local inputs cannot reproduce every multi-body collision. Use server contact outcomes, bounded correction, and blending of small visual errors; snap large or invalid divergences.
- Cap extrapolation at 100 ms, then freeze the remote visual and show degraded connection state. Never extrapolate damage or elimination.
- Do not rewind the entire physics world for melee hits. Server-time overlap/sweep decisions are authoritative. This avoids granting late attacks against positions already left by an opponent.
- Physics interpolation for a locally simulated body is separate from snapshot interpolation. Avoid applying both smoothers to the same visual transform. See [Godot's interpolation guidance](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html).

Prototype network feel before expanding the part catalogue. Acceptance under 80 ms RTT must include collisions, pins, flips, and recovery, not just unobstructed driving. If collision correction remains distracting, simplify mechanisms or revise prediction before content production proceeds.

### Session lifecycle and failure behavior

State machine: `Lobby → Loading → Countdown → Active → Overtime/Resolve → Intermission → Countdown` or `Results → Lobby/Exit`. Transitions carry a match ID, round index, and server tick. Clients cannot advance the round independently.

All clients must acknowledge scene/content readiness within 30 seconds. Failure returns the session to lobby before play begins. Late arrivals cannot occupy a live match slot; they may wait in the lobby. Reconnect is reserved for the original participant using a server-issued session token.

After 250 ms without valid input, set throttle to zero, brake, and stop weapon activation. On disconnect, retain the bot as a vulnerable stationary participant for 20 seconds. Rejoining restores control of that bot, preserving damage. After timeout, eliminate it. A connected team may unanimously forfeit through the menu. If the dedicated server fails, mark the match incomplete and do not award a competitive result.

### Public-service requirements

Release needs a small HTTPS control service for guest/account identity, region selection, lobby listing, queue tickets, server allocation, and result receipts. Use short-lived join tokens binding player, match, slot, expiry, and build version. Hosting provider and account platform are implementation selections, not assumed engine features.

Start public quick play with one 2v2 queue to avoid splitting a small population. Match parties of up to two, prefer nearby regions and comparable recent performance, and broaden skill range before accepting higher latency. Target under 120 ms RTT; show region and ping before joining a distant server. Custom 5v5 and FFA remain available without separate public queues.

Validate sender-to-bot ownership, command sequence/rate, action eligibility, and loadout IDs. Bound packet sizes, reject malformed values and non-finite vectors, and rate-limit lobby operations. Accept no remote script/resource paths or arbitrary object deserialization. Servers issue final results; clients cannot submit progression awards. Use sanitized names, mute/report controls for names and ping abuse, and no text chat in the first release.

## 12. Progression and persistence

All functional parts are available immediately. Progression awards cosmetic paints, badges, and profile frames through participation and milestone completion. Launch includes no paid gameplay advantages, loot boxes, crafting grind, durability costs, or consumable repairs. Monetization is outside this specification.

Local profile stores settings, tutorial progress, loadouts, and cosmetic preferences. Public-release backend stores identity and verified cosmetic unlocks. Practice and private matches do not grant competitive rating. An interrupted match cannot award duplicate rewards: result processing is keyed by match ID and player ID. Ranked rating is deferred.

## 13. Performance, reliability, and delivery

### Initial engineering budgets

- Client target: 1080p at 60 FPS on a provisional Ryzen 5 3600 / GTX 1660-class PC with 16 GB RAM; confirm supported renderer/driver combinations on hardware before advertising minimum requirements.
- Client frame budget: 16.7 ms; 95th-percentile frame time under 20 ms in a ten-bot stress match, excluding explicit loading.
- Server target: 60 Hz with 95th-percentile simulation time below 12 ms per tick on the chosen deployment hardware; report actual CPU model in benchmarks.
- Network target: below 100 KB/s downstream and 30 KB/s upstream per player at ten bots, including protocol overhead; measure rather than assume.
- Arena load target: under 10 seconds from local SSD after first import/export preparation.
- No sustained memory growth above 5% after warm-up during a 60-minute repeated-match soak.

Use spatially simple hit queries, pooled effects, per-frame particle budgets, cached part definitions, and network IDs rather than repeated strings. Prefer profiling to speculative native extensions. Include build ID, mode, latency, correction metrics, and physics timing in development diagnostics. Logs exclude authentication secrets.

### Build and deployment

Maintain separate Windows client and headless Linux server export presets. CI validates data, runs headless tests, imports resources, and builds both artifacts using pinned templates. Client/server handshake rejects mismatched protocol or content hashes with a useful message. Version each balance update with the content manifest.

Dedicated servers advertise ready/active/draining status; draining prevents new allocation and lets current matches finish. Keep the previous build available for rollback. Store lightweight authoritative event logs for debugging; do not promise deterministic replay or ship a replay viewer in the first release.

## 14. Verification and acceptance criteria

| Area | Required verification |
|---|---|
| Construction | Every starter build is valid; overweight, excess-power, missing, duplicate, unknown, and incompatible parts are rejected on client and server |
| Driving | Acceleration/brake targets are measurable; wall contacts do not tunnel; bots recover from representative flips without explosive impulses |
| Damage | One contact cannot hit multiple zones; attack cadence, armor break, component disable, overkill clamp, and ally immunity match the rules |
| Resources | Battery exhaustion, heat lockout, cooldowns, and recovery are identical on all observers |
| Match logic | All three modes handle timer expiry, same-tick wipes, draws, forfeits, and disconnects; five-round cap terminates tied team matches |
| Camera | Walls, corners, flips, wheel loss, and first-person toggle cannot place the view outside the arena or leave it permanently clipped |
| Network | Four- and ten-client sessions complete with 0/80/150 ms RTT, 0/20/40 ms jitter, and 0/1/3% loss; include reordered/duplicated inputs and reconnects |
| Authority | Forged movement, damage, part stats, duplicate commands, and unauthorized bot commands cannot alter authoritative state |
| Performance | Ten bots with simultaneous weapon effects meet the measured budgets on recorded hardware |
| Persistence | Interrupted save retains backup; migrations preserve valid builds; unknown content yields a recoverable error |
| Accessibility | 150% text scaling, remapping, color-independent team recognition, reduced motion, and mute settings work throughout the match flow |

Unit tests cover pure build validation, damage routing, resource rules, and scoring. Headless integration tests cover round state transitions and multiple peers. Manual playtests cover control feel, visual clarity, tactics, and camera comfort. Automated checks cannot substitute for real remote-machine collision testing.

**MVP acceptance:** four remote players can create/select legal builds, join a lobby, complete a first-to-two 2v2 match on the Foundry, observe consistent damage and winners, save builds, and rematch without restarting. At 80 ms RTT, non-contact driving prediction error should be under 0.25 meters at the 95th percentile; contact correction must settle within 250 ms after the last collision impulse. These are go/no-go targets to measure during the network prototype.

**Release acceptance:** MVP criteria plus complete 5v5 and 4–8-player FFA, five weapon families, accessibility settings, tutorial, first-person option, public-service deployment, result persistence, and no unresolved defects that lose matches, corrupt saves, crash common match flows, or permit client-authoritative damage.

## 15. Delivery plan

Development is shared by two people on separate office computers, each using ChatGPT against the same Git repository. Each computer must use its own local clone. The ownership split and integration workflow in [TEAM_WORKFLOW.md](TEAM_WORKFLOW.md) are part of this specification. Phases are ordered by risk and exit criteria, not promised dates. Estimate calendar duration after the first network milestone.

| Phase | Deliverable | Exit criterion |
|---|---|---|
| 0 — Foundation | Pinned engine, client/server launch, graybox arena, input and stabilized follow camera | One bot drives and collides reliably across the arena |
| 1 — Network physics spike | Two remote bots, authoritative drive, snapshots, prediction, one spinner, flips | Collision/recovery feel passes 80 ms RTT target; measured ten-body server budget |
| 2 — 2v2 vertical slice | Four players, two weapons (spinner and lifter), health, recovery, round rules, results | A complete remote 2v2 match and rematch with disconnect handling |
| 3 — MVP builder | Three chassis/drives/armor packages, three utilities, starter builds, save/load, lobby validation | MVP acceptance suite passes with the two available weapons |
| 4 — Full modes/content | 5v5, FFA, remaining three weapons, final Foundry art/audio, first-person camera, controller input | Ten-player performance and mode-specific rules pass |
| 5 — Release services and polish | Quick play, allocation, identities, cosmetics, tutorial, accessibility, telemetry | Release criteria pass in an external multiplayer playtest and soak |

If schedule pressure appears, defer cosmetic quantity, elaborate crowd animation, and additional audio variations. Preserve the core 2v2 feel and authoritative simulation. 5v5, FFA, and customization remain required for the requested full release even though they arrive after the first playable slice.

## 16. Balance method and unresolved production choices

Track weapon pick rate, win rate by matchup, effective damage, flip success, recovery frequency, timeout frequency, immobilization causes, and team composition. Separate experienced players from first-time players and identify small sample sizes. Review match footage alongside statistics; a 50% win rate can still hide frustrating interactions.

Starting goals: most 2v2 rounds finish in 90–180 seconds; at least two distinct team compositions remain viable; no weapon combines best damage, best control, and easiest use; failed attacks create recognizable punish windows. Tune damage/charge/cooldowns first, then budgets and module integrity, and only then global physics. Publish rule changes with the content version.

| Production choice | Working assumption | Decision point |
|---|---|---|
| Public hosting/account provider | Provider-neutral HTTPS service and dedicated Linux processes | Select after network prototype, before public-service work |
| Final hardware minimum | Provisional baseline in section 13 | Set after ten-bot art stress test |
| Ranked play | Deferred; unranked 2v2 quick play at launch | Revisit when population and exploit resistance justify it |
| Commercial name and visual identity | Project Battlebots is a working title; create original bot identities and branding | Set before public marketing/assets are finalized |
| First-person comfort | Supported optional mode, stabilized horizon | Validate after third-person vertical slice |
| Schedule/team capacity | Two developers, each assisted by ChatGPT; available hours unspecified | Estimate from phases 0–1 measurements |

The immediate implementation milestone is a graybox 50 × 50 arena with two remotely controlled rigid-body bots, a stable third-person camera, and one authoritative weapon. It must establish that contact feels good online before the project commits to its complete content catalogue.
