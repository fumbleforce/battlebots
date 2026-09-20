# A — weapon and armor status audio

Intent 2026-09-20, `codex/a-combat-status-audio`, base `fb3d633`.
A reserves audio scripts, game-menu audio composition, independent audio tests
and docs. Consume existing detached BotView fields plus weapon family from the
published audio accessor. No B combat, controls, bot assets or wire changes.

Detect new armor breaches and weapon status edges from accepted local views.
Initial/rejoined state is a silent baseline. Ignore stale ticks and malformed
state; reset across rounds and leave. Use precise captions: spinner full speed,
lift charged, saw running, and hammer cooldown complete. These describe observed
state, not a new claim that an attack can afford its battery cost or will land.
Keep warning playback bounded and preserve simultaneous critical captions.

Independent detector tests cover family semantics, repeated/stale/invalid data,
silent baselines, repair/rearm, elimination and round reset. Game integration
must use accepted local baseline/freshness instead of a client's default bot.
Validate PCM and caption/playback behavior, then baseline and relevant composed
game/audio checks. Human listening acceptance remains separate.

## Implemented behavior and evidence

- `CombatAudioStatus` tracks per-panel integrity and family-specific charge or
  cooldown edges. Invalid fields invalidate only their relevant baseline;
  repeated ticks cannot replay events. Positive cues use hysteresis and a
  750 ms playback limit, with critical warnings taking precedence.
- Original `weapon_ready` and `armor_break` PCM were appended to the bank;
  the 11 existing waveforms remain unchanged (before/after hash comparison).
  New PCM tests cover deterministic cache, bounds, DC, decay, endpoints and
  distinct metallic fracture texture.
- Core/recovery/armor messages retain the latest caption of each type together.
  Review caught three simultaneous warnings replacing one another in the old
  two-voice pool. Three fixed announcement voices now retain all three; the
  playback test checks each active stream, not just emitted cue signals.
- The composed game supplies accepted local views and weapon metadata, omitting
  stale audio records past 250 ms. Armor warnings also duck continuous ambience.
  No B producers, simulation rules, controls, assets or wire fields changed.
- Combined captions required more HUD space. A reserves that layout adjustment
  in `combat_hud.gd`: central caption area at default text, right-side area below
  network status at enlarged text. Persistent warning wrap also fixes stale
  width after changing text scale. Full critical messages are not truncated.

Godot 4.7.2 stable / Jolt checks on 2026-09-20:

- `combat_audio_status_test.gd`, `status_sound_bank_test.gd` and
  `combat_status_playback_test.gd`: PASS. The playback fixture lets the actual
  mixer consume its rapid controlled transitions before teardown; otherwise
  pending WAV/playback references produced cleanup warnings. With that lifecycle
  wait it exits cleanly while still asserting simultaneous active voices.
- Existing `gameplay_audio_test.gd`: PASS with updated fixed-pool assertions.
- `status_audio_game_test.gd`: PASS through actual practice spin-up commands,
  authoritative armor depletion, captions, ambience ducking, repair/restart and
  leave. Damage is controlled fixture input, not natural-duel acceptance.
- `status_caption_layout_test.gd`: PASS headless and native D3D12 across
  1280x720, 1920x1080 and 3840x2160 at 100/150% text in duel/practice layouts.
  Checks actual shaped line heights and overlaps with combat, warning, match,
  practice and network panels. Native captures under `user://a-status-caption-*`
  were reviewed, including 720p enlarged text. Existing HUD accessibility checks
  and `tools/check-baseline.ps1` also pass.
- Full `tests/presentation/check-presentation.ps1`: PASS with all five new
  status/caption checks, prior audio/HUD/menu checks and actual network
  reconnect/results/rematch coverage. Exit zero and final presentation PASS;
  no script errors or native crash signatures. Some existing composed fixtures
  still report ObjectDB cleanup warnings; that outstanding issue remains open.

Remaining audio scope is crowd response, spatial/material impact mix and human
listening polish. This increment does not claim hosted-internet acceptance or
resolve the separately tracked Windows native shutdown issue.
