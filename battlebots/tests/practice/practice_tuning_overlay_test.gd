extends SceneTree
## Practice Duel HUD tuning panel (#94): Z toggles a copy of the Esc menu's
## tuning card while driving; the cursor is free for it, mouse motion does not
## orbit, clicks on the card stay off the weapons and clicks elsewhere fire.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count := 4) -> void:
	for index: int in count:
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)
	await frames()

func mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	root.push_input(event)

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	var preview: Node3D = game.preview
	var overlay: Control = game.practice_tuning_overlay
	await key(KEY_Z)
	check(not overlay.visible and not preview.free_cursor, "Z does nothing outside a Practice Duel")
	game.start_practice("", "duel")
	await frames(30)
	check(preview.controls_enabled and not overlay.visible, "Practice starts with the panel hidden")
	await key(KEY_Z)
	check(overlay.visible and preview.free_cursor, "Z shows the panel and frees the cursor")
	var panel: VBoxContainer = overlay.tuning_panel
	check(panel.pickers.has("weapon") and panel.pickers.has("chassis") and not panel._spins.is_empty(),
		"The panel lists the same weapon and body tuning as the Esc menu")
	var focusable := panel.find_children("*", "BaseButton", true, false).filter(
		func(button: Node) -> bool: return (button as BaseButton).focus_mode != Control.FOCUS_NONE)
	check(focusable.is_empty(), "HUD panel buttons take no keyboard focus")
	var card: Rect2 = overlay.card.get_global_rect()
	check(card.size.x > 0 and card.end.x <= 1920.5 and card.end.x > 1800 and card.position.x > 800, "The card sits on the right (%s)" % card)
	# Mouse motion no longer orbits the camera.
	var yaw: float = preview.rig.yaw
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(200, 540)
	motion.relative = Vector2(120, 40)
	motion.screen_relative = Vector2(120, 40)
	root.push_input(motion)
	await frames()
	check(is_equal_approx(preview.rig.yaw, yaw), "Mouse motion does not orbit while the panel shows")
	# A click on the card never reaches the weapons.
	mouse(card.get_center(), true)
	check(preview._action_strength(&"primary") == 0.0 and not preview._action_edge(&"primary"), "A click on the card does not fire")
	mouse(card.get_center(), false)
	# A click elsewhere is an ordinary gameplay click.
	mouse(Vector2(200, 540), true)
	check(preview._action_strength(&"primary") == 1.0 and preview._action_edge(&"primary"), "A click outside the card fires")
	mouse(Vector2(200, 540), false)
	check(preview._action_strength(&"primary") == 0.0, "Releasing the click stops firing")
	# The Esc menu hides the HUD copy; resuming brings it back.
	preview.release_controls()
	await frames()
	check(not overlay.visible and preview.pause_menu.visible, "The Esc menu hides the HUD panel")
	game.resume_gameplay()
	await frames()
	check(overlay.visible and preview.free_cursor, "Resuming shows the HUD panel again")
	await key(KEY_Z)
	check(not overlay.visible and not preview.free_cursor, "Z hides the panel and recaptures the cursor")
	motion.position = Vector2(300, 540)
	root.push_input(motion)
	await frames()
	check(not is_equal_approx(preview.rig.yaw, yaw), "Mouse motion orbits again once the panel is hidden")
	await key(KEY_Z)
	game.return_to_main()
	await frames()
	check(not overlay.visible and not preview.free_cursor and not game._practice_tuning_open, "Leaving practice closes the panel")
	game.queue_free()
	await frames()
	if failures.is_empty():
		print("PRACTICE_TUNING_OVERLAY_TEST_PASS")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		print("PRACTICE_TUNING_OVERLAY_TEST_FAIL")
		quit(1)
