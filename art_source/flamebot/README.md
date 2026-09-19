# Flamebot 07 — Blender art handoff

Owner: Developer B. Branch: `codex/b-flamebot-art`. Base: `origin/main` / `60feafe`.

Original 3D interpretation of the user's supplied red four-wheel robot reference:
segmented front wedge, armored flamethrower tower, perforated heat shield,
six-barrel minigun, fuel canister, hoses, flame insignia and 07 markings.
The reference's printed triangle/texture counts were not treated as requirements.

## Deliverables

- `flamebot_07.blend`: editable Blender 5.2.1 source with packed textures, seven
  moving mesh assemblies, studio lighting and a framed hero camera.
- `../../battlebots/assets/models/flamebot/flamebot_07.glb`: runtime art with
  embedded PBR color textures; studio floor, cameras and lights are excluded.
- `flamebot_07_hero.png` and `flamebot_07_rear.png`: inspected front/rear renders.
- `build_flamebot.py`: deterministic rebuild; individual panels, tires, fasteners,
  hoses and weapons can be edited in its construction parameters. The saved
  Blender meshes are consolidated per assembly but remain editable in Edit Mode.
- `asset_stats.json`: measured full-detail geometry and dimensions.

## Integration

31,788 triangles, seven mesh objects. Eight surface materials (four packed 512px
color maps plus four plain materials); metallic/roughness values are authored.
Godot's committed import settings enable generated mesh LODs and shadow meshes.
Hand-authored LODs and a consolidated texture atlas remain future optimization.

Meters. Blender +Z up / +Y forward exports to Godot +Y up / -Z forward.
Overall envelope including wheels, wedge and antenna is approximately
2.088 m wide, 2.373 m long, 2.043 m tall. Root origin is near ground center;
tread corners extend 0.014 m below zero. The hull is 1.38 m wide.

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

Blender rebuilt and saved the source and GLB successfully. Front/rear Cycles
renders inspected. Godot 4.7.2 stable imported the GLB; `check-baseline.ps1`
passed. `check_flamebot.gd` checks seven assemblies, preserved pivots, imported
materials, meter scale, Y-up/-Z-forward and absence of physics/studio nodes.

Rebuild from repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python art_source/flamebot/build_flamebot.py
& ./tools/check-baseline.ps1 -GodotPath '<Godot 4.7.2 executable>'
& '<Godot 4.7.2 executable>' --headless --path battlebots --script ../art_source/flamebot/check_flamebot.gd
```

Gameplay installation and ten-bot performance are untested. Avoid editing this
asset folder concurrently until the art branch is merged. Existing A-owned menu
edits in the original checkout were left untouched.
