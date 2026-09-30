extends Node3D
## Melee weapons are solid at rest (#112): every primary melee weapon carries a
## collision shape on the bot body, real Jolt bodies stop against it, and it
## lets them through while the weapon works. Empty space and zero gravity
## isolate the bot-to-bot contact.
const WEAPON_COLLIDERS := preload("res://scripts/core/weapon_colliders.gd")
const ORIGIN := Vector3(0, 10, 0) * BotScale.FACTOR
const STEP := 1.0 / 60.0
## The victim is driven into the attacker's front at this speed (m/s), for long
## enough to cross the gap it starts with (m) and settle.
const PUSH_SPEED := 3.0
const START_GAP := 4.0
const PUSH_TICKS := 150
## How closely (m) the victim must stop at the weapon, and hull against hull.
const CONTACT_TOLERANCE := 0.15
## A ram faster than CombatWorld.RAM_MIN_CLOSING_SPEED.
const RAM_SPEED := CombatWorld.RAM_MIN_CLOSING_SPEED + 3.0
var failures := 0
var registry := ContentRegistry.new()
var weapons := CombatWorld.new()
var tick := 0
var sequence := 0
var next_id := 1

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func spawn(build: Dictionary, at: Vector3, team := 0, meta := "") -> MvpBot:
	var bot := MvpBot.create(next_id, team, build, registry)
	if bot == null:
		check(false, "%s must pass validation" % build.get("name", "Build"))
		return null
	next_id += 1
	if not meta.is_empty(): bot.set_meta(meta, "wedge")
	add_child(bot)
	bot.body.gravity_scale = 0
	bot.body.linear_damp = 0
	bot.body.freeze = true
	bot.body.global_transform = Transform3D(Basis.IDENTITY, at)
	bot.previous_pose = bot.body.global_transform
	# The weapon turns solid on the first tick that finds it clear.
	hold(bot, false)
	return bot

func with_weapon(build: Dictionary, weapon: String) -> Dictionary:
	build.parts.weapon = weapon
	return build

## Body-frame bounds of a weapon collider.
func bounds(collider: CollisionShape3D) -> AABB:
	var shape := collider.shape
	var local := AABB()
	if shape is BoxShape3D:
		local = AABB(-shape.size * 0.5, shape.size)
	elif shape is CylinderShape3D:
		local = AABB(Vector3(-shape.radius, -shape.height * 0.5, -shape.radius), Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0))
	else:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		local = AABB(points[0], Vector3.ZERO)
		for point: Vector3 in points: local = local.expand(point)
	return collider.transform * local

## Every melee weapon on every body it mounts on has a collider that adds to
## the hull and stays off the floor.
func verify_catalogue() -> void:
	var builds: Array[Dictionary] = []
	for weapon: String in registry.MELEE_WEAPONS:
		builds.append(with_weapon(registry.starter(), weapon))
		builds.append(with_weapon(SawbladeConfig.starter(registry), weapon))
		builds.append(with_weapon(registry.scorpion(), weapon))
		builds.append(with_weapon(registry.atlas(), weapon))
	builds.append(registry.bracken())
	builds.append_array(registry.nimble())
	var at := ORIGIN + Vector3(0, 0, 60)
	var covered := {}
	for build: Dictionary in builds:
		# A body that cannot mount the weapon (front tools off the Atlas, the
		# other body's lifting tool) has no build to check.
		if not registry.validate(build).valid:
			continue
		covered[build.parts.weapon] = true
		var bot := spawn(build, at)
		var label := "%s / %s" % [build.parts.chassis, build.parts.weapon]
		var collider := bot.weapon_collision
		if build.parts.weapon not in registry.MELEE_WEAPONS:
			check(collider == null, label + ": a gun has no weapon collider")
		elif collider == null:
			check(false, label + ": melee weapon has a collider")
		else:
			var solid := bounds(collider)
			check(collider.get_parent() == bot.body and not collider.disabled, label + ": collider is on the body and solid at rest")
			check(not bot.collision_bounds().grow(0.001).encloses(solid), label + ": collider reaches beyond the hull")
			check(solid.position.y >= -bot.ground_clearance() - 0.001, label + ": collider stays off the floor")
			check(bot._weapon_solid_when_active == (build.parts.weapon == "ramp"), label + ": only the Sawblade ramp stays solid while active")
		bot.free()
	for weapon: String in registry.MELEE_WEAPONS:
		check(covered.has(weapon), weapon + " is checked on at least one body")
	var obstacle := spawn(with_weapon(registry.starter(), "saw"), at)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blocked := spawn(with_weapon(registry.starter(), "saw"), at + Vector3.BACK * obstacle.combat.stats.size.z)
	check(blocked.weapon_collision.disabled and not obstacle.weapon_collision.disabled, "A weapon placed inside another bot stays open")
	obstacle.free()
	await get_tree().physics_frame
	blocked.body.reset_pose = Transform3D(Basis.IDENTITY, at)
	hold(blocked, false)
	check(blocked.weapon_collision.disabled, "A weapon about to be moved waits for its new place")
	blocked.body.reset_pose = null
	hold(blocked, false)
	check(not blocked.weapon_collision.disabled, "A clear weapon turns solid")
	blocked.free()
	var npc := spawn(with_weapon(registry.starter(), "saw"), at, 1, "practice_variant")
	check(npc.weapon_collision == null, "Practice NPC models keep their own collision")
	npc.free()

