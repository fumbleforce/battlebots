extends SceneTree
## Headless playback state checks; no audible window or user settings writes.
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

func run() -> void:
	var game: Node3D = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	var music: AudioStreamPlayer = game.get_node("MenuMusic")
	check(music.stream is AudioStreamMP3 and music.stream.get_length() > 0, "Provided MP3 is playable")
	check(music.stream.loop and is_equal_approx(music.volume_db, -16.0), "Menu melody loops at moderate volume")
	var imported := load("res://assets/audio/menu/system_discovery.mp3") as AudioStreamMP3
	check(music.stream != imported, "Loop configuration uses a private stream resource")
	check(music.playing, "Main menu starts music")
	var playback := music.get_stream_playback()
	var router: Node = root.get_node("MenuRouter")
	for screen: String in ["mode_select", "lobby", "garage", "main"]:
		router.goto(screen, false)
		await frames()
		check(music.playing and music.get_stream_playback() == playback, "Navigation to %s keeps the current melody playing" % screen)
	game.open_settings()
	await frames()
	check(game.settings_hub.visible and music.playing and music.get_stream_playback() == playback,
		"Settings opened from main keep the melody continuous")
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(music.playing and music.get_stream_playback() == playback, "Closing menu settings does not restart the melody")
	game.start_practice()
	await frames()
	check(game.session.connection_state == "practice" and not music.playing, "Practice stops menu music")
	game.preview.release_controls()
	await frames()
	check(not music.playing, "Pausing gameplay does not start menu music")
	game.open_settings()
	await frames()
	check(game.settings_hub.visible and not music.playing, "Settings opened from gameplay stay silent")
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(not music.playing, "Closing gameplay settings stays silent")
	game.return_to_main()
	await frames()
	check(game.session.connection_state == "offline" and game.menu_host.visible and music.playing,
		"Returning to main resumes menu music")
	game.queue_free()
	await frames()
	check(not is_instance_valid(music), "Leaving the shell also frees its music player")
	print("MENU MUSIC PASS" if failures == 0 else "MENU MUSIC FAIL")
	quit(0 if failures == 0 else 1)
