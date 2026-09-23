extends SceneTree
## Shared heat regression: real public tick order, combined actions and lock recovery.
const DT := 1.0 / 60.0
var failures := 0
var registry := ContentRegistry.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func fresh() -> CombatState:
	return CombatState.new(registry.validate(registry.starter()).stats)

func step(state: CombatState, command: BotCommand, active := true, grounded := true) -> void:
	state.tick(DT, command, active)
	state.tick_perks(DT, command, active, grounded)

func run() -> void:
	var state := fresh()
	check(not state.stats.has("battery") and not state.snapshot().has("battery"),
		"Runtime and derived state have no battery resource")
	var boost := BotCommand.new()
	boost.throttle = 1.0
	boost.nitro_held = true
	for tick: int in 60: step(state, boost)
	check(is_equal_approx(state.heat, 14.0) and state.nitro_active,
		"Idle primary cannot cancel Nitro's fourteen heat per second")
	state = fresh()
	boost.primary_held = true
	for tick: int in 60: step(state, boost)
	check(is_equal_approx(state.heat, 26.0),
		"Spinner and Nitro accumulate both existing heat rates")
	state = fresh()
	state.heat = 99.9
	boost.primary_held = false
	step(state, boost)
	check(state.heat == 100.0 and state.overheated, "Nitro reaches the shared heat limit")
	step(state, boost)
	check(not state.nitro_active and state.heat < 100.0,
		"Held Nitro stops and permits cooling while overheated")
	check(state.drive_scale() == 1.0, "Overheating preserves ordinary driving")
	state.heat = 50.1
	step(state, boost)
	check(not state.nitro_active, "Tick cooling through fifty stays locked")
	step(state, boost)
	check(state.nitro_active and not state.overheated, "Next tick below fifty permits Nitro")

	state = fresh()
	var jump := BotCommand.new()
	jump.jump_held = true
	for tick: int in 72: step(state, jump)
	check(is_equal_approx(state.jump_charge, 1.0) and state.heat == 0.0,
		"Holding jump charges without generating heat")
	jump.jump_held = false
	step(state, jump)
	check(is_equal_approx(state.heat, 20.0) and state.jump_release_speed > 0.0,
		"A released charged jump generates twenty heat once")
	step(state, jump)
	check(state.jump_release_speed == 0.0 and state.heat < 20.0,
		"Release does not repeat, and an idle bot cools")

	state = fresh()
	state.inverted_seconds = 2.0
	state.zones.weapon = 0.0
	var recovery := BotCommand.new()
	recovery.recovery_pressed = true
	step(state, recovery)
	check(is_equal_approx(state.heat, 30.0) and state.recovery_remaining > 0.0,
		"Self-right with a destroyed weapon generates thirty heat")
	state = fresh()
	state.inverted_seconds = 2.0
	state.heat = 99.0
	step(state, recovery)
	check(state.heat == 100.0 and state.overheated and state.recovery_remaining > 0.0,
		"Accepted self-right completes when its cost reaches the heat cap")
	state = fresh()
	step(state, boost, false)
	check(state.heat == 0.0 and not state.nitro_active, "Inactive rounds cannot generate heat")
	print("HEAT ONLY STATE PASS" if failures == 0 else "HEAT ONLY STATE FAIL")
	quit(0 if failures == 0 else 1)
