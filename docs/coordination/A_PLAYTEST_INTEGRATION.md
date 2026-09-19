# A/B playtest integration

Historical `d417d7e` checkpoint. Current menu navigation is superseded by
[A_MENU_FLOW.md](A_MENU_FLOW.md): direct Join, immediate Practice, unified lobby.
Its complete CI run [35464908428](https://github.com/fumbleforce/battlebots/actions/runs/35464908428)
passed A/B suites, art validation, both exports and packaged process checks.

User requested winding down feature work, merging incoming work and preparing
for testing. Integration branch: `codex/a-b-playtest`, based on the FFA increment.
Keep the full game goal open; this is a testing checkpoint, not release acceptance.

## Incoming published work

- `codex/b-match-hud` at `d983612` includes B controls/rebinding, diagnostics,
  lobby and match HUD. `codex/b-match-results` at `0f343f7` adds results-work intent.
- `codex/b-flamebot-art` at `909b666` contains Flamebot runtime GLB and source.
- `codex/b-sawblade-tank` at `5e163af` is an independent Blender-source asset.
- Fresh fetch also found `codex/b-menu-kit` at `595c8f9`: the supplied polished
  menus, loadout editing/saves and persistent gameplay shell. It is merged and
  becomes the default F5 scene, retaining A's command-line startup route.

Merge committed heads only. Leave the separate modelling checkout untouched.
Preserve A session/rules, including B's numeric JSON team-selection fix alongside
FFA rejection of team changes. Preserve both developers' contract/TODO additions.

B's new frontend supports duel/2v2; the mode selection screen links to A's existing
setup for 5v5/FFA. Each route has one input/session owner. Returning from A's setup
opens the configured new F5 menu. Joining an advanced-mode host from B's four-slot
frontend is rejected with directions to the correct route. Full mode-aware B
lobby/loading/results presentation remains separate follow-up work.
The advanced setup currently selects the two starter builds; carrying a garage
custom build into that alternate shell is not wired in this checkpoint.

Art is merged for inspection, not assigned combat stats or collision. Flamebot
has a Godot runtime export; the saw source still needs an export excluding studio
objects. Exclude that source folder from Godot import until a portable runtime
export is provided, so this checkpoint does not require Blender to run/export.

## Validation

Run baseline/full A regression, B presentation runner, targeted art-import check
and independent process startup on the merged tree. Record actual outcomes and
CI link below. Human two-computer LAN, contact/camera feel, full combat performance
and sustained soak remain open.

Clock regression: `clock_delivery.tscn` uses public ENet throttle configuration
and an actual RTT increase to reach zero unreliable throttle. A fresh reliable
baseline resets readiness, then the reliable clock exchange restores it with a
267 ms measured RTT. The prior failure log remains preserved. Optional
`BATTLEBOTS_CLOCK_TRACE=1` exposes per-peer throttle/pending clocks in 5v5 tests.

Merged resource import passed without Blender. The Flamebot Godot check passed:
seven moving meshes, expected pivots/materials/axis conventions, no collision or
studio nodes. The saw source folder has `.gdignore` until its portable runtime
export is supplied; it remains available as source/reference material in Git.

The first merged A suite exposed an unrelated source of loss in the one-shot
snapshot ordering fixture: ENet's adaptive throttle had fallen to 30/32. That
fixture now disables adaptive drops at transport admission and requires full
32/32 delivery before injecting the same 250 ms reorder. Its ordering, per-entity
stale tick and duplicate assertions are unchanged. Four targeted runs pass;
normal whole-session tests retain production throttling and injected packet loss.

B's complete presentation runner passed, including all supplied-menu loadout,
navigation, live lobby, full-match/rematch and new advanced-mode guard checks.
The advanced-route test passed separately, including safe host cleanup, FFA8
selection and return to the configured main menu. Windows and Linux exports
succeeded. The packaged Windows menu starts without errors; the exported binary
passed dedicated-server startup with four team clients, ten team clients and four
FFA clients. `check-processes.ps1 -Exported` omits the editor-only path override;
CI now checks the actual exported Windows executable too.

The final A run passed all shared checks and the complete 0/80 ms profiles, then
passed network/contact at 150 ms before exposing a reconnect clock bias. A delayed
reliable first reply contaminated the smoothed clock even after a clean reply.
The estimator now selects the lowest-RTT sample from eight recent replies. The
new asymmetric-reply regression failed before the fix and passes after it; sample
expiry also passes. Clock delivery still passes at zero unreliable throttle.
The corrected 150 ms transport check passes with 0.5-tick reconnect error at
186 ms measured RTT, below the unchanged four-tick gate. The remaining 150 ms
5v5 and four/eight-player FFA checks pass. This records a failed full run plus targeted fixes,
not a subsequent complete `MVP PASS` run.
Original failure evidence: `%TEMP%/battlebots-playtest-mvp-final.log`.
Final network logs: `%TEMP%/battlebots-final-five-v-five-150.log` and
`%TEMP%/battlebots-final-ffa-150.log`. Final baseline checks pass too. Windows and
Linux exports were refreshed after the clock fix, and all three packaged Windows
process checks (four players, ten players, FFA) passed again.

## Manual playtest handoff

Use the same packaged build on both computers, with one window per person.
Choose Play → Private Duel, select a build and Foundry, then host on one PC and
join its LAN IPv4 address from the other. Both players Ready up. Check driving,
weapon use, collisions, Escape/Resume, elimination, round transitions and rematch.
Also try leaving before Ready and returning to the main menu after the match.
For 5v5/FFA, all players use the labelled advanced setup route. Test four-person
FFA and ten-person teams when enough people or scripted clients are available.

Record the build, mode, player count, host/client role, observed error and steps
to reproduce. Human LAN, camera/contact feel, full combat performance and sustained
soak remain acceptance work; local headless success does not close those items.
