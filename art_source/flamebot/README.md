# Flamebot 07 — Blender art handoff

Owner: Developer B. Branch: `codex/b-flamebot-art`. Base: `origin/main` / `60feafe`.

Revised 3D interpretation of the user's supplied red four-wheel robot reference:
low faceted hull, continuous angled hood and a solid full-width protective plow,
tapered turret and canted cheek armor, external flamethrower mantlet, perforated
heat shield, six-barrel minigun, fuel canister, hoses, flame insignia and 07 markings.
The plow has closed wing volumes that fold backward in top view and rise in
front of the tires. The outer cutting edge extends beyond the tire width; this
replaces the earlier flat triangular fins, which did not defend the wheels.
The reference's printed triangle/texture counts were not treated as requirements.

## Deliverables

- `flamebot_07.blend`: editable Blender 5.2.1 source with packed textures,
  individually editable mechanical parts under seven moving assembly pivots, studio
  lighting and a framed hero camera. Only the exported GLB consolidates meshes.
- `../../battlebots/assets/models/flamebot/flamebot_07.glb`: runtime art with
  embedded PBR color textures; studio floor, cameras and lights are excluded.
- `flamebot_07_hero.png`, `flamebot_07_rear.png`, `flamebot_07_side.png` and
  `flamebot_07_front.png`, `flamebot_07_top.png`: beauty renders and orthographic checks.
- `flamebot_07_texture_detail.png`: close-up for inspecting paint wear and metal relief.
- `build_flamebot.py`: deterministic rebuild; individual panels, tires, fasteners,
  hoses and weapons can be edited in `geometry_v2.py` or directly in the blend.
- `asset_stats.json`: measured full-detail geometry and dimensions.

## Integration

See `asset_stats.json` for measured triangle count and editable component count.
The GLB has seven mesh objects and nine surface materials. Main armor has a 4096px
color map and 2048px roughness/metallic and tangent-space normal maps. Supporting
red paint, ochre paint and two steel finishes each use 2048px PBR maps. The worn
stencil color map is 1024px; lettering, rubber and bronze reuse the steel normal
map at reduced strength. All maps are packed in the Blender source and GLB.
Paint is a rough dielectric coating (roughness .91/.92,
metallic .025); chipped areas reveal rough bare steel. Packed texture masks drive
color, roughness, metal exposure, pitting and scratches together. Raised chip
stickers were removed. Matte steel, rubber and heat-stained metal have distinct
PBR values. Jagged chips expose steel beneath darker primer borders; directional
scuffs and scanned abrasion, corrosion and paint relief replace the previous
blurred noise. Thirteen main armor surfaces have per-face UV projections to
preserve texture resolution and place edge wear along panel borders. The finish
remains matte, with roughness variation rather than a clear glossy coat.
`surface_materials.py` authors these maps reproducibly using the bundled CC0 maps
credited in [reference_textures/CREDITS.md](reference_textures/CREDITS.md).
`refresh_textures.py` updates materials and UVs on an existing source file while
asserting an identical hash of all approved vertices, faces and world transforms.
Godot's committed import settings enable generated mesh LODs and shadow meshes.
Hand-authored LODs and a consolidated texture atlas remain future optimization.
This revision prioritizes the user's requested mechanical detail; its full-detail
mesh is above the original 20k–40k provisional target. Profile or make a separate
optimized gameplay LOD before placing ten full-detail copies in a match.

Meters. Blender +Z up / +Y forward exports to Godot +Y up / -Z forward.
See `asset_stats.json` for the overall envelope. Root origin is at ground center.
Wheel centers are X +/-0.93, Y +/-approximately 0.64, Z 0.42 in Blender. The main
hull is approximately 1.32 m wide, leaving space to the widened wheel stance.

Mount the imported scene beneath the simulation's presentation root after
accounting for its existing body-to-ground offset. It contains no colliders,
damage code, gameplay stats, animation clips, scripts or networking.

- `Chassis`: fixed hull and front armor.
- `TurretYaw`: tower, flamer, tank and minigun mount. Animate local Godot Y.
- `TurretYaw/MinigunSpin`: barrel cluster. Animate local Godot Z.
- `WheelLeftFront`, `WheelLeftRear`, `WheelRightFront`, `WheelRightRear`:
  centered wheel pivots. Animate local Godot X. Left/right labels follow
  Blender X sign; all four pivots are direct children of the asset root.

No shared API or runtime assembly was changed. Developer A must decide mounting,
collision envelopes and weapon rules before making this bot playable. The game
spec currently excludes ranged weapons; this requested art does not amend that
rule or implement either weapon.

## Validation

Blender rebuilt and saved the source and GLB successfully. Front/rear/side/top Cycles
renders and a 2400px material close-up inspected. The texture-only iteration
preserves the approved solid plow and all other geometry: before/after geometry
SHA-256 values match in `texture_validation.json`, which also records packed map
dimensions. The geometry builder asserts positive wheel/hull, tread/arch,
plow overhang/fold and external flamer-mount/tower clearances; measurements are
recorded in `asset_stats.json`. `check_geometry.py` additionally inspects actual
saved world-space tire meshes against armor with BVH surface intersection tests,
checks wheel extents and measures the external flamer boss's clearance. It also
casts 24 frontal rays toward the tire area to require interception by the solid
shields, verifies a backward sweep of the outer plow corners in top view, and
checks matte paint and normal maps. Results
are recorded in `geometry_validation.json`. Godot 4.7.2 stable imported the GLB; `check-baseline.ps1`
passed. `check_flamebot.gd` checks seven assemblies, preserved pivots, imported
materials including imported grit normal maps, widened wheel pivot positions,
meter scale, Y-up/-Z-forward and absence
of physics/studio nodes. These are static rest-pose checks, not a full animated
swept-clearance or runtime combat validation.

Rebuild from repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python art_source/flamebot/build_flamebot.py
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background art_source/flamebot/flamebot_07.blend --python art_source/flamebot/check_geometry.py
& ./tools/check-baseline.ps1 -GodotPath '<Godot 4.7.2 executable>'
& '<Godot 4.7.2 executable>' --headless --path battlebots --script ../art_source/flamebot/check_flamebot.gd
```

Gameplay installation and ten-bot performance are untested. Avoid editing this
asset folder concurrently until the art branch is merged. Existing A-owned menu
edits in the original checkout were left untouched.
