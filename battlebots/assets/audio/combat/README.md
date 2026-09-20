# Supplied combat recordings

User-supplied on 20 September 2026. Mapping follows the source filenames:

- `source/metal_collision.mp3`: `two_heavy_metal_cars_#3-1789930881672.mp3`.
  `metal_collision.wav` plays once at a confirmed ram contact position.
- `source/hammer_crash.mp3`: `Massive,_earth-shatt_#1-1789936763566.mp3`.
  The user's later "hammer smash noise" replaces the earlier hammer recording.
  `hammer_crash.wav` plays once at a confirmed hammer hit position.
- `source/scorpion_footfall.mp3`: `one_gigantic_massive_#3-1789937147181.mp3`.
  `scorpion_footfall.wav` accompanies a completed Scorpion leg plant on terrain.
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
Hammer: retain 0.325–1.500 s, same fades, peak 0.70. The runtime is 1.175 s
(56,400 frames), RMS -11.33 dBFS. Removing the quiet precursor aligns the main
smash within 15 ms of confirmed contact while preserving the strong body and
remaining recorded decay. The denser supplied recording retains the existing
peak headroom; impact timing, priority, voice gain and spatial routing are unchanged.
Footfall: retain 0.660–1.160 s, same fades, peak 0.60. The runtime is 0.500 s
(24,000 frames), RMS -13.78 dBFS. Remove the long quiet lead and diffuse late
noise; retain the heavy plant, body and a short decay. Each Scorpion has two
reusable spatial voices at -9 dB on BBEffects. A tripod landing emits one sound
at the mean contact position, avoiding three copies stacked at each plant.
Only completed, displaced steps with a real terrain collider play; parked feet,
garage previews, reset/teleport/recovery baselines and eliminated bots are silent.
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

SHA-256 (original supplied bytes and reproducible runtime adaptations):

- Hammer MP3: `a4b815b518eb7e8342611fb4e300e11f74df459dad51ea36c25615de64106137`
- Hammer WAV: `c7367ad2464ba479c75aef800837cc7ee58a7b2bcdf02d2da97e9ac75c558efb`
- Footfall MP3: `ed2882a1ef0a4266412904bf046381bf615488b1e1d329098361ce49ca3d9ff3`
- Footfall WAV: `39763ad8d6bb7a28779730d3f9916682c1feabde258ae1f5bfde2a133e134abe`
