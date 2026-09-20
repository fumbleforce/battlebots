extends SceneTree
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 5) -> void:
	for index: int in range(count):
		await process_frame

func select_large(panel: HudSettingsPanel) -> void:
	panel.text_scale_choice.select(2)
	panel.text_scale_choice.item_selected.emit(2)
	panel.palette_choice.select(1)
	panel.palette_choice.item_selected.emit(1)
	panel.contrast_toggle.button_pressed = true

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var path := "user://a-hud-integration-%d.cfg" % OS.get_process_id()
	var original_audio := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.hud_settings_path = path
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	game.screen.get_node("%Settings").pressed.emit()
	await frames()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(game.hud_settings_button.get_global_rect()), "HUD accessibility entry fits settings at720p")
	game.hud_settings_button.pressed.emit()
	await frames()
	check(game._hud_overlay.visible and not game.preview.settings_panel.visible and not game.gameplay_input_allowed(), "HUD settings are modal")
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(game.hud_settings.get_global_rect()), "HUD settings panel fits720p")
	select_large(game.hud_settings)
	await frames()
	check(game.combat_hud.resources.Core.value.get_theme_font_size("font_size") == 27, "Live draft increases actual text size to150%")
	check(game.hud_preferences.text_scale == 1.0, "Preview does not publish unsaved preferences")
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	root.push_input(escape)
	await frames()
	check(not game._hud_overlay.visible and game.preview.settings_panel.visible, "Escape returns to settings")
	check(game.combat_hud.resources.Core.value.get_theme_font_size("font_size") == 18, "Cancel restores original HUD text")
	game.hud_settings_button.pressed.emit()
	select_large(game.hud_settings)
	game.hud_settings.save_button.pressed.emit()
	await frames()
	check(game.hud_preferences.text_scale == 1.5 and HudPreferences.load_file(path).high_contrast, "Save publishes and persists HUD preferences")
	game.preview.settings_panel.cancel()
	game.start_practice()
	await frames()
	var bot: MvpBot = game.session.local_source()
	bot.combat.core = bot.combat.stats.core * 0.2
	bot.combat.zones.front = 0.0
	for extent: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = extent
		await frames(10)
		game.gameplay_audio.caption_changed.emit("Core integrity critical")
		await frames()
		check(game.combat_hud.visible and game.practice_hud.visible, "Large HUD and practice target remain visible")
		check(not game.practice_hud.get_global_rect().intersects(game.combat_hud.resources.Core.value.get_global_rect()), "Practice target avoids resource text")
		check(not game.practice_hud.get_global_rect().intersects(game.combat_hud.warning_label.get_global_rect()), "Practice target avoids elimination warning")
		check(not game._audio_caption.get_global_rect().intersects(game.combat_hud.heading_label.get_global_rect()), "Scaled caption avoids compass")
		check(not game._audio_caption.get_global_rect().intersects(game.combat_hud.recovery_label.get_global_rect()), "Scaled caption avoids recovery")
		check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(game.practice_hud.get_global_rect()), "Large practice readout fits viewport")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://a-accessible-game-%d.png" % extent.x)
	game.return_to_main()
	game.queue_free()
	await frames()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	original_audio.apply()
	print("HUD ACCESSIBILITY MENU PASS" if failures == 0 else "HUD ACCESSIBILITY MENU FAIL")
	quit(0 if failures == 0 else 1)
