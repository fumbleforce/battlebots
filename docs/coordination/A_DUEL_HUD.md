# A — 1v1 HUD

Intent recorded 2026-09-20, branch `codex/a-duel-hud`, base `1a5d38a`.

A reserves new combat HUD presentation, `scripts/ui/match_hud.gd` and its scene,
`scripts/presentation/menu_game.gd` composition, and independent HUD fixtures.
Read published BotView/match/lobby data only. Show core/battery/heat, component
status, weapon readiness/cooldown, recovery/immobilization, heading and 1v1 round
state clearly using the original menu theme. Preserve practice and menu/settings
suppression. No B combat, controls, camera, bot/registry or garage edits.

Parallel work: one subagent owns match HUD styling/round presentation; parent
owns combat HUD and app composition. A second subagent audits published state
semantics and acceptance gaps read-only. Shared schemas remain unchanged unless
a missing producer field requires a separate documented B handoff.

Validate detached edge cases, rendered 720p/1080p composition and real session
propagation. Record actual evidence before merging and pushing shared main.
External hosting remains separately outstanding; other modes/tutorial deferred.

## Implemented behavior

Original-theme round HUD and a new read-only CombatHud provide core/battery/heat,
generic weapon charge and explicit weapon phase/cooldown, raw integrity diagram,
recovery availability/cooldown, immobilization and elimination warnings, chassis
bearing and 1v1 local/rival survival status. Other modes retain local bot status;
practice is explicitly unscored. Match phase overrides recovery readiness during
round locks. Armor values are not normalized using guessed maxima, and timers
never advance locally. Missing/invalid data is unknown, never dead or healthy.

The shell consumes new `MvpSession.bot_views()` for both local and rival state.
The method omits uninitialized client bodies and returns detached views without
changing any wire data. Existing B preview controls and camera code are untouched.
Combat, practice, diagnostics and captions use a scalable HUD canvas; old preview
HUD/hints are hidden only in the default game. Diagnostics interactions, settings,
practice repair and menu suppression remain integrated.

## Evidence and limits

Godot 4.7.2 stable / Jolt, 2026-09-20:

- Baseline import/smoke passed via `tools/check-baseline.ps1`.
- Independent `combat_hud.tscn` and `combat_hud_test.gd` passed invalid/missing
  data, raw-zone meaning, heading cardinal/vertical cases, remapped recovery
  label, round lock, overheat latch, elimination priority and no local countdown.
- `combat_hud_session_test.gd` passed actual ENet server/client propagation of
  damage, component loss, recovery cooldown, opponent elimination, next-round
  repair and leave clearing. It also verifies detached views and missing-baseline
  omission. Its server state and round clock are controlled fixtures; this is
  not new natural-combat acceptance evidence.
- `game_hud_test.gd` passed real practice composition, HUD replacement, damage
  feedback, caption/target clearance, menu/settings suppression, repair and leave.
- Match HUD authoritative/layout tests and game-menu interaction regression pass.
- Audio menu regression passes. Some checks retain the documented two-object
  ObjectDB cleanup warning; no native crash occurred in these runs.
- Actual two-player `menu_game_network_test.gd` passes the composed menu/HUD
  through readiness, gameplay, rounds, results and repaired rematch. This existing
  match-flow fixture advances rounds by forfeit, not natural combat.
- Rendered combat and game HUD views at 720p/1080p inspected. Logical/native
  layout checks extend through 4K; match header has rendered 4K evidence too.
  Captures are local ignored Godot user data `a-combat-hud-*`, `a-game-hud-*`
  and `a-match-hud-*`, not distributed game exports.

Visual review fixed the round panel retaining empty height in practice after a
results/unknown state; a content-minimum-size callback and regression now keep
the practice header compact. State review also ensured local HUD data uses the
same baseline-filtered view list as rivals, including unknown-data handling.

New fixtures are registered in the presentation runner, with ENet checks in real
time. Full release acceptance is not claimed. Public hosted 1v1 deployment,
human review of the new HUD, independent text scaling, color-vision/high-contrast
presets and coordinated ping presentation remain open. Existing tunnel human
multiplayer success is retained as prior evidence, not rerun or replaced here.

Integration: commit only this increment, fetch and rebase preserving merges,
then merge locally into main and push directly after final checks. No B-owned
implementation paths remain reserved by this completed HUD feature.
