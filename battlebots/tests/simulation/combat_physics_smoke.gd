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
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, 0))
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 0.5, -2.15))
	await frames(60, false)
	a.previous_pose = a.body.global_transform
	a.combat.charge = 1
	var before := b.combat.core
	world.step(1.0 / 60, true, 1)
	check(b.combat.core < before and not world.weapons.events.is_empty(), "Authoritative spinner overlaps and damages enemy")
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
	check(b.combat.core == b.combat.stats.core and b.combat.battery == b.combat.stats.battery, "Round reset repairs/refills")
	check(a.body.mass == 103 and b.body.mass == 108 and b.body.top_speed == 8, "Server assembly uses catalogue stats")
	b.combat.eliminate("test")
	world.step(1.0 / 60, true, 1)
	check(b.body.collision_layer == 0 and b.body.freeze, "Wreck loses combat collision")
	world.queue_free()
	await process_frame
	print("COMBAT PHYSICS PASS" if failures == 0 else "COMBAT PHYSICS FAIL")
	quit(0 if failures == 0 else 1)
