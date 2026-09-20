extends SceneTree
## Real practice composition, authored damage only for visible warning coverage.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func frames(count := 6) -> void:
	for index: int in range(count):
		await process_frame

func run() -> void:
	var original_audio := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	check(not game.combat_hud.visible, "Main menu hides combat HUD")
	game.start_practice()
	await frames()
	check(game.combat_hud.visible and not game.preview.hud.visible and not game.preview.hint.visible, "Composed HUD replaces old resource and hint overlays")
	check(game.combat_hud.resources.Core.value.text == "100%", "Actual practice bot provides full core")
	check(game.combat_hud.roster_label.text.contains("UNSCORED"), "Practice has no fabricated duel rival")
	var bot: MvpBot = game.session.local_source()
	bot.combat.core = bot.combat.stats.core * 0.2
	bot.combat.zones.front = 0.0
	await frames()
	check(game.combat_hud.warning_label.text == "CORE CRITICAL" and game.combat_hud.components.front.text.contains("BREACHED"), "Actual bot state reaches visible HUD")
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = resolution
		await frames(12)
		game.gameplay_audio.caption_changed.emit("Core integrity critical")
		await frames()
		check(game._audio_caption.get_parent() == game.combat_hud.canvas, "Audio captions share scalable HUD layout")
		check(not game._audio_caption.get_global_rect().intersects(game.combat_hud.recovery_label.get_global_rect()), "Caption does not overlap recovery state")
		check(not game.practice_hud.get_global_rect().intersects(game.combat_hud.components.front.get_global_rect()), "Practice target does not overlap component diagram")
		var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
		check(bounds.encloses(game.practice_hud.get_global_rect()) and bounds.encloses(game.preview.network_diagnostics.get_global_rect()), "Auxiliary panels fit scalable HUD")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless" and resolution.x <= 1920:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://a-game-hud-%d.png" % resolution.x)
	game.preview.release_controls()
	await frames()
	check(not game.combat_hud.visible and not game.match_hud.visible, "Game menu suppresses HUD")
	game.preview.settings_button.pressed.emit()
	await frames()
	check(not game.combat_hud.visible, "Settings suppresses HUD")
	game.preview.settings_panel.cancel()
	game.restart_practice()
	await frames()
	check(game.combat_hud.visible and game.combat_hud.resources.Core.value.text == "100%" and not game.combat_hud.warning_label.visible, "Restart clears damage warning and restores new state")
	game.return_to_main()
	await frames()
	check(not game.combat_hud.visible and game.session.bot_views().is_empty(), "Leave hides HUD and clears public roster")
	game.queue_free()
	await frames()
	original_audio.apply()
	print("GAME HUD PASS" if failures == 0 else "GAME HUD FAIL")
	quit(0 if failures == 0 else 1)
