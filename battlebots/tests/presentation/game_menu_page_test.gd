extends SceneTree
## Independent menu composition fixture; practice uses the real session.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index: int in range(count):
		await process_frame

func run() -> void:
	var original_audio := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	game.start_practice()
	await frames()
	game.preview.release_controls()
	await frames()
	check(game.preview.pause_menu.visible, "Practice exposes in-game menu")
	check(not game.gameplay_input_allowed(), "Game menu gates gameplay input")
	check(not game.match_hud.visible and not game.practice_hud.visible and not game.preview.get_node("DiagnosticsLayer").visible, "Arena overlays do not cover the game menu")
	check(game._diagnostics_canvas.visible and game.preview.network_diagnostics.is_visible_in_tree(), "Pause exposes diagnostics on its dedicated canvas")
	check(game.preview.pause_menu.theme == load("res://ui/menus/theme/menu_theme.tres"), "Game menu uses original menu theme")
	check(game.game_menu_page.context.text == "PRACTICE", "Menu identifies practice without invented score")
	for extent: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = extent
		await frames()
		for button: Button in [game.preview.resume_button, game.preview.settings_button, game.preview.return_button, game._restart_practice]:
			check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(button.get_global_rect()), "Menu action fits %s: %s" % [extent, button.text])
		check(game.preview.resume_button.get_global_rect().end.y <= game._restart_practice.get_global_rect().position.y, "Resume and restart do not overlap")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://exports/menu-review")
			root.get_texture().get_image().save_png("res://exports/menu-review/game-menu-%d.png" % extent.x)
	game.preview.settings_button.pressed.emit()
	await frames()
	check(game.settings_hub.visible and not game.preview.pause_menu.visible, "Settings replaces game menu")
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(game.preview.pause_menu.visible and not game.preview.controls_enabled, "Closing settings returns safely to game menu")
	game.preview.resume_button.pressed.emit()
	await frames()
	check(game.preview.controls_enabled and not game.preview.pause_menu.visible, "Resume returns to arena")
	check(not game._diagnostics_canvas.visible, "Ordinary play hides diagnostic details")
	game.preview.release_controls()
	await frames()
	check(game._diagnostics_canvas.visible and game.preview.network_diagnostics.is_visible_in_tree(), "Open pause before interacting with diagnostics")
	game.preview.network_diagnostics.details_button.button_down.emit()
	await frames()
	check(game._diagnostics_canvas.visible and not game.preview.controls_enabled, "Pause diagnostics stays visible after button-down with controls released")
	game.preview.network_diagnostics.details_button.pressed.emit()
	await frames()
	check(game.preview.network_diagnostics.expanded and game.preview.network_diagnostics.is_visible_in_tree(), "Diagnostics expansion completes after release")
	game.preview.resume_button.pressed.emit()
	await frames()
	check(game.preview.controls_enabled and not game.preview.network_diagnostics.expanded and not game._diagnostics_canvas.visible, "Resume collapses hidden details and restores gameplay")
	game.preview.release_controls()
	game.game_menu_page.render({"mode":"1v1", "round":2, "scores":[1, 0], "phase":"active", "remaining":73.0}, false)
	check(game.game_menu_page.score.text.contains("1 : 0"), "Online card uses published score")
	check(game.game_menu_page.phase_label.text.contains("1:13"), "Online card formats published clock")
	game.preview.return_button.pressed.emit()
	await frames()
	check(game.session.connection_state == "offline" and game.menu_host.visible, "Leave returns to main and closes session")
	game.queue_free()
	await frames()
	original_audio.apply()
	print("GAME MENU PAGE PASS" if failures == 0 else "GAME MENU PAGE FAIL")
	quit(0 if failures == 0 else 1)
