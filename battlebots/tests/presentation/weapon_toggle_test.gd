extends SceneTree
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func new_gate(toggle: bool = true) -> GameplayInputGate:
	var gate := GameplayInputGate.new()
	gate.toggle_primary = toggle
	gate.sample({}, {}, true)
	return gate

func press(gate: GameplayInputGate) -> BotCommand:
	return gate.sample({&"primary": 1.0}, {&"primary": true}, true)

func charged(gate: GameplayInputGate) -> CombatState:
	var registry := ContentRegistry.new()
	var combat := CombatState.new(registry.validate(registry.starter(true)).stats)
	combat.tick(1.0 / 60.0, press(gate), true)
	for frame: int in range(65):
		combat.tick(1.0 / 60.0, gate.sample({}, {}, true), true)
	check(combat.charge >= 1.0, "Toggle charges actual lifter after physical release")
	return combat

func _initialize() -> void:
	var gate := new_gate()
	var activated := press(gate)
	check(activated.primary_held and activated.primary_pressed, "First click activates")
	for frame: int in range(4):
		var repeated := press(gate)
		check(repeated.primary_held and not repeated.primary_pressed, "Repeated held edge cannot retoggle")
	check(gate.sample({}, {}, true).primary_held, "Physical release preserves latch")
	var stopped := press(gate)
	check(not stopped.primary_held and stopped.primary_pressed and not stopped.secondary_held,
		"Second click releases the held latch and preserves its physical press edge")
	gate = new_gate()
	var combat := charged(gate)
	combat.tick(1.0 / 60.0, press(gate), true)
	check(combat.launch, "Second click launches charged lifter")

	for cancellation: String in ["menu", "focus", "mode"]:
		gate = new_gate()
		combat = charged(gate)
		var canceled: BotCommand
		if cancellation == "menu":
			canceled = gate.sample({}, {}, false)
		elif cancellation == "mode":
			gate.toggle_primary = false
			canceled = gate.sample({}, {}, true)
		else:
			gate.require_release()
			canceled = gate.sample({}, {}, true)
		combat.tick(1.0 / 60.0, canceled, true)
		check(canceled.secondary_held and not canceled.primary_held and not combat.launch,
			"%s cancels even when physical primary was already released" % cancellation)
		gate.require_release()
		check(not press(gate).primary_held, "Held input cannot rearm after cancellation")
		gate.sample({}, {}, true)
		check(press(gate).primary_held, "Release then fresh press rearms")

	gate = new_gate()
	combat = charged(gate)
	var lower := gate.sample({&"secondary": 1.0}, {}, true)
	combat.tick(1.0 / 60.0, lower, true)
	check(lower.secondary_held and not lower.primary_held and not combat.launch, "Secondary safely cancels latch")
	check(not gate.sample({}, {}, true).primary_held, "Secondary release cannot restart latch")
	var both := gate.sample({&"primary": 1.0, &"secondary": 1.0}, {&"primary": true}, true)
	check(both.secondary_held and not both.primary_held, "Simultaneous actions prefer cancellation")
	check(not press(gate).primary_held, "Primary held after secondary cancellation stays blocked")
	gate.sample({}, {}, true)
	check(press(gate).primary_held, "Fresh click after secondary cancellation rearms")

	gate = new_gate(false)
	var registry := ContentRegistry.new()
	combat = CombatState.new(registry.validate(registry.starter(true)).stats)
	var held := press(gate)
	check(held.primary_pressed and held.primary_held, "Default hold activation unchanged")
	for frame: int in range(65):
		combat.tick(1.0 / 60.0, gate.sample({&"primary": 1.0}, {}, true), true)
	combat.tick(1.0 / 60.0, gate.sample({}, {}, true), true)
	check(combat.launch, "Default hold physical release launches")
	for toggle: bool in [false, true]:
		gate = new_gate(toggle)
		combat = CombatState.new(registry.validate(registry.duelist()).stats)
		for activation: int in range(1, 4):
			combat.tick(1.0 / 60.0, press(gate), true)
			check(combat.attack_id == activation, "Every fresh hammer click starts an attack in mode %s" % toggle)
			for frame: int in range(120):
				combat.tick(1.0 / 60.0, gate.sample({&"primary": 1.0}, {}, true), true)
			check(combat.attack_id == activation, "Held hammer input never repeats in mode %s" % toggle)
			combat.tick(1.0 / 60.0, gate.sample({}, {}, true), true)
	print("WEAPON TOGGLE PASS" if failures == 0 else "WEAPON TOGGLE FAIL")
	quit(0 if failures == 0 else 1)
