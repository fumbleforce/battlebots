extends SceneTree
## Pure committed hammer timing and resource regression, independent of hit geometry.
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

func fresh() -> CombatState:
	return CombatState.new(registry.validate(registry.duelist()).stats)

func press() -> BotCommand:
	var command := BotCommand.new()
	command.primary_pressed = true
	command.primary_held = true
	return command

func ticks(state: CombatState, count: int, command: BotCommand) -> void:
	for index: int in range(count):
		state.tick(STEP, command, true)

func run() -> void:
	catalogue()
	committed_timing()
	activation_gates()
	cancellation()
	resources()
	legacy_regression()
	print("HAMMER STATE PASS" if failures == 0 else "HAMMER STATE FAIL")
	quit(0 if failures == 0 else 1)

func catalogue() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mvp_parts.json"))
	check(data.revision >= 3, "Catalogue includes hammer revision")
	var part: Dictionary = registry.parts.get("hammer", {})
	check(part.get("mass") == 24 and part.get("power") == 35 and part.get("category") == "weapon", "Hammer uses authored mass, power and category")
	var draft := registry.duelist()
	var result := registry.validate(draft)
	check(result.valid and draft.name == "Duelist", "Duelist is a legal canonical starter")
	check(draft.parts == {"chassis":"balanced", "drive":"agile", "weapon":"hammer", "armor":"standard_armor", "utility":"cooling_pack", "nitro":"nitro_boost", "suspension":"charged_jump"}, "Duelist uses the offered body, five combat modules and both perks")
	near(result.stats.mass, 96, "Duelist mass")
	near(result.stats.power, 70, "Duelist installed power")
	draft.parts.weapon = "lifter"
	check(registry.duelist().parts.weapon == "hammer", "Duelist returns detached loadouts")
	check(registry.starter().parts.weapon == "vertical_spinner" and registry.starter(true).parts.weapon == "lifter", "Existing starter defaults remain unchanged")

func committed_timing() -> void:
	var state := fresh()
	state.tick(STEP, press(), true)
	near(state.battery, 84, "Accepted activation spends sixteen battery immediately")
	near(state.heat, 0, "Windup does not charge strike heat early")
	near(state.charge, 1.0 / 21.0, "First physics tick reports windup progress")
	check(state.attack_id == 1 and state.weapon_phase == "windup" and not state.strike, "Activation creates one attack identity")
	# Release and secondary cannot cancel a committed hammer. Additional presses
	# during windup are discarded instead of being buffered for another attack.
	var cancel := press()
	cancel.primary_held = false
	cancel.secondary_held = true
	ticks(state, 19, cancel)
	check(not state.strike and state.attack_id == 1, "No strike before twenty-one physics ticks")
	near(state.charge, 20.0 / 21.0, "Windup progress immediately before strike")
	state.tick(STEP, cancel, true)
	check(state.strike and state.weapon_phase == "strike" and not state.launch, "Exactly 0.35 seconds produces one hammer strike")
	near(state.charge, 1, "Strike publishes completed windup")
	near(state.heat, 20, "Strike produces twenty heat once")
	near(state.cooldown, 1.4, "Strike begins full miss recovery")
	near(state.battery, 84, "Committed strike has no second battery charge")
	check(state.snapshot().weapon_state == "strike", "Existing snapshot fields expose strike phase")
	state.tick(STEP, press(), true)
	check(not state.strike and state.attack_id == 1 and state.failure_reason == "cooldown", "Strike pulse clears next tick and recovery rejects presses")
	ticks(state, 82, press())
	near(state.cooldown, STEP, "Recovery remains active through tick eighty-three")
	state.tick(STEP, press(), true)
	near(state.cooldown, 0, "Recovery ends after exactly eighty-four ticks")
	check(state.attack_id == 1, "Press during final recovery tick is discarded")
	var held := BotCommand.new()
	held.primary_held = true
	ticks(state, 120, held)
	check(state.attack_id == 1 and not state.strike and state.weapon_phase == "idle", "Holding does not repeat or queue a strike")
	state.tick(STEP, press(), true)
	check(state.attack_id == 2 and state.weapon_phase == "windup", "Fresh physical press after recovery begins next attack")

