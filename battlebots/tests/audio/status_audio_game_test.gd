extends SceneTree
## Real practice commands and controlled authoritative damage, not a natural duel.
var failures := 0
var cues: Array[String] = []

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
	game.gameplay_audio.cue_played.connect(func(cue: String) -> void: cues.append(cue))
	await frames()
	game.start_practice()
	await frames(30)
	check(cues.is_empty(), "New practice starts without invented status events")
	game.preview.set_physics_process(false)
	for step in 150:
		var command := BotCommand.new()
		command.sequence = game.preview.sequence
		game.preview.sequence += 1
		command.primary_held = true
		game.session.submit_local(command)
		await physics_frame
	await frames(2)
	check(cues.count("weapon_ready") == 1 and game._audio_caption.text == "Spinner at full speed", "Real spin-up reaches composed status audio and caption")
	var bot: MvpBot = game.session.local_source()
	# The practice build fits side armour only; unarmoured faces have nothing to breach.
	bot.combat.damage("left", bot.combat.zones.left)
	await frames(4)
	check(not bot.combat.eliminated and cues.count("armor_break") == 1, "Authoritative armor depletion plays one breach cue")
	check(game._audio_caption.text.to_lower().contains("left") and game.continuous_audio._arena.volume_db < game.continuous_audio.ARENA_DB,
		"Breach caption reaches actual HUD and ducks arena")
	game.preview.set_physics_process(true)
	game.restart_practice()
	await frames(15)
	check(cues.count("armor_break") == 1 and game._audio_caption.text.is_empty(), "Practice repair/reset does not replay breach history")
	game.return_to_main()
	await frames()
	check(game._audio_caption.text.is_empty(), "Leave clears status caption")
	game.queue_free()
	await frames()
	print("STATUS AUDIO GAME PASS" if failures == 0 else "STATUS AUDIO GAME FAIL")
	quit(0 if failures == 0 else 1)
