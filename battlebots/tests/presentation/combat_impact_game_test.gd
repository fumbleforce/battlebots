extends Node
## Frozen, positioned real colliders isolate confirmed contact integration, not driving feel.
var failures: Array[String] = []
var game: Node
var impacts: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count := 4) -> void:
	for index: int in count: await get_tree().process_frame

func _ready() -> void:
	run.call_deferred()

func contact_hit() -> bool:
	var attacker := game.session.local_source() as MvpBot
	var target := game.session.practice_target() as MvpBot
	for bot: MvpBot in [attacker, target]:
		bot.body.freeze = true
		bot.body.collision_mask = 0
		bot.body.linear_velocity = Vector3.ZERO
		bot.body.angular_velocity = Vector3.ZERO
	attacker.body.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0) * BotScale.FACTOR)
	target.body.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, -2.3) * BotScale.FACTOR)
	for tick: int in 3: await get_tree().physics_frame
	attacker.previous_pose = attacker.body.global_transform
	target.previous_pose = target.body.global_transform
	var before := impacts.size()
	var core_before := target.combat.core
	for tick: int in 100:
		var command := BotCommand.new()
		command.primary_held = true
		game.session.submit_local(command)
		await get_tree().physics_frame
		if impacts.size() > before: break
	game.session.submit_local(BotCommand.new())
	check(impacts.size() > before, "Real world saw contact emits confirmed session event")
	check(target.combat.core < core_before, "Real contact damages authoritative target")
	return impacts.size() > before

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	add_child(game)
	await frames()
	var profile := get_node("/root/PlayerProfile")
	var profile_index: int = profile.active_bot
	var previous_draft: Dictionary = profile.loadouts[profile_index].duplicate(true)
	var draft := SawbladeConfig.starter(ContentRegistry.new())
	draft.parts.weapon = "saw"
	profile.loadouts[profile.active_bot] = draft
	game.start_practice()
	await frames(30)
	game.preview.set_physics_process(false)
	game.preview.rig.auto_recenter = false
	game.preview.rig.yaw = -0.8
	game.preview.rig.desired_distance = 12.0
	game.session.combat_event.connect(func(event: Dictionary): impacts.append(event.duplicate(true)))
	var visual: CombatImpactVisual = game.impact_feedback.visual
	check(visual.spark_count() == 0 and visual.fragment_count() == 0, "Practice has no invented impact")
	if await contact_hit():
		check(visual.spark_count() > 0 and visual.fragment_count() > 0, "Actual game renders confirmed damaging hit")
		var count := visual.spark_count() + visual.fragment_count()
		game.session.combat_event.emit(impacts.back().duplicate(true))
		check(visual.spark_count() + visual.fragment_count() == count, "Duplicate real event does not duplicate decoration")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await get_tree().create_timer(0.16).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("combat-impact-game.png"))
		await get_tree().create_timer(1.6).timeout
		check(visual.spark_count() == 0 and visual.fragment_count() == 0, "Real hit decoration expires without further contacts")
	if await contact_hit():
		game.restart_practice()
		check(visual.spark_count() == 0 and visual.fragment_count() == 0, "Practice restart clears real impact immediately")
		await frames()
		game.preview.set_physics_process(false)
	if await contact_hit():
		game.return_to_main()
		check(visual.spark_count() == 0 and visual.fragment_count() == 0, "Leaving clears real impact immediately")
	game.queue_free()
	await frames()
	profile.loadouts[profile_index] = previous_draft
	if failures.is_empty(): print("COMBAT IMPACT GAME PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
