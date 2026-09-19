# Sawblade Tank — reference-focused Blender asset

Developer B / `codex/b-sawblade-tank`.
Reference: user-supplied `SawbladeTank2_ps3.png` (not redistributed).

Open `sawblade_tank.blend` in Blender 4.0 or newer and press Space in the 3D view.
The source includes a studio camera and lighting, with the neutral surface texture packed.

## Modular controls

Select `SawbladeTank_ROOT`, open **Object Properties → Custom Properties**, and
change these integer selectors. Hover over each property for its choices.
Changes update both viewport and rendered visibility. All alternatives are
already modeled and included in the file.

| Property | Choices |
| --- | --- |
| `weapon` | 0 Saw, 1 Hammer, 2 Full-width ramp |
| `drive` | 0 Tracks, 1 Four wheels |
| `armor_side` | 0 None, 1 Reference covers, 2 Heavy skirts and over-wheel fenders |
| `armor_top` | 0 None, 1 Machinery roof guard |
| `armor_front` | 0 None, 1 Front chin plate |
| `armor_rear` | 0 None, 1 Rear pack armor |
| `exhaust` | 0 None, 1 Small single, 2 Medium twin, 3 Large twin |

The default is the reference-style saw/tracks with side covers. Every module has
its own collection and root, parented to one of seven named `Socket_*` mounts.
Module roots have zero local translation at their sockets. The hammer also has
a separate `Hammer_SWING_X` pivot and a baked `hammer_attack` animation.

Four `paint_*` color swatches on the same root control **primary paint, secondary
paint, bare metal and rubber**, across every module. Wear is stored in a neutral
grayscale texture, so changing the paint does not leave yellow/brown patches.
The material relation is `base_color = palette_color * (2 * surface_texture.r)`;
surface groups retain their authored metallic and roughness values.

`module_manifest.json` records module IDs, origins, socket positions, choices,
material palette channels and the shader formula for a future game adapter.
Measured triangle counts for the default assembly and all 13 alternatives are
recorded in `module_manifest.json` and `validation.json`. Inactive modules are hidden in both
the viewport and rendering.

## Current revision

The user explicitly retired the previous PS3 polygon/texture restrictions in
favor of closer reference fidelity. No geometry decimation or triangle cap is
applied. A 4096 × 4096 grayscale atlas replaces the original 1024 color texture; the measured
triangle count is recorded in `validation.json` and the Blender scene properties.

- Rebuilt the thin upright housing as a deep, chamfered counterweight pack:
  1.10 m wide, 0.88 m deep and 1.04 m tall, with a small top carry handle.
- Authored broad vertical black bands and paired diagonal branches on the pack
  faces, following the reference instead of evenly repeated caution stripes.
- Lowered the chassis into a steel belly pan, exposed longitudinal rails and
  crossmembers. Added a central transmission, finned motor and manifold hoses.
- Reworked the paired rams into rectangular yellow hydraulic jackets, exposed
  polished pistons, inclined upper linkages, clevises and mounting gussets.
- Replaced rectangular side covers with tapered plates and twin vent slots.
- Changed the track silhouette to a larger front drive wheel and smaller rear
  idler, with an inclined upper run. Treads remain flat single-piece plates.
- Replaced broad camouflage patches with smaller block-shaped paint wear.
- Retained the sharpened, double-beveled saw and swept carbide teeth.

## Hammer attack and connected mechanisms

Select **weapon = 1** and play frames **1-33 at 30 FPS**. The named NLA track
`hammer_attack` coordinates the hinge and four actuator transform actions. It
plays once, holds contact at frames 9-12, returns by frame 33, and then holds
ready. The scene still spans 120 frames for the independent saw/drive loops.
Reset to frame 1 to replay the hammer. The clip duration is 32/30 seconds;
impact is 8/30 seconds after its start. The 33-frame preview includes both endpoints.

The exact -69.002609 degree hinge rotation is derived from the head-center offset
and striking-face depth. The entire head, straps and face are pre-aligned together.
`Hammer_Impact` marks the center of the contact plane; the frame-9 timeline marker
is presentation metadata only. Neither applies damage or triggers game input.

Paired fixed chassis clevises at (+/-0.35, -0.32, 0.745) connect cylinders to
cranks below/ahead of the hinge. Barrels pivot and rods telescope, with their
transforms baked every quarter frame. Both actuators use 0.44 m barrels and
0.49 m rods; pin-to-pin lengths change from approximately 0.790 to 0.571 m.
Swivel inlets at the fixed pins connect to bowed supply hoses. The raised hammer
arms clear the front chin; the top guard has a 0.50 m-wide central front notch.

