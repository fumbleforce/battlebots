# Sawblade Tank — Blender art asset

Developer B / `codex/b-sawblade-tank`.
Starting checkout: `7979b77` (existing integrated development work).
Reference: user-supplied `SawbladeTank2_ps3.png` (not redistributed).

Open `sawblade_tank.blend` in Blender 4.0 or newer and press Space in the 3D view.
The source includes a studio camera and lighting, with all textures packed.

## Art and animation

- PS3-inspired asset budget: 17,132 evaluated model triangles, also recorded in
  `validation.json`. No subdivision surfaces.
- One shared 1024 × 1024 color atlas, supplied as PNG and packed into the blend.
  Surface groups use scalar metallic/roughness values. No runtime procedural
  shaders or external texture dependencies.
- Two continuous tracks with 44 individually animated tread links each.
- Track links travel one full circuit in four seconds; wheel rotation matches
  belt travel. Both belts currently run forward at the same fixed preview speed.
- `Saw_SPIN_X` makes six revolutions in four seconds (90 RPM for the preview).
- Frames 1–120 at 30 FPS form the loop. Frame 121 is the matching endpoint.
  Linear keys and cycle modifiers keep the loops running beyond the timeline.
- Exposed hydraulic rods, fork supports, service covers, handle, hazard stripes,
  chamfered armor and a toothed vertical saw follow the supplied reference.

## Coordinates and integration handoff

The model uses meters, Blender Z-up and +Y-forward. Standard glTF axis conversion
maps these to Godot Y-up and -Z-forward. Root origin is on the ground beneath the
chassis. The saw pivot is at Blender `(0, 1.16, 0.97)` and rotates about local X.
The approximate envelope is 1.7 m wide, 2.8 m long including saw, and 1.8 m tall.

`SAWBLADE TANK | model` holds the bot. Exclude `STUDIO | exclude from game export`
when exporting for integration. Keep `SawbladeTank_ROOT` and its children.
The independent track assemblies and saw pivot are available for later animation
control by Developer A's bot assembly and Developer B's presentation adapter.

This delivery is an animated Blender art asset. It does not change shared game
contracts, bot assembly, collision, damage, networking or project settings.
Gameplay-driven track speed, weapon-state control, LODs, draw-call consolidation,
Godot import configuration and in-game performance checks remain integration work.

## Rebuild and verification

Run Blender in background mode with `--python build_sawblade_tank.py`. The build
script models the bot, applies geometry reduction, creates shared UVs, bakes the
1K atlas, packs it, saves the blend, renders the still and writes validation.
`prepare_ps3.py` is a helper executed by the builder, not a standalone script.

Validation checks that all 88 links move and return to their starting positions
at the loop seam, checks the saw's six complete rotations, and measures evaluated
mesh triangles. The final saved file is visually inspected via its studio render.
Reopening the saved source also verified the packed 1024 texture and matching
position and orientation for every tread link across the loop seam.
No shared scenes/contracts changed, so the repository baseline check is not
applicable to this isolated asset delivery.

Load the blend in background mode with `--python render_motion_preview.py` to
render an optional MP4 preview. Generated movies and Blender backups are ignored
by Git; the blend, atlas and still preview are the committed source deliverables.
