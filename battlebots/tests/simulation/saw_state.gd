extends SceneTree
## Saw power is immediate; cadence/contact geometry belongs to separate world tests.
const STEP := 1.0 / 60.0
var failures := 0
var registry := ContentRegistry.new()

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func near(actual: float, expected: float, message: String) -> void:
	check(absf(actual - expected) < 0.000001, "%s: expected %.6f, got %.6f" % [message, expected, actual])

func fresh(utility := "recovery_assist") -> CombatState:
	var draft := registry.starter()
	draft.parts.weapon = "saw"
	draft.parts.utility = utility
	var validation := registry.validate(draft)
	check(validation.valid, "Saw test loadout validates")
	return CombatState.new(validation.stats)

func held() -> BotCommand:
	var command := BotCommand.new()
	command.primary_held = true
	return command

func ticks(state: CombatState, count: int, command: BotCommand) -> void:
	for index: int in range(count):
		state.tick(STEP, command, true)

func run() -> void:
	catalogue()
	power_and_resources()
	stop_conditions()
	thermal_lock()
	idle_and_recovery()
	legacy()
	print("SAW STATE PASS" if failures == 0 else "SAW STATE FAIL")
	quit(0 if failures == 0 else 1)

func catalogue() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mvp_parts.json"))
	check(data.revision >= 4, "Catalogue includes the saw introduced in revision four")
	var part: Dictionary = registry.parts.get("saw", {})
	check(part.get("mass") == 20 and part.get("power") == 30 and part.get("category") == "weapon", "Saw uses specified mass, installed power and category")
	var state := fresh()
	near(state.stats.mass, 77, "Balanced saw build mass (no armour pieces)")
	near(state.stats.power, 65, "Balanced saw build installed power")
	check(registry.validate(registry.starter()).valid and registry.validate(registry.starter(true)).valid and registry.validate(registry.duelist()).valid, "All existing canonical starters remain legal")

func power_and_resources() -> void:
	var state := fresh()
	state.tick(STEP, held(), true)
	check(state.charge == 1 and state.weapon_phase == "active", "Saw powers immediately without a spinup or press edge")
	near(state.heat, 14.0 / 60.0, "First saw tick heat")
	ticks(state, 59, held())
	near(state.heat, 14, "One second of powered misses produces fourteen heat")
	check(state.attack_id == 0 and not state.launch and not state.strike, "Saw power does not invent a contact event or committed attack")
	check(state.snapshot().weapon == "saw" and state.snapshot().weapon_state == "active" and state.snapshot().charge == 1, "Existing snapshot fields publish saw power")

func stop_conditions() -> void:
	for reason: String in ["release", "secondary", "destroyed", "inactive", "eliminated"]:
		var state := fresh()
		state.tick(STEP, held(), true)
		var command := held()
		if reason == "release":
			command.primary_held = false
		elif reason == "secondary":
			command.secondary_held = true
		elif reason == "destroyed":
			state.zones.weapon = 0
		elif reason == "eliminated":
			state.eliminate("fixture")
		state.tick(STEP, command, reason != "inactive")
		check(state.charge == 0 and state.weapon_phase != "active", reason + " immediately removes saw contact eligibility")
	var state := fresh()
	state.tick(STEP, held(), false)
	check(state.heat == 0 and state.charge == 0, "Countdown blocks saw resource use")
	state.tick(STEP, held(), true)
	state.tick(STEP, BotCommand.new(), true)
	state.tick(STEP, held(), true)
	check(state.charge == 1 and state.weapon_phase == "active", "Fresh held contact can restart immediately after release")

func thermal_lock() -> void:
	var state := fresh()
	state.heat = 99.9
	state.tick(STEP, held(), true)
	check(state.heat == 100 and state.overheated and state.charge == 0 and state.weapon_phase == "overheated", "Heat100 locks the saw and removes same-tick contact eligibility")
	state.heat = 53
	state.tick(0.25, held(), true)
	near(state.heat, 50, "Overheated saw cools at twelve per second despite held primary")
	check(state.charge == 0 and state.failure_reason == "overheated", "Tick cooling toward threshold stays blocked")
	state.tick(STEP, held(), true)
	check(not state.overheated and state.weapon_phase == "active" and state.charge == 1, "Saw restarts when heat begins at fifty")
	state = fresh("cooling_pack")
	state.heat = 30
	state.tick(0.5, BotCommand.new(), true)
	near(state.heat, 22.5, "Cooling utility preserves fifteen heat per second")

func idle_and_recovery() -> void:
	var state := fresh()
	ticks(state, 60, held())
	ticks(state, 60, BotCommand.new())
	near(state.heat, 2, "Idle saw cools twelve heat immediately in one second")
	ticks(state, 60, BotCommand.new())
	near(state.heat, 0, "Cooling never takes heat below zero")
	state = fresh("cooling_pack")
	state.inverted_seconds = 2
	state.zones.weapon = 0
	var command := BotCommand.new()
	command.recovery_pressed = true
	state.tick(STEP, command, true)
	near(state.heat, 30, "Destroyed saw does not block recovery heat")
	near(state.recovery_remaining, 2, "Non-assist recovery duration is unchanged")
	ticks(state, 120, BotCommand.new())
	near(state.heat, 0, "Cooling works while completing recovery, with no recharge wait")
	state = fresh()
	state.inverted_seconds = 2
	command = held()
	command.recovery_pressed = true
	state.tick(STEP, command, true)
	near(state.heat, 30 + 14.0 / 60.0, "Simultaneous recovery and saw add both heat costs")
	check(state.charge == 1 and state.recovery_count == 1, "Recovery does not silently disable legal saw power")

func legacy() -> void:
	for weapon: String in ["vertical_spinner", "horizontal_spinner", "lifter", "hammer"]:
		var draft := registry.starter()
		draft.parts.weapon = weapon
		var state := CombatState.new(registry.validate(draft).stats)
		var command := held()
		command.primary_pressed = true
		state.tick(STEP, command, true)
		command.primary_pressed = false
		var duration := 120 if weapon == "horizontal_spinner" else (90 if weapon == "vertical_spinner" else (21 if weapon == "hammer" else 60))
		ticks(state, duration - 1, command)
		near(state.charge, 1, weapon + " preserves existing activation timing")
		if weapon == "hammer":
			check(state.strike and state.cooldown == 1.4, "Hammer retains committed strike and recovery")
		elif weapon == "lifter":
			state.tick(STEP, BotCommand.new(), true)
			check(state.launch and state.cooldown == 3, "Lifter release remains unchanged")
