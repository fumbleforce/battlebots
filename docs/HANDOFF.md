# Current A/B handoff

## Shared integration baseline

Per the user's instruction, completed task branches merge locally into main
after validation and main is pushed directly. No PRs. Main is the shared latest
combined game; future tasks begin from
updated origin/main. Historical feature-branch names below identify provenance,
not separate places the other developer must collect to obtain finished work.
Any genuinely unfinished remote branch is called out rather than merged blindly.

## Current ownership — user revision

- **A:** menus, networking, game rules, game world and audio.
- **B:** combat, bot assets (models and weapons), bot-customisation menus and
  player controls.

General menu/session/results integration, arena/world and audio move to A.
Combat/weapon mechanics, bot assembly/catalogue and driving move to B. Garage
and bot customisation stay with B. Historical author/owner labels below describe
past work only. AGENTS.md and TEAM_WORKFLOW.md contain the current boundaries.
The natural-duel fixture remains A integration of network and match rules;
demonstrated combat/control defects are handed to B rather than changed by A.

## Current user priority

Updated by the user on 2026-09-20: finish a fully working 1v1 game first. External
matchmaker/dedicated-server deployment remains outstanding and HUD work is raised
in priority. Deliver the full hosted duel loop through combat, rounds, results
and rematch. Defer 2v2, FFA and all other multiplayer modes until the 1v1 game is
fully working. The tutorial is also deferred until then, with B retaining control
exercise ownership and A retaining menu integration.

Further user feedback (2026-09-20): menus still need refinement, particularly
the multiplayer/networking screens that fit poorly into the original menu
system. A owns this high-priority 1v1 work alongside hosting and HUD: consistent
visual design, layout and navigation across online entry, host/join, connection
progress, errors/retry/cancel and lobby transitions. Validate the complete
rendered player flow; this board entry does not claim the menus are fixed.

The user also requests win and score screens and an in-game menu page consistent
with the other panels (2026-09-20). These are high-priority A-owned 1v1 delivery
tasks. Existing results/rematch implementation is a foundation; its historical
completion does not close these requested presentation tasks. Use authoritative
outcomes/scores and review navigation through game menu, win, score and rematch.

The user reports human multiplayer was conducted successfully through a tunnel.
Record that gate as completed human-play evidence; do not keep describing human
multiplayer as untested. No specific measurements were supplied, and this does
not establish external-hosting reachability or release acceptance. Older human
LAN/playtest and 1v1/2v2 priority statements below are historical and superseded.
Existing modes/tests remain; larger-mode expansion, optimization and soak work
do not block the active 1v1 scope.

## Current Developer A increment

`codex/a-hud-accessibility` follows `bd1dd3f`. General Settings now offers HUD
text at 100/125/150%, four color palettes and opaque high-contrast panels with a
visible sample, save and cancel. Combat/round HUD fonts enlarge independently
from viewport scaling; larger panels reflow. Practice readout and announcement
captions follow the selected size. B implementation and wire format are unchanged.
See [accessibility evidence](coordination/A_HUD_ACCESSIBILITY.md). Whole-menu text
scaling, world/team markers, pings and human accessibility acceptance remain open.
Hosting remains unprovisioned pending the recurring-cost decision.

### Preceding reconnect increment

`codex/a-reconnect-flow` follows `50f3a63`. The general game now offers manual
same-session recovery after unexpected transport loss, with bounded status,
retry/leave and original-menu styling. It retains hosted membership, restores
the damaged bot or result screen from the authoritative baseline, and clears
private credentials on leave/rejection/expiry. A local session API addition is
documented in CONTRACTS.md; no B implementation or wire schema changes.
Independent network, composed-game, rendered panel and existing regressions pass;
see [reconnect evidence](coordination/A_RECONNECT_FLOW.md). Rebuild deployment
artifacts from updated main before external provisioning. Billable hosting still
awaits confirmation and no external reachability is claimed.

### Preceding hosted acceptance increment

