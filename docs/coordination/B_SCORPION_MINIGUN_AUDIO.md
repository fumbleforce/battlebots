# Minigun presentation audio handoff

`MinigunEffects` now owns a `MinigunWeaponAudio` child for both primary guns and
the Scorpion's auxiliary gun. This is weapon presentation only: authoritative
cadence, damage, resource costs, snapshots and A's general audio pools are
unchanged.

Four reusable spatial one-shot voices play a designed 24 kHz mono PCM report
(powder crack, chamber body, bolt/carrier transient). A fifth spatial voice
plays a seamless motor/gear loop whose pitch and gain follow accepted spool.
Both use the existing `BBEffects` bus, world positions, distance attenuation
and existing user volume settings. There is no client-generated shot or hit.

Only a fresh accepted shot-sequence advance can play a report; batched history
produces at most the current fresh report, with a short voice-rate bound.
Initial snapshots, old shot ticks, rollback, elimination, reset and preview
views do not play historical reports. A frozen accepted tick stops the motor
after 0.25 seconds. Primary and auxiliary spool fields use the same sound path.

The node registers in `bot_action_audio` and exposes
`set_playback_enabled(bool)`. A's narrow MenuGame integration supplies the same
active-match/visible-HUD gate already used by continuous gameplay audio.
Disabling stops all five voices. Re-enabling requires a fresh observation
baseline, so menu-time shots are not replayed. Standalone fixtures default to
enabled. `clear_effects()` resets sound together with flash/tracers/casings;
Scorpion's explicit round reset already calls it.

Native acceptance is `res://tests/audio/minigun_audio_test.tscn` with pinned
Godot 4.7.2 and an actual audio device. The test drives the real authoritative
Scorpion auxiliary gun, captures native stereo audio downstream of the Effects
gain, checks pan and distance falloff, effects-volume zero, bounded players,
generic primary presentation, stale/rollback/reset/elimination behavior and
menu gating/resume. The first native run passed with firing energy 4.00,
left/right channel energies 1.55/0.63 and 0.62/1.52, and near/far total energy
10.06/0.007. The final native run also passed menu gating/resume checks; its log
is `%TEMP%/scorpion-minigun-audio-gated.log`. A seven-Texture-RID shutdown warning also
appears in this full-bot native fixture; no script or shader errors occurred.

Diesel's independent native lifecycle fixture is
`res://tests/presentation/scorpion_diesel_test.tscn`. Its inspected captures show
thick rolling charcoal smoke trailing behind 16.49 m of actual Jolt walking,
sparse idle exhaust, shutdown residual smoke, and a clear view after dissipation.
The two stack emitters use imported outlet transforms and a fixed maximum of
256 sprites per bot (1024 for four), with 3.6-second lifetime. No network or
combat contract is required for diesel; load derives from accepted presentation
motion. Native captures are in `battlebots/exports/scorpion-diesel/` and remain
untracked review artifacts.
