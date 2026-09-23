extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	var registry := ContentRegistry.new()
	var stats := registry.validate(registry.starter()).stats
	var bot := CombatState.new(stats)
	check(bot.damage("front", 50) == 50 and bot.zones.front == 0 and bot.core == 190, "Bare face passes full damage to core")
	var armoured := registry.starter()
	armoured.cosmetics = {"paint":"cyan", "sawblade":SawbladeConfig.defaults()}
	armoured.cosmetics.sawblade.armor_front = 1
	var armoured_stats := registry.validate(armoured).stats
	bot = CombatState.new(armoured_stats)
	check(bot.zones.front == 90 and bot.zones.left == 60 and bot.zones.right == 60 and bot.zones.top == 0
		and bot.zones.underside == 0 and bot.snapshot().plate_max == armoured_stats.plates, "Zones hold selected piece HP")
	check(bot.damage("left", 40) == 40 and bot.zones.left == 20 and bot.core == 240, "Intact piece fully shields core")
	check(bot.damage("front", 100) == 100 and bot.zones.front == 0 and bot.core == 230, "Overflow beyond piece HP reaches core")
	check(bot.damage("front", 10) == 10 and bot.core == 220, "Broken piece leaves face bare")
	check(bot.damage("weapon", 40) == 40 and bot.zones.weapon == 110 and bot.core == 210, "Exposed component 75/25 split")
	check(bot.damage("top", 20) == 20 and bot.core == 190, "Unarmoured top passes full damage")
	check(bot.damage("underside", 10) == 10 and bot.core == 180, "Underside has no piece")
	check(bot.damage("bogus", 10) == 0 and bot.core == 180, "Unknown zone ignored")
	bot.core = 1
	check(bot.damage("top", 1000) == 1 and bot.eliminated, "Clamp overkill")
	check(bot.damage("top", 1000) == 0, "Wreck takes no damage")
	bot = CombatState.new(stats)
	var command := BotCommand.new()
	command.primary_held = true
	bot.tick(1.5, command, true)
	check(is_equal_approx(bot.charge, 1) and is_equal_approx(bot.heat, 18), "Spinner spin-up and heat")
	bot.heat = 99
	bot.tick(0.1, command, true)
	check(bot.overheated and bot.charge == 0, "Overheat locks weapon")
	command.primary_held = false
	bot.tick(5, command, true)
	bot.tick(0.01, command, true)
	check(not bot.overheated, "Overheat clears at 50")
	bot = CombatState.new(registry.validate(registry.starter(true)).stats)
	command.primary_held = true
	bot.tick(1, command, true)
	command.primary_held = false
	bot.tick(1.0 / 60, command, true)
	check(bot.launch and bot.cooldown == 3 and is_equal_approx(bot.heat, 22), "Charged lifter release")
	bot.tick(0.1, command, true)
	check(not bot.launch, "Flipper launch is one tick")
	bot = CombatState.new(stats)
	bot.mobility(2, false, true, 0)
	command.recovery_pressed = true
	bot.tick(0.01, command, true)
	check(bot.recovery_remaining == 1 and bot.heat == 30 and bot.recovery_cooldown == 20, "Recovery eligibility/cost/assist")
	bot = CombatState.new(stats)
	bot.mobility(60, true, false, 0)
	check(not bot.eliminated, "Standing still is legal")
	bot.zones.drive_left = 0
	check(bot.drive_scale() == 0.5, "One pod halves drive")
	bot.zones.drive_right = 0
	bot.mobility(10, true, false, 0)
	check(bot.eliminated, "Both pods disabled count out")
	bot = CombatState.new(stats)
	bot.mobility(5, false, true, 0)
	bot.mobility(1, true, false, 0.5)
	check(bot.immobilized_seconds == 0, "Own drive cancels immobilization")
	var match_state := MatchState.new()
	var bots := {1:CombatState.new(stats), 2:CombatState.new(stats), 3:CombatState.new(stats), 4:CombatState.new(stats)}
	var teams := {1:0, 2:0, 3:1, 4:1}
	check(match_state.judge(bots, teams) == -1, "Identical teams tie")
	bots[1].core -= 0.01
	check(match_state.judge(bots, teams) == -1, "Judging rounds health percentages to 0.1 points")
	bots[3].effective_damage = 1
	check(match_state.judge(bots, teams) == 1, "Effective damage breaks rounded-health tie")
	bots[3].core -= 10
	check(match_state.judge(bots, teams) == 0, "Health outranks damage")
	bots[3].core = stats.core
	bots[3].effective_damage = 0
	bots[1].core = stats.core
	match_state.begin()
	match_state.advance(30, bots, teams)
	check(match_state.phase == "lobby", "Loading timeout returns to lobby")
	match_state.begin()
	match_state.transition("countdown", 5)
	match_state.advance(5, bots, teams)
	check(match_state.phase == "active", "Countdown gates round")
	match_state.advance(180, bots, teams)
	check(match_state.phase == "overtime", "Tie enters overtime")
	match_state.advance(30, bots, teams)
	check(match_state.phase == "intermission" and match_state.rounds[0].winner == -1, "Overtime tie draws")
	for round_number: int in range(2, 6):
		match_state.round_index = round_number
		match_state.resolve(-1)
	check(match_state.phase == "results" and match_state.winner == -1, "Five-round draw cap")
	match_state.begin()
	match_state.resolve(1)
	match_state.round_index = 2
	match_state.resolve(1)
	check(match_state.winner == 1 and match_state.phase == "results", "First to two wins")
	bots[3].eliminate("test")
	bots[4].eliminate("test")
	match_state.transition("active", 100)
	bots[1].eliminate("test")
	bots[2].eliminate("test")
	match_state.advance(0, bots, teams)
	check(match_state.rounds.back().winner == -1, "Same-tick wipe draws")
	print("RULES PASS" if failures == 0 else "RULES FAIL")
	quit(0 if failures == 0 else 1)