`codex/a-hosted-duel-deployment` prepares external 1v1 acceptance after `bca152c`.
The hosted harness can target an HTTPS allocator without starting a local server,
and verifies assigned ENet play through two forfeit-driven rounds, agreed scores,
results and an active rematch. Fresh Linux and Windows exports, service checks
and Fly configuration validation pass. External hosting remains unprovisioned;
the existing pending confirmation concerns the recurring one-Machine/dedicated-IP
cost. See [deployment acceptance](coordination/A_HOSTED_DUEL_DEPLOYMENT.md).
Do not treat a local test or a Linux export as proof of external reachability.

### Preceding HUD increment

`codex/a-duel-hud` follows menu panels `1a5d38a`. The default game now has a
read-only combat HUD for resources, raw component integrity/breaches/disables,
weapon state/charge/cooldown, recovery availability/cooldown, prominent
immobilization/elimination/core/heat warnings, chassis heading and duel bot status.
Round countdown/time/score/outcome use the original menu theme and scale through
4K. Combat, practice, diagnostics and captions share the HUD layout; menus and
settings suppress it. The preview's old resource/hint overlays remain for its
standalone fixtures, while the default game uses the composed HUD.

`MvpSession.bot_views()` is a local read-only API with fresh detached records;
clients omit bots without an accepted snapshot. It prevents missing baselines
from masquerading as healthy bots. No B combat/control/bot implementation or
wire/schema changed. See [HUD evidence](coordination/A_DUEL_HUD.md) for validation
and limitations. External hosting remains outstanding. Text-scale/color-vision
presets and coordinated ping presentation are still open, not part of this core
HUD delivery. The known intermittent engine shutdown issue also remains open.

### Preceding menu-panel increment

`codex/a-duel-menu-panels` implements the requested general menu refinement from
`1a56c38`. Online entry now focuses on private 1v1 create/join with original menu
art/theme, service status and cancellation. Direct host/join uses labelled,
centered connection panels and the connected lobby retains the roster/build flow.
Win overview and score-detail tabs read authoritative records; local BotView team
determines victory/defeat. The in-game menu shares the original panel styling,
preserves resume/settings/restart/leave actions and prevents HUD overlap.

Baseline and all four new independent panel checks pass, with rendered 720p and
1080p review. Real HTTP/ENet private-duel cancellation/join/leave and two-peer
round/results/rematch pass; the latter asserts local defeat and score navigation.
Practice, audio, menu flow/music and existing results checks also pass. Review
caught and fixed a diagnostics button-down visibility regression, now tested.
Some checks still report the known two-object shutdown warning; no native crash
occurred in these runs and the historical intermittent engine issue stays open.
See [full evidence](coordination/A_DUEL_MENU_PANELS.md). External deployment and
HUD expansion remain outstanding; this increment does not provision hosting.

### Preceding Foundry increment

`codex/a-foundry-arena` follows practice `c83d266` with the user-requested regular
octagonal Foundry (50 m across faces), eight cage/gallery bays, radial trusses,
worn steel materials and an octagonal lighting crown with warm/cool spots and
volumetric haze. Spawn transforms are unchanged. The existing camera scene gets
the matching corner boundary setting; no camera/input algorithm changes.
Build `mvp-ab-11` prevents older square-arena peers from joining. Protocol and
catalogue stay at 4. See [arena evidence](coordination/A_FOUNDRY_ARENA.md).

Baseline, headless arena/spawn-clearance, camera containment, rendered review,
80 ms actual-ENet straight/diagonal wall contacts, and the integrated practice
reset check pass. Rendered screenshots are in the arena worktree's ignored
`battlebots/exports/arena-review/`. These use primitive runtime bots; bot art
remains B-owned. Human review and lower-end graphics performance remain open.
Audio/practice are retained. Completed ownership clarification `86abe77` is also
integrated; the other A session removed its unfinished tutorial rather than
publishing control-training work.

