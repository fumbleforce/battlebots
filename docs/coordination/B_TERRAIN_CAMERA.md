# Terrain-aware camera clearance — B implementation

Branch `codex/b-terrain-camera`, from main `f570bf9`. B owns camera presentation;
A owns terrain/world geometry. The active Sawblade/legs task retains drive/model
work. This increment changes no world, gravity, drive, models, networking or
BotSource API.

## Reproduction and correction

The independent scene sweeps an actual frozen MvpBot chassis onto real Jolt Moon
collision, stopping 1 cm before support and checking that the body does not
penetrate. The original camera failed 27 inverted combinations across three
raised patches, three yaw angles and three pitches. A representative ground
height of 0.383 m left the rolled anchor at 0.074 m and the collapsed camera at
0.300 m, embedded in terrain.

The camera queries supporting ground from chassis height, accounts for its surface
normal, and accepts a raised pivot only when its sphere is clear. An upward ray
rejects crossing an overhead surface. Existing bot-contact and boom clearance
continue afterwards. Insufficient room under a ceiling can retain a collapsed
view; this fix does not promise an unobstructed camera in impossible spaces.

## Validation

- `tests/presentation/camera_terrain_test.tscn`: CAMERA TERRAIN PASS. Five real
  ground locations, upright/side/inverted poses, three yaw and three pitch angles;
  sphere clearance and horizon checks, including near the perimeter.
- Real low ceiling and adjacent wall leave the fixture chassis nonpenetrating,
  constrain camera movement, and restore the view after removal.
- Existing CAMERA CONTACT PASS, PRESENTATION PASS and CAMERA SETTINGS PASS.
- `tools/check-baseline.ps1`: BASELINE PASS with Godot 4.7.2/Jolt.
- Native OpenGL capture with `-- --capture`, inspected at
  `%TEMP%/camera-lunar-inverted.png`: readable inverted chassis and level horizon.
- Registered the independent scene in the presentation validation runner.

These deterministic frozen poses verify collision behavior, not natural driving,
low-gravity balance or human camera feel. Those acceptance items remain open.
