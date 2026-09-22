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
preserve primer and exposed steel. Repeated shoes use eight shared geometry/UV
variants to vary the visible wear; connectors share geometry and atlas coordinates.
No external texture libraries are required.

Geometry helpers use Godot meters, Y up and -Z forward. Blender export performs
the axis conversion. Runtime applies the shared factor three once. The chassis
has forty independent tread shoes and forty connector frames per side, twelve
wheel pivots and eleven named mounts. Attachment positions, wheel radii and the
capsule track path are in the manifest.
The lifter GLB uses its existing animated mechanism's local frame, preserving
canonical attack/contact dimensions.

The fifth geometry candidate has 159,877 base triangles, with automatic Godot LOD generation.
This exceeds the older provisional 20k-40k whole-bot target; do not describe that
target as met. Individually shared tread geometry reduces asset size but does
not reduce visible triangle or draw counts. See the coordination record for
native measurements and their hardware/scope limitations.

Optional side/top/front/rear armor and three exhaust packages are separate groups.
They export with the chassis and are selected by the garage at runtime. Studio
base views hide these options and the separate lifter. All existing bots remain.

Inspect the actual Godot import with `res://tests/presentation/atlas_showcase.tscn`.
It captures the bare chassis, assembled Foundry practice bot and actual garage.
The user approved the cohesive compact V5 design on 22 September 2026.

The compact fifth candidate joins the deck, folded shoulders, front glacis,
lower apron, side skirts and rear closure into a cohesive armored shell. Narrow
seams have structural backing. Corner sockets are centered on the shoulders;
deck rails, service hatches and cooling openings are recessed. Side skirts have
real frame brackets, hinges and louvers. Single-layer slate-grey shoes have two
visible articulated connecting strips per gap. The drive backbone and swing
arms sit inboard of the tires. The source construction lives in
`atlas_front_shell.py`, `atlas_deck_shell.py` and `atlas_armor_shell.py` beside
the generator.

The final material system replaces constant bright painted edges and repeated scratch
maps with geometry-aware enamel wear, exposed metal, primer and local occlusion.
Thin edge chamfers are independent of larger cast corner rounds. Rounded machined
hubs and button fasteners have actual recessed hex sockets; washers seat against
their supporting surfaces. The detail views expose the mounts, running gear and
side armor. Track chamfers have intermittent polished patches instead of a
uniform bright outline. Final baseline, native assembly, material and sampled-motion
checks pass; see [final evidence](../../docs/coordination/B_ATLAS_MX.md).

The full reusable workflow, failed approaches and implementation lessons are in
[the industrial asset guide](../../docs/art/STYLIZED_INDUSTRIAL_ASSETS.md).
[Preserved references and approved captures](references/README.md) anchor future reviews.
Regeneration resets manifest approval because the new artifact needs its own review.
