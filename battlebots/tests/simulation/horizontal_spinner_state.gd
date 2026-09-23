extends SceneTree
## Pure state/catalogue checks. Contact damage, hit cadence and recoil live in CombatWorld tests.
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
	check(absf(actual - expected) < 0.00001, "%s: expected %.6f, got %.6f" % [message, expected, actual])

func make_state(weapon := "horizontal_spinner", utility := "recovery_assist") -> CombatState:
	var draft := registry.starter()
	draft.parts.weapon = weapon
	draft.parts.utility = utility
	var validation := registry.validate(draft)
	check(validation.valid, "Fixture weapon build is legal: " + weapon)
	return CombatState.new(validation.stats)

func held() -> BotCommand:
	var command := BotCommand.new()
	command.primary_held = true
	return command

func ticks(state: CombatState, count: int, command: BotCommand, active := true) -> void:
	for index: int in range(count):
		state.tick(STEP, command, active)

func run() -> void:
	catalogue()
	spinup_and_resources()
	brake_and_gates()
	overheat_and_recovery()
	legacy_weapons()
	print("HORIZONTAL SPINNER STATE PASS" if failures == 0 else "HORIZONTAL SPINNER STATE FAIL")
	quit(0 if failures == 0 else 1)

func catalogue() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mvp_parts.json"))
	check(data.revision >= 2, "Catalogue includes horizontal spinner revision")
	var part: Dictionary = registry.parts.get("horizontal_spinner", {})
	check(part.get("category") == "weapon" and part.get("mass") == 30 and part.get("power") == 40, "Horizontal spinner uses authored category, mass and power")
	var draft := registry.starter()
	draft.parts.weapon = "horizontal_spinner"
	var legal := registry.validate(draft)
	check(legal.valid, "Balanced horizontal starter variant is legal")
	near(legal.stats.mass, 87, "Horizontal starter mass")
	near(legal.stats.power, 75, "Horizontal starter installed power")
	draft.parts.chassis = "wide"
	draft.parts.drive = "traction"
	draft.parts.utility = "cooling_pack"
	var armour := SawbladeConfig.defaults()
	armour.armor_side = 2
	armour.armor_top = 1
	armour.armor_front = 1
	draft.cosmetics = {"paint":"cyan", "sawblade":armour}
	var overweight := registry.validate(draft)
	check(not overweight.valid and "Mass exceeds 120 kg" in overweight.reasons, "122kg horizontal build with heavy skirts is rejected rather than clamped")
	draft.parts.utility = "recovery_assist"
	draft.parts.chassis = "balanced"
	var heavy := registry.validate(draft)
	check(heavy.valid, "116kg horizontal heavy-skirt build remains legal")
	near(heavy.stats.mass, 116, "Heavy-skirt horizontal build includes 23kg of armour pieces")
	check(registry.validate(registry.starter()).valid and registry.validate(registry.starter(true)).valid, "Both existing starter builds remain legal")

func spinup_and_resources() -> void:
	var state := make_state()
	var command := held()
	ticks(state, 30, command)
	near(state.charge, 0.25, "Half-second horizontal charge")
	near(state.heat, 6, "Half-second spinner heat")
	ticks(state, 89, command)
	check(state.charge < 1.0, "Horizontal is not fully charged at tick119")
	ticks(state, 1, command)
	near(state.charge, 1, "Horizontal reaches full charge at exactly120 ticks")
	near(state.heat, 24, "Two-second spinner heat")
	check(state.weapon_phase == "active" and not state.launch and state.attack_id == 0, "Powered spinner does not synthesize a lifter launch")
	var view := state.snapshot()
	check(view.weapon == "horizontal_spinner" and view.weapon_state == "active" and view.charge == state.charge, "Existing detached snapshot publishes horizontal state")
	state = make_state()
	state.heat = 97.0
	state.tick(0.25, command, true)
	near(state.heat, 100, "Sustained power reaches heat cap")
	state.tick(0.25, command, true)
	check(state.failure_reason == "overheated" and state.charge == 0, "Heat lock stops continued power")
	near(state.drive_scale(), 1, "Heat lock does not disable driving")
	near(state.heat, 97, "Locked spinner cools despite held input")

