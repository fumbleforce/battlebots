# A — spatial impacts and arena reactions

Intent 2026-09-20, branch `codex/a-impact-crowd-audio`, base `0023ad9`.
A reserves gameplay audio, independent audio fixtures, menu-game composition
and documentation. Existing authoritative impact positions and match phase
transitions drive presentation; B combat, assets and controls remain unchanged.
No wire changes or invented contact-material information.

Replace the existing four non-spatial impact voices with four spatial voices,
preserving event validation, deduplication, throttling and readable captions.
Round/critical announcements remain non-spatial. Add a separate bounded arena
reaction voice for genuine round/match outcomes, silent on initial/rejoined
results, practice and duplicate phase refreshes. Crowd sound is original
procedural first-pass texture, not a licensed recording or human speech.

Validate actual positions, reuse/caps, lifecycle/dedup, invalid events, crowd
transitions, PCM and composed game behavior in independent scenes. Verify
stereo/distance mixing with captured engine audio if feasible; distinguish
property checks from audible/mixer acceptance. Run relevant existing audio,
presentation and baseline checks before merging to shared main.

## Implementation and validation

- Four existing impact slots now use AudioStreamPlayer3D, placed at the accepted
  combat-event world position. Captions, event high-water marks and throttling
  are retained. Three announcement voices remain non-spatial.
- One crowd voice plays distinct original round/match textures, prewarmed before
  combat. Genuine transitions emit one reaction; initial/rejoined results,
  practice, repeated/stale phases and retired matches cannot invent a crowd.
  New rounds/matches and leave stop preceding reactions. Crowd is locally ducked
  under announcements, with saved effects/announcement volume buses unchanged.
- All 13 pre-existing PCM cue hashes match before/after addition. New
  `crowd_sound_bank_test.gd` checks bounded memory, cache, deterministic texture,
  smooth onset/decay, endpoints, energy and DC: CROWD_SOUND_BANK_PASS.
- `crowd_audio_test.gd`: CROWD AUDIO PASS; asserts actual player streams, single
  voice reuse, phase guards, local duck/restore, captions and cleanup.
- `spatial_impact_audio_test.gd`: SPATIAL_IMPACT_AUDIO_PASS. Actual engine
  AudioEffectCapture measures left/right energy about (46.115,18.641) versus
  (18.641,46.115), and near/far energy about (90.775,90.775) versus (0.275,0.275)
  at unchanged voice gain. This proves mixer panning and distance attenuation,
  beyond configuration properties. Translated-parent world positions, fixed
  slots, invalid/stale rejection and reset are also checked.
- Existing gameplay-audio and status-playback tests pass with four spatial
  impacts, three announcements and one crowd player. Baseline passes on Godot
  4.7.2 stable / Jolt. Independent read-only review found no blocking issue.
- Full presentation suite: PASS, exit zero with final presentation marker and
  no script errors or native crash signatures. The actual two-peer game fixture
  verifies one round crowd and one final crowd reaction through authoritative
  results, then silence from the old match after rematch. New audio capture and
  HTTP fixture checks are registered. Some existing fixtures still emit ObjectDB
  cleanup warnings; those are not claimed fixed.

CI inspected during this increment: Windows35504204396 atfb3d633 completed
successfully, Linux35504840929 at0023ad9 succeeded, and Windows35504840930 at0023ad9
failed after DRIVE PASS with native0xC0000005. That intermittent crash is not
claimed fixed. An older online-menu test bind failure is addressed separately
in [the fixture repair](A_ONLINE_FIXTURE_PORT.md); no production service changed.

Human listening/mix acceptance and material-specific variation remain open.
No contact material tag exists in the consumed event, so none is inferred from
weapon family or damage. These tests do not certify external hosting.
