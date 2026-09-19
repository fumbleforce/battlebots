# Current A/B handoff

## Integration checkpoint

`codex/a-b-integration` at `bdb42ef` is the playable combined checkpoint. Its CI
passed: full MVP checks, Windows/Linux exports, and independent process startup.
It includes B's published arena/camera/HUD/settings at `40aa6b1`, A's simulation,
networking, simple app menus and primitive weapon placeholders. Main has not been
updated. Use the same branch/build on both PCs; current wire build is `mvp-ab-2`.

Host chooses 2 players (1v1, app default) or 4 players (2v2). One window per person;
all players must Ready. Session actions are conditional on connection/match phase.
Escape toggles the app menu; explicit Main menu safely leaves. Independent tests
cover round-end Escape, full matches/rematches, reconnect and malformed input.

## Active A work

A is on `codex/a-contact-reconciliation`, based on `bdb42ef`. Reserved paths:
`scripts/networking/`, relevant `scripts/simulation/` prediction code,
`tests/network/`, A check scripts, and these shared coordination docs.

Next acceptance: independent network scenes measure response to collisions,
weapon impulses and round resets at 0/80/150 ms. Existing non-contact p95 is about
0.145 m at 80 ms. Existing contact tests establish finite state only; they do not
prove the spec's 250 ms settling target. Any failures will be recorded and fixed,
not relabelled as passing. Human camera/contact feel and two-computer LAN remain
unverified; headless tests cannot replace them.

## Other developer / modelling boundary

B's `codex/b-sawblade-tank` at `daa0c8c` publishes modelling work. A has not imported
it. A separate local modelling worktree exists at `C:/Users/jorge/battlebots-art-flame`.
A will not edit that worktree, B assets, presentation, arena or UI files. No new
weapon geometry or art changes are planned in this increment. The shared
[TODO](DEVELOPER_B_TODO.md) records intentions and dependencies.

## Remaining delivery scope

See [A MVP acceptance](A_MVP_TASKS.md) and the phase assignments in
[TEAM_WORKFLOW.md](TEAM_WORKFLOW.md). A still owns network/contact acceptance,
full-mode authority (5v5/FFA), remaining weapon mechanics, server performance,
public services and verified persistence. These are not complete just because
MVP automated tests pass. B owns the final garage/presentation/user experience.

Earlier measurements and incremental handoffs are retained in
[the dated archive](archive/A_HANDOFF_2026-09-19.md); that archive is historical.
