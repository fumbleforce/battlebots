extends Node
const FreePort := preload("res://tests/fixtures/free_port.gd")
## Scripted test input, not gameplay AI. All movement, attacks and match outcomes
## use the public session API from normal spawns with unmodified production rules.
const MATCH_TIMEOUT := 500.0
var failures := 0
var host: MvpSession
var client: MvpSession
var sessions: Array[MvpSession] = []
var effects: Array[Dictionary] = []
var client_effects: Array[Dictionary] = []
var host_results: Dictionary = {}
var client_results: Dictionary = {}
var driving := false
var previous_primary := false
var cooling := false
var active_seconds := 0.0
var last_recovery := -10.0
var started_ms := 0
var next_progress := 0.0
var last_phase := ""
var last_round := 0
var last_round_count := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func make_session(label: String) -> MvpSession:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	add_child(viewport)
	get_tree().set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	var session := MvpSession.new()
	session.name = "Session"
	viewport.add_child(session)
	sessions.append(session)
	return session

func driver_command() -> BotCommand:
	var command := BotCommand.new()
	command.brake = true
	if not driving or client.match_view.get("phase") not in ["active", "overtime"] \
		or client.world == null or not client.world.bots.has(client.local_entity) \
		or not client.world.bots.has(host.local_entity):
		previous_primary = false
		return command
	var state: Dictionary = client.world.bots[client.local_entity].remote_state
	var target: Dictionary = client.world.bots[host.local_entity].remote_state
	if state.is_empty() or target.is_empty() or state.eliminated or target.eliminated:
		previous_primary = false
		return command
	active_seconds += 1.0 / 60.0
	var pose: Transform3D = state.pose
	var displacement: Vector3 = target.pose.origin - pose.origin
	displacement.y = 0
	var local_target := pose.basis.inverse() * displacement
	var angle := atan2(local_target.x, -local_target.z)
	var distance := displacement.length()
	# Slow before contact rather than depending on a high-speed chassis impact.
	var forward_speed: float = Vector3(state.velocity).dot(-pose.basis.z)
	var contact_distance := 2.0 * BotScale.FACTOR
	var desired_speed := clampf((distance - contact_distance) * 1.3, -1.0, 4.0)
	command.steering = clampf(angle * 1.4, -1.0, 1.0)
	command.throttle = clampf((desired_speed - forward_speed) * 0.5, -0.4, 0.7) if absf(angle) < 1.2 else 0.0
	command.brake = absf(distance - contact_distance) < 0.10 * BotScale.FACTOR and absf(angle) < 0.10
	if state.heat > 80:
		cooling = true
	elif state.heat < 35:
		cooling = false
	command.primary_held = not cooling and absf(angle) < 0.25 and distance < 2.3 * BotScale.FACTOR \
		and fmod(active_seconds, 2.1) < 0.25
	command.primary_pressed = command.primary_held and not previous_primary
	previous_primary = command.primary_held
	if state.get("recovery_available", false) and active_seconds - last_recovery >= 1.0:
		command.recovery_pressed = true
		last_recovery = active_seconds
	return command

func frame() -> void:
	if host.local_entity > 0:
		var brake := BotCommand.new()
		brake.brake = true
		host.submit_local(brake)
	if client.local_entity > 0:
		client.submit_local(driver_command())
	await get_tree().physics_frame
	await get_tree().process_frame
	progress()

func until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await frame()
	return predicate.call()

func progress() -> void:
	var elapsed := (Time.get_ticks_msec() - started_ms) / 1000.0
	var phase := host.match_state.phase
	var round_number := host.match_state.round_index
	if phase != last_phase or round_number != last_round or elapsed >= next_progress:
		var bots: Array[Dictionary] = []
		if host.world != null:
			for bot: MvpBot in host.world.bots.values():
				bots.append({"entity":bot.entity_id, "position":bot.body.global_position,
					"core":bot.combat.core, "heat":bot.combat.heat,
					"weapon":bot.combat.weapon_phase, "eliminated":bot.combat.eliminated})
		print("NATURAL DUEL t=%.1f phase=%s round=%d remaining=%.1f scores=%s hits=%d bots=%s" %
			[elapsed, phase, round_number, host.match_state.remaining, host.match_state.scores, effects.size(), bots])
		last_phase = phase
		last_round = round_number
		next_progress = elapsed + 30.0
	if host.match_state.rounds.size() > last_round_count:
		var result: Dictionary = host.match_state.rounds.back()
		var hits := effects.filter(func(event: Dictionary) -> bool: return event.round == result.round)
		check(result.winner == host.players[client.local_entity].team, "Each natural round is won by the attacker; draws fail")
		check(not hits.is_empty(), "Every completed round contains actual hammer damage")
		var defender: Dictionary = result.participants[host.local_entity]
		check(defender.core < defender.core_max and result.participants[client.local_entity].damage > 0,
			"Natural round result records real defender health loss and attacker damage credit")
		print("NATURAL DUEL round result: ", result, " weapon_hits=", hits.size())
		last_round_count = host.match_state.rounds.size()

