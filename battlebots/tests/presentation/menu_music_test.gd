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
	var battle: AudioStreamPlayer = game.get_node("BattleMusic")
	check(battle.stream is AudioStreamMP3 and battle.stream.get_length() > 60.0, "Supplied battle MP3 is playable")
	check(battle.stream.loop and battle.bus == &"BBMusic", "Battle song loops through the music volume bus")
	check(battle.stream != load("res://assets/audio/battle/relentless_action.mp3"), "Battle loop uses a private resource")
	check(not battle.playing, "Battle song stays silent in the main menu")
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
	check(battle.playing, "Practice starts the battle song")
	var battle_playback := battle.get_stream_playback()
	game.preview.release_controls()
	await frames()
	check(not music.playing, "Pausing gameplay does not start menu music")
	check(battle.playing and battle.get_stream_playback() == battle_playback, "Pause keeps the battle song continuous")
	game.open_settings()
	await frames()
	check(game.settings_hub.visible and not music.playing, "Gameplay settings keep the menu melody silent")
	check(battle.playing and battle.get_stream_playback() == battle_playback, "Gameplay settings preserve battle playback")
	game.settings_hub.back_button.pressed.emit()
	await frames()
	check(not music.playing, "Closing gameplay settings keeps the menu melody silent")
	check(game.session.restart_practice() == OK, "Practice can restart with its soundtrack running")
	await frames()
	check(battle.playing and battle.get_stream_playback() == battle_playback, "Practice restart does not restart the song")
	# Cross the real MP3 boundary to verify playback loops rather than ending.
	battle.seek(battle.stream.get_length() - 0.05)
	# Audio mixing uses wall time even when CI accelerates scene time with fixed-fps.
	var loop_deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < loop_deadline:
		await process_frame
	check(battle.playing and battle.get_playback_position() < 1.0, "Battle MP3 loops at the end of the recording")
	game.return_to_main()
	await frames()
	check(game.session.connection_state == "offline" and game.menu_host.visible and music.playing,
		"Returning to main resumes menu music")
	check(not battle.playing, "Returning to main stops the battle song")
	game.queue_free()
	await frames()
	check(not is_instance_valid(music), "Leaving the shell also frees its music player")
	check(not is_instance_valid(battle), "Leaving the shell also frees battle playback")
	print("MENU MUSIC PASS" if failures == 0 else "MENU MUSIC FAIL")
	quit(0 if failures == 0 else 1)