func brake_and_gates() -> void:
	var state := make_state()
	state.charge = 1
	state.heat = 12
	var command := held()
	command.secondary_held = true
	state.tick(0.25, command, true)
	near(state.charge, 0, "Secondary brakes full spinner charge in quarter second")
	near(state.heat, 9, "Braked spinner cools at twelve per second")
	check(not state.launch and state.weapon_phase == "idle", "Brake cancels instead of launching")
	state.charge = 1
	state.tick(0.25, BotCommand.new(), true)
	near(state.charge, 0.75, "Ordinary release coasts more slowly than secondary braking")
	state = make_state()
	state.cooldown = 0.5
	state.tick(0.25, held(), true)
	check(state.failure_reason == "cooldown" and state.weapon_phase == "cooldown", "Cooldown blocks horizontal activation")
	state.tick(0.25, held(), true)
	near(state.cooldown, 0, "Cooldown expires after its exact duration")
	near(state.charge, 0.125, "Activation resumes when cooldown expires")
	state = make_state()
	state.zones.weapon = 0
	state.charge = 1
	state.tick(STEP, held(), true)
	check(state.charge == 0 and state.weapon_phase == "disabled" and state.failure_reason == "disabled", "Destroyed weapon cannot activate or retain charge")
	state = make_state()
	ticks(state, 120, held(), false)
	check(state.charge == 0 and state.heat == 0, "Countdown freezes all primary activation resources")
	state.eliminate("fixture")
	ticks(state, 120, held())
	check(state.charge == 0 and state.weapon_phase == "disabled", "Eliminated bot cannot power its spinner")

func overheat_and_recovery() -> void:
	var state := make_state()
	state.heat = 99
	state.tick(0.125, held(), true)
	check(state.heat == 100 and state.overheated and state.charge == 0, "Heat cap latches overheat and cancels charge")
	state.heat = 53
	state.tick(0.25, held(), true)
	near(state.heat, 50, "Overheated weapon cools despite held activation")
	check(state.overheated and state.failure_reason == "overheated", "Overheat blocks the tick cooling down to recovery threshold")
	state.tick(0.25, held(), true)
	check(not state.overheated and state.weapon_phase == "active", "Weapon resumes once heat is at50")
	state = make_state("horizontal_spinner", "cooling_pack")
	state.heat = 40
	state.tick(0.5, BotCommand.new(), true)
	near(state.heat, 32.5, "Cooling utility retains its25-percent stronger dissipation")
	state = make_state()
	state.zones.weapon = 0
	state.inverted_seconds = 2
	var recovery := BotCommand.new()
	recovery.recovery_pressed = true
	state.tick(STEP, recovery, true)
	near(state.heat, 30, "Weapon disability does not prevent thirty-heat recovery")
	check(state.recovery_count == 1 and state.recovery_cooldown == 20 and state.recovery_remaining == 1, "Recovery assist timing and cooldown remain unchanged")

func legacy_weapons() -> void:
	var vertical := make_state("vertical_spinner")
	ticks(vertical, 90, held())
	near(vertical.charge, 1, "Vertical spinner preserves1.5-second spinup")
	near(vertical.heat, 18, "Vertical spinner heat rate is unchanged")
	var lifter := make_state("lifter")
	ticks(lifter, 60, held())
	near(lifter.charge, 1, "Lifter preserves one-second raise")
	near(lifter.heat, 4, "Lifter preserves four heat per second")
	lifter.tick(STEP, BotCommand.new(), true)
	check(lifter.launch and lifter.attack_id == 1 and lifter.cooldown == 3, "Charged lifter release preserves launch and three-second cooldown")
	near(lifter.heat, 22, "Lifter launch adds eighteen heat")