func hold(bot: MvpBot, primary: bool) -> void:
	var command := BotCommand.new()
	sequence += 1
	command.sequence = sequence
	command.primary_held = primary
	command.primary_pressed = primary
	bot.submit_command(command)
	bot.step(STEP, true)

## The bots meet along Z only: zero gravity would otherwise let the blade's
## curve deflect the hull under it.
func on_rails(bot: MvpBot) -> void:
	bot.body.axis_lock_linear_x = true
	bot.body.axis_lock_linear_y = true
	bot.body.axis_lock_angular_x = true
	bot.body.axis_lock_angular_y = true
	bot.body.axis_lock_angular_z = true

## How far ahead of the attacker's front face its saw blade stops a hull of the
## same height at the same level: the blade's chord at the hull's top edge.
func saw_reach(attacker: MvpBot) -> float:
	var disc := attacker.weapon_collision.shape as CylinderShape3D
	var axle := attacker.weapon_collision.position
	var size: Vector3 = attacker.combat.stats.size
	var above := maxf(0.0, axle.y - size.y * 0.5)
	return -axle.z + sqrt(disc.radius * disc.radius - above * above) - size.z * 0.5

## Hull-to-hull gap along Z between a bot and the one in front of it.
func gap(attacker: MvpBot, victim: MvpBot) -> float:
	return attacker.body.global_position.z - victim.body.global_position.z \
		- (attacker.combat.stats.size.z + victim.combat.stats.size.z) * 0.5

## Drives the victim into the attacker's front; returns the combat events.
func push(attacker: MvpBot, victim: MvpBot, primary: bool, ticks := PUSH_TICKS) -> Array:
	var events: Array = []
	for index: int in ticks:
		victim.body.linear_velocity = Vector3(0, 0, PUSH_SPEED)
		victim.body.angular_velocity = Vector3.ZERO
		hold(attacker, primary)
		tick += 1
		weapons.step(STEP, {attacker.entity_id: attacker, victim.entity_id: victim}, tick, 1)
		events.append_array(weapons.events.duplicate(true))
		await get_tree().physics_frame
	return events

