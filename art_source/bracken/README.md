# Bracken reference tank

Original model authored from the user's foreground-tank image for issue #100.
Visual direction: readable, stylized adventure-game forms, muted olive armor,
oxide-red panels, warm exposed steel and chipped matte paint.

- `bracken.blend`: editable assembled hierarchy, fourteen packed PBR images.
- `bracken_complete.glb`: standalone complete model with embedded textures.
- `../../battlebots/assets/models/bracken_runtime/`: three runtime GLBs (hull,
  turret, lifter), external base/ORM/normal maps and enamel coverage masks.
- `../../tools/build-bracken.py`: reproducible construction, baking and export.

Coordinates are source metres, X right / Y up / −Z forward; the runtime applies
the existing factor of three. The complete source has the ramp attached in a
raised inspection pose. Runtime attachments export in their local rig frames.
Tracks, wheels, turret traverse, barrel elevation/recoil, hydraulic rods/cylinders and lifter are separate
nodes, animated by the shared Atlas presentation code.
Bracken has its own narrower hull and bore offsets in `data/bracken_geometry.json`.
The large rear suspension rams have fixed chassis/drive anchors; the smaller
elevation actuators solve both moving eyes without stretching their meshes.
Armor panels and ramp slats remain separate parts for the generic destruction
pipeline. Every permanent metal/paint/rubber surface uses baked texture maps;
only the tiny stencil and sensor lens retain flat authored materials. The standalone
GLB has the same moving hierarchy; it does not contain baked animation clips.

Run `blender --background --python tools/build-bracken.py` to rebuild. `--quick`
and `--no-bake` write only under ignored `battlebots/exports/bracken-preview/`.
Import with `godot --headless --path battlebots --editor --import --quit`.

Manual playtest:

```sh
godot --path battlebots --script res://tests/presentation/bracken_playtest.gd -- --practice
```

This selects Bracken in memory and opens the normal Practice game; it does not
overwrite saved builds. Primary fire shoots the turret; secondary charges and
releases the lifter using the existing tank controls.

The factory preset is deliberately a complete assembly. Its drive, weapons and
armor modules are fixed; a broader modular version has not been authored.
Studio previews show the actual baked source, not concept art. Reference fidelity remains subject to visual review. The rejected initial broad
version was replaced with the slimmer, exposed-hydraulic revision.
No native game/editor is automatically launched by the builder.
