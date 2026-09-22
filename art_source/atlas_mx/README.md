# Atlas MX

Original modular tracked chassis built for the supplied visual reference.
Editable source: `atlas_mx.blend`. Reproducible authoring: `tools/build-atlas.py`.
This is a real 3D asset; review PNGs are renders of that source.

Rebuild with Blender 5.2:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python tools/build-atlas.py
```

Add `-- --quick` for a reduced-resolution bake and 32-sample hero in the isolated
`battlebots/exports/atlas-source-preview` directory. It leaves production assets
untouched. The full build writes seven 1600x1200 Cycles views, source with packed
textures, runtime chassis and lifter GLBs, and `atlas_manifest.json`.

`tools/atlas_surface_bake.py` unwraps unique geometry into four material atlases:
4096px primary enamel and hardware, plus 2048px secondary enamel and track steel.
Each exports base color, packed occlusion/roughness/metallic and tangent normals.
Both enamel families also export explicit paint coverage masks so garage recolors
preserve primer and exposed steel. Repeated shoes and connectors share geometry
and atlas coordinates. No external texture libraries are required.

Geometry helpers use Godot meters, Y up and -Z forward. Blender export performs
the axis conversion. Runtime applies the shared factor three once. The chassis
has forty independent tread shoes and forty connector frames per side, twelve
wheel pivots and eleven named mounts. Attachment positions, wheel radii and the
capsule track path are in the manifest.
The lifter GLB uses its existing animated mechanism's local frame, preserving
canonical attack/contact dimensions.

The fourth geometry candidate has 155,467 base triangles, with automatic Godot LOD generation.
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

The third review candidate centers each corner socket on a shorter supported
fender, without black corner overplates. Single-layer slate-grey shoes have two
visible articulated connecting strips per gap. The side casting, gasket and steel
carrier share a profile that clears the smaller lower rollers and narrower return
wheel. The drive backbone and swing arms sit inboard of the tires.

The fourth candidate replaces constant bright painted edges and repeated scratch
maps with geometry-aware enamel wear, exposed metal, primer and local occlusion.
Thin edge chamfers are independent of larger cast corner rounds. Rounded machined
hubs and button fasteners have actual recessed hex sockets; washers seat against
their supporting surfaces. The detail views expose the mounts, running gear and
side casting. Explicit user visual approval remains outstanding.
