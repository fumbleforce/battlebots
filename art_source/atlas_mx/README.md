# Atlas MX

Original modular tracked chassis built for the supplied visual reference.
Editable source: `atlas_mx.blend`. Reproducible authoring: `tools/build-atlas.py`.
This is a real 3D asset; review PNGs are renders of that source.

Rebuild with Blender 5.2:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/build-atlas.py
```

Add `-- --quick` for the 32-sample hero only. The full build writes five 1600x1200
Cycles views, source with packed textures, runtime chassis and lifter GLBs, shared
1024px base/metallic-roughness/normal maps, and `atlas_manifest.json`.

Geometry helpers use Godot meters, Y up and -Z forward. Blender export performs
the axis conversion. Runtime applies the shared factor three once. The chassis
has forty independent tread shoes per side, twelve wheel pivots and seven named
mounts. Attachment positions and the capsule track path are in the manifest.
The lifter GLB uses its existing animated mechanism's local frame, preserving
canonical attack/contact dimensions.

The base has approximately 71,455 triangles, with automatic Godot LOD generation.
This exceeds the older provisional 20k-40k whole-bot target; do not describe that
target as met. Individually shared tread geometry reduces asset size but does
not reduce visible triangle or draw counts. See the coordination record for
native measurements and their hardware/scope limitations.

Optional side/top/front/rear armor and three exhaust packages are separate groups.
They export with the chassis and are selected by the garage at runtime. Studio
base views hide these options and the separate lifter. All existing bots remain.

Inspect the actual Godot import with `res://tests/presentation/atlas_showcase.tscn`.
It captures the bare chassis, assembled Foundry practice bot and actual garage.
Visual acceptance remains subject to explicit user approval.
