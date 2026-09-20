# Resolution-independent camera input — B implementation

Branch `codex/b-camera-mouse-scale`, from main `8978fdf`. The real preview input
adapter previously consumed viewport-scaled `InputEventMouseMotion.relative`.
Under content scaling, identical screen movement produced different camera angles.
It now consumes `screen_relative`, keeping the selected X/Y sensitivity in radians
per screen pixel. At the design resolution behavior is unchanged; scaled windows
now use the same setting consistently. Saved preferences need no migration.

Scope: B baseline_preview input adapter, one outdated camera-preferences ownership
comment, independent presentation test scene/runner and handoff docs. No drive,
model, weapon, Customize, project input action, BotSource or network API changes.
The active Sawblade task retains its model/drive/weapon paths.

## Reproduction and validation

The independent `camera_mouse_scale_test.tscn` instantiates the real presentation
fixture and applies Godot's `InputEventMouseMotion.xformed_by` at 0.5, 1 and 2.
The engine scales `relative` but preserves `screen_relative`. Before correction,
a 20-by-12-pixel move at X=0.004/Y=0.007 sensitivity produced yaw -0.04/-0.08/-0.16
and pitch 0.042/0.084/0.168 radians. Eight assertions failed across both axes and
normal/inverted vertical input. After correction all scales produce yaw -0.08
and pitch +/-0.084. Released controls and settings modal reject orbit.

CAMERA MOUSE SCALE PASS, CAMERA SETTINGS PASS, INPUT MENU PASS and BASELINE PASS
with Godot 4.7.2. The new scene is registered in the presentation runner.
This tests actual engine transforms and the actual event consumer, not physical
OS mouse injection or human camera-feel acceptance. Spectator cycling remains
in deferred team/FFA scope; this increment does not implement it.
