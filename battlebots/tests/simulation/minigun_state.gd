extends SceneTree
## Independent authoritative resources, spool, cadence, controls and reset checks.
const STEP := 1.0 / 60.0
var failures := 0
var registry := ContentRegistry.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fresh(auxiliary := false) -> CombatState:
	var build := registry.scorpion()
	if not auxiliary:
		build.parts.weapon = "minigun"
		build.parts.utility = "cooling_pack"
	return CombatState.new(registry.validate(build).stats)

func held(auxiliary := false) -> BotCommand:
	var command := BotCommand.new()
	command.primary_held = not auxiliary
	command.secondary_held = auxiliary
	command.auxiliary_held = auxiliary
	return command

func ticks(state: CombatState, count: int, command: BotCommand, active := true) -> int:
	var shots := 0
	for index: int in count:
		state.tick(STEP, command, active)
		shots += int(state.gun_shot)
	return shots

func run() -> void:
	var state := fresh()
	check(ticks(state, 35, held()) == 0, "No bullet before complete 0.6-second spool")
	check(ticks(state, 1, held()) == 1 and state.weapon_phase == "active",
		"Full spool fires the first round at tick 36")
	check(ticks(state, 120, held()) == 24 and state.shot_sequence == 25,
		"Two subsequent seconds yield exactly 24 more rounds at 12 Hz")
	check(is_equal_approx(state.battery, 74.8) and is_equal_approx(state.heat, 42.8),
		"Motor plus actual shot battery/heat costs are charged exactly, without idle recovery")
	state.tick(STEP, BotCommand.new(), true)
	check(not state.gun_shot and state.weapon_phase == "idle" and state.charge < 1.0,
		"Release immediately stops fire and winds the rotor down")
	state = fresh(true)
	ticks(state, 156, held(true))
	check(is_equal_approx(state.battery, 74.8) and is_equal_approx(state.heat, 42.8),
		"An idle primary cannot cool or recharge behind a firing auxiliary gun")
	state = fresh()
	state.tick(30.0, held(), true)
	check(state.shot_sequence <= 1, "Long frame never emits an unbounded catch-up volley")
	for reason: String in ["inactive", "disabled", "overheated", "battery", "eliminated", "secondary"]:
		state = fresh()
		ticks(state, 35, held())
		var command := held()
		if reason == "disabled": state.zones.weapon = 0.0
		if reason == "overheated":
			state.overheated = true
			state.heat = 80.0
		if reason == "battery": state.battery = 0.0
		if reason == "eliminated": state.eliminate("fixture")
		if reason == "secondary": command.secondary_held = true
		check(ticks(state, 1, command, reason != "inactive") == 0,
			reason + " blocks even a fully wound minigun")
	state = fresh()
	ticks(state, 35, held())
	state.heat = 99.0
	state.tick(STEP, held(), true)
	check(state.gun_shot and state.overheated and state.charge == 0.0,
		"One paid final shot can reach overheat and locks subsequent fire")
	check(ticks(state, 60, held()) == 0, "Held trigger cannot fire through overheat lock")
	state.heat = 50.0
	state.tick(STEP, held(), true)
	check(not state.overheated and not state.gun_shot and state.charge > 0.0,
		"Cooling to fifty unlocks but requires a fresh spool")
	state = fresh(true)
	var aux := held(true)
	check(ticks(state, 40, aux) == 1 and state.attack_id == 0,
		"RMB powers auxiliary without inventing hammer presses")
	aux.primary_pressed = true
	state.tick(STEP, aux, true)
	aux.primary_pressed = false
	ticks(state, 20, aux)
	check(state.strike and state.gun_shot and state.attack_id == 1 and state.shot_sequence == 6,
		"Committed hammer and auxiliary minigun can strike on the same tick")
	check(state.battery < 80.0 and state.heat > 20.0,
		"Simultaneous weapons pay both shared resource costs")
	state = fresh(true)
	var cancelled := BotCommand.new()
	cancelled.primary_pressed = true
	cancelled.secondary_held = true
	ticks(state, 60, cancelled)
	check(state.attack_id == 0 and state.shot_sequence == 0 and state.secondary_charge == 0.0,
		"Synthetic pause/timeout secondary brake neither fires gun nor commits hammer")
	state = fresh(true)
	ticks(state, 60, held(true))
	state.tick(STEP, held(true), false)
	check(not state.gun_shot and not state.secondary_active and state.secondary_charge == 0.0,
		"Inactive match clears auxiliary activation")
	var reset := CombatState.new(state.stats)
	check(reset.shot_sequence == 0 and reset.last_shot_tick == -1 and reset.secondary_charge == 0.0,
		"Round reset clears shot sequence, endpoints and partial spool")
	print("MINIGUN STATE PASS" if failures == 0 else "MINIGUN STATE FAIL")
	quit(0 if failures == 0 else 1)
