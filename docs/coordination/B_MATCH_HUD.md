# B-08a — live match status

Owner: Developer B. Branch: codex/b-match-hud, based on eea0bb2 (B lobby).
Intent: show authoritative round, clock, team scores and round/match outcomes in
B's playable scene. Practice remains explicitly unscored. No simulation, transport,
app bootstrap or shared contract changes. A retains those paths and F5 mounting.
B reserves new match_hud UI/scene/tests and lobby_game presentation integration.
Validation: independent phase/malformed-state HUD checks and real playable scene
regressions. Full results statistics, rematch voting and spectating remain next.

Implemented: MatchHud.render(match_view, practice) plus standalone mock F6 fixture.
Playable scene stays in arena for countdown/intermission/results, with neutral
input outside active/overtime. Explicit menus survive phase transitions. Resume
works via actual UI in results/countdown. No A-owned source changed.
Validation: all 15 presentation checks pass, including real UDP two-player full
match (public forfeits for deterministic round completion), independent malformed
snapshot/draw/Practice cases, and rendered 1280x720 HUD and actual Practice.
The display uses the latest server clock; no client-side match advancement.
Remaining B-08: detailed statistics, rematch/forfeit controls, teammate spectating,
component/recovery HUD and combat feedback. A still owns F5 mounting and runtime
integration; this branch retains mvp-ab-2/protocol3 and needs matching peer builds.
Baseline import/contract smoke also passes on Godot 4.7.2.
