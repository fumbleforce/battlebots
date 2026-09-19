# Current A/B handoff

## Current Developer A increment

`codex/a-hammer` follows horizontal spinner `b46084e` and menu/music export
`db87257`. Hammer adds a committed overhead strike, per-activation target dedup,
resource/recovery timing and the legal Duelist starter. See
[hammer coordination](coordination/A_HAMMER.md) and the preceding
[horizontal spinner coordination](coordination/A_HORIZONTAL_SPINNER.md).
This branch uses build `mvp-ab-7`/protocol 4 with catalogue revision three; both
peers must update together. Known revision-one/two saves migrate without changing
parts. The `db87257` playtest ZIP is preserved separately. The menu/music CI run
35465682771 passed; horizontal CI 35466215676 failed an FFA observer-health check.
A local reproduction passed; failure diagnostics were added without weakening the
exact-health gate. The cause remains unproven pending further CI evidence.

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
Both developers' contract/TODO additions are preserved. Detailed results frontend
work on `codex/b-match-results` remains an intent document, not completed UI.

## Remaining delivery scope

See [A MVP acceptance](A_MVP_TASKS.md) and the phase assignments in
[TEAM_WORKFLOW.md](TEAM_WORKFLOW.md). A still owns network/contact acceptance,
remaining weapon mechanics, ten-player combat/server performance,
public services and verified persistence. These are not complete just because
MVP automated tests pass. B owns the final garage/presentation/user experience.

Earlier measurements and incremental handoffs are retained in
[the dated archive](archive/A_HANDOFF_2026-09-19.md); that archive is historical.
