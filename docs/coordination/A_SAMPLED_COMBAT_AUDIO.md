# A supplied combat sounds — 20 September 2026

Owner: A. Branch: `codex/a-sampled-combat-audio`, base `ac2bda4`.

User request: adapt the three supplied MP3s according to their descriptions.
Filename mapping: two heavy metal cars -> confirmed ram impact; huge hammer
crashing -> confirmed hammer impact; heavy saw continuous -> powered saw loop.

Reserved scope: `battlebots/assets/audio/combat/`, A-owned sound/loop banks and
continuous audio presentation, related audio tests, source preparation tooling
and this handoff. Consume the existing confirmed events/accepted audio records.
No B combat, weapons, controls, bot/catalogue or shared network schema changes.

Prepare mono 48 kHz PCM for spatial playback, with unclipped mix headroom and
quiet impact endpoints. Extract/crossfade the sustained saw body for looping and
retain its recorded pitch. Preserve the existing effects bus, bounded voice pools,
event deduplication and stale-state/menu/recovery silence.

Implemented recordings and reproducible conversion are documented in
`battlebots/assets/audio/combat/README.md`. Original MP3 bytes are preserved in
the excluded source folder. `tools/prepare-combat-audio.py` uses ffmpeg float
decoding before gain reduction, avoiding the source MP3s' above-full-scale peaks.
Runtime WAV imports explicitly use uncompressed PCM16, since default WAV
compression would invalidate the sample-frame loop calculation.

- Ram: 0.80 s, peak 0.65, RMS -21.87 dBFS, 1 ms attack/35 ms tail fade.
- Hammer: 0.90 s, peak 0.70, RMS -19.75 dBFS, same short fades.
- Saw: sustained 0.18–1.32 s source region with 80 ms equal-power overlap; final
  1.06 s/50,880-frame loop, peak 0.30, RMS -22.96 dBFS and negligible DC.
  Playback uses pitch 1.0 and -14 dB gain to retain the recording's weight and
  compensate its lower sustained level versus the synthesized sound.

Both sound banks cache private resources. Ram/hammer remain one-shots driven
only by confirmed events; the saw uses existing accepted binary power and never
restarts on a repeated state refresh. All existing pool limits, effects/mute
settings, spatial attenuation, stale-state guards and captions remain active.

Validation: Godot 4.7.2.stable.official.ed1daf0bf, headless, audio checks at
`--max-fps 60`:

- `tools/check-baseline.ps1`: BASELINE PASS, including source asset import.
- `gameplay_audio_test.gd`: GAMEPLAY AUDIO PASS; correct recorded impact data,
  PCM format, duration, quiet endpoints, headroom, deduplication and voice caps.
- `gameplay_loop_bank_test.gd`: GAMEPLAY_LOOP_BANK_PASS; full-frame loop,
  waveform/cache identity, DC/energy and sample/slope continuity across the seam.
- `continuous_gameplay_audio_test.gd`: CONTINUOUS_GAMEPLAY_AUDIO_TEST: PASS;
  recorded saw, original pitch, mix gain, uninterrupted power and power-off.
- `spatial_impact_audio_test.gd`: SPATIAL_IMPACT_AUDIO_PASS; captured left/right
  hammer energies approximately (183.36, 74.12)/(74.32, 183.86), near/far combined
  energies 715.49/2.10. Captured stereo verifies direction and distance attenuation.
- `continuous_audio_game_test.gd`: CONTINUOUS AUDIO GAME PASS; real practice
  command/state composition, menu/settings/restart/recovery/leave behavior.
- Original source/copy bytes match; generated assets have unclipped PCM peaks.

Final validation repeated the five audio checks and direct baseline smoke in the
isolated `battlebots-sampled-audio` checkout; all passed with exit 0. The first
cold full-project editor import there completed asset import but exited with
Windows 0xC0000005 before baseline smoke ran. The original-checkout baseline
wrapper had passed. This matches the documented intermittent native shutdown
failure class, but its root cause is not established and no clean cold-import
acceptance is claimed. No retry of that failed import was used to report success.

Spatial/continuous tests intermittently report ObjectDB shutdown warnings (2/7
instances). Releasing comparison references and allowing in-tree spatial/mixer
teardown produced one clean continuous test, but the warning recurred in the
isolated validation; it remains unresolved. No native crash or script error
occurred in the passing runtime checks.

No hosted deployment/export or human listening acceptance is claimed. This
changes client presentation only, with no protocol/build/catalogue change.
Pre-existing and concurrent unrelated working edits remain outside this task.
