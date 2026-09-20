extends SceneTree
## Real composed practice consumes public commands and authority audio records.
var failures := 0
var action_audio: Array[Node] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 8) -> void:
	for index in count: await process_frame

func check_action_audio(enabled: bool, label: String) -> void:
	for item: Node in action_audio:
		check(item.playback_enabled == enabled, label + " sets the owned action-audio gate")
		if not enabled:
			for voice: AudioStreamPlayer3D in item.find_children("*", "AudioStreamPlayer3D", true, false):
				check(not voice.playing, label + " stops every owned spatial voice")

func run() -> void:
	# Select the canonical Scorpion in memory; never write the user's profile.
	root.get_node("PlayerProfile").active_bot = 3
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
	check(game.session.audio_views().size() == 4 and audio._bots.size() == 2 and audio._arena.playing,
		"Practice publishes four records while the existing two-bot loop pool and arena ambience stay bounded")
	if DisplayServer.get_name() != "headless":
		var scorpion: ScorpionVisual = game.session.local_source().scorpion_visual
		action_audio = [scorpion.walker_legs.footfall_audio, scorpion.gun_effects.weapon_audio]
		check_action_audio(true, "Active Scorpion practice")
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
		command.secondary_held = true
		command.auxiliary_held = true
		game.session.submit_local(command)
		await physics_frame
	await frames(2)
	check(audio._bots.has(id) and audio._bots[id].get_node("drive").playing, "Real public drive commands activate spatial motor loop")
	for item: Node in action_audio:
		check(item.played_count > 0, "Normal walking and accepted gun commands produce owned action sounds")
	var record: Dictionary = game.session.audio_views().filter(func(value: Dictionary) -> bool: return value.entity_id == id)[0]
	check(audio._bots[id].global_position.distance_to(record.position) < 1.0, "Audio follows actual bot presentation")
	game.preview.set_physics_process(true)
	game.gameplay_audio.cue_played.emit("low_core")
	check(audio._arena.volume_db < audio.ARENA_DB, "Existing warning cue ducks arena ambience")
	game.preview.release_controls()
	await frames()
	check(audio._bots.is_empty() and not audio._arena.playing, "Game menu stops continuous sound")
	check_action_audio(false, "Game menu")
	game.open_settings()
	await frames()
	check(audio._bots.is_empty(), "Settings do not resume gameplay loops")
	check_action_audio(false, "Settings")
	game._close_settings_hub()
	game.restart_practice()
	await frames(12)
	check(game.session.audio_views().size() == 4 and audio._bots.size() == 2 and audio._arena.playing,
		"Practice restart republishes four fresh records through the existing bounded loop pool")
	check_action_audio(true, "Restart and resume")
	game._recovering = true
	await frames()
	check(audio._bots.is_empty() and not audio._arena.playing, "Recovery screen stops stale continuous sound")
	check_action_audio(false, "Recovery screen")
	game._recovering = false
	game.resume_gameplay()
	await frames()
	check_action_audio(true, "Recovery resume")
	game.return_to_main()
	await frames()
	check(audio._bots.is_empty() and not audio._arena.playing, "Leave clears arena and bot loops")
	for item: Node in action_audio: check(not is_instance_valid(item), "Leave frees owned action-audio players")
	action_audio.clear()
	game.queue_free()
	await frames()
	print("CONTINUOUS AUDIO GAME PASS" if failures == 0 else "CONTINUOUS AUDIO GAME FAIL")
	quit(0 if failures == 0 else 1)
