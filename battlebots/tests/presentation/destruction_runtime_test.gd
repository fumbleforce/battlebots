extends Node3D
## Exercises real bot presentation and accepted wire snapshots; no network or authority code is replaced.
var failures: Array[String] = []
var registry := ContentRegistry.new()

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func make_bot(id: int, authored := true) -> MvpBot:
	var draft := SawbladeConfig.starter(registry) if authored else registry.starter()
	var bot := MvpBot.create(id, 0, draft, registry)
	add_child(bot)
	bot.set_process(false)
	bot.body.freeze = true
	bot.body.reset_pose = null
	return bot

func terminal_packet(bot: MvpBot, tick: int, round_index := 1) -> PackedByteArray:
	bot.combat.damage("underside", 10000.0)
	bot.server_tick = tick
	return WireCodec.encode_bot(bot, WireCodec.snapshot_epoch("destruction-fixture", round_index))

func healthy_packet(bot: MvpBot, tick: int, round_index := 1) -> PackedByteArray:
	bot.reset_round()
	bot.body.freeze = true
	bot.body.reset_pose = null
	bot.server_tick = tick
	return WireCodec.encode_bot(bot, WireCodec.snapshot_epoch("destruction-fixture", round_index))

func match_view(round_index := 1) -> Dictionary:
	return {"match_id":"destruction-fixture", "round":round_index, "phase":"active", "event_id":round_index}

func baseline(session: MvpSession, source: MvpBot, packet: PackedByteArray) -> MvpBot:
	var data := {"arena":"foundry", "server_tick":source.server_tick, "results":{},
		"match":match_view(), "bots":{source.entity_id:packet},
		"lobby":{"capacity":2, "mode":"teams", "slots":[
			{"entity_id":source.entity_id, "team":0, "peer":2, "loadout":source.loadout}]}}
	session._baseline(var_to_bytes(data))
	var remote: MvpBot = session.world.bots[source.entity_id]
	remote.set_process(false)
	return remote

