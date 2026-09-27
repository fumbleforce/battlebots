extends "res://tests/simulation/atlas_turret_physics.gd"
## Exercise the new chassis through existing authoritative Jolt cannon tests.
## Inherited scenarios remain scoped to controlled contact, not online play.

func turret_build(_kind: String, _weapon := "lifter") -> Dictionary:
	return registry.bracken()

func run() -> void:
	var validation := registry.validate(registry.bracken())
	check(validation.valid, "Factory tank validates for actual simulation")
	setup("cannon_quad")
	var target := Vector3(0, ORIGIN.y, -25)
	await reset_case(target)
	run_ticks(Engine.physics_ticks_per_second, target, false)
	var hits := run_ticks(Engine.physics_ticks_per_second, target, true)
	check(attacker.combat.shot_sequence == 4 and hits.size() == 4, "Bracken's four barrels land one authoritative volley")
	check(victim.combat.core < victim.combat.stats.core, "Bracken cannon deals real damage")
	wire_records()
	# Lifter shares heat and remains independently operable while the turret is fitted.
	await reset_case(target)
	var command := BotCommand.new()
	command.primary_held = true
	for frame: int in Engine.physics_ticks_per_second:
		attacker.combat.tick(STEP, command, true)
	check(attacker.combat.charge > 0.0, "Bracken charges its hull lifter")
	command.primary_held = false
	attacker.combat.tick(STEP, command, true)
	check(attacker.combat.cooldown > 0.0, "Releasing the lifter starts a real launch")
	for bot: MvpBot in [attacker, victim]: bot.free()
	attacker = null
	victim = null
	# Real driven body settles on a floor, then accelerates along -Z.
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	add_child(floor_body)
	attacker = MvpBot.create(1, 0, registry.bracken(), registry)
	add_child(attacker)
	attacker.body.global_position = Vector3.UP * attacker.ground_clearance()
	for frame: int in Engine.physics_ticks_per_second:
		await get_tree().physics_frame
	check(attacker.body.grounded, "Bracken settles with ground contact")
	var start := attacker.body.global_position
	for frame: int in Engine.physics_ticks_per_second * 2:
		var drive := BotCommand.new()
		drive.sequence = frame + 1
		drive.throttle = 1.0
		attacker.submit_command(drive)
		attacker.step(STEP, true)
		await get_tree().physics_frame
	check(attacker.body.global_position.z < start.z - validation.stats.size.z, "Bracken drives forward more than its own length")
	attacker.free()
	floor_body.free()
	print("BRACKEN PHYSICS PASS" if failures == 0 else "BRACKEN PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
