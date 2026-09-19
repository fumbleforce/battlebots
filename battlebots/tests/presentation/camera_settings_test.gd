extends SceneTree
var failures: int = 0
var test_directory: String

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	test_directory = "user://b_settings_test_%d" % Time.get_ticks_usec()
	check(DirAccess.make_dir_recursive_absolute(test_directory) == OK, "Create isolated test directory")
	var path := test_directory + "/camera.cfg"
	var initial := CameraPreferences.new()
	initial.sensitivity = 0.006
	initial.invert_y = true
	initial.auto_recenter = false
	initial.recenter_speed = 4.0
	check(initial.save_file(path) == OK, "Save new settings")
	var reloaded := CameraPreferences.load_file(path)
	check(is_equal_approx(reloaded.sensitivity, 0.006) and reloaded.invert_y \
		and not reloaded.auto_recenter and reloaded.recenter_speed == 4.0, "Settings round-trip")
	initial.sensitivity = 0.009
	check(initial.save_file(path) == OK, "Replace existing settings")
	check(is_equal_approx(CameraPreferences.load_file(path).sensitivity, 0.009), "Replacement persisted")

	var sandbox: Node3D = load("res://scenes/dev/b_presentation.tscn").instantiate()
	var preview: Node3D = sandbox.get_node("Preview")
	preview.settings_path = path
	root.add_child(sandbox)
	await process_frame
	preview.set_physics_process(false)
	var source: BotSource = sandbox.get_node("Bot")
	source.set_physics_process(false)
	check(is_equal_approx(preview.rig.sensitivity, 0.009), "Fresh scene loads persisted settings")
	var command := BotCommand.new()
	command.throttle = 1.0
	command.primary_held = true
	source.submit_command(command)
	preview.open_settings()
	var panel: CameraSettingsPanel = preview.settings_panel
	check(panel.visible and not preview.controls_enabled, "Opening settings disables control")
	check(source.last_command.throttle == 0.0 and not source.last_command.primary_held,
		"Opening settings immediately submits neutral input")
	Input.action_press("drive_forward")
	Input.action_press("primary")
	preview._physics_process(0.016)
	check(source.last_command.throttle == 0.0 and not source.last_command.primary_held,
		"Held gameplay actions cannot pass through modal")
	Input.action_release("drive_forward")
	Input.action_release("primary")
	check(root.gui_get_focus_owner() == panel.sensitivity, "Settings opens with keyboard focus")
	panel.sensitivity.value = 1.5
	check(is_equal_approx(preview.rig.sensitivity, 0.0045), "Sensitivity applies live")
	panel.cancel()
	check(is_equal_approx(preview.rig.sensitivity, 0.009), "Cancel restores pre-open settings")
	check(is_equal_approx(CameraPreferences.load_file(path).sensitivity, 0.009), "Cancel does not persist")
	await process_frame
	preview.open_settings()
	panel.reset_defaults()
	check(is_equal_approx(preview.rig.sensitivity, 0.003) and not preview.rig.invert_y \
		and preview.rig.auto_recenter, "Reset restores defaults live")
	panel.save_and_close()
	check(not panel.visible, "Successful save closes settings")
	check(is_equal_approx(CameraPreferences.load_file(path).sensitivity, 0.003), "Saved defaults persist")
	await process_frame
	preview.open_settings()
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	preview._input(escape)
	check(not panel.visible and is_instance_valid(sandbox), "Escape closes panel, not scene")
	await process_frame
	preview.settings_path = ""
	preview.open_settings()
	panel.sensitivity.value = 2.0
	panel.save_and_close()
	check(panel.visible and not panel.message.text.is_empty(), "Save failure stays visible")
	panel.cancel()
	await process_frame
	preview.settings_path = path
	preview.open_settings()
	preview.release_controls()
	check(panel.visible and not preview.controls_enabled, "Focus loss keeps modal without recapture")

	if "--capture" in OS.get_cmdline_user_args():
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var output := "user://b-settings-preview.png"
		check(root.get_texture().get_image().save_png(output) == OK, "Save settings preview")
		print("CAPTURE: ", ProjectSettings.globalize_path(output))
	sandbox.queue_free()
	await process_frame

	var malformed := ConfigFile.new()
	malformed.set_value("camera", "version", 1)
	malformed.set_value("camera", "sensitivity", "invalid")
	malformed.set_value("camera", "invert_y", "true")
	malformed.set_value("camera", "recenter_speed", 999.0)
	malformed.save(path)
	var sanitized := CameraPreferences.load_file(path)
	check(sanitized.sensitivity == 0.003 and not sanitized.invert_y \
		and sanitized.recenter_speed == 8.0, "Invalid settings use defaults or clamp")
	malformed.set_value("camera", "version", 999)
	malformed.save(path)
	check(CameraPreferences.load_file(path).load_error == ERR_FILE_UNRECOGNIZED,
		"Unknown schema returns recoverable load error")
	for file: String in [path, path + ".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(test_directory)
	print("CAMERA SETTINGS PASS" if failures == 0 else "CAMERA SETTINGS FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