func verify_saw() -> void:
	var attacker := spawn(with_weapon(registry.starter(), "saw"), ORIGIN)
	var victim := spawn(with_weapon(registry.starter(), "minigun"), ORIGIN)
	victim.team = 1
	var lengths: float = (attacker.combat.stats.size.z + victim.combat.stats.size.z) * 0.5
	var reach := saw_reach(attacker)
	victim.body.global_position = ORIGIN + Vector3(0, 0, -lengths - reach - START_GAP)
	on_rails(victim)
	victim.body.freeze = false
	await get_tree().physics_frame
	var events := await push(attacker, victim, false)
	check(absf(gap(attacker, victim) - reach) < CONTACT_TOLERANCE, "A resting saw stops the hull that drives into it (gap %.2f, reach %.2f)" % [gap(attacker, victim), reach])
	check(events.is_empty(), "A resting saw deals no damage")
	events = await push(attacker, victim, true)
	check(attacker.weapon_collision.disabled, "A running saw is not solid")
	check(gap(attacker, victim) < CONTACT_TOLERANCE, "A running saw lets the target in up to the hull (gap %.2f)" % gap(attacker, victim))
	check(events.any(func(event: Dictionary) -> bool: return event.kind == "saw" and event.target == victim.entity_id), "The running saw cuts the target it reaches")
	await push(attacker, victim, false, 30)
	check(attacker.weapon_collision.disabled and gap(attacker, victim) < CONTACT_TOLERANCE, "A saw that stops inside a target stays open instead of shoving it out")
	victim.body.linear_velocity = Vector3.ZERO
	victim.body.global_position = ORIGIN + Vector3(0, 0, -lengths - reach - START_GAP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	hold(attacker, false)
	check(not attacker.weapon_collision.disabled, "The saw is solid again once it is clear")
	attacker.combat.zones.weapon = 0.0
	hold(attacker, false)
	check(attacker.weapon_collision.disabled, "A destroyed weapon is no longer solid")
	attacker.free()
	victim.free()

## Driving into a resting weapon is an ordinary ram.
func verify_ram() -> void:
	var attacker := spawn(with_weapon(registry.starter(), "saw"), ORIGIN)
	var victim := spawn(with_weapon(registry.starter(), "minigun"), ORIGIN)
	victim.team = 1
	var lengths: float = (attacker.combat.stats.size.z + victim.combat.stats.size.z) * 0.5
	var reach := saw_reach(attacker)
	victim.body.global_position = ORIGIN + Vector3(0, 0, -lengths - reach - START_GAP)
	for bot: MvpBot in [attacker, victim]:
		on_rails(bot)
		bot.body.freeze = false
	await get_tree().physics_frame
	victim.body.linear_velocity = Vector3(0, 0, RAM_SPEED)
	var rams := 0
	var widest := INF
	for index: int in PUSH_TICKS:
		hold(attacker, false)
		tick += 1
		weapons.step(STEP, {attacker.entity_id: attacker, victim.entity_id: victim}, tick, 1)
		for event: Dictionary in weapons.events:
			if event.kind == "ram":
				rams += 1
				widest = minf(widest, gap(attacker, victim))
		await get_tree().physics_frame
	check(rams == 2, "A ram against a resting saw hits both bots once (%d events)" % rams)
	check(widest > reach - 2.0 * CONTACT_TOLERANCE - RAM_SPEED * STEP * 2.0, "The ram lands at the saw, not at the hull (gap %.2f, reach %.2f)" % [widest, reach])
	attacker.free()
	victim.free()

func verify_ramp() -> void:
	var ramp := spawn(with_weapon(SawbladeConfig.starter(registry), "ramp"), ORIGIN)
	for index: int in 20: hold(ramp, true)
	check(ramp.combat.weapon_phase == "active" and ramp.combat.charge > 0.0 and not ramp.weapon_collision.disabled, "A charging Sawblade ramp stays solid")
	hold(ramp, false)
	check(ramp.combat.launch and not ramp.weapon_collision.disabled, "A launching Sawblade ramp stays solid")
	ramp.combat.zones.weapon = 0.0
	hold(ramp, false)
	check(ramp.weapon_collision.disabled, "A destroyed ramp is no longer solid")
	ramp.free()
	var lifter := spawn(with_weapon(registry.atlas(), "lifter"), ORIGIN)
	for index: int in 20: hold(lifter, true)
	check(lifter.weapon_collision.disabled, "A charging Atlas lifter is not solid")
	lifter.free()

## Clients follow the replicated weapon state.
func verify_replica() -> void:
	var replica := spawn(with_weapon(registry.starter(), "saw"), ORIGIN)
	replica.simulated = false
	var state := replica.combat.snapshot()
	state.weapon_state = "active"
	state.charge = 1.0
	replica.remote_state = state
	# process_frame fires before the bot's own _process in that frame.
	await get_tree().process_frame
	await get_tree().process_frame
	check(replica.weapon_collision.disabled, "A replica's running saw is not solid")
	state = replica.combat.snapshot()
	replica.remote_state = state
	# process_frame fires before the bot's own _process in that frame.
	await get_tree().process_frame
	await get_tree().process_frame
	check(not replica.weapon_collision.disabled, "A replica's resting saw is solid")
	replica.free()

func run() -> void:
	var problems: Array[String] = []
	check(WEAPON_COLLIDERS.from_json("{}", problems) == null and not problems.is_empty(), "A collider file without its mounts is rejected")
	await verify_catalogue()
	await verify_saw()
	await verify_ram()
	verify_ramp()
	await verify_replica()
	print("WEAPON COLLIDER PHYSICS PASS" if failures == 0 else "WEAPON COLLIDER PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
