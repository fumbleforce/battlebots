extends Node
## Real composed practice lifecycle; elimination is explicit authoritative fixture setup.
## Practice restart preserves identity; leaving and starting again replaces it.
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index in range(count):
		await get_tree().physics_frame
		await get_tree().process_frame

func held(pressed: bool) -> void:
	for action in [&"drive_forward", &"primary", &"recover"]:
		if pressed: Input.action_press(action)
		else: Input.action_release(action)

func camera_check(game: Node, bot: MvpBot, label: String) -> void:
	var rig: BotOrbitCamera = game.preview.rig
	rig.update_camera(1.0)
	check(rig.source == game.source, label + ": camera retains stable session adapter")
	check(game.source.camera_anchor() == bot.camera_anchor(), label + ": current bot anchor")
	check(game.source.camera_exclusions() == bot.camera_exclusions(), label + ": current bot collision exclusions")
	check(rig.global_transform.is_finite() and rig.camera.global_transform.is_finite(), label + ": finite camera transform")
	check(rig.actual_distance >= 0.0 and rig.actual_distance <= rig.desired_distance + 0.001, label + ": bounded camera boom")
	check(rig.camera.global_position.distance_to(bot.camera_anchor().global_position) <= rig.desired_distance + 4.1, label + ": camera stays with current bot")

func canceled(bot: MvpBot, label: String) -> void:
	check(is_zero_approx(bot.command.throttle) and not bot.command.primary_held and bot.command.brake and bot.command.secondary_held,
		label + ": authoritative command brakes and cancels weapon")
	check(not bot.combat.launch, label + ": no release attack")

func run() -> void:
	var original_audio := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var game = preload("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	add_child(game)
	await frames()
	game.start_practice()
	await frames()
	check(game.session.connection_state == "practice", "Real practice started")
	var bot: MvpBot = game.session.local_source()
	if bot == null:
		get_tree().quit(1)
		return
	camera_check(game, bot, "Active")
	check(game.gameplay_input_allowed(), "Actual composed input gate permits focused active practice")
	held(false)
	await frames()
	held(true)
	await frames()
	check(bot.command.throttle > 0.9 and bot.command.primary_held, "Active held input reaches real bot")
	bot.combat.eliminate("camera lifecycle fixture")
	await frames()
	# Practice keeps driving captured through a knockout; the bot respawns on a timer.
	check(not game.gameplay_input_allowed() and game.preview.controls_enabled and not game.preview.pause_menu.visible,
		"Elimination suppresses actual app input without opening pause")
	canceled(bot, "Eliminated")
	camera_check(game, bot, "Eliminated")
	var anchor_id := bot.camera_anchor().get_instance_id()
	var old_exclusions := bot.camera_exclusions().duplicate()
	game.restart_practice()
	await frames()
	check(game.session.local_source() == bot and bot.camera_anchor().get_instance_id() == anchor_id, "Restart retains bot and camera anchor")
	check(not bot.combat.eliminated and game.gameplay_input_allowed(), "Restart revives and enables actual app gate")
	canceled(bot, "Held through restart")
	camera_check(game, bot, "Restarted")
	held(false)
	await frames()
	held(true)
	await frames()
	check(bot.command.throttle > 0.9 and bot.command.primary_held, "Release then press rearms after restart")
	game.return_to_main()
	await frames()
	check(game.session.local_source() == null and not game.preview.controls_enabled, "Leave removes source and cancels controls")
	check(game.source.camera_anchor() == game.source and game.source.camera_exclusions().is_empty(), "No stale anchor or collision exclusions while offline")
	game.preview.rig.update_camera(1.0)
	check(game.preview.rig.camera.global_transform.is_finite(), "Offline camera remains finite")
	game.start_practice()
	await frames()
	var replacement: MvpBot = game.session.local_source()
	check(replacement != null and replacement.camera_anchor().get_instance_id() != anchor_id, "New practice replaces bot anchor")
	for exclusion: RID in replacement.camera_exclusions():
		check(not old_exclusions.has(exclusion), "Replacement exclusions do not retain old bot RIDs")
	camera_check(game, replacement, "Replacement")
	canceled(replacement, "Held through replacement")
	held(false)
	await frames()
	held(true)
	await frames()
	check(replacement.command.throttle > 0.9 and replacement.command.primary_held, "Release then press rearms replacement")
	held(false)
	game.return_to_main()
	# Let the audio server release playback before destroying the fixture.
	game.set_process(false)
	game._menu_music.stop()
	await frames(8)
	game.queue_free()
	await frames()
	original_audio.apply()
	print("CAMERA ROUND LIFECYCLE PASS" if failures == 0 else "CAMERA ROUND LIFECYCLE FAIL")
	get_tree().quit(0 if failures == 0 else 1)
