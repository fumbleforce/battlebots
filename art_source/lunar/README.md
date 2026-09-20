# Original Selene environment kit

All new meshes and material maps are authored by `art_source/lunar/build.py` in
Blender 5.2. No purchased or downloaded assets. Eight individually fractured rock
meshes and an editable service-bay assembly are retained in `lunar_kit.blend`.
The bay includes beveled structural panels, recessed airlock, mullioned glazing,
tanks and straps, pipe manifolds, HVAC/louvers, grating, stairs, rails and gantry.
Four original 2048² material sets contain color, normal and packed relief maps
(R occlusion, G roughness, B height). Runtime imports use mipmaps and compression.
The earlier generated Moon regolith/Earth maps retain their existing provenance.

## Rebuild

1. Run Blender in background with `--python art_source/lunar/build.py` from repo root.
2. Import the Godot project using pinned 4.7.2; generated GLBs use mesh LOD imports.
3. Run Godot with `--headless --path battlebots --script res://tools/prepare_lunar_bake.gd`.
   This creates a standalone scene with unique lightmap UVs and explicit receivers.
4. Open `assets/models/lunar/baked_service_bay.tscn` in the Godot editor, select
   IndirectLight and Bake Lightmaps, then save. Keep its `.lmbake`, `.exr` and import
   metadata. Runtime removes the bake reference sun and uses the arena's sun.
5. Run `tools/check-lunar-cinematic.ps1` with the pinned engine path.

The committed bake has three indirect bounces, medium quality, 0.12m UV texels,
a 2048 atlas cap and dynamic direct sunlight. Receiver paths are validated by
`lunar_asset_test.gd`. Each service bay instances the same baked local kit; its
indirect treatment rotates with the module. Direct shadows remain world-correct.

Procedural dressing is deterministically seeded. Rock batches are divided into
octants for culling. Tiny visual pebbles, fog, particles and track marks never
create authoritative collisions. The play surface itself is unchanged.
