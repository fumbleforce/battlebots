# Camera/input lifecycle — B validation

Branch `codex/b-camera-round-lifecycle`, rebased onto main `7ce48ab`.
Two independent scenes now cover real practice source replacement and real ENet
1v1 round transitions through the composed menu/input/camera adapter. No production
logic, match rules, BotSource API, content identity or saved preferences changed.

## Evidence

- `camera_round_lifecycle_test.tscn`: active input, authoritative practice knockout,
  restart with same bot, full leave/recreate with new bot and collision RIDs.
  Held input remains canceled until release/repress; camera follows current source.
- `camera_duel_lifecycle_test.tscn`: two real ENet peers, readiness/loading,
  countdown, active input received by authority, elimination/intermission,
  second-round reset/countdown/active. Actual app gates remain intact. Held throttle,
  steering, primary/recovery edges and weapon hold stay canceled across transitions;
  release/repress rearms. Camera sphere is clear of world/other bots at each phase,
  transforms/boom remain finite/bounded, and anchor/exclusions stay current.
- Both markers pass headless with exit 0; duel also passes native D3D12/Forward+.
  Both scenes are registered at real-time 60 FPS in the presentation runner.
- Full Godot 4.7.2 baseline import/smoke runner passes on resumed main runtime.

These deterministic tests directly eliminate an authoritative combatant and shorten
only server phase timers. They do not synthesize client match views, bypass input
gates, certify natural combat outcomes or replace human hosted playtests. Team/FFA
spectator cycling remains deferred behind 1v1. No production defect was found.

## Shutdown observations

An earlier baseline run printed PASS but exited -1073741819; the runner rejected
it. Standalone verbose and complete baseline reruns exit 0 unchanged. The earlier
access violation remains intermittent/unresolved, not claimed fixed by this task.
A practice teardown warning identified retained MP3 playback; the fixture now
stops menu playback and lets the audio server drain before freeing the game.
Its final verbose run exits 0 without leaked-object warnings.

Updated stale B task notes to reflect merged Sawblade assets. Next substantive B
work is recognizable component damage presentation from authoritative snapshots.
