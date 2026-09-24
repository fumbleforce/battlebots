extends Node
const FreePort := preload("res://tests/fixtures/free_port.gd")
## Two real ENet peers exercise the composed client input/camera lifecycle.
## Only authority elimination and phase remaining timers are fixture shortcuts.
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

func until(predicate: Callable, count := 360) -> bool:
	for index in range(count):
		if predicate.call(): return true
		await frames(1)
	return false

func held(pressed: bool) -> void:
	for action in [&"drive_forward", &"primary", &"recover"]:
		if pressed: Input.action_press(action)
		else: Input.action_release(action)

func viewport(label: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	add_child(view)
	get_tree().set_multiplayer(SceneMultiplayer.new(), view.get_path())
	return view

func camera_check(game: Node, label: String) -> void:
	var bot: MvpBot = game.session.local_source()
	check(bot != null, label + ": local bot exists")
	if bot == null: return
	var rig: BotOrbitCamera = game.preview.rig
	rig.update_camera(1.0)
	check(rig.source == game.source, label + ": stable session adapter")
	check(game.source.camera_anchor() == bot.camera_anchor(), label + ": current anchor")
	check(game.source.camera_exclusions() == bot.camera_exclusions(), label + ": current collision exclusions")
	check(rig.camera.global_transform.is_finite(), label + ": finite camera")
	check(rig.actual_distance >= 0.0 and rig.actual_distance <= rig.desired_distance + 0.001, label + ": bounded boom")
	var sphere := SphereShape3D.new()
	sphere.radius = rig.camera_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = rig.camera.global_position
	query.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	query.exclude = game.source.camera_exclusions()
	check(bot.get_world_3d().direct_space_state.intersect_shape(query).is_empty(), label + ": camera sphere clear")

func canceled(bot: MvpBot, label: String) -> void:
	check(is_zero_approx(bot.command.throttle) and is_zero_approx(bot.command.steering) and not bot.command.primary_held and not bot.command.primary_pressed and not bot.command.recovery_pressed and bot.command.brake and bot.command.secondary_held,
		label + ": authoritative controls canceled and brake held")
	check(not bot.combat.launch, label + ": no release attack")

func run() -> void:
	var original_audio := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var host_view := viewport("Host")
	var host_app := Node.new()
	host_app.name = "Game"
	host_view.add_child(host_app)
	var host := MvpSession.new()
	host.name = "Session"
	host_app.add_child(host)
	var client_view := viewport("Client")
	var game = preload("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.name = "Game"
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	client_view.add_child(game)
	await frames()
	var port := FreePort.udp()
	check(host.host(port, true, 2) == OK, "Real duel host starts")
	check(game.session.join("127.0.0.1", port) == OK, "Real composed client joins")
	var joined := await until(func() -> bool: return game.session.local_entity > 0 and game.session.lobby_view.get("slots", []).size() == 2)
	check(joined, "Both actual ENet peers admitted")
	if joined:
		host.set_ready(true)
		game.session.set_ready(true)
		var countdown := await until(func() -> bool: return game.session.match_view.get("phase") == "countdown")
		check(countdown, "Readiness and loading reach server countdown")
		if countdown:
			game.resume_gameplay()
			held(false)
			await frames()
			held(true)
			await frames(12)
			check(not game.gameplay_input_allowed(), "Countdown denies actual input gate")
			var authority_bot: MvpBot = host.world.bots[game.session.local_entity]
			canceled(authority_bot, "Initial countdown")
			camera_check(game, "Initial countdown")
			host.match_state.remaining = 0.0
			check(await until(func() -> bool: return game.session.match_view.get("phase") == "active"), "Server starts first round")
			await frames(12)
			check(game.gameplay_input_allowed(), "Focused active client permits actual gate")
			canceled(authority_bot, "Held through initial start")
			held(false)
			await frames(6)
			held(true)
			check(await until(func() -> bool: return authority_bot.command.throttle > 0.9 and authority_bot.command.primary_held, 90), "Fresh controls reach authority over ENet")
			camera_check(game, "First active round")
			var anchor_id: int = game.session.local_source().camera_anchor().get_instance_id()
			authority_bot.combat.eliminate("duel camera fixture")
			check(await until(func() -> bool: return game.session.match_view.get("phase") == "intermission"), "Elimination reaches real server intermission")
			await frames(12)
			check(game.session.local_source().read_view().eliminated and not game.gameplay_input_allowed(), "Eliminated client cannot control")
			canceled(authority_bot, "Eliminated intermission")
			camera_check(game, "Eliminated intermission")
			host.match_state.remaining = 0.0
			check(await until(func() -> bool: return game.session.match_view.get("phase") == "countdown" and game.session.match_view.get("round") == 2), "Server resets second round")
			await frames(12)
			check(not game.session.local_source().read_view().eliminated and not game.gameplay_input_allowed(), "Revived countdown still gates controls")
			check(game.session.local_source().camera_anchor().get_instance_id() == anchor_id, "Round reset preserves current bot anchor")
			canceled(authority_bot, "Second countdown")
			camera_check(game, "Second countdown")
			host.match_state.remaining = 0.0
			check(await until(func() -> bool: return game.session.match_view.get("phase") == "active"), "Server starts second round")
			await frames(12)
			check(game.gameplay_input_allowed(), "Second active round permits actual input gate")
			canceled(authority_bot, "Held through second start")
			camera_check(game, "Second active round")
			held(false)
			await frames(6)
			held(true)
			check(await until(func() -> bool: return authority_bot.command.throttle > 0.9 and authority_bot.command.primary_held, 90), "Release then fresh press rearms next round over ENet")
	held(false)
	game.session.leave()
	host.leave()
	await frames()
	for view in [client_view, host_view]:
		get_tree().set_multiplayer(null, view.get_path())
		view.queue_free()
	await frames()
	original_audio.apply()
	print("CAMERA DUEL LIFECYCLE PASS" if failures == 0 else "CAMERA DUEL LIFECYCLE FAIL")
	get_tree().quit(0 if failures == 0 else 1)
