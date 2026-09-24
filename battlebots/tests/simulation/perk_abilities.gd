extends SceneTree
## Authoritative perk state, command wire and real Jolt launch regression.

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var registry := ContentRegistry.new()
	var starter := registry.starter()
	check(registry.validate(starter).valid and registry.validate(starter).stats.nitro
		and registry.validate(starter).stats.charged_jump, "Starter equips both independent perks")
	var unequipped := starter.duplicate(true)
	unequipped.parts.nitro = "nitro_off"
	unequipped.parts.suspension = "jump_off"
	check(registry.validate(unequipped).valid, "Both perk slots can be independently unequipped")
	# Historical schema 1 had five slots, including the now-retired armour
	# package. Do not manufacture it by dropping perks from a current starter.
	var old := {"schema_version":1, "name":"Legacy Striker",
		"parts":{"chassis":"balanced", "drive":"standard_wheels",
			"weapon":"vertical_spinner", "armor":"standard_armor", "utility":"recovery_assist"},
		"cosmetics":{"paint":"cyan"}, "content_hash":LoadoutStore.REVISION_EIGHT_HASHES[0]}
	var original := old.duplicate(true)
	var migrated := LoadoutStore.new("user://perk_legacy_fixture.json").migrate({"schema_version":1, "loadouts":[old]})
	check(registry.validate(migrated.loadouts[0]).valid and migrated.loadouts[0].parts.nitro == "nitro_off"
		and migrated.loadouts[0].parts.suspension == "jump_off", "Known saved builds migrate without enabling new abilities")
	check(not migrated.loadouts[0].parts.has("armor") and migrated.loadouts[0].name == old.name
		and migrated.loadouts[0].cosmetics == old.cosmetics and old == original,
		"Migration retires the armour package while preserving identity and the original save")

	var command := BotCommand.new()
	command.nitro_held = true
	command.jump_held = true
	command.jump_cancel = true
	var decoded := WireCodec.command_from_array(WireCodec.command_to_array(command))
	check(decoded != null and decoded.nitro_held and decoded.jump_held and decoded.jump_cancel,
		"Network command preserves both abilities and safe cancellation")
	check(WireCodec.command_from_array([0, 0.0, 0.0, 512]) == null, "Unknown command bits rejected")
	var gate := GameplayInputGate.new()
	gate.sample({}, {}, true)
	var held := gate.sample({&"jump":1.0, &"nitro":1.0}, {}, true)
	check(held.jump_held and held.nitro_held, "Held perk inputs reach gameplay")
	var canceled := gate.sample({}, {}, false)
	check(canceled.jump_cancel and not canceled.jump_held and not canceled.nitro_held,
		"Focus/menu suppression cancels stored jump and Nitro")

	var combat := CombatState.new(registry.validate(starter).stats)
	var jump := BotCommand.new()
	jump.jump_held = true
	for i: int in range(72):
		combat.tick_perks(1.0 / 60.0, jump, true, true)
	check(is_equal_approx(combat.jump_charge, 1.0), "Grounded hold reaches full charge")
	jump.jump_held = false
	combat.tick_perks(1.0 / 60.0, jump, true, true)
	check(is_equal_approx(combat.jump_release_speed, 7.5) and is_equal_approx(combat.heat, 20.0)
		and combat.jump_cooldown > 3.9, "Release generates heat and produces a full jump")
	combat.tick_perks(1.0 / 60.0, jump, true, true)
	check(combat.jump_release_speed == 0.0, "One release cannot launch twice")
	var canceled_charge := CombatState.new(registry.validate(starter).stats)
	jump.jump_held = true
	for i: int in range(30): canceled_charge.tick_perks(1.0 / 60.0, jump, true, true)
	jump.jump_cancel = true
	canceled_charge.tick_perks(1.0 / 60.0, jump, true, true)
	jump.jump_held = false
	jump.jump_cancel = false
	canceled_charge.tick_perks(1.0 / 60.0, jump, true, true)
	check(canceled_charge.jump_release_speed == 0.0 and canceled_charge.heat == 0.0,
		"Canceled charge cannot launch or generate heat")
	var nitro := CombatState.new(registry.validate(starter).stats)
	var boost := BotCommand.new()
	boost.nitro_held = true
	boost.throttle = 1.0
	nitro.tick_perks(1.0, boost, true, true)
	check(nitro.nitro_active and is_equal_approx(nitro.heat, 14.0), "Nitro generates heat while driving")
	nitro.tick_perks(1.0, boost, false, true)
	check(not nitro.nitro_active, "Inactive rounds disable Nitro")
	var drive_config := {"speed":10.0, "acceleration":8.0, "grip":9.0, "brake":9.0,
		"coast":1.1, "drive_scale":1.0, "turn":1.65, "steering_scale":1.0,
		"nitro":false, "nitro_equipped":true, "charged_jump":true,
		"gravity":Vector3(0, -9.8, 0), "max_rise":BotPhysics.settings().rise_speed_cap_at_1g,
		"support_release_speed":BotPhysics.settings().support_release_speed,
		"nitro_acceleration":BotPhysics.settings().nitro_acceleration_multiplier,
		"nitro_speed":BotPhysics.settings().nitro_top_speed_multiplier,
		"nitro_grip":BotPhysics.settings().nitro_grip_multiplier}
	var normal_force: float = DriveModel.forces(Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO,
		Vector3.UP, 1.0, 0.0, false, 1.0 / 60.0, drive_config).acceleration.length()
	drive_config.nitro = true
	var boosted_force: float = DriveModel.forces(Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO,
		Vector3.UP, 1.0, 0.0, false, 1.0 / 60.0, drive_config).acceleration.length()
	check(boosted_force > normal_force, "Nitro increases grounded drive force")
	var replay_state := {"pose":Transform3D.IDENTITY, "velocity":Vector3.ZERO,
		"angular":Vector3.ZERO, "drive_input":0.0, "turn_input":0.0,
		"grounded":true, "jump_charge":1.0, "jump_cooldown":0.0}
	var replayed := DriveModel.replay(replay_state, [WireCodec.command_to_array(BotCommand.new())], drive_config)
	check(replayed.velocity.y > 7.0, "Client replay preserves a charged release")

	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80, 1, 80)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var bot := MvpBot.create(1, 0, starter, registry)
	bot.position.y = 2.0
	world.add_child(bot)
	for i: int in range(110):
		await physics_frame
	check(bot.body.grounded, "Perk test bot settles on Jolt floor")
	for i: int in range(72):
		var input := BotCommand.new()
		input.sequence = i
		input.jump_held = true
		bot.submit_command(input)
		bot.step(1.0 / 60.0, true)
		await physics_frame
	var release := BotCommand.new()
	release.sequence = 72
	bot.submit_command(release)
	bot.step(1.0 / 60.0, true)
	for i: int in range(3): await physics_frame
	check(bot.body.linear_velocity.y > 5.0 and not bot.body.grounded,
		"Charged release launches real rigid body")
	var published := WireCodec.decode_bot(WireCodec.encode_bot(bot, "perk-test:1"), bot.combat.stats)
	check(not published.is_empty() and published.jump_cooldown > 3.0
		and published.jump_charge == 0.0 and not published.nitro_active,
		"Bot snapshot carries authoritative perk state")
	world.queue_free()
	await process_frame
	print("PERK ABILITIES PASS" if failures == 0 else "PERK ABILITIES FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
