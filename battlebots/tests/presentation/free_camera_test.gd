extends SceneTree
## Free camera (#102): F detaches the orbit rig from the bot where the view is,
## the rig flies along its own heading and turns in place, and F again returns
## it behind the bot. The key is F by default and belongs to no other action.
## godot --headless --path battlebots --script res://tests/presentation/free_camera_test.gd
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var prefs := InputPreferences.new()
	check(prefs.bindings[&"free_camera"].physical_keycode == KEY_F, "Free camera defaults to F")
	for action: StringName in prefs.bindings:
		if action != &"free_camera":
			check(InputPreferences._identity(prefs.bindings[action]) != "key:%d" % KEY_F, "F is not bound to %s" % action)
	check(InputMap.has_action(&"free_camera"), "Project declares free_camera")
	var rig: BotOrbitCamera = load("res://scenes/ui/orbit_camera.tscn").instantiate()
	root.add_child(rig)
	await process_frame
	rig.global_position = Vector3(3, 5, 7)
	rig.camera.position = Vector3(0, 0, 6)
	await process_frame
	var eye := rig.camera.global_position
	rig.set_free_flight(true)
	check(rig.free_flight and rig.free_position.distance_to(eye) < 0.01, "Detaches where the view is")
	rig.yaw = 0.0
	rig.pitch = 0.0
	rig.fly(Vector3(0, 0, -10), 1.0)
	await process_frame
	check(rig.camera.global_position.distance_to(eye + Vector3(0, 0, -10)) < 0.05, "Flies along its heading (%s)" % str(rig.camera.global_position))
	rig.orbit(Vector2(0, 100000))
	check(rig.pitch > deg_to_rad(80.0), "Looks straight down in free flight")
	rig.set_free_flight(false)
	check(not rig.free_flight and rig.pitch < deg_to_rad(71.0), "Returns to the orbit behind the bot")
	rig.queue_free()
	await process_frame
	print("FREE CAMERA PASS" if failures.is_empty() else "FREE CAMERA FAIL")
	quit(0 if failures.is_empty() else 1)