### Preceding practice increment

`codex/a-practice-loop` adds practice-only Restart, a read-only target damage and
knockout panel, and automatic pause/focus on player knockout. Both bots are
repaired/repositioned in the same world with their loadouts retained; queued
actions are cleared. Network sessions reject the reset API unchanged. Baseline,
independent HUD/session/menu tests and real two-peer round/results/rematch passed.
A real post-reset hammer hit confirms the repaired target remains playable.
The network test reported four ObjectDB instances at shutdown; the known cleanup
issue remains open. See [practice evidence](coordination/A_PRACTICE_LOOP.md).
The following arena increment now includes this completed practice work.

`codex/a-gameplay-audio` adds A-owned first-pass impact, round, warning and recovery
cues with captions, plus saved volume/mute settings. The menu composes Audio
alongside existing control settings and routes the supplied melody through its
own music bus. B combat, controls, assets and customisation remain unchanged.
Focused audio/controller/settings/menu checks, the baseline and the real-time
two-peer results/rematch check with cue assertions passed; see
[audio evidence and limitations](coordination/A_GAMEPLAY_AUDIO.md). This is
procedural first-pass sound, with spatial mixing and listening polish still open.
The existing playtest ZIP below predates this increment.

`codex/a-duel-combat-loop` adds an independent two-player natural-combat check
and applies the user's revised ownership throughout the active docs. The final
check passed at 93.5 seconds: sixteen real hammer hits, two core-destruction
round wins, synchronized results and a fully repaired active rematch. Canonical
commands/physics/rules remain unchanged; no forfeit or injected health/charge.
No ten-player work is included. See [duel evidence](coordination/A_DUEL_COMBAT_LOOP.md).

CI 35470427285 reproduced native exit 0xC0000005 after DRIVE PASS. This extends
the known shutdown evidence below; it is not a passing drive validation run.
No retries or relaxed failure detection are used to declare that issue fixed.
Hosted CI 35470075437 subsequently passed its complete suite/export checks;
that successful run does not resolve the intermittent native shutdown failure.

Fresh Windows gameplay package from source `8433dc0`:
`battlebots/exports/playtest/battlebots-gameplay-8433dc0.zip` (129,573,157 bytes),
SHA256 `CECFF8AAD19C33D5BFAAE9330434943A18408E1598F8D82B5EA7214820F9865C`.
Contains executable, matching PCK and short Practice/LAN/control instructions.
Includes B results/rematch and the supplied menu melody. The old menu/music ZIP
is preserved. Exported menu startup/exit and dedicated server plus two independent
clients reaching active passed. Menu shutdown reported the known two-object
warning; no native crash occurred in that run. Human combat feel and internet
play are not certified. The endpoint remains empty pending deployment, so this
package offers Practice and LAN, not a working public service.

`codex/a-results-integration` combines hosted `2eefc31` with B results `cc49a15`.
The shared menu retains online cancellation/error routing and now presents B's
authoritative final/per-round results, FFA placements and rematch controls.
Baseline, detached results, actual online lobby and full two-peer match/rematch
checks passed. The results fixture is registered in the presentation runner.
See [integration evidence](coordination/A_RESULTS_INTEGRATION.md). B's existing
two-object test shutdown warning did not reproduce in one verbose diagnostic
run and remains unresolved; the native engine
shutdown limitation below remains open. Fly deployment is awaiting the user's
confirmation of the concrete billable resources, not a technical deployment claim.

### Preceding hosted increment

`codex/a-hosted-matchmaking` follows performance `3f0e80f`. The user's new priority
is externally hosted matchmaking/gameplay without tunnelling, using Fly.io or
Cloudflare. Fly.io supports the existing native Godot/UDP server; the chosen
first deployment combines HTTPS guest/room/queue service and a bounded dedicated
server pool on one Stockholm Machine. Build `mvp-ab-10`, protocol 4, catalogue four.
See [hosted coordination](coordination/A_HOSTED_MATCHMAKING.md) and
[deployment](../services/matchmaking/DEPLOYMENT.md).

