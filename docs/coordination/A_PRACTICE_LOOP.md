# A practice loop

Owner A, branch codex/a-practice-loop from main 7feb900. Arena work proceeds in
the separate arena worktree; combat/bots/controls remain B-owned.

Intent: show read-only target damage and knockout feedback in practice, and add
a practice-only restart action so players can repair/reposition both bots and
repeat weapon testing without leaving to the main menu. Player knockout opens
the existing pause menu with restart available. Online/LAN sessions cannot use
this reset. This increment is not the full guided tutorial.

Allowed paths: A session practice lifecycle, general menu-shell composition,
new practice HUD and independent practice tests. Reuse world.reset_round and
published BotView; no changes to damage, driving, input actions, camera or arena.

Root implements session/menu integration; UI agent owns the new HUD and its
fixture; validation agent owns the independent practice session fixture.
Validate the shared baseline, state restoration and actual menu flow. Commit,
fetch/rebase, merge locally into main and push directly; no PRs.

Implemented API: practice_target() returns the target BotSource only during
practice. restart_practice() rejects every other session state unchanged; in
practice it restores the existing world/bots through reset_round, clears queued
actions and emits practice_restarted. Sequence marks and world ticks remain
monotonic. The shell resets sound deduplication, repairs/repositions both bots,
and resumes directly. Player knockout opens pause focused on Restart; closing
settings cannot recapture controls for an eliminated practice bot.

The panel reads actual target core and disabled components from BotView, handles
missing/non-finite data explicitly, and leaves source views unchanged. Practice
actions are absent in main/LAN/online; keyboard focus follows available buttons.

Validation so far: Godot 4.7.2 baseline passed. PRACTICE SESSION passed including
offline/hosting/connecting/connected rejection, two reset cycles and a real
post-reset hammer hit from normal spawn (target 300→263.90). Reset damage was
explicit fixture setup; the final hit used ordinary commands. MENU GAME NETWORK
passed its real-time two-peer rounds/results/rematch check, with an ObjectDB
warning for four instances at shutdown; this does not resolve the existing
engine cleanup issue.

Final PRACTICE HUD and PRACTICE MENU checks passed without warnings. The menu
fixture exposed a hidden-panel autowrap minimum-height error; labels now receive
their known inner width before shaping. Independent hidden→shown CanvasLayer
and actual menu fixtures verify the panel stays within 720p, and keyboard focus
includes Restart. The three practice fixtures are in the presentation runner.
Logs: %TEMP%/battlebots-practice-hud-test.log,
%TEMP%/battlebots-practice-session.log, %TEMP%/battlebots-practice-menu.log and
%TEMP%/battlebots-practice-network.log. Human rendered playtesting and the guided
tutorial are still open; this increment adds no tutorial-completion claims.
