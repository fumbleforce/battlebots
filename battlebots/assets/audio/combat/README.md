# Supplied combat recordings

User-supplied on 20 September 2026. Mapping follows the source filenames:

- `source/metal_collision.mp3`: `two_heavy_metal_cars_#3-1789930881672.mp3`.
  `metal_collision.wav` plays once at a confirmed ram contact position.
- `source/hammer_crash.mp3`: `huge_hammer_crashing_#4-1789930938003.mp3`.
  `hammer_crash.wav` plays once at a confirmed hammer hit position.
- `source/heavy_saw.mp3`: `heavy_saw_continuous_#1-1789930233585.mp3`.
  `heavy_saw_loop.wav` follows a powered saw's accepted position/state.

Original MP3 bytes are preserved under `source/`, excluded from Godot import by
`.gdignore`. Rebuild the runtime WAV files from the repository root with
`python tools/prepare-combat-audio.py` (Python standard library and ffmpeg).

Decode to floating-point mono before reducing gain: the supplied MP3s decode
above full scale, so converting directly to PCM16 would clip. Runtime files use
mono 48 kHz PCM16 for positional playback. All user Effects/Master/mute settings
continue to apply.

Collision: retain 0–0.80 s, 1 ms attack/35 ms tail fade, peak 0.65.
Hammer: retain 0–0.90 s, same fades, peak 0.70.
Saw: retain 0.18–1.32 s of the sustained body, join tail/head with an 80 ms
equal-power crossfade, rotate the result to an adjacent-source-sample seam,
remove DC and scale to peak 0.30. The final loop is 1.06 s (50,880 frames).
The sound bank enables its full-length forward loop on a private resource.

Saw playback stays at pitch 1.0 instead of the procedural rotor's former 1.5.
Its -14 dB voice gain compensates the sample's lower RMS while retaining the
existing spatial attenuation and cap. Spinners retain their charge-driven pitch.
Impact voices remain pooled and event-driven; the saw does not restart each
frame or on each damage tick, and stops on power loss, stale/eliminated state,
menus, recovery and leaving. Other sounds and battle music retain their roles.
