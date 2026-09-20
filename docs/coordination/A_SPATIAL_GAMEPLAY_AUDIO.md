# A — continuous gameplay audio

Intent 2026-09-20, branch `codex/a-spatial-gameplay-audio`, base `9a3053a`.
A owns audio, the session presentation accessor, menu-game composition and
independent audio tests. B combat, drive, camera, controls and bot assets stay
unchanged. Existing snapshot data supplies physical movement and weapon state;
no wire or BotView schema change is planned.

Add detached `MvpSession.audio_views()` dictionaries: entity_id, tick, position
(presentation world position), pose (physical world transform), velocity,
angular, drive_input, turn_input, grounded, weapon, charge, eliminated, age.
Server/practice read current physical state and validated combat metadata;
clients read accepted current-epoch snapshots, including for the local player.
Reset-pending motion is neutral. Missing baseline yields no record. Age is
seconds since accepted client snapshot, zero on the server.

Continuous layers use actual demand/speed and family-specific charge. Lateral
grounded motion is an approximate sliding cue, not a measured tire-slip value.
Spinner coast-down must remain audible while charge remains; saw power is
binary, and hammer/lifter readiness must not masquerade as rotor speed.
Bound voices, reject invalid/stale records, stop on menus/recovery/round changes
and leave. Preserve user bus volumes, captions and existing menu music. Duck
arena ambience locally during announcements/warnings.

Validate generated PCM, detached controller behavior, accepted session data,
and composed practice/menu lifecycle in independent scenes. Run baseline for
the new local session contract and audio/presentation regressions. Procedural
first-pass sounds and automatic checks do not certify human listening polish.

## Implemented behavior and evidence

- `GameplayLoopBank` generates five cached, deterministic, two-second mono PCM
  loops with periodic seams and bounded peaks. The controller prewarms them
  before combat, avoiding waveform generation during active play.
- `ContinuousGameplayAudio` keeps two reusable three-voice spatial rigs and one
  arena player. Undriven airborne falling does not fabricate motor sound.
  Duplicate/invalid/eliminated/missing/stale records silence their sources.
  Announcements duck only the arena player's gain; user volume buses are intact.
- `MvpSession.audio_views()` and the composed game implement the source and
  lifecycle boundary above. The wire protocol/build remain unchanged, as do
  B's runtime, assets and input configuration.
- Independent PCM and controller tests pass, covering cache, bounds, DC/seams,
  voice reuse/caps, family semantics, spatial placement, expiry and duck restore.
- `audio_session_test.gd` passes over real two-peer ENet: client local audio
  uses accepted server state despite deliberately divergent prediction; missing
  baselines and wrong epochs are excluded. Practice supplies its unadmitted
  target metadata, pending resets are neutral and returned records are detached.
- `continuous_audio_game_test.gd` passes actual practice composition, public
  drive commands, warning ducking, menu/settings/restart/recovery/leave. Its
  first run exposed competing headless keyboard sampling in the fixture; the
  corrected fixture disables only that sampler while submitting commands and
  preserves its sequence counter. Production controls were not changed.
- `tools/check-baseline.ps1` passes with pinned Godot 4.7.2 stable / Jolt.
- Full `tests/presentation/check-presentation.ps1` passes, including the four
  new audio checks and existing settings/music/practice/HUD/menu/real-session
  reconnect/results/rematch checks. Exit zero with final presentation PASS;
  no script errors or native crash signatures. Some fixtures still report
  two-to-seven ObjectDB instances at exit; cleanup warnings remain unresolved.
  The separate intermittent Windows native shutdown issue is not claimed fixed.
- Independent read-only review found no blocking correctness or ownership
  issues. Diff checks pass; completed increment merges to shared main directly.

Remaining scope: human listening/mix polish, material-specific spatial impacts,
weapon-ready, armor-break and crowd cues. This is continuous first-pass audio,
not completion of all spec audio or external hosted acceptance.
