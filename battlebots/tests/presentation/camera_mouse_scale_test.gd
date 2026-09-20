extends Node
## Exercises Godot's event transform and the real preview input consumer.
## Deterministic content-scale transforms do not simulate physical OS mouse input.

var failures := 0

func _ready() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var sandbox: Node3D = preload("res://scenes/dev/b_presentation.tscn").instantiate()
	var preview: Node3D = sandbox.get_node("Preview")
	preview.settings_path = ""
	add_child(sandbox)
	await get_tree().process_frame
	sandbox.set_process(false)
	sandbox.get_node("Bot").set_physics_process(false)
	preview.set_physics_process(false)
	preview.rig.set_physics_process(false)
	preview.controls_enabled = true
	preview.pause_menu.hide()
	preview.rig.auto_recenter = false
	preview.rig.sensitivity_x = 0.004
	preview.rig.sensitivity_y = 0.007
	var physical_motion := Vector2(20.0, 12.0)
	var raw := InputEventMouseMotion.new()
	raw.relative = physical_motion
	raw.screen_relative = physical_motion
	for inverted: bool in [false, true]:
		preview.rig.invert_y = inverted
		for factor: float in [0.5, 1.0, 2.0]:
			var transform := Transform2D.IDENTITY.scaled(Vector2.ONE * factor)
			var event := raw.xformed_by(transform) as InputEventMouseMotion
			check(event.relative.is_equal_approx(physical_motion * factor),
				"Godot transforms viewport relative motion at scale %.1f" % factor)
			check(event.screen_relative.is_equal_approx(physical_motion),
				"Godot preserves screen motion at scale %.1f" % factor)
			preview.rig.yaw = 0.0
			preview.rig.pitch = 0.0
			preview._unhandled_input(event)
			check(is_equal_approx(preview.rig.yaw, -physical_motion.x * 0.004),
				"Physical horizontal sensitivity invariant at scale %.1f inverted=%s, got %.3f" % [factor, inverted, preview.rig.yaw])
			var expected_pitch := physical_motion.y * 0.007 * (-1.0 if inverted else 1.0)
			check(is_equal_approx(preview.rig.pitch, expected_pitch),
				"Physical vertical sensitivity invariant at scale %.1f inverted=%s, got %.3f" % [factor, inverted, preview.rig.pitch])
	preview.controls_enabled = false
	preview.rig.yaw = 0.0
	preview.rig.pitch = 0.0
	preview._unhandled_input(raw)
	check(is_zero_approx(preview.rig.yaw) and is_zero_approx(preview.rig.pitch),
		"Released controls reject mouse orbit")
	preview.controls_enabled = true
	preview.settings_panel.show()
	preview._unhandled_input(raw)
	check(is_zero_approx(preview.rig.yaw) and is_zero_approx(preview.rig.pitch),
		"Settings modal rejects mouse orbit even with controls flag set")
	preview.settings_panel.hide()
	sandbox.queue_free()
	await get_tree().process_frame
	print("CAMERA MOUSE SCALE PASS" if failures == 0 else "CAMERA MOUSE SCALE FAIL: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
