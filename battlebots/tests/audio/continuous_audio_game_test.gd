extends SceneTree
## Real composed practice consumes public commands and authority audio records.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 8) -> void:
	for index in count: await process_frame

func run() -> void:
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	var audio = game.continuous_audio
	check(audio._bots.is_empty() and not audio._arena.playing, "Main menu does not play arena sound")
	game.start_practice()
	await frames(45)
	check(audio._bots.size() == 2 and audio._arena.playing, "Practice composition supplies both bots and arena ambience")
	var id: int = game.session.local_entity
	# This integration fixture supplies commands itself; avoid a competing live
	# keyboard sampler overwriting them with neutral input in the headless window.
	game.preview.set_physics_process(false)
	for step in 60:
		var command := BotCommand.new()
		command.sequence = game.preview.sequence
		game.preview.sequence += 1
		command.throttle = -1.0
		command.primary_held = true
		game.session.submit_local(command)
		await physics_frame
	await frames(2)
	check(audio._bots.has(id) and audio._bots[id].get_node("drive").playing, "Real public drive commands activate spatial motor loop")
	var record: Dictionary = game.session.audio_views().filter(func(value: Dictionary) -> bool: return value.entity_id == id)[0]
	check(audio._bots[id].global_position.distance_to(record.position) < 1.0, "Audio follows actual bot presentation")
	game.preview.set_physics_process(true)
	game.gameplay_audio.cue_played.emit("low_core")
	check(audio._arena.volume_db < audio.ARENA_DB, "Existing warning cue ducks arena ambience")
	game.preview.release_controls()
	await frames()
	check(audio._bots.is_empty() and not audio._arena.playing, "Game menu stops continuous sound")
	game.open_settings()
	await frames()
	check(audio._bots.is_empty(), "Settings do not resume gameplay loops")
	game.preview.settings_panel.cancel()
	game.restart_practice()
	await frames(12)
	check(audio._bots.size() == 2 and audio._arena.playing, "Practice restart resumes fresh sound sources")
	game._recovering = true
	await frames()
	check(audio._bots.is_empty() and not audio._arena.playing, "Recovery screen stops stale continuous sound")
	game._recovering = false
	game.return_to_main()
	await frames()
	check(audio._bots.is_empty() and not audio._arena.playing, "Leave clears arena and bot loops")
	game.queue_free()
	await frames()
	print("CONTINUOUS AUDIO GAME PASS" if failures == 0 else "CONTINUOUS AUDIO GAME FAIL")
	quit(0 if failures == 0 else 1)
