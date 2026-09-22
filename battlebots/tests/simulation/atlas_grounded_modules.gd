extends Node3D
## Real floor, full-health wheeled opponent and ordinary accepted combat commands.
var failures: Array[String] = []
var world: AuthorityWorld
var attacker: MvpBot
var victim: MvpBot
var primary_held := false
var primary_edge := false
var auxiliary_held := false
var throttle := 0.0
var nitro_held := false
var jump_held := false
var hits: Array[Dictionary] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _physics_process(delta: float) -> void:
	if attacker == null: return
	for bot: MvpBot in [attacker, victim]:
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		command.throttle = throttle if bot == attacker else 0.0
		command.brake = is_zero_approx(command.throttle)
		command.nitro_held = nitro_held and bot == attacker
		command.jump_held = jump_held and bot == attacker
		command.primary_held = primary_held and bot == attacker
		command.primary_pressed = primary_edge and bot == attacker
		command.auxiliary_held = auxiliary_held and bot == attacker
		command.secondary_held = auxiliary_held and bot == attacker
		bot.submit_command(command)
	primary_edge = false
	world.step(delta, true, 1)
	for event: Dictionary in world.weapons.events:
		if event.attacker == attacker.entity_id and event.target == victim.entity_id:
			hits.append(event.duplicate(true))

func frames(count: int) -> void:
	for frame: int in count: await get_tree().physics_frame

func run() -> void:
	await spawn_case("foundry")
	await spawn_case("moon")
	await walker_spawn_case()
	world = AuthorityWorld.new()
	add_child(world)
	for weapon: String in ["saw", "lifter", "vertical_spinner", "horizontal_spinner", "hammer", "minigun"]:
		await grounded_case(weapon)
	await grounded_case("lifter", true)
	await handling_case()
	if failures.is_empty(): print("ATLAS GROUNDED MODULES PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)

func spawn_case(arena_id: String) -> void:
	var spawn_world := AuthorityWorld.new()
	spawn_world.arena_id = arena_id
	add_child(spawn_world)
	var bot := spawn_world.spawn(1, 0, 0, spawn_world.registry.atlas())
	await frames(4)
	var collision: CollisionShape3D = bot.get_node("Body/Collision")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = bot.spawn_pose * collision.transform
	query.collision_mask = BaselineConfig.WORLD_LAYER
	query.exclude = [bot.body.get_rid()]
	check(spawn_world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
		arena_id + " normal authored spawn clears the whole physical Atlas hull without a test reposition")
	check(bot.zone_at(bot.body.global_transform * Vector3(3.51, -1.0, 0)) == "drive_right",
		"A real right-track contact damages the drive rather than being mistaken for exposed underside")
	check(bot.zone_at(bot.body.global_transform * Vector3(-3.51, -1.0, 0)) == "drive_left",
		"A real left-track contact damages the left drive")
	check(bot.zone_at(bot.body.global_transform * Vector3(0, -1.74, 0)) == "underside"
		and bot.zone_at(bot.body.global_transform * Vector3(0, 1.65, 0)) == "top",
		"Atlas top and underside follow the actual tall hull")
	spawn_world.reset_round()
	check(bot.body.reset_pose == bot.spawn_pose, arena_id + " rematch restores the verified clear spawn")
	await frames(4)
	check(spawn_world.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
		arena_id + " round reset never embeds the tracks in the terrain")
	spawn_world.free()
	await frames(2)

func walker_spawn_case() -> void:
	var spawn_world := AuthorityWorld.new()
	add_child(spawn_world)
	var walker := SawbladeConfig.starter(spawn_world.registry)
	walker.parts.drive = "walker"
	for draft: Dictionary in [spawn_world.registry.scorpion(), walker]:
		var bot := spawn_world.spawn(1, 0, 0, draft)
		check(is_equal_approx(bot.spawn_pose.origin.y, WalkerDrive.RIDE_HEIGHT + 0.05),
			"The new clearance contract preserves existing walking-drive spawn height")
		await frames(120)
		check(bot.body.grounded and absf(bot.body.global_position.y - WalkerDrive.RIDE_HEIGHT) < 0.10,
			"Existing Scorpion and Sawblade walkers acquire support from their normal spawn")
		spawn_world.clear_bots()
		await frames(2)
	spawn_world.free()
	await frames(2)

func grounded_case(weapon: String, auxiliary := false) -> void:
	var draft := world.registry.atlas()
	draft.parts.weapon = weapon
	draft.parts.utility = "minigun_pod" if auxiliary else "cooling_pack"
	draft.parts.armor = "light"
	attacker = world.spawn(1, 0, 0, draft)
	victim = world.spawn(2, 1, 0, world.registry.starter())
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 3, 4))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -7 if auxiliary or weapon == "minigun" else -2.95))
	primary_held = false
	primary_edge = false
	auxiliary_held = false
	hits.clear()
	await frames(120)
	check(absf(attacker.body.global_position.y - 1.74) < 0.08 and attacker.body.grounded,
		weapon + " real tracks settle against the floor and retain working drive contact")
	check(victim.body.grounded and victim.body.global_position.y < 0.9,
		weapon + " attacks a normally grounded wheeled target")
	var before := victim.combat.core
	primary_held = not auxiliary
	primary_edge = not auxiliary
	auxiliary_held = auxiliary
	await frames(66 if weapon == "lifter" and not auxiliary else 120)
	primary_held = false
	auxiliary_held = false
	await frames(4)
	var count := 0
	for event: Dictionary in hits:
		if event.kind == ("minigun" if auxiliary else weapon): count += 1
	check(count > 0 and victim.combat.core < before,
		("Auxiliary minigun" if auxiliary else weapon) + " damages through real equipped geometry and ordinary commands")
	print("ATLAS GROUNDED %s auxiliary=%s hits=%d core=%.1f -> %.1f" % [weapon, auxiliary, count, before, victim.combat.core])
	attacker = null
	victim = null
	world.clear_bots()
	await frames(2)

func handling_case() -> void:
	attacker = world.spawn(1, 0, 0, world.registry.atlas())
	victim = world.spawn(2, 1, 0, world.registry.starter())
	attacker.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 3, 10))
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(15, 1, -10))
	await frames(120)
	var start := attacker.body.global_position
	throttle = 1.0
	await frames(90)
	check(attacker.body.global_position.distance_to(start) > 4.0,
		"Atlas keeps powerful acceleration with its real full-size collider")
	check(attacker.body.linear_velocity.length() > 6.0,
		"Tracks approach normal traction speed rather than becoming an excavator")
	throttle = 0.0
	await frames(90)
	check(attacker.body.linear_velocity.length() < 0.2, "Finite existing brakes stop the modular chassis")
	throttle = 1.0
	nitro_held = true
	await frames(90)
	check(attacker.combat.nitro_active and attacker.body.linear_velocity.length() > 8.5,
		"Equipped Nitro accelerates the real Atlas beyond normal traction speed")
	nitro_held = false
	throttle = 0.0
	await frames(90)
	jump_held = true
	await frames(72)
	jump_held = false
	await frames(4)
	check(attacker.body.linear_velocity.y > 5.0 and not attacker.body.grounded,
		"Equipped charged jump lifts the full-height Atlas through ordinary commands")
	attacker = null
	victim = null
	world.clear_bots()
	await frames(2)