func activation_gates() -> void:
	var state := fresh()
	var blocked := press()
	blocked.secondary_held = true
	state.tick(STEP, blocked, true)
	check(state.attack_id == 0 and state.battery == 100, "Secondary prevents starting a new hammer attack")
	state.battery = 15.99
	state.tick(STEP, press(), true)
	check(state.attack_id == 0 and state.failure_reason == "battery_empty", "Insufficient activation battery rejects hammer")
	state.battery = 16
	state.tick(STEP, press(), true)
	near(state.battery, 0, "Exactly sixteen battery commits an attack")
	ticks(state, 20, BotCommand.new())
	check(state.strike, "Committed attack completes with zero remaining battery")
	state = fresh()
	state.heat = 80
	state.tick(STEP, press(), true)
	ticks(state, 20, BotCommand.new())
	check(state.strike and state.overheated and state.heat == 100 and state.weapon_phase == "strike", "Final strike completes even when its heat causes overheat")
	state.cooldown = 0 # Isolate thermal gate from independent recovery timer.
	state.heat = 50.1
	state.tick(STEP, press(), true)
	check(state.attack_id == 1 and state.failure_reason == "overheated", "Heat above fifty blocks a new activation")
	state.heat = 50
	state.tick(STEP, press(), true)
	check(not state.overheated and state.attack_id == 2, "Heat at fifty permits a fresh activation")

func cancellation() -> void:
	for reason: String in ["inactive", "destroyed", "eliminated"]:
		var state := fresh()
		state.tick(STEP, press(), true)
		if reason == "destroyed":
			state.zones.weapon = 0
		elif reason == "eliminated":
			state.eliminate("fixture")
		state.tick(STEP, BotCommand.new(), reason != "inactive")
		check(not state.strike and state.charge == 0, reason + " cancels committed hammer windup")
		near(state.battery, 84, reason + " does not refund committed battery")
		if reason == "destroyed":
			state.zones.weapon = 140
		elif reason == "eliminated":
			state.eliminated = false
		ticks(state, 30, BotCommand.new())
		check(not state.strike and state.attack_id == 1 and state.heat == 0, reason + " cannot later resurrect the cancelled strike")
	var state := fresh()
	state.tick(STEP, press(), false)
	check(state.attack_id == 0 and state.battery == 100, "Inactive countdown rejects a new activation")

func resources() -> void:
	var state := fresh()
	state.tick(STEP, press(), true)
	ticks(state, 20, BotCommand.new())
	ticks(state, 59, BotCommand.new())
	near(state.battery, 84, "No recharge before one second after the strike")
	state.tick(STEP, BotCommand.new(), true)
	near(state.battery, 84, "Exactly one inactive second produces no premature recharge")
	ticks(state, 60, BotCommand.new())
	near(state.battery, 92, "Next idle second recharges eight battery")
	near(state.heat, 0, "Duelist cooling dissipates strike heat")
	state = fresh()
	state.heat = 40
	state.tick(0.5, BotCommand.new(), true)
	near(state.heat, 32.5, "Duelist cooling pack dissipates fifteen heat per second")
	state.zones.weapon = 0
	state.inverted_seconds = 2
	var command := BotCommand.new()
	command.recovery_pressed = true
	state.tick(STEP, command, true)
	near(state.battery, 70, "Recovery remains available with a destroyed hammer")
	near(state.recovery_cooldown, 20, "Recovery keeps its twenty-second cooldown")
	near(state.recovery_remaining, 2, "Duelist without recovery assist takes two seconds")
	ticks(state, 60, BotCommand.new())
	near(state.battery, 70, "Active recovery prevents recharge")
	ticks(state, 60, BotCommand.new())
	near(state.recovery_remaining, 0, "Recovery completes after exactly two seconds")
	near(state._inactive, 0, "Final recovery tick does not count toward inactivity")
	ticks(state, 60, BotCommand.new())
	near(state.battery, 70, "Full one-second recharge wait follows completed recovery")
	ticks(state, 60, BotCommand.new())
	near(state.battery, 78, "Following idle second restores eight battery after recovery")

func legacy_regression() -> void:
	for weapon: String in ["vertical_spinner", "horizontal_spinner", "lifter"]:
		var draft := registry.starter()
		draft.parts.weapon = weapon
		var state := CombatState.new(registry.validate(draft).stats)
		var command := BotCommand.new()
		command.primary_held = true
		var count := 120 if weapon == "horizontal_spinner" else (90 if weapon == "vertical_spinner" else 60)
		ticks(state, count, command)
		near(state.charge, 1, weapon + " spinup/raise timing remains unchanged")
		check(not state.strike, weapon + " never emits hammer strike")
		if weapon == "lifter":
			state.tick(STEP, BotCommand.new(), true)
			check(state.launch and state.cooldown == 3, "Lifter release still launches")
