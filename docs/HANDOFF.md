# Current A/B handoff

## Integration checkpoint

`codex/a-b-integration` at `bdb42ef` is the playable combined checkpoint. Its CI
passed: full MVP checks, Windows/Linux exports, and independent process startup.
It includes B's published arena/camera/HUD/settings at `40aa6b1`, A's simulation,
networking, simple app menus and primitive weapon placeholders. Main has not been
updated. That checkpoint uses `mvp-ab-2`/protocol 3. The A follow-up described below
uses `mvp-ab-3`/protocol 4; both PCs must use the same branch/build.

Host chooses 2 players (1v1, app default) or 4 players (2v2). One window per person;
all players must Ready. Session actions are conditional on connection/match phase.
Escape toggles the app menu; explicit Main menu safely leaves. Independent tests
cover round-end Escape, full matches/rematches, reconnect and malformed input.

## Active A work

A is on `codex/a-contact-reconciliation`, based on `bdb42ef`. Reserved paths:
`scripts/networking/`, relevant `scripts/simulation/` prediction code,
`tests/network/`, A check scripts, and these shared coordination docs.

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
80 ms was 0.125 m in the final real-time run. Manual LAN, full control-channel impairment and a broad collision
matrix still remain acceptance work.

Validation: final `tools/check-mvp.ps1` passed with Godot 4.7.2/Jolt, including all
three real-time network profiles and the independent clock/reset scenes.
Worst scripted settling was 183.3 ms at 80 ms and 250 ms at 150 ms. The independent
dedicated-server/four-client process check also passed. This follow-up is ready
for integration; its new CI run is separate from the older checkpoint above.

Network checks now cap execution to real-time 60 FPS while preserving 60 Hz fixed
physics. Accelerated fixed-120 testing produced an ENet packet throttle drop from
32 to 1 and lost a recovery press before server validation (8 accepted commands/s).
The real-time 120-render/60-physics check delivered it once at 60–62 commands/s and
passed. Do not retry away that failure or interpret accelerated transport loss as
the configured impairment profile. Pure physics checks may still run accelerated.

## Other developer / modelling boundary

B's `codex/b-sawblade-tank` at observed `52e8e99` publishes modelling work. A has not imported
it. A separate local modelling worktree exists at `C:/Users/jorge/battlebots-art-flame`.
A will not edit that worktree, B assets, presentation, arena or UI files. No new
weapon geometry or art changes are planned in this increment. The shared
[TODO](DEVELOPER_B_TODO.md) records intentions and dependencies.
B's input-menu branch has published X/Y sensitivity at `6e42594` and controls/
rebinding intent at `d53967e`; A has not imported these follow-ups. A preserves the
existing preview API and SessionBotSource gate. No app/input/presentation changes
here. A future integration must preserve both owners' contract/TODO additions.

## Remaining delivery scope

See [A MVP acceptance](A_MVP_TASKS.md) and the phase assignments in
[TEAM_WORKFLOW.md](TEAM_WORKFLOW.md). A still owns network/contact acceptance,
full-mode authority (5v5/FFA), remaining weapon mechanics, server performance,
public services and verified persistence. These are not complete just because
MVP automated tests pass. B owns the final garage/presentation/user experience.

Earlier measurements and incremental handoffs are retained in
[the dated archive](archive/A_HANDOFF_2026-09-19.md); that archive is historical.
