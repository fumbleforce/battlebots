extends SceneTree
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func action_event(action: String, pressed: bool = true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event

func charge(probe: BotSource) -> void:
	var registry := ContentRegistry.new()
	probe.combat = CombatState.new(registry.validate(registry.starter(true)).stats)
	var command := BotCommand.new()
	command.primary_held = true
	for index: int in range(65):
		probe.submit_command(command)
	check(probe.combat.charge >= 1.0, "Fixture must reach charged lifter")

func run() -> void:
	var gate := GameplayInputGate.new()
	gate.sample({}, {}, true)
	var active := gate.sample({&"drive_forward": 0.7, &"primary": 1.0, &"recover": 1.0},
		{&"primary": true, &"recover": true}, true)
	check(active.throttle == 0.7 and active.primary_held and active.recovery_pressed,
		"Fresh actions and analog strengths reach gameplay")
	var canceled := gate.sample({}, {}, false)
	check(canceled.brake and canceled.secondary_held and not canceled.primary_held,
		"Suppression must cancel weapons and brake")
	var held := gate.sample({&"drive_forward": 1.0, &"primary": 1.0, &"recover": 1.0},
		{&"primary": true, &"recover": true}, true)
	check(held.throttle == 0.0 and held.brake and held.secondary_held \
		and not held.primary_held and not held.recovery_pressed,
		"Held actions remain blocked across resume")
	gate.sample({}, {}, true)
	var fresh := gate.sample({&"drive_forward": 1.0, &"primary": 1.0, &"recover": 1.0},
		{&"primary": true, &"recover": true}, true)
	check(fresh.throttle == 1.0 and fresh.primary_held and fresh.recovery_pressed,
		"Released then pressed actions must rearm")

	var scene: Node3D = load("res://scenes/dev/b_input_menu.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var probe: BotSource = scene.get_node("Bot")
	var preview: Node3D = scene.get_node("Preview")
	preview.set_physics_process(false)
	charge(probe)
	var launches_before: int = probe.launch_count
	preview.release_controls()
	check(probe.launch_count == launches_before and not probe.combat.launch,
		"Menu release cannot launch a charged lifter")
	check(probe.last_command.brake and probe.last_command.secondary_held,
		"Immediate menu command brakes and lowers")
	check(root.gui_get_focus_owner() == preview.resume_button, "Menu focuses Resume")
	preview._physics_process(0.016)
	check(probe.last_command.brake and probe.last_command.secondary_held,
		"Disabled-control physics ticks keep canceling")

	# Exercise real GUI event dispatch rather than calling button callbacks directly.
	root.push_input(action_event("ui_focus_next"))
	root.push_input(action_event("ui_focus_next", false))
	check(root.gui_get_focus_owner() == preview.settings_button, "Tab selects settings")
	root.push_input(action_event("ui_accept"))
	root.push_input(action_event("ui_accept", false))
	check(preview.settings_panel.visible and not preview.controls_enabled,
		"Keyboard opens settings without resuming")
	var panel: CameraSettingsPanel = preview.settings_panel
	panel.automatic.button_pressed = false
	panel.automatic.grab_focus()
	root.push_input(action_event("ui_focus_next"))
	root.push_input(action_event("ui_focus_next", false))
	check(root.gui_get_focus_owner() == panel.form.get_node("Buttons/Defaults"),
		"Keyboard skips disabled recenter strength")
	root.push_input(action_event("pause"))
	root.push_input(action_event("pause", false))
	check(not panel.visible and is_instance_valid(scene), "Escape closes settings safely")
	# Simulate losing focus between a scheduled resume and the next idle frame.
	preview._on_settings_closed(false)
	preview.release_controls()
	await process_frame
	check(not preview.controls_enabled, "Deferred settings close cannot recapture after focus loss")

	charge(probe)
	preview.capture_controls()
	get_root().focus_exited.emit()
	check(probe.launch_count == launches_before and probe.last_command.secondary_held,
		"Window focus loss cancels charged lifter")
	var old_scene := current_scene
	root.push_input(action_event("pause"))
	root.push_input(action_event("pause", false))
	check(preview.controls_enabled and current_scene == old_scene, "Escape resumes, not exits")
	root.push_input(action_event("pause"))
	root.push_input(action_event("pause", false))
	check(not preview.controls_enabled and current_scene == old_scene, "Escape reopens menu")

	# Cancellation protection must not disable intentional weapon release.
	charge(probe)
	probe.submit_command(BotCommand.new())
	check(probe.launch_count == launches_before + 1, "Intentional release still launches")

	if "--capture" in OS.get_cmdline_user_args():
		preview.release_controls()
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var output := "user://b-input-menu-preview.png"
		check(root.get_texture().get_image().save_png(output) == OK, "Save menu preview")
		print("CAPTURE: ", ProjectSettings.globalize_path(output))

	# Explicit return is idempotent and deferred; dispatch never sees a freed viewport.
	preview.return_to_launcher()
	preview.return_to_launcher()
	check(is_instance_valid(scene) and current_scene == scene, "Return must be deferred")
	await process_frame
	await process_frame
	check(not is_instance_valid(scene), "Return frees old standalone scene")
	check(current_scene != null and current_scene.scene_file_path == "res://scenes/app/main.tscn",
		"Return reaches launcher")
	print("INPUT MENU PASS" if failures == 0 else "INPUT MENU FAIL")
	quit(0 if failures == 0 else 1)