Implemented flow: Play Online → Quick Play (2v2), Create private game, or Join by
code → assigned ENet server → existing lobby/Ready. Only actual server welcome
advances the menu. Guest credentials stay in memory; expiry, cancellation and
server errors are explicit. Admission binds build, identity, slot and reservation
generation; reconnect retains damage while revoked reservations lose access.
LAN and practice remain available. Source-level HTTP plus independent Godot
processes passed both private two-player and queued four-player active gameplay.
Nineteen Node checks, pure/real-ENet admission, service-client cancellation/errors,
online menu-to-ENet lobby, existing LAN duel/rematch and snapshot recovery passed.
The same private/queue check passed with a released Windows server executable;
Linux server artifacts and Fly configuration are prepared. Exported workers use
normal application startup because templates ignore the editor's script override.
No public app/IP/Machine has been provisioned. Linux runtime and real external
UDP reachability still require deployment; the default service URL remains empty.

Performance CI 35468529835 passed all A checks and the repaired catalogue check.
It failed after CAMERA CONTACT PASS with native exit code 0xC0000005. Local
baseline validation also intermittently crashes after BASELINE PASS, despite an
earlier successful run. Diagnostics map the native fault to GDScript language
shutdown; scene nodes were already freed and extra teardown frames did not fix
it. Some crashes print a native backtrace but return zero, so test gates now reject
native crash signatures as well as script errors and nonzero exits. This remains
an unresolved engine shutdown limitation, not a passing baseline or a proven
gameplay fault. No speculative production workaround or gate relaxation was made.

The full public-release service scope remains open: durable accounts/results,
parties, region/skill matching, multi-Machine allocation and release acceptance.
The earlier performance increment's 300-second run reached 59.996 Hz, all five
weapons, one completed match and rematch. Its average downstream was under budget,
but ten-second peaks reached about 114 KB/s. Those ten-player optimization and
soak targets are now outside active scope per the user's priority correction.

### Preceding performance and weapons increment

`codex/a-performance` follows saw `5d3fd30`, hammer `9610946`, horizontal spinner `b46084e` and menu/music
export `db87257`. All five weapon families now have authoritative mechanics and
primitive visuals. The saw cuts for 6 raw per third-second of maintained contact;
breaking contact or power clears the partial interval. See
[saw coordination](coordination/A_SAW.md), [hammer](coordination/A_HAMMER.md) and
[horizontal spinner](coordination/A_HORIZONTAL_SPINNER.md) for independent evidence.
This branch uses build `mvp-ab-9`/protocol 4 with catalogue revision four; both peers
must update together. Known revision-one/two/three saves migrate without changing
parts. The `db87257` playtest ZIP is preserved separately.

Menu/music CI 35465682771 passed. Horizontal CI 35466215676 failed an FFA exact-health
observer check; hammer CI 35466883297 failed two observer spawn comparisons after
a ten-player rematch. Both bounded local reproductions passed. Failure-only
diagnostics were added without weakening either gate; the causes remain unproven.
Neither run is described as full acceptance. Performance/soak, public services
and manual LAN/internet/contact-feel remain open A work.

Saw CI 35467391486 subsequently passed every A MVP check, including FFA and 5v5
profiles. It stopped in B's catalogue fixture, which still expected fourteen
parts after the catalogue grew to seventeen. This increment updates only that
assertion to verify the registry and each part, including all five weapons;
the targeted presentation test passes. Production B UI and assets are untouched.

The current increment adds reliable bot-state checkpoints on match transitions
and during the existing one-second active/countdown heartbeat. A new actual-ENet
regression reproduces and repairs stale health/epoch after a round reset when
unreliable snapshots are entirely lost. Delayed checkpoints cannot rewind newer
snapshots. This is a proven defect, not a confirmed cause of the earlier CI
failures. Baseline, combat physics, detailed-results bounds, profile-zero 5v5 and
the recovery scene pass. Contact regressions at 80/150 ms both pass with worst
settling 183.3 ms against the unchanged 250 ms gate.

