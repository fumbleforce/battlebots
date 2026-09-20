# A battle music — 20 September 2026

Owner: A. Branch: `codex/a-battle-music`, base `de4fd0e`.

User request: add the supplied `relentless action (1).mp3` as the in-battle song.
Reserved paths: `assets/audio/battle/`, the music setup/sync in
`scripts/presentation/menu_game.gd`, existing audio/music/session presentation
checks, and this coordination/handoff entry. All game paths are below battlebots/.

Use the supplied recording unchanged, looped on BBMusic at the menu theme's
moderate player gain. Start with arena countdown and continue through active,
overtime and intermission phases, including pause/settings. Stop during results,
loading, lobby, leave and reconnect recovery. Keep the existing menu theme and
volume/mute preferences. No combat, controls, catalogue or network changes.

Acceptance: pinned Godot import/baseline, existing practice/menu/music settings
checks and real ENet match/results/rematch/reconnect playback assertions. These
checks establish playback state, not human listening or hosted release acceptance.

Implemented: the unchanged 67.04-second stereo/48 kHz MP3 is imported as
`assets/audio/battle/relentless_action.mp3`; its private playback resource loops
at -16 dB on BBMusic. Menu and battle tracks are mutually exclusive. A music sync
also runs on the recovery early-return path, preventing stale battle playback.
Practice restart and in-battle settings retain the same playback instance.

Validation with Godot 4.7.2.stable.official.ed1daf0bf:

- `tools/check-baseline.ps1`: BASELINE PASS, including MP3 import.
- `tests/presentation/menu_music_test.gd`: MENU MUSIC PASS, including playback
  across the actual MP3 loop boundary, practice restart and source cleanup.
- `tests/audio/audio_menu_test.gd`: AUDIO MENU PASS, including battle volume
  preview/cancel through the existing Music slider.
- `tests/presentation/menu_game_network_test.gd --max-fps 60`: MENU GAME NETWORK
  PASS through real ENet countdown, two forfeit-driven rounds, results and rematch.
- `tests/presentation/game_reconnect_test.gd`: GAME RECONNECT PASS through
  transport loss and active/results recovery, with both tracks mutually exclusive.
- Source/copy SHA256 match:
  `7F8FD2BF606B5696CA712662A7EB9CD999488BD40A245F8AFE6AF2E9EEF12C1F`.

The first network invocation omitted the runner's `--max-fps 60`; its frame-based
wait expired before real intermission finished. The corrected invocation passed.
The first fixed-fps loop-boundary check used scene time and failed before real
audio advanced. It now waits 250 ms of wall time and passes the runner's fixed-fps
invocation. No runtime workaround or assertion threshold was weakened.
Music/reconnect checks report the existing ObjectDB shutdown warning (2–4
instances); no native crash or script error occurred in the passing checks.

This is client presentation only; no hosted deployment/export or human listening
acceptance is claimed. Protocol/build/catalogue remain unchanged. The ownership
reservation is released on integration. Pre-existing project.godot and Sawblade
texture import edits remain outside this commit.
