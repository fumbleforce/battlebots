extends SceneTree
## Minimal executable checks for the shared foundation.

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var command := BotCommand.new()
	_check(command.is_valid(), "Neutral command must be valid")
	command.throttle = NAN
	_check(not command.is_valid(), "Reject non-finite throttle")
	command.throttle = 2.0
	_check(not command.is_valid(), "Reject out-of-range throttle")
	for action: String in ["drive_forward", "drive_reverse", "steer_left",
			"steer_right", "primary", "secondary", "brake", "recover",
			"camera_toggle", "camera_recenter", "camera_zoom_in", "camera_zoom_out",
			"ping", "scoreboard", "pause"]:
		_check(InputMap.has_action(action), "Missing input action: " + action)
		_check(not InputMap.action_get_events(action).is_empty(), "Unbound action: " + action)
	for path: String in ["res://scenes/app/main.tscn",
			"res://scenes/dev/a_simulation.tscn", "res://scenes/dev/b_presentation.tscn"]:
		var packed := load(path) as PackedScene
		_check(packed != null, "Cannot load " + path)
		if packed == null:
			continue
		var scene := packed.instantiate()
		root.add_child(scene)
		await process_frame
		if scene.has_node("Bot"):
			var source := scene.get_node("Bot") as BotSource
			_check(source != null, "Bot must implement BotSource")
			_check(source.camera_anchor() != null, "Missing camera anchor")
			var first := source.read_view()
			first.core_fraction = 0.0
			_check(source.read_view().core_fraction > 0.0, "Snapshot leaked mutable state")
			if scene.get_node("Bot").has_node("Body"):
				for frame: int in range(90):
					await physics_frame
				var body := source.get_node("Body") as RigidBody3D
				_check(body.position.y > 0.15 and body.position.y < 0.4,
					"Passive bot did not settle on arena floor")
		scene.queue_free()
		await process_frame
	if failures == 0:
		print("BASELINE PASS")
	else:
		print("BASELINE FAIL: ", failures)
	quit(0 if failures == 0 else 1)
