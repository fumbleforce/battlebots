"""Remove the photographed sun from the Woodland HDRI sky.

Run: blender --background --python art_source/woodland/prepare_sky.py -- <source.hdr>
Writes battlebots/assets/textures/woodland/woodland_sky_4k.hdr.

The arena's DirectionalLight3D is the sun. Leaving the HDRI's sun disc (peak
~1.3e5) in the panorama makes Godot's sky ambient and radiance reflections count
it a second time, which washes every surface out. Pixels are soft-clamped to a
bright-cloud level, so the sun area stays a visible glow without its energy.
"""
import bpy, sys, pathlib, numpy as np
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "battlebots/assets/textures/woodland/woodland_sky_4k.hdr"
source = sys.argv[sys.argv.index("--") + 1]
CEILING = 6.0
image = bpy.data.images.load(source)
px = np.array(image.pixels[:], dtype=np.float32).reshape(-1, 4)
rgb = px[:, :3]
peak = rgb.max(axis=1, keepdims=True)
# Smoothly compress anything above 2.0 toward CEILING, preserving hue.
over = np.maximum(peak - 2.0, 0.0)
target = 2.0 + (CEILING - 2.0) * (1.0 - np.exp(-over / (CEILING - 2.0)))
scale = np.where(peak > 2.0, target / np.maximum(peak, 1e-6), 1.0)
px[:, :3] = rgb * scale
image.pixels.foreach_set(px.ravel())
image.filepath_raw = str(OUT)
image.file_format = "HDR"
image.save()
print("SKY peak before", float(peak.max()), "after", float((rgb * scale).max()))
