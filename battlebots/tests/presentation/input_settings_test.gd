extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func key(code: Key, pressed: bool = true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func dispatch(code: Key) -> void:
	root.push_input(key(code))
	root.push_input(key(code, false))

func run() -> void:
	var directory := "user://b_controls_test_%d" % Time.get_ticks_usec()
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create test directory")
	var path := directory + "/camera.cfg"
	var original := InputPreferences.snapshot_input_map()
	var scene: Node3D = load("res://scenes/dev/b_controls.tscn").instantiate()
	var preview: Node3D = scene.get_node("Preview")
	preview.settings_path = path
	root.add_child(scene)
	await process_frame
	preview.set_physics_process(false)
	preview.open_settings()
	var camera: CameraSettingsPanel = preview.settings_panel
	camera.controls_button.grab_focus()
	dispatch(KEY_ENTER)
	var panel: InputSettingsPanel = camera.input_panel
	check(panel.visible and camera.visible and not camera.form.visible,
		"Controls page stays inside A's existing modal boundary")
	check(root.gui_get_focus_owner() == panel.binding_buttons[&"drive_forward"],
		"Controls page focuses first binding")
	dispatch(KEY_ENTER)
	check(panel.capture_action == &"drive_forward", "Keyboard starts binding capture")
	dispatch(KEY_S)
	check(panel.capture_action == &"drive_forward" and panel.message.text.contains("Already"),
		"Duplicate binding reports error without changing draft")
	dispatch(KEY_ESCAPE)
	check(panel.capture_action.is_empty() and panel.visible and camera.visible,
		"Escape cancels capture without closing settings")
	panel.begin_capture(&"drive_forward")
	dispatch(KEY_I)
	check(panel.draft.label_for(&"drive_forward") == "I", "Raw key updates draft")
	check(InputMap.action_get_events(&"drive_forward")[0].physical_keycode == KEY_W,
		"Draft cannot change live input map")
	panel.begin_capture(&"primary")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	mouse.pressed = true
	root.push_input(mouse)
	mouse = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	root.push_input(mouse)
	check(panel.capture_action.is_empty() and panel.draft.label_for(&"primary") == "Mouse 4",
		"Raw mouse button capture updates draft")
	panel.mode.button_pressed = true
	panel.save_button.grab_focus()
	dispatch(KEY_ENTER)
	check(not panel.visible and camera.form.visible and camera.visible, "Save returns to camera page")
	check(preview.input_preferences.toggle_primary and preview.input_gate.toggle_primary,
		"Saved toggle preference reaches input gate")
	check(InputMap.action_get_events(&"drive_forward")[0].physical_keycode == KEY_I,
		"Saved binding reaches runtime action map")
	var loaded := InputPreferences.load_file(path + ".input")
	check(loaded.load_error == OK and loaded.toggle_primary and
		loaded.label_for(&"drive_forward") == "I", "Saved controls persist")
	Input.action_press("primary")
	preview._physics_process(0.016)
	check(scene.get_node("Bot").last_command.secondary_held and
		not scene.get_node("Bot").last_command.primary_held, "Settings suppress held weapon after remapping")
	Input.action_release("primary")
	camera.open_controls()
	panel.begin_capture(&"primary")
	root.focus_exited.emit()
	check(panel.capture_action.is_empty() and camera.visible and not preview.controls_enabled,
		"Focus loss cancels capture and preserves modal suppression")
	panel.reset_defaults()
	panel.cancel()
	check(preview.input_preferences.label_for(&"drive_forward") == "I", "Cancel discards reset draft")
	camera.open_controls()
	panel._path = ""
	panel.reset_defaults()
	panel.save()
	check(panel.visible and panel.message.text.contains("Could not save"), "Save failure retains draft page")
	check(preview.input_preferences.label_for(&"drive_forward") == "I", "Failed save preserves live controls")
	panel.cancel()
	camera.open_controls()
	dispatch(KEY_ESCAPE)
	check(camera.visible and not panel.visible and not preview.controls_enabled,
		"Escape from Controls returns to camera without gameplay")
	dispatch(KEY_ESCAPE)
	check(not camera.visible, "Next Escape closes settings")
	preview.release_controls()
	await process_frame
	preview.open_settings()
	camera.open_controls()
	if "--capture" in OS.get_cmdline_user_args():
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://b-controls-preview.png") == OK,
			"Capture controls layout")
		print("CAPTURE: ", ProjectSettings.globalize_path("user://b-controls-preview.png"))
	panel.cancel()
	camera.cancel()
	await process_frame
	preview.capture_controls()
	# Exercise A's lifecycle hook without requiring an entire network session.
	var lifecycle: SessionBotSource = load("res://tests/fixtures/input_lifecycle_probe.gd").new()
	lifecycle.input_allowed = func() -> bool: return false
	var real_source: BotSource = preview.source
	preview.source = lifecycle
	preview.input_gate.sample({}, {}, true)
	preview.input_gate.sample({&"primary": 1.0}, {&"primary": true}, true)
	preview._physics_process(0.016)
	check(lifecycle.last_command.secondary_held and not lifecycle.last_command.primary_held,
		"Session lifecycle suppression cancels latched primary")
	lifecycle.input_allowed = func() -> bool: return true
	preview._physics_process(0.016)
	check(not lifecycle.last_command.primary_held, "Restored eligibility cannot restore old toggle latch")
	preview.source = real_source
	lifecycle.free()
	# Remapping resets virtual action state while the underlying key may remain down.
	Input.parse_input_event(key(KEY_I))
	Input.flush_buffered_events()
	preview._apply_input_preferences(preview.input_preferences)
	preview._physics_process(0.016)
	check(real_source.last_command.throttle == 0.0, "Physically held remapped key requires release")
	Input.parse_input_event(key(KEY_I, false))
	Input.flush_buffered_events()
	preview._physics_process(0.016)
	Input.parse_input_event(key(KEY_I))
	Input.flush_buffered_events()
	preview._physics_process(0.016)
	check(real_source.last_command.throttle == 1.0, "Fresh remapped press reaches gameplay")
	Input.parse_input_event(key(KEY_I, false))
	Input.flush_buffered_events()
	scene.queue_free()
	await process_frame
	check(InputMap.action_get_events(&"drive_forward")[0].physical_keycode ==
		original[&"drive_forward"][0].physical_keycode, "Scene exit restores previous bindings")
	# Recreate the fixture to prove the disk value reaches a fresh preview and gate.
	scene = load("res://scenes/dev/b_controls.tscn").instantiate()
	preview = scene.get_node("Preview")
	preview.settings_path = path
	root.add_child(scene)
	await process_frame
	check(preview.input_gate.toggle_primary and preview.input_preferences.label_for(&"drive_forward") == "I",
		"Fresh fixture restores saved bindings and weapon mode")
	scene.queue_free()
	await process_frame
	for file: String in [path, path + ".input", path + ".input.tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(directory)
	print("INPUT SETTINGS PASS" if failures == 0 else "INPUT SETTINGS FAIL")
	quit(0 if failures == 0 else 1)