The eleven-process performance harness uses normal five-weapon 5v5 matches,
measures UDP bytes with overhead and OS process memory, and distinguishes smoke
evidence from the required sixty-minute soak. Combat events now expose canonical
weapon IDs or `ram` in `kind`. See [performance coordination](coordination/A_PERFORMANCE.md)
for measurements and limits: callback timing excludes the engine's Jolt step,
and headless runs cannot certify rendered frame-time budgets.

## Current playtest checkpoint

`codex/a-menu-flow` follows `d417d7e` with the user-requested menu-flow correction.
Main has Host Game, Join Game, Practice and Garage. Joining goes directly to an
endpoint and accepts the host's mode; hosting chooses mode then lobby. Mandatory
garage/map steps are removed; all four modes share the polished lobby with an
optional saved-build selector. FFA uses individual HUD outcomes and all large-mode
players appear in loading/roster views. See [menu correction](coordination/A_MENU_FLOW.md).
The user requested an updated export, then resumption of A's remaining spec work.

### Earlier combined checkpoint

`codex/a-b-playtest` combines A FFA `b71cb9b`, B menu kit `595c8f9` (including
controls, diagnostics, lobby and match HUD), results intent `0f343f7`, Flamebot
`909b666` and sawblade source `5e163af`. Build is `mvp-ab-5`, protocol 4.
F5 opens the supplied menus; advanced modes use the explicit 5v5/FFA setup route.
See [integration record](coordination/A_PLAYTEST_INTEGRATION.md) for validation.
This was the wind-down checkpoint; remaining game scope stays open. It does not
claim release acceptance. Current menu navigation is described above.
Local Windows and Linux exports are under `battlebots/exports/playtest/` (ignored
build output). The Windows ZIP contains the executable, its required adjacent
PCK and build/testing notes. The separate modelling checkout remains untouched.

## Integration checkpoint

`codex/a-b-integration` at `bdb42ef` is the playable combined checkpoint. Its CI
passed: full MVP checks, Windows/Linux exports, and independent process startup.
It includes B's published arena/camera/HUD/settings at `40aa6b1`, A's simulation,
networking, simple app menus and primitive weapon placeholders. Main has not been
updated. That checkpoint uses `mvp-ab-2`/protocol 3. The A follow-up described below
uses `mvp-ab-5`/protocol 4; both PCs must use the same branch/build. The preceding
transport branch remains `mvp-ab-3`/protocol 4 and has passed CI.

Host chooses 2 players (1v1, app default), 4 players (2v2), or 10 players (5v5
on the current branch), or FFA with a 4–8-player maximum. FFA needs at least four
connected/ready players; team modes need the full count. One window per person;
all players must Ready. Session actions are conditional on connection/match phase.
Escape toggles the app menu; explicit Main menu safely leaves. Independent tests
cover round-end Escape, full matches/rematches, reconnect and malformed input.

## Active A work

A's FFA implementation is on `codex/a-ffa`, based on tested 5v5 `e118f91` and transport fix `df509a0`
(which builds on contact `7235e50` and integration `bdb42ef`). Reserved paths:
`scripts/networking/`, relevant `scripts/simulation/` prediction code,
`tests/network/`, A check scripts, and these shared coordination docs.
Current FFA work includes match rules, spawn selection, independent simulation
tests and A's app host selector. See [FFA coordination](coordination/A_FFA.md).

Independent network scenes now measure a launch/flip, actual lifter and spinner
hits, head-on ramming, recovery and round resets at 0/80/150 ms. At 80 ms, these
scripted cases settle within 250 ms. Settled means the
local presentation remains within 0.25 m and 10 degrees of the simultaneous
server pose for the rest of the observation window (at least 500 ms after each
weapon/ram hit). These are repeatable headless cases, not proof of all contact
conditions. Human camera/contact feel and two-computer LAN remain unverified.

