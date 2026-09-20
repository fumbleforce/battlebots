# Scorpion supplied hammer and footfall recordings

User-authorized narrow A-audio handoff, 20 September 2026. The Scorpion request
now explicitly includes `Massive,_earth-shatt_#1-1789936763566.mp3` as the hammer
smash and `one_gigantic_massive_#3-1789937147181.mp3` as the footfall. B integrates
those two assets and Scorpion leg synchronization after rebasing onto A's sampled
audio implementation on main `32341d1`; other A recordings/banks remain intact.

The replacement hammer uses the existing `impact_hammer` path and confirmed
combat-event playback. No command, damage, event timing, positional routing,
priority, gain, pool, preference or caption rules change. Its trimmed strong
transient starts within 15 ms, with the remaining recorded body/decay preserved.

The Scorpion-only gait adapter detects actual completed displaced leg steps on a
valid terrain collider. All three feet in a landing tripod share one recording
at their mean contact position. Two pooled spatial voices per Scorpion have a
fixed -9 dB gain on BBEffects; a short event gate prevents burst stacking.
Presentation supplies the same behavior for local and remote Scorpion models.
No authoritative contact/damage or network contract is introduced for footsteps.
The composed MenuGame uses its existing combat-HUD/active-phase visibility gate
for weapon-owned minigun and gait audio too. Opening menus/settings/recovery or
results silences these voices; returning establishes a fresh observation baseline
instead of replaying queued footsteps or old reports. Existing A voice pools
are unchanged.

Garage previews have no terrain and remain silent. Foot resets stop pending
voices and establish a 350 ms quiet baseline; actual state observation resets
on first baseline, tick rollback, elimination and recovery edges. Teleport and
invalid-orientation resets use the existing foot solver's reset path. MvpBot's
round reset calls ScorpionVisual.reset_observation, covering a restart at the
same position as well as distant teleports. Leaving frees voices with the bot.
Pure vertical suspension settling never counts as a displaced step.
Footfall and minigun-owned voices also join the `bot_action_audio` group. The
normal menu-game visibility gate stops and rebaselines them under menus,
settings and the recovery screen, then admits fresh action on gameplay resume.

Source provenance, trim windows, format, levels and hashes are recorded in
`battlebots/assets/audio/combat/README.md`; `tools/prepare-combat-audio.py`
reproduces all four runtime samples. Original MP3 bytes are preserved. The
existing ram and saw generated files are byte-identical after regeneration.

The existing practice audio-record fixtures now expect the player and three
NPCs. Their two-player ENet expectations and bounded-pool tests remain intact.
ContinuousGameplayAudio deliberately retains its existing two-bot pool and
weapon-family filter. Practice publishes four records, but that legacy loop
consumer still chooses at most two supported bots; new Scorpion footsteps are
independent. Expanding generic NPC/minigun motor loops remains an A-audio handoff.

Validation with Godot 4.7.2.stable.official.ed1daf0bf:

- `gameplay_audio_test.gd`: PASS; private recorded hammer stream, 1.175 s duration,
  strong onset within 30 ms, preserved last-quarter-second energy, PCM peak,
  quiet endpoints and existing confirmed-event deduplication/voice cap behavior.
- `audio_session_test.gd`: PASS; four practice records and actual two-player
  ENet accepted-state sourcing/reconnect safeguards.
- `continuous_audio_game_test.gd`: headless and native D3D12 PASS; four practice
  records feed the unchanged two-bot loop pool. The native Scorpion portion
  verifies actual drive/accepted gun commands produce owned sounds, then tests
  the group gate and stopped voices under menus/settings/recovery, fresh resume,
  restart and freed audio nodes on leaving. This caught and fixed the recovery
  early-return path that initially bypassed the action-audio visibility gate.
- `scorpion_footfall_test.tscn`: native D3D12 PASS. Real commanded Jolt walking
  produced captured stereo energy (21.58, 21.47); positioned recordings gave
  left (52.08, 21.05) and right (21.05, 52.08). Effects volume zero produced
  silence at the downstream Master capture. Three grounded landing contacts
  combine into one cue, with non-contact feet excluded. Initial/idle, lifted-step
  restart, same-position restart, teleport and terrain-disabled movement remain
  silent; leaving releases the two voices. The native run reports a
  seven-Texture-RID shutdown warning, with exit 0 and no script/shader errors.
- `spatial_impact_audio_test.gd`: native D3D12 PASS for the new hammer; left/right
  dominant channel captures and near/far energy verify actual spatial playback.
- Editor import exited 0; footfall metadata explicitly preserves PCM16.
- Native movie `exports/evidence/scorpion-practice-review.mp4` is 11.533 s,
  1920x1080 at 60 fps with 48 kHz stereo AAC; source AVI remains alongside it.
  Normal commands walked into reach, pressed primary against the untouched
  300-core Bulwark at frame 132, and produced a confirmed 36-damage hammer hit
  at frame 152. Forty-seven accepted gun shots then completed natural destruction
  at frame 595 (48 total accepted hits). No health, pose or stats overrides were
  used. The supplied hammer waveform matches the native movie audio with 0.983
  normalized correlation at 2.540 s, confirming actual event-driven playback.
  The final destruction PNG and walking still were visually inspected; the
  entire Scorpion tail and feet remain in frame, with smoke and detached chunks.

No hosted deployment or human listening acceptance is implied by mixer capture
tests. No combat damage, cooldown, movement or scoring changes were needed.