func run() -> void:
	var headless := DisplayServer.get_name() == "headless"
	for authored: bool in [true, false]:
		var bot := make_bot(1, authored)
		var camera := bot.camera_anchor()
		var collider_count := bot.find_children("*", "CollisionObject3D", true, false).size()
		check((bot.destruction_visual == null) == headless, "Dedicated authority creates no destruction renderer; native bot does")
		bot._process(0.016)
		bot.combat.damage("underside", 10000.0)
		bot.step(0.0, false)
		bot._process(0.016)
		check(bot.combat.eliminated and bot.combat.core == 0.0, "Fixture reaches destruction through authoritative damage")
		check(bot.body.collision_layer == 0 and bot.body.collision_mask == 0, "Destruction preserves authoritative collision removal")
		check(bot.camera_anchor() == camera and is_instance_valid(camera), "Destroyed bot retains its camera anchor")
		check(bot.find_children("*", "CollisionObject3D", true, false).size() == collider_count, "Explosion adds no physics bodies")
		if not headless:
			var effect: Node3D = bot.destruction_visual
			check(effect.active and effect.burst_count == 1, "Real authored/classic bot explodes after lethal damage")
			bot._process(0.016)
			check(effect.burst_count == 1, "Actual repeated bot process cannot duplicate destruction")
			bot.reset_round()
			bot.body.freeze = true
			check(not effect.active, "Actual local round reset clears transient destruction immediately")
			bot._process(0.016)
			bot.combat.damage("underside", 10000.0)
			bot._process(0.016)
			check(effect.active and effect.burst_count == 2, "Actual repaired bot rearms for the next round")
			if authored:
				check(not bot.presentation.get_node("Visual").visible and not bot.presentation.get_node("ForwardStripe").visible,
					"Authored destruction/reset preserves hidden baseline primitives")
		bot.free()
	if not headless:
		check_remote_snapshots()
		if "--capture" in OS.get_cmdline_user_args(): await capture_arenas()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("DESTRUCTION RUNTIME PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

func check_remote_snapshots() -> void:
	var source := make_bot(9)
	var session := MvpSession.new()
	add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session._make_world()
	var first_terminal := terminal_packet(source, 100)
	var remote := baseline(session, source, first_terminal)
	remote._process(0.016)
	check(remote.destruction_visual.burst_count == 0 and not remote.destruction_visual.active,
		"Actual reconnect baseline creates a wreck without replaying its explosion")
	var original_healthy := healthy_packet(source, 200)
	remote = baseline(session, source, original_healthy)
	remote._process(0.016)
	var effect: Node3D = remote.destruction_visual
	var terminal := terminal_packet(source, 201)
	session._snapshot(terminal)
	var accepted := remote.remote_state.duplicate(true)
	remote._process(0.016)
	check(effect.burst_count == 1 and effect.active, "Accepted remote destruction explodes")
	check(remote.remote_state == accepted, "Explosion does not mutate the accepted wire state")
	check(remote.combat.core > 0.0 and not remote.combat.eliminated, "Remote presentation cannot change its local combat authority")
	session._snapshot(terminal)
	session._snapshot(original_healthy)
	session._snapshot(healthy_packet(source, 250, 99))
	remote._process(0.016)
	check(effect.burst_count == 1 and remote.remote_state.tick == 201, "Duplicate, old and wrong-round wire packets cannot rearm destruction")
	var repaired := healthy_packet(source, 202, 2)
	session._match(var_to_bytes({"view":match_view(2), "results":{}, "bots":{9:repaired}}))
	remote._process(0.016)
	check(not effect.active and not remote.read_view().eliminated, "Accepted new-round checkpoint clears the old explosion")
	session._snapshot(terminal_packet(source, 203, 2))
	remote._process(0.016)
	check(effect.active and effect.burst_count == 2, "Remote next round supports a fresh explosion")
	var burst: Node = effect.burst_root
	session.world.clear_bots()
	# clear_bots queues deletion; forcing the queued bot free models removal before the next render.
	remote.free()
	check(not is_instance_valid(burst), "Removing a network bot removes its lingering burst")
	session.free()
	source.free()
	# Remote construction can precede the accepted baseline by one rendered frame.
	var waiting := make_bot(12)
	waiting.simulated = false
	waiting._process(0.016)
	waiting.remote_state = waiting.combat.snapshot()
	waiting.remote_state.core = 0.0
	waiting.remote_state.eliminated = true
	waiting._process(0.016)
	check(waiting.destruction_visual.burst_count == 0, "Absent remote data never establishes a fabricated alive baseline")
	waiting.free()

func capture_arenas() -> void:
	get_window().size = Vector2i(1280, 720)
	var camera := Camera3D.new()
	add_child(camera)
	var target := Vector3(0, 0.7, 0)
	camera.position = target + Vector3(-3.4, 2.8, -4.2).normalized() * 7.0
	camera.look_at(target)
	camera.current = true
	var heading := Label.new()
	heading.position = Vector2(24, 20)
	heading.add_theme_font_size_override("font_size", 22)
	add_child(heading)
	for arena_name: String in ["foundry", "moon"]:
		var arena_path := "res://scenes/arenas/moon_arena.tscn" if arena_name == "moon" else "res://scenes/arenas/baseline_arena.tscn"
		var arena: Node3D = load(arena_path).instantiate()
		add_child(arena)
		var bot := make_bot(20)
		bot.body.global_position = Vector3(0, bot.combat.stats.size.y * 0.5 + 0.02, 0)
		bot._process(0.016)
		for frame: int in 8: await get_tree().process_frame
		bot.combat.damage("underside", 10000.0)
		bot._process(0.0)
		bot.destruction_visual.set_process(false)
		var elapsed := 0.0
		for moment: float in [0.08, 0.25, 0.7, 1.5]:
			bot.destruction_visual._process(moment - elapsed)
			elapsed = moment
			heading.text = "%s  /  core destruction  /  %.2f s" % [arena_name.capitalize(), moment]
			await RenderingServer.frame_post_draw
			var output := OS.get_environment("TEMP").path_join("destruction-%s-%03d.png" % [arena_name, roundi(moment * 100)])
			check(get_viewport().get_texture().get_image().save_png(output) == OK, "Native capture saved: " + output)
			print("DESTRUCTION CAPTURE ", output)
		bot.free()
		arena.free()
		await get_tree().process_frame
	heading.free()
	camera.free()
