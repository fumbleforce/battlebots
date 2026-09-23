extends SceneTree
## Synthetic joypad events exercise Godot's InputMap and actual menu dispatch.
var failures := 0
const DEVICE := 7
var preview: Node3D
var probe: InputCombatProbe

func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func axis(index: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = index
	event.axis_value = value
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func button(index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func sample() -> BotCommand:
	preview._physics_process(1.0 / 60.0)
	return probe.last_command
func neutral() -> void:
	for index: JoyAxis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y, JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]: axis(index, 0.0)
	for index: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]: button(index, false)

func run() -> void:
	var original_accumulation := Input.use_accumulated_input
	Input.use_accumulated_input = false
	var scene := load("res://scenes/dev/b_input_menu.tscn").instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	preview = scene.get_node("Preview")
	probe = scene.get_node("Bot")
	preview.set_process(false)
	preview.set_physics_process(false)
	preview.rig.set_process(false)
	neutral()
	preview.capture_controls()
	sample()
	axis(JOY_AXIS_LEFT_Y, -0.1)
	check(is_zero_approx(sample().throttle), "Left-stick drift stays inside deadzone")
	axis(JOY_AXIS_LEFT_Y, -0.6)
	axis(JOY_AXIS_LEFT_X, 0.6)
	var command := sample()
	check(command.throttle > 0.0 and command.throttle < 1.0 and command.steering > 0.0 and command.steering < 1.0, "Partial sticks preserve analog drive and steering")
	axis(JOY_AXIS_LEFT_Y, 1.0)
	axis(JOY_AXIS_LEFT_X, -1.0)
	check(sample().throttle == -1.0 and sample().steering == -1.0, "Full reverse/left reaches ordinary BotCommand")
	button(JOY_BUTTON_LEFT_SHOULDER, true)
	check(sample().brake, "LB brakes")
	button(JOY_BUTTON_LEFT_SHOULDER, false)
	button(JOY_BUTTON_RIGHT_SHOULDER, true)
	button(JOY_BUTTON_A, true)
	button(JOY_BUTTON_X, true)
	command = sample()
	check(command.nitro_held and command.jump_held and command.recovery_pressed, "RB, south and west map to Nitro, jump and recovery")
	neutral()
	sample()
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	for tick: int in 65: sample()
	check(probe.combat.charge > 0.9, "RT charges a real lifter")
	var launches := probe.launch_count
	axis(JOY_AXIS_LEFT_Y, -1.0)
	sample()
	button(JOY_BUTTON_START, true)
	check(not preview.controls_enabled and preview.pause_menu.visible and probe.last_command.brake, "Start opens the menu and immediately brakes")
	check(probe.launch_count == launches and probe.last_command.secondary_held, "Opening menu cancels a charged weapon")
	button(JOY_BUTTON_START, false)
	button(JOY_BUTTON_A, true)
	button(JOY_BUTTON_A, false)
	check(preview.controls_enabled, "Controller menu accept activates focused Resume")
	check(not sample().primary_held and is_zero_approx(probe.last_command.throttle), "Held trigger and stick cannot activate through Resume")
	axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	axis(JOY_AXIS_LEFT_Y, 0.0)
	sample()
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	check(sample().primary_held, "Release then pull rearms the trigger")
	preview._apply_input_preferences(preview.input_preferences.clone())
	check(preview._action_strength(&"primary") > 0.9 and not sample().primary_held, "Remapping preserves physical held-trigger suppression")
	neutral()
	sample()
	axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	check(sample().secondary_held, "LT reaches secondary/cancel command")
	neutral()
	sample()
	button(JOY_BUTTON_BACK, true)
	check(Input.is_action_pressed("scoreboard"), "View/Back holds the scoreboard action")
	button(JOY_BUTTON_BACK, false)
	var zoom: float = preview.rig.desired_distance
	button(JOY_BUTTON_DPAD_UP, true)
	button(JOY_BUTTON_DPAD_UP, false)
	check(preview.rig.desired_distance < zoom, "D-pad zoom uses existing camera handler")
	preview.rig.yaw = 1.0
	button(JOY_BUTTON_RIGHT_STICK, true)
	button(JOY_BUTTON_RIGHT_STICK, false)
	check(absf(preview.rig.yaw) < 0.01, "Right-stick press recenters")
	preview._process(1.0 / 60.0)
	axis(JOY_AXIS_RIGHT_X, 1.0)
	preview._process(1.0 / 60.0)
	check(preview.rig.yaw < 0.0, "Right stick orbits through existing sensitivity")
	axis(JOY_AXIS_RIGHT_X, 0.0)
	axis(JOY_AXIS_RIGHT_Y, 1.0)
	var pitch: float = preview.rig.pitch
	preview._process(1.0 / 60.0)
	check(preview.rig.pitch > pitch, "Right-stick pitch follows normal camera direction")
	preview.rig.invert_y = true
	pitch = preview.rig.pitch
	preview._process(1.0 / 60.0)
	check(preview.rig.pitch < pitch, "Camera inversion applies to the right stick")
	preview.rig.invert_y = false
	axis(JOY_AXIS_RIGHT_X, 1.0)
	axis(JOY_AXIS_RIGHT_Y, 0.0)
	var yaw: float = preview.rig.yaw
	preview.release_controls()
	preview._process(1.0 / 60.0)
	preview.capture_controls()
	preview._process(1.0 / 60.0)
	check(is_equal_approx(preview.rig.yaw, yaw), "Camera requires neutral stick after a menu")
	neutral()
	sample()
	preview._process(1.0 / 60.0)
	axis(JOY_AXIS_LEFT_Y, -1.0)
	check(sample().throttle > 0.9, "Drive rearmed before disconnect")
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	for tick: int in 65: sample()
	launches = probe.launch_count
	Input.joy_connection_changed.emit(DEVICE, false)
	check(not preview.controls_enabled and probe.last_command.brake and probe.last_command.jump_cancel, "Active controller disconnect releases controls immediately")
	check(not sample().primary_held and probe.launch_count == launches, "Disconnect cancels charged weapons instead of firing")
	Input.joy_connection_changed.emit(DEVICE, true)
	check(not preview.controls_enabled, "Reconnection alone does not resume gameplay")
	neutral()
	preview.capture_controls()
	sample()
	axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	sample()
	preview._on_focus_lost()
	check(not preview.controls_enabled and probe.last_command.secondary_held, "Focus loss cancels controller weapon intent")
	preview._on_focus_regained()
	check(not sample().primary_held, "Held trigger stays blocked after focus returns")
	neutral()
	preview.open_settings()
	preview.settings_panel.open_controls()
	var panel: InputSettingsPanel = preview.settings_panel.input_panel
	panel.begin_capture(&"drive_forward")
	button(JOY_BUTTON_B, true)
	button(JOY_BUTTON_B, false)
	check(panel.capture_action.is_empty() and panel.visible, "Controller Back cancels keyboard binding capture only")
	panel.show_page(panel.GROUPS.size() - 1)
	check(panel.controller_guide.visible and panel.controller_guide.get_child_count() == GamepadInput.GUIDE.size(), "Settings exposes the complete controller guide")
	var first := GamepadInput.new()
	var second := GamepadInput.new()
	first.look_delta(Vector2.ZERO, 0.0, true)
	second.look_delta(Vector2.ZERO, 0.0, true)
	var at30 := Vector2.ZERO
	var at120 := Vector2.ZERO
	for tick: int in 30: at30 += first.look_delta(Vector2(0.5, 0.25), 1.0 / 30.0, true)
	for tick: int in 120: at120 += second.look_delta(Vector2(0.5, 0.25), 1.0 / 120.0, true)
	check(at30.is_equal_approx(at120), "Camera orbit is independent of render frame rate")
	neutral()
	scene.queue_free()
	await process_frame
	Input.use_accumulated_input = original_accumulation
	print("GAMEPAD INPUT PASS" if failures == 0 else "GAMEPAD INPUT FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
