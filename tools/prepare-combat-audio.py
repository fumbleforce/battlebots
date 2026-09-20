"""Build spatial combat WAVs from the supplied recordings. Requires ffmpeg on PATH."""

import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[1] / "battlebots/assets/audio/combat"
RATE = 48000


def decode(name):
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(ROOT / "source" / name),
         "-map", "0:a:0", "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
        check=True, capture_output=True,
    ).stdout
    samples = array.array("f", raw)
    if sys.byteorder != "little":
        samples.byteswap()
    if not samples or not all(math.isfinite(value) for value in samples):
        raise ValueError(f"Invalid decoded samples: {name}")
    return list(samples)


def remove_dc(samples):
    mean = sum(samples) / len(samples)
    return [value - mean for value in samples]


def impact(name, end, start=0.0):
    # Align the selected strike with contact, retaining its useful recorded decay.
    samples = remove_dc(decode(name)[round(start * RATE):round(end * RATE)])
    attack, release = round(0.001 * RATE), round(0.035 * RATE)
    for index in range(attack):
        samples[index] *= index / (attack - 1)
    for index in range(release):
        samples[-release + index] *= 1.0 - index / (release - 1)
    return samples


def saw_loop():
    # Use the sustained body, excluding the recording's softer start/end.
    samples = decode("heavy_saw.mp3")[round(0.18 * RATE):round(1.32 * RATE)]
    overlap = round(0.08 * RATE)
    # The crossfade joins the tail to the head; rotating the middle to the front
    # puts the file seam on two adjacent source samples, not an arbitrary splice.
    blend = []
    for index in range(overlap):
        phase = index / (overlap - 1) * math.pi / 2
        blend.append(samples[-overlap + index] * math.cos(phase)
                     + samples[index] * math.sin(phase))
    return remove_dc(samples[overlap:-overlap] + blend)


def write(name, samples, peak):
    gain = peak / max(abs(value) for value in samples)
    pcm = array.array("h", (round(value * gain * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = ROOT / name
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())
    rms = math.sqrt(sum((value * gain) ** 2 for value in samples) / len(samples))
    print(json.dumps({"file": name, "seconds": len(samples) / RATE,
                      "peak": peak, "rms_db": round(20 * math.log10(rms), 2),
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}))


if __name__ == "__main__":
    write("metal_collision.wav", impact("metal_collision.mp3", 0.80), 0.65)
    write("hammer_crash.wav", impact("hammer_crash.mp3", 1.50, 0.325), 0.70)
    write("scorpion_footfall.wav", impact("scorpion_footfall.mp3", 1.16, 0.66), 0.60)
    write("heavy_saw_loop.wav", saw_loop(), 0.30)
