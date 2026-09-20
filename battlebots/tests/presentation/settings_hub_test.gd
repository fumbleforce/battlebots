extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count := 8) -> void:
	for index in count: await process_frame
func inspect_labels(node: Node, bounds: Rect2) -> void:
	for child: Node in node.find_children("*", "Label", true, false):
		var label := child as Label
		if label.is_visible_in_tree():
			check(bounds.encloses(label.get_global_rect()), "Visible category label fits: " + label.text)
			check(label.get_visible_line_count() == label.get_line_count(), "Full shaped category text visible: " + label.text)
func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.video_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	game.screen.get_node("%Settings").pressed.emit()
	await frames()
	check(game.settings_hub.visible and not game.preview.settings_panel.visible and not game.preview.controls_enabled, "Main opens category hub without enabling controls")
	for extent in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160)]:
		root.size = extent
		for factor in [1.0,1.5]:
			game.settings_hub.apply_text_scale(factor)
			await frames()
			for button: Button in game.settings_hub.buttons.values():
				check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(button.get_global_rect()), "Category visible without scrolling at all sizes")
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(game.settings_hub.back_button.get_global_rect()), "Hub Back is always visible")
			inspect_labels(game.settings_hub, Rect2(Vector2.ZERO,Vector2(extent)))
			check(game.settings_hub.find_children("*","ScrollContainer",true,false).is_empty(), "Hub has no scroll container")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://settings-hub-%d-%d.png" % [extent.x,roundi(factor*100)])
	root.size = Vector2i(1280,720)
	var preferences = game.hud_preferences.copy()
	preferences.text_scale = 1.5
	game._apply_hud_preferences(preferences)
	for category in ["audio","accessibility","camera","controls","video"]:
		game._apply_hud_preferences(preferences)
		game.settings_hub.buttons[category].pressed.emit()
		await frames()
		check(not game.settings_hub.visible and not game.preview.controls_enabled and not game.preview.pause_menu.visible, "Category modal: " + category)
		var category_root: Control = game.preview.settings_panel if category in ["camera", "controls"] else (game._audio_overlay if category == "audio" else (game._hud_overlay if category == "accessibility" else game._video_overlay))
		if category != "controls":
			inspect_labels(category_root, Rect2(Vector2.ZERO,Vector2(root.size)))
		for item: Node in category_root.find_children("*", "Button", true, false):
			if item.is_visible_in_tree() and category != "controls":
				check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(item.get_global_rect()), "Category action fits without scroll: " + item.text)
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://settings-category-%s-720-150.png" % category)
		if category == "camera":
			var before: float = game.preview.rig.sensitivity_x
			game.preview.settings_panel.sensitivity.value += 0.2
			game.preview.settings_panel.cancel()
			check(is_equal_approx(game.preview.rig.sensitivity_x,before), "Camera cancel restores live camera preview")
		elif category == "controls":
			game.preview.settings_panel.input_panel.begin_capture(&"drive_forward")
			game.preview.settings_panel.cancel()
			check(game.preview.settings_panel.input_panel.visible, "Escape capture keeps controls category open")
			game.preview.settings_panel.cancel()
		else:
			game._cancel_general_settings()
		await frames()
		check(game.settings_hub.visible and game.settings_hub.buttons[category].has_focus() and not game.preview.controls_enabled, "Category returns to focused hub without deferred recapture: " + category)
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(game.menu_host.visible and not game.preview.controls_enabled, "Hub Back restores originating main menu")
	game.start_practice()
	await frames(20)
	game.preview.release_controls()
	game.preview.settings_button.pressed.emit()
	await frames()
	check(game.settings_hub.visible and not game.preview.pause_menu.visible, "Pause Settings routes to hub")
	game.settings_hub.buttons.camera.pressed.emit()
	game.preview.settings_panel.cancel()
	await frames()
	check(game.settings_hub.visible and not game.preview.controls_enabled, "Camera close cannot recapture gameplay behind hub")
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(game.preview.pause_menu.visible and not game.preview.controls_enabled and not game.menu_host.visible, "Hub Back restores pause menu, not driving")
	game.open_settings()
	game.open_audio_settings()
	game.return_to_main()
	await frames()
	check(not game._general_settings_open() and not game.preview.settings_panel.visible and game.menu_host.visible, "Leave dismisses all category transactions")
	game.queue_free()
	await frames()
	print("SETTINGS HUB PASS" if failures == 0 else "SETTINGS HUB FAIL")
	quit(0 if failures == 0 else 1)
