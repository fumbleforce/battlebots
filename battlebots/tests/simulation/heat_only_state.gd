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
	jump.jump_held = true
	for tick: int in 72: step(state, jump)
	state.heat = 80.0
	jump.jump_held = false
	step(state, jump)
	check(state.heat == 100.0 and state.overheated and state.jump_release_speed > 0.0,
		"Warm jump release gets its full heat cost without same-tick idle cooling")

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
	migration_and_wire()
	print("HEAT ONLY STATE PASS" if failures == 0 else "HEAT ONLY STATE FAIL")
	quit(0 if failures == 0 else 1)

func migration_and_wire() -> void:
	check(not registry.parts.has("battery_pack"), "Retired Battery Pack is absent from the catalogue")
	var store := LoadoutStore.new()
	for old_hash: String in LoadoutStore.REVISION_TEN_HASHES + LoadoutStore.REVISION_ELEVEN_HASHES:
		var old := registry.starter()
		old.content_hash = old_hash
		old.parts.utility = "battery_pack"
		old.name = "My saved machine"
		var migrated: Dictionary = store.migrate({"schema_version":1, "loadouts":[old]}).loadouts[0]
		check(registry.validate(migrated).valid and migrated.parts.utility == "cooling_pack",
			"Known Battery Pack save migrates to a legal Cooling Pack")
		check(migrated.name == old.name and migrated.cosmetics == old.cosmetics
			and old.parts.utility == "battery_pack", "Migration preserves identity/appearance and never mutates input")
	var unknown := registry.starter()
	unknown.content_hash = "unknown"
	unknown.parts.utility = "battery_pack"
	check(store.migrate({"schema_version":1, "loadouts":[unknown]}).loadouts[0] == unknown,
		"Unknown catalogue identities are not silently repaired")
	var bot := MvpBot.create(1, 0, registry.starter(), registry)
	root.add_child(bot)
	bot.combat.heat = 75.0
	bot.combat.overheated = true
	bot.combat.zones.weapon = 0.0
	var packet := WireCodec.encode_bot(bot, "heat:1")
	var decoded := WireCodec.decode_bot(packet, bot.combat.stats)
	check(decoded.overheated and decoded.heat == 75.0 and not decoded.has("battery"),
		"Wire round-trip preserves shared heat lock without battery")
	check(bot.read_view().overheated, "Bot view preserves thermal lock independently of weapon disability")
	var legacy: Array = bytes_to_var(packet)
	legacy[9] = 100.0
	check(WireCodec.decode_bot(var_to_bytes(legacy), bot.combat.stats).is_empty(),
		"Legacy numeric battery slot cannot masquerade as a thermal latch")
	var boost := BotCommand.new()
	boost.throttle = 1.0
	boost.nitro_held = true
	decoded.jump_charge = 1.0
	decoded.grounded = true
	decoded.velocity = Vector3.ZERO
	decoded.angular = Vector3.ZERO
	var config := bot.body.model_config()
	var blocked := DriveModel.replay(decoded, [WireCodec.command_to_array(boost)], config.duplicate())
	boost.nitro_held = false
	var normal := DriveModel.replay(decoded, [WireCodec.command_to_array(boost)], config.duplicate())
	check(blocked.velocity.is_equal_approx(normal.velocity) and blocked.velocity.y <= 0.0,
		"Authoritative thermal lock prevents predicted Nitro and jump")
	bot.free()