First measured fix: airborne command replay now integrates gravity and full
roll/pitch/yaw, using the body's angular damping and the same velocity caps.
`tests/network/airborne_replay.tscn` compares 250 ms of replay with a real Jolt
body after a launch/spin. Before the fix, maximum errors were 0.327 m, 2.45 m/s
and 75.99 degrees; after, below 0.001 m, 0.001 m/s and 0.04 degrees. This isolated
free-flight check is part of `tools/check-mvp.ps1`.

The delayed-network test then exposed over-replay of authoritative impulses and
a visual offset applied before its physical correction. Replay now uses an
estimated server clock, separately from the pending input backlog; offsets apply
when Jolt consumes the correction. Visual offsets above 0.25 m decay faster than
small driving corrections: a 150 ms lifter trace had already converged physically
but missed the visual settling target at 283 ms with the old blend rate.
Active reconnect baselines restore velocity
and angular velocity too. Snapshot epochs include round number, old-round packets
are rejected, and reset interpolation history is cleared. Baselines produced
before Jolt applies a pending reset encode the spawn with zero prior-round motion.
No B-facing API changed;
private messages require the new build/protocol. See [contracts](CONTRACTS.md).

Regression scenes: `tests/network/contact_reconciliation.tscn` and
`tests/network/clock_sync.tscn`. The clock scene checks real staggered join/reconnect
origins, synthetic symmetric RTT samples, bounded replay and airborne baselines.
Synthetic RTT samples do not emulate the reliable control transport. The existing
profiles impair unreliable input/snapshot traffic only. Full MVP suite also covers
round navigation/rematch and four-client sessions; non-contact correction p95 at
80 ms was 0.125 m in the final real-time run. Whole-control-transport and wall
coverage are added by the current follow-up below; manual LAN and a broader
collision matrix remain acceptance work.

Validation: final `tools/check-mvp.ps1` passed with Godot 4.7.2/Jolt, including all
three real-time network profiles and the independent clock/reset scenes.
Worst scripted settling was 183.3 ms at 80 ms and 250 ms at 150 ms. The independent
dedicated-server/four-client process check also passed. This follow-up is ready
for integration; its CI run 35459583307 passed validation, exports and process
checks, separately from the older checkpoint above.

Network checks now cap execution to real-time 60 FPS while preserving 60 Hz fixed
physics. Accelerated fixed-120 testing produced an ENet packet throttle drop from
32 to 1 and lost a recovery press before server validation (8 accepted commands/s).
The real-time 120-render/60-physics check delivered it once at 60–62 commands/s and
passed. Do not retry away that failure or interpret accelerated transport loss as
the configured impairment profile. Pure physics checks may still run accelerated.

### Completed transport follow-up

See [the current acceptance record](coordination/A_TRANSPORT_ACCEPTANCE.md).
New independent scenes cover opaque whole-UDP impairment, a four-client full
match/reconnect/rematch through that relay, sustained north-wall/chamfer contacts,
and phase-aware remote extrapolation. The relay drops the initial connect packet
deliberately to exercise ENet retransmission; actual RTT is measured separately
from configured delay. Wall replay previously crossed the north wall; static
geometry sweeps reduced the targeted peak error from 1.060 m to 0.014 m. A second
reproduced defect extrapolated stale falling remote poses below the floor during
countdown; extrapolation is now limited to active/overtime surviving bots.
These fixes preserve public APIs, protocol 4 and build mvp-ab-3. No B/model files
are changed. Final `tools/check-mvp.ps1` passed, including all three whole-UDP
profiles and existing contact/session checks. The separate dedicated server plus
four client processes also reached active without errors. Current contact worst
settling was 183.3 ms at 80 ms and 216.7 ms at 150 ms; 80 ms non-contact correction
p95 was 0.137 m. Whole-UDP measured RTT samples were 119–151 ms with an 80 ms
injection and 185–219 ms with 150 ms, with clock error at most 0.5 physics ticks.
These are local automated results; two-computer LAN and human feel remain open.
CI run 35460811964 passed the complete transport increment, both exports and
independent-process checks.

