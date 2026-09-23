extends SceneTree
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index: int in range(count):
		await process_frame

func escape() -> void:
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	root.push_input(event)
	await frames()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var original := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	check(game._menu_music.bus == &"BBMusic" and game._menu_music.playing, "Menu melody uses the music bus and plays in menu")
	game.screen.get_node("%Settings").pressed.emit()
	await frames()
	check(game.settings_hub.visible, "Main Settings remains available")
	check(root.get_visible_rect().encloses(game.audio_settings_button.get_global_rect()), "Audio entry fits the 720p settings viewport")
	game.audio_settings_button.pressed.emit()
	await frames()
	check(game.audio_settings.visible and game._audio_overlay.visible and not game.settings_hub.visible,
		"Audio opens its own modal without changing control-settings implementation")
	check(game._menu_music.playing and not game.gameplay_input_allowed(), "Menu music continues while audio preview keeps driving disabled")
	check(root.get_visible_rect().encloses(game.audio_settings.get_global_rect()), "Audio panel fits the 720p viewport")
	var initial_volume := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BBMusic"))
	game.audio_settings.sliders.music.value = 0.1
	await frames()
	check(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BBMusic")) < initial_volume, "Music slider previews audible bus gain")
	await escape()
	check(not game._audio_overlay.visible and game.settings_hub.visible, "Escape returns from Audio to Settings")
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BBMusic")), initial_volume), "Escape restores original audio preferences")
	game._close_settings_hub()
	await frames()
	check(game.menu_host.visible and not game.preview.controls_enabled, "Leaving settings returns safely to main menu")
	game.start_practice()
	await frames()
	check(game.session.connection_state == "practice" and not game._menu_music.playing, "Practice stops menu melody")
	check(game._battle_music.playing and game._battle_music.bus == &"BBMusic", "Practice song uses the existing music controls")
	var battle_playback: AudioStreamPlayback = game._battle_music.get_stream_playback()
	game.open_settings()
	game.audio_settings_button.pressed.emit()
	await frames()
	check(game._audio_overlay.visible and not game._menu_music.playing and not game.gameplay_input_allowed(), "In-game audio settings do not restart menu music or enable input")
	game.audio_settings.sliders.music.value = 0.1
	await frames()
	check(game._battle_music.playing and game._battle_music.get_stream_playback() == battle_playback
		and AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BBMusic")) < initial_volume,
		"In-battle music volume previews without restarting playback")
	await escape()
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"BBMusic")), initial_volume), "Cancel restores battle music volume")
	game._close_settings_hub()
	game.return_to_main()
	await frames()
	check(game._menu_music.playing and game._audio_caption.text.is_empty(), "Return to menu restores music and clears game captions")
	check(not game._battle_music.playing, "Menu return stops the battle song")
	game.queue_free()
	await frames()
	original.apply()
	print("AUDIO MENU PASS" if failures == 0 else "AUDIO MENU FAIL")
	quit(0 if failures == 0 else 1)