func health_converged() -> bool:
	if client.world == null or host.world == null:
		return false
	for id: int in host.world.bots:
		if not client.world.bots.has(id):
			return false
		var remote: Dictionary = client.world.bots[id].remote_state
		var combat: CombatState = host.world.bots[id].combat
		if remote.is_empty() or not is_equal_approx(remote.core, combat.core) \
			or remote.eliminated != combat.eliminated or remote.zones != combat.zones:
			return false
	return true

func run() -> void:
	started_ms = Time.get_ticks_msec()
	host = make_session("DuelHost")
	client = make_session("DuelClient")
	var port := FreePort.udp()
	check(host.host(port, true, 2) == OK, "Listen host binds a normal two-player lobby")
	check(client.join("127.0.0.1", port) == OK, "Remote attacker connects over real ENet")
	if not await until(func() -> bool: return client.local_entity > 0, 10):
		check(false, "Remote attacker admitted")
		await finish()
		return
	var draft := client.registry.duelist()
	check(client.registry.validate(draft).valid, "Canonical Duelist starter is legal")
	client.set_loadout(draft)
	if not await until(func() -> bool:
		return host.players[client.local_entity].loadout.parts == draft.parts \
			and host.players[client.local_entity].loadout.name == draft.name \
			and host.registry.validate(host.players[client.local_entity].loadout).valid, 5):
		check(false, "Canonical Duelist is admitted through normal loadout request")
		await finish()
		return
	host.combat_event.connect(func(event: Dictionary) -> void:
		if event.kind == "hammer" and event.attacker == client.local_entity \
			and event.target == host.local_entity and event.damage > 0:
			effects.append(event.duplicate(true))
			print("NATURAL DUEL hit: ", event))
	client.combat_event.connect(func(event: Dictionary) -> void: client_effects.append(event.duplicate(true)))
	host.session_event.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "results": host_results = data.duplicate(true))
	client.session_event.connect(func(kind: String, data: Dictionary) -> void:
		if kind == "results": client_results = data.duplicate(true))
	driving = true
	host.set_ready(true)
	client.set_ready(true)
	if not await until(func() -> bool: return host.match_state.phase == "results" or failures > 0, MATCH_TIMEOUT):
		check(false, "Normal combat reaches results within 500 seconds")
	if failures > 0:
		await finish()
		return
	driving = false
	check(host.match_state.rounds.size() == 2, "Two natural round wins finish the duel")
	check(host.match_state.winner == host.players[client.local_entity].team, "Attacker wins the match")
	check(await until(func() -> bool: return not client_results.is_empty() and health_converged(), 5),
		"Reliable results and final damage converge at the remote peer")
	check(host_results == client_results and not host_results.is_empty(), "Both peers receive identical complete results")
	check(client.match_view.get("scores") == host.match_view.get("scores"), "Both peers agree on final score")
	for event: Dictionary in effects:
		check(client_effects.any(func(received: Dictionary) -> bool:
			return received.match_id == event.match_id and received.round == event.round \
				and received.event_id == event.event_id and received.damage == event.damage),
			"Every authority hit reaches the remote peer with its correct match/round identity")
	var previous_match := host.match_state.match_id
	last_round_count = 0
	host.vote_rematch()
	client.vote_rematch()
	check(await until(func() -> bool:
		return host.match_state.match_id != previous_match and host.match_state.phase == "active" \
			and client.match_view.get("match_id") == host.match_state.match_id \
			and client.match_view.get("phase") == "active" and health_converged(), 20),
		"Both rematch votes start a synchronized new active duel")
	check(host.match_state.scores == [0, 0] and host.match_state.round_index == 1, "Rematch resets score and round")
	for bot: MvpBot in host.world.bots.values():
		check(not bot.combat.eliminated and is_equal_approx(bot.combat.core, bot.combat.stats.core), "Rematch fully repairs each bot")
		var fresh := CombatState.new(bot.combat.stats)
		check(bot.combat.zones == fresh.zones \
			and bot.combat.heat == 0 and bot.combat.cooldown == 0,
			"Rematch restores every zone, heat and weapon cooldown")
		check(bot.combat.effective_damage == 0 and bot.combat.charge == 0, "Rematch clears prior combat counters and charge")
	print("NATURAL DUEL completed: hits=%d delivered=%d duration=%.1fs" %
		[effects.size(), client_effects.size(), (Time.get_ticks_msec() - started_ms) / 1000.0])
	await finish()

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	await get_tree().physics_frame
	for viewport: Node in get_children():
		get_tree().set_multiplayer(null, viewport.get_path())
		viewport.queue_free()
	await get_tree().process_frame
	print("NATURAL DUEL PASS" if failures == 0 else "NATURAL DUEL FAIL")
	get_tree().quit(0 if failures == 0 else 1)