The saw owns its lower, upper and central cylinders, outboard yokes, transverse
pins, rod-end eyes and connected hoses. The ramp owns rigid mounting braces and
capped unused hydraulic ports. Switching weapons removes their mechanisms together.

All exhaust outlets point along Blender **-Y**, directly rearward. Small-single,
medium-twin and large-twin pipes are **0.25 / 0.40 / 0.60 m** long with their
original **0.05 / 0.068 / 0.095 m** radii. Supported manifolds sit behind the rear
armor; their brackets route beneath it. Existing socket coordinates and selector
values are unchanged.

## Animation and coordinates

Two independent track assemblies have 44 tread links each. Both run forward in
the preview, completing one circuit in four seconds. Wheel rotation follows
belt travel. `Saw_SPIN_X` makes six revolutions per four seconds (90 RPM).
Frames 1–120 at 30 FPS form the loop; frame 121 is the matching endpoint.
Linear keys and cycle modifiers continue motion beyond the timeline.

Meters, Blender Z-up, +Y-forward. Standard glTF conversion maps these to Godot
Y-up and -Z-forward. Root origin is on the ground beneath the chassis. The saw
pivot is `(0, 1.16, 0.97)` in Blender coordinates and rotates around local X.

## Integration handoff

Export only `SAWBLADE TANK | model`; exclude the `STUDIO` collection.
Keep `SawbladeTank_ROOT` and its children. The source is an animated art asset,
not a runtime bot assembly. Godot action-button wiring, runtime clip selection, collision, damage, LODs,
draw-call consolidation and Godot performance checks remain integration work.
No shared game contracts, simulation scenes or project settings were changed.

## Rebuild and verification

Run Blender in background mode with `--python build_sawblade_tank.py`.
`build_modules.py` authors the interchangeable parts; `build_mechanics.py` builds
the connected weapon mechanisms and bakes the non-looping hammer motion. `prepare_asset.py` applies
the bevels, creates shared UVs, and bakes/packs the neutral 4K atlas without
geometry reduction. `configure_modules.py` installs visibility and palette
controls and writes the manifest. The builder renders the front
preview and records the measured mesh triangle count and animation checks.

Load the saved blend in background mode with `--python render_motion_preview.py`
to verify the packed texture plus tread position/orientation at the loop seam,
and render the MP4. `render_reference_views.py` renders rear and side views for
comparison with the reference. Movies and Blender backups are ignored by Git.
`validate_modules.py` reopens and checks every selector value, module mounting
hierarchy, visibility drivers, color controls and packed texture; it also renders
hammer/wheel and armored-ramp example configurations. Results are recorded in
`module_validation.json`.

Validation covers all 88 moving links, the complete belt-loop seam, six saw
rotations, packed texture dimensions and visual review of front/rear/side views.
The baseline game check is not applicable to this isolated art-asset change.


Run `validate_mechanics.py` against the saved blend to check 257 subframe poses,
flat ground contact within 1 mm, actuator attachment/alignment, rod engagement,
positive leverage without dead center, return-and-hold behavior, and exhaust
lengths/armor clearance. Moving hammer geometry (including cranks and actuators)
is checked for surface intersections against both drives and every optional armor
mesh at 65 poses. Intended hinge-bearing contacts are excluded. Results are in
`mechanics_validation.json`; these are art/kinematic checks, not game physics tests.

`render_attack_preview.py` produces ready/impact/return side views, an impact view
with armored wheels, the one-shot `sawblade_tank_hammer_attack.mp4`, and rear views
for all three exhaust sizes. `module_manifest.json` includes the clip timing,
hinge, marker, bake channels, and exhaust dimensions for the later game adapter.
No Godot input, animation player, damage logic, or shared contracts are implemented
by this asset revision. Import/export assembly and gameplay integration remain
Developer A's follow-up work.

On Windows, run assemble_preview_sheet.ps1 after the attack renderer to combine
the three exhaust rear views into sawblade_tank_exhaust_comparison.png.

Saved-asset validation: 257 kinematic poses and 65 full-clearance poses passed;
contact height error was below 0.001 mm, maximum interpolated pin error was
0.149 mm, minimum rod engagement was 139.98 mm, and minimum hinge moment arm
was 118.86 mm. All 18 selector states and four palette channels passed; the
88 tread seams and six saw revolutions remain verified.
