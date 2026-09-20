extends Node
## Independent F6 scene: ten physical spawns plus pure authoritative team rules.
var failures := 0
var world: AuthorityWorld
var registry := ContentRegistry.new()
var teams: Dictionary = {}

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func combatants() -> Dictionary:
	var states := {}
	var stats: Dictionary = registry.validate(registry.starter()).stats
	for id: int in range(1, 11):
		states[id] = CombatState.new(stats)
	return states

func frames(count: int) -> void:
	for index: int in range(count):
		world.step(1.0 / 60.0, false, 1)
		await get_tree().physics_frame
		await get_tree().process_frame

func run() -> void:
	for id: int in range(1, 11):
		teams[id] = 0 if id <= 5 else 1
	check_rules()
	world = AuthorityWorld.new()
	add_child(world)
	for id: int in range(1, 11):
		var team: int = teams[id]
		var slot := (id - 1) % 5
		var bot := world.spawn(id, team, slot, registry.starter(), 5)
		var marker: Node3D = world.arena.get_node("SpawnPoints/Team%d_%d" % [team + 1, slot + 1])
		check(bot.spawn_pose.basis.is_equal_approx(marker.global_basis) and is_equal_approx(bot.spawn_pose.origin.x, marker.global_position.x)
			and absf(bot.spawn_pose.origin.z) <= absf(marker.global_position.z), "5v5 bot %d preserves its authored lane and facing with hull clearance" % id)
		var forward := -bot.spawn_pose.basis.z
		check(forward.dot(Vector3.FORWARD if team == 0 else Vector3.BACK) > 0.99,
			"5v5 bot %d faces the enemy side" % id)
	await frames(90)
	check_spawns("initial")
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		bot.combat.damage("front", 100)
		bot.body.linear_velocity = Vector3(3, 2, 1)
		bot.body.angular_velocity = Vector3(1, 2, 3)
		bot.body.global_position = bot.spawn_pose.origin + Vector3(1, 2, 0)
	world.reset_round()
	await frames(90)
	check_spawns("reset")
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		check(is_equal_approx(bot.combat.core, bot.combat.stats.core), "5v5 reset repairs bot %d" % id)
		check(bot.body.linear_velocity.length() < 0.1 and bot.body.angular_velocity.length() < 0.1,
			"5v5 reset clears old motion for bot %d" % id)
	world.clear_bots()
	await get_tree().process_frame
	for team: int in range(2):
		for slot: int in range(2):
			var id := team * 2 + slot + 1
			var bot := world.spawn(id, team, slot, registry.starter())
			var marker: Node3D = world.arena.get_node("SpawnPoints/Team%d_%d" % [team + 1, 2 if slot == 0 else 4])
			check(bot.spawn_pose.is_equal_approx(world.clear_spawn_pose(bot, marker.global_transform)), "Default 2v2 preserves marker mapping with physical clearance")
	world.clear_bots()
	await get_tree().process_frame
	for team: int in range(2):
		var bot := world.spawn(team + 1, team, 0, registry.starter(), 1)
		var marker: Node3D = world.arena.get_node("SpawnPoints/Team%d_2" % (team + 1))
		check(bot.spawn_pose.is_equal_approx(world.clear_spawn_pose(bot, marker.global_transform)), "Duel preserves marker 2 per team with physical clearance")
	world.queue_free()
	await get_tree().process_frame
	print("FIVE V FIVE RULES PASS" if failures == 0 else "FIVE V FIVE RULES FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func check_spawns(label: String) -> void:
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		var at := bot.body.global_position
		check(at.is_finite() and absf(at.x) < 25 and absf(at.z) < 25 and at.y > 0,
			"%s bot %d stays on playable floor" % [label, id])
		check(Vector2(at.x, at.z).distance_to(Vector2(bot.spawn_pose.origin.x, bot.spawn_pose.origin.z)) < 0.05,
			"%s bot %d physically reaches assigned spawn" % [label, id])
		check((-bot.body.global_basis.z).dot(-bot.spawn_pose.basis.z) > 0.99,
			"%s bot %d keeps authored facing" % [label, id])
		for other_id: int in world.bots:
			if other_id > id:
				check(at.distance_to(world.bots[other_id].body.global_position) > 5.9,
					"%s spawns %d and %d stay separated" % [label, id, other_id])

func check_rules() -> void:
	var match_state := MatchState.new()
	var states := combatants()
	match_state.begin(10)
	check(match_state.snapshot().mode == "5v5" and match_state.snapshot().capacity == 10,
		"5v5 match snapshot carries mode and capacity")
	match_state.transition("countdown", 5)
	match_state.advance(5, states, teams)
	check(match_state.phase == "active" and match_state.remaining == 240, "5v5 starts a 240-second round")
	match_state.advance(180, states, teams)
	check(match_state.phase == "active" and match_state.remaining == 60, "5v5 remains active beyond the 2v2 timer")
	match_state.advance(60, states, teams)
	check(match_state.phase == "overtime" and match_state.remaining == 30, "Tied 5v5 enters 30-second overtime")
	match_state.advance(30, states, teams)
	check(match_state.phase == "intermission" and match_state.rounds.back().winner == -1, "Overtime tie draws")
	for round_number: int in range(2, 6):
		match_state.advance(15, states, teams)
		check(match_state.round_index == round_number and match_state.phase == "countdown", "Draw advances round")
		match_state.advance(5, states, teams)
		check(match_state.remaining == 240, "Every 5v5 round uses 240 seconds")
		match_state.advance(240, states, teams)
		match_state.advance(30, states, teams)
	check(match_state.phase == "results" and match_state.winner == -1 and match_state.rounds.size() == 5,
		"Five drawn 5v5 rounds finish the match")
	match_state.begin(10)
	for round_number: int in range(1, 3):
		states = combatants()
		match_state.transition("countdown", 5)
		match_state.advance(5, states, teams)
		for id: int in range(6, 11):
			states[id].eliminate("test")
		match_state.advance(1.0 / 60, states, teams)
		if round_number == 1:
			check(match_state.phase == "intermission" and match_state.scores == [1, 0], "First five-bot wipe wins one round")
			match_state.advance(15, states, teams)
	check(match_state.phase == "results" and match_state.winner == 0 and match_state.scores == [2, 0],
		"5v5 remains first to two round wins")
	match_state.begin(10)
	states = combatants()
	match_state.transition("active", 240)
	for state: CombatState in states.values():
		state.eliminate("same_tick")
	match_state.advance(1.0 / 60, states, teams)
	check(match_state.rounds.back().winner == -1 and match_state.scores == [0, 0], "Simultaneous ten-bot wipe draws")
	for count: int in [2, 4]:
		match_state.begin(count)
		match_state.transition("countdown", 5)
		match_state.advance(5, combatants(), teams)
		check(match_state.remaining == 180 and match_state.snapshot().capacity == count,
			"Existing %d-player timer remains 180 seconds" % count)
		check(match_state.snapshot().mode == ("1v1" if count == 2 else "2v2"), "Existing mode label stays correct")
	match_state.begin()
	check(match_state.capacity == 4 and match_state.mode == "2v2" and match_state.round_seconds == 180,
		"No-argument begin preserves default 2v2")