### Completed local 5v5 follow-up

Ten-slot custom lobbies use five existing Foundry markers per side, 240-second
rounds and the same judging, first-to-two, overtime and five-round cap. The host
menu and `--players=10` select the mode; every slot must connect and Ready. The
new build ID rejects older clients. Result payloads now accommodate all ten
players and five rounds, while frequent timer messages contain compact summaries.
Detailed stats remain in the results event and are restored on reconnect.
Reordered entity snapshots also no longer discard each other's valid updates:
the transport is unordered, with stale/duplicate rejection by per-entity tick.
An actual-ENet adversarial scene failed with the old annotation and passes after
the fix, including stale and duplicate packet rejection.
The final full MVP suite passed, including independent rule/spawn, full-results
delivery, adversarial snapshot ordering and ten-client sessions at 0/80/150 ms
injection. Separate server-plus-ten-client and server-plus-four-client process
checks passed. Evidence: `%TEMP%/battlebots-five-mvp-final.log` and the linked
coordination record. This is not yet a ten-player combat performance certification.
Its CI run 35462495199 failed the older network presentation movement fixture:
that ENet integration scene was still accelerated with `--fixed-fps`. The FFA
follow-up runs all ENet integration scenes in real time and measures driving by
physics frames, preserving the movement threshold. Its new CI must verify this.

### Current FFA follow-up

FFA now has 4–8-slot custom lobbies, unique hostile bot identities, existing FFA
arena spawns, one 300-second round, individual forfeits and all-survivor spectator
candidates. Elimination ticks determine placement, simultaneous eliminations
share place, and complete first-place ties share the win. Timeout survivors rank
by rounded core percentage then effective damage. The A app exposes mode/capacity
and placement results. B should use the new winners/placements fields documented
in CONTRACTS.md, retaining team result semantics for team modes.
Independent rule/menu tests and FFA sessions at 0/80/150 ms pass. Reservation
expiry, results reconnect and reduced-roster rematches pass separately. The first
full run found a 5v5 unreliable-clock starvation case; bounded clock exchange now
uses reliable control. Combined integration testing subsequently exposed reliable
reply asymmetry after reconnect; a bounded minimum-RTT clock filter fixes it, with
the 150 ms transport reconnect gate passing at 0.5 ticks. The integration record
distinguishes the failed full run from focused reruns. No performance or human
LAN acceptance is claimed.

## Other developer / modelling boundary

The user authorized merging published B/art work for this testing checkpoint.
Flamebot `909b666` and sawblade `5e163af` are included as assets/source; no combat
geometry or stats were changed. The separate modelling worktree at
`C:/Users/jorge/battlebots-art-flame` remains untouched. Saw source is excluded
from Godot import until a portable runtime export exists.
B controls, diagnostics, match HUD and menu kit are merged. Small integration
changes add the advanced-mode route and guard, consume rebound control labels,
and return to the configured main menu. SessionBotSource's input gate remains.
Both developers' contract/TODO additions are preserved. The historical
`codex/b-match-results` intent was superseded by the merged results follow-up;
current win/score presentation is described in the latest increment above.

## Remaining delivery scope

See [A MVP acceptance](A_MVP_TASKS.md) and the phase assignments in
[TEAM_WORKFLOW.md](TEAM_WORKFLOW.md), subject to the current priority above.
A still owns playable small-match network/contact acceptance,
public services and verified persistence. These are not complete just because
MVP automated tests pass. B owns combat, bots, garage/customisation and player
controls; A owns general menus, world and audio under the revised division.

Earlier measurements and incremental handoffs are retained in
[the dated archive](archive/A_HANDOFF_2026-09-19.md); that archive is historical.
