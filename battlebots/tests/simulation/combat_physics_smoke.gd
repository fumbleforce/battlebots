extends SceneTree
var failures := 0
var world: AuthorityWorld
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func frames(count: int, active := true) -> void:
	for index: int in range(count):
		world.step(1.0 / 60, active, 1)
		await physics_frame
	await process_frame
func run() -> void:
	world = AuthorityWorld.new()
	root.add_child(world)
	var a := world.spawn(1, 0, 0, world.registry.starter())
	var b := world.spawn(2, 1, 0, world.registry.starter(true))
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0) * BotScale.FACTOR)
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, -2.15) * BotScale.FACTOR)
	await frames(60, false)
	a.previous_pose = a.body.global_transform
	a.combat.charge = 1
	var before := b.combat.core
	world.step(1.0 / 60, true, 1)
	check(b.combat.core < before and not world.weapons.events.is_empty(), "Authoritative spinner overlaps and damages enemy")
	check(world.weapons.events.all(func(event: Dictionary) -> bool: return event.kind == "vertical_spinner"),
		"Weapon events identify authored impacts separately from ramming")
	check(a.combat.charge < 0.6, "Hit drains spinner")
	var damage_after := b.combat.core
	a.combat.charge = 1
	world.step(1.0 / 60, true, 1)
	check(b.combat.core == damage_after, "Continuous contact respects cooldown")
	world.weapons.cooldowns.clear()
	b.team = 0
	a.combat.charge = 1
	world.step(1.0 / 60, true, 1)
	check(b.combat.core == damage_after, "Allies cannot take weapon damage")
	b.team = 1
	world.reset_round()
	await frames(60, false)
	check(b.combat.core == b.combat.stats.core and b.combat.heat == 0 and not b.combat.overheated, "Round reset repairs/refills")
	check(a.body.mass == 85 and b.body.mass == 90 and b.body.top_speed == 8, "Server assembly uses catalogue stats")
	b.combat.eliminate("test")
	world.step(1.0 / 60, true, 1)
	check(b.body.collision_layer == 0 and b.body.freeze, "Wreck loses combat collision")
	a.body.reset_pose = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, 0.4, 0) * BotScale.FACTOR)
	a.body.sleeping = false
	await frames(160)
	var recovery := BotCommand.new()
	recovery.sequence = 1
	recovery.recovery_pressed = true
	a.submit_command(recovery)
	await frames(110)
	print("Recovery upright dot: ", a.body.global_basis.y.dot(Vector3.UP), " activations: ", a.combat.recovery_count)
	check(a.body.global_basis.y.dot(Vector3.UP) > 0.5 and a.combat.recovery_count == 1,
		"Physical recovery rights an unpinned inverted bot without teleporting")
	world.reset_round()
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0) * BotScale.FACTOR)
	b.body.reset_pose = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.5, -2.15) * BotScale.FACTOR)
	await frames(60, false)
	a.previous_pose = a.body.global_transform
	b.previous_pose = b.body.global_transform
	a.combat.stats.weapon = "lifter"
	a.combat.charge = 1
	a.combat._previous_held = true
	a.input_age = 0
	a.command = BotCommand.new()
	var lift_core := b.combat.core
	world.step(1.0 / 60, true, 1)
	await physics_frame
	await process_frame
	check(b.combat.core < lift_core and b.body.linear_velocity.y > 2, "Charged lifter release damages and launches physical enemy")
	world.reset_round()
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0) * BotScale.FACTOR)
	b.body.reset_pose = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.5, -2.15) * BotScale.FACTOR)
	await frames(60, false)
	a.previous_pose = a.body.global_transform
	b.previous_pose = b.body.global_transform
	a.combat.stats.weapon = "vertical_spinner"
	b.combat.stats.weapon = "vertical_spinner"
	a.combat.charge = 1
	b.combat.charge = 1
	a.combat.core = 1
	b.combat.core = 1
	world.step(1.0 / 60, true, 1)
	check(a.combat.eliminated and b.combat.eliminated, "Mutual lethal attacks resolve together before judging")
	world.reset_round()
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0) * BotScale.FACTOR)
	b.body.reset_pose = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.5, -2.15) * BotScale.FACTOR)
	await frames(60, false)
	a.previous_pose = a.body.global_transform
	b.previous_pose = b.body.global_transform
	a.combat.stats.weapon = "lifter"
	a.combat.charge = 1
	a.combat._previous_held = true
	a.input_age = 1
	var safe_core := b.combat.core
	world.step(1.0 / 60, true, 1)
	check(not a.combat.launch and b.combat.core == safe_core, "Stale held input lowers lifter without firing")
	a.body.freeze = true
	b.body.freeze = true
	a.combat.charge = 1
	a.combat.weapon_phase = "active"
	b.body.linear_velocity = Vector3.ZERO
	for frame: int in range(305):
		world.weapons.step(1.0 / 60, world.bots, frame, 1)
	check(world.weapons.blocked.has("1:2"), "Five-second weapon restraint enforces three-second release")
	world.queue_free()
	await process_frame
	print("COMBAT PHYSICS PASS" if failures == 0 else "COMBAT PHYSICS FAIL")
	quit(0 if failures == 0 else 1)
