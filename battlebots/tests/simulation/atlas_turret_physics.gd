extends Node3D
## Atlas turret: catalogue rules, wire records, bounded servo and real Jolt rays.
## Frozen bodies isolate weapon contact from driving, as in minigun_physics.
const STEP := 1.0 / 60.0
const ORIGIN := Vector3(0, 20, 0)
const SIDE_TARGET := Vector3(-30, 20, 0)
var failures := 0
var registry := ContentRegistry.new()
var attacker: MvpBot
var victim: MvpBot
var weapons: CombatWorld
var bots: Dictionary
var tick := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func turret_build(kind: String, weapon := "lifter") -> Dictionary:
	var draft := registry.atlas()
	draft.parts.utility = "turret_" + kind
	draft.parts.weapon = weapon
	return draft

func catalogue_rules() -> void:
	for kind: String in ["cannon", "plasma"]:
		var result := registry.validate(turret_build(kind))
		check(result.valid, "Default Atlas accepts the %s turret: %s" % [kind, result.reasons])
		check(result.stats.get("secondary_weapon") == kind, "Turret publishes secondary weapon " + kind)
		check(AtlasGeometry.turret_kind(turret_build(kind)) == kind, "Geometry resolves the fitted turret")
		var minigun := registry.validate(turret_build(kind, "minigun"))
		check(not minigun.valid and "The turret occupies the Atlas roof gun mount; select another primary weapon" in minigun.reasons,
			"Turret and primary minigun share the roof mount")
		for other: Dictionary in [registry.scorpion(), registry.starter()]:
			other.parts.utility = "turret_" + kind
			if other.parts.chassis == "scorpion_hex": other.parts.weapon = "hammer"
			var rejected := registry.validate(other)
			check(not rejected.valid and "Turret modules require the Atlas MX roof traverse race" in rejected.reasons,
				"Turret is rejected off Atlas: " + str(other.parts.chassis))
	check(registry.validate(registry.atlas()).stats.secondary_weapon == "", "Plain Atlas has no auxiliary weapon")
	for model: String in ["cannon_dual", "cannon_quad", "plasma_dual", "plasma_quad"]:
		var upgrade := registry.validate(turret_build(model))
		check(upgrade.valid and upgrade.stats.secondary_weapon == model.get_slice("_", 0)
			and upgrade.stats.turret_model == model and upgrade.stats.turret_barrels == (2 if model.ends_with("dual") else 4),
			"Upgrade %s is a legal Atlas build: %s" % [model, upgrade.reasons])
	for preset: Dictionary in registry.atlas_showcase():
		var shown := registry.validate(preset)
		check(shown.valid, "Showcase preset %s is legal: %s" % [preset.name, shown.reasons])
	var seeded := registry.validate(registry.atlas_turret())
	check(seeded.valid and seeded.stats.secondary_weapon == "cannon", "Seeded Atlas turret preset is legal: %s" % seeded.reasons)
	var old := registry.atlas()
	var migrated: Dictionary
	old = registry.atlas()
	old.content_hash = LoadoutStore.REVISION_TEN_HASHES[0]
	migrated = LoadoutStore.new("user://turret_migration_unused.json").migrate({"schema_version":1, "loadouts":[old]})
	check(migrated.loadouts[0].content_hash == registry.content_hash and registry.validate(migrated.loadouts[0]).valid,
		"Revision-ten Atlas saves migrate to the current catalogue")

func wire_records() -> void:
	var command := BotCommand.new()
	command.sequence = 7
	command.aim_valid = true
	command.aim_yaw = -2.5
	command.aim_pitch = 0.3
	command.auxiliary_held = true
	var decoded := WireCodec.command_from_array(WireCodec.command_to_array(command))
	check(decoded != null and decoded.aim_valid and is_equal_approx(decoded.aim_yaw, -2.5)
		and is_equal_approx(decoded.aim_pitch, 0.3) and decoded.auxiliary_held, "Aim survives the command wire")
	var legacy := [1, 0.0, 0.0, 0]
	check(WireCodec.command_from_array(legacy) == null, "Protocol-six four-field commands are rejected")
	for bad: Array in [[1, 0.0, 0.0, 0, NAN, 0.0], [1, 0.0, 0.0, 0, 0.0, 2.0], [1, 0.0, 0.0, 0, 4.0, 0.0],
			[1, 0.0, 0.0, 2048, 0.0, 0.0], [1, 0.0, 0.0, 0, "x", 0.0]]:
		check(WireCodec.command_from_array(bad) == null, "Malformed aim is rejected: " + str(bad))
	attacker.combat.turret_yaw = 2.0
	attacker.combat.gun_pitch = 0.25
	var state := WireCodec.decode_bot(WireCodec.encode_bot(attacker, "m:1"), attacker.combat.stats)
	check(not state.is_empty() and is_equal_approx(state.turret_yaw, 2.0) and is_equal_approx(state.gun_pitch, 0.25),
		"Snapshot carries turret yaw and elevation")

func flush_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func setup(kind: String) -> void:
	for bot: MvpBot in [attacker, victim]:
		if bot != null: bot.queue_free()
	attacker = MvpBot.create(1, 0, turret_build(kind), registry)
	victim = MvpBot.create(2, 1, registry.starter(), registry)
	for bot: MvpBot in [attacker, victim]:
		add_child(bot)
		bot.body.gravity_scale = 0
		bot.body.collision_mask = 0
		bot.body.freeze = true
	bots = {1: attacker, 2: victim}

func reset_case(target := SIDE_TARGET, chassis_yaw := 0.0) -> void:
	weapons = CombatWorld.new()
	for bot: MvpBot in [attacker, victim]:
		bot.combat = CombatState.new(bot.combat.stats)
		bot.command = BotCommand.new()
	attacker.body.global_transform = Transform3D(Basis(Vector3.UP, chassis_yaw), ORIGIN)
	victim.body.global_transform = Transform3D(Basis.IDENTITY, target)
	attacker.team = 0
	victim.team = 1
	await flush_physics()
	attacker.previous_pose = attacker.body.global_transform
	victim.previous_pose = victim.body.global_transform

func aim_at(point: Vector3, held := false) -> BotCommand:
	var command := BotCommand.new()
	var breech := attacker.body.global_transform * AtlasGeometry.turret_breech(attacker.combat.stats.size, attacker.combat.turret_yaw)
	var direction := point - breech
	command.aim_valid = true
	command.aim_yaw = atan2(-direction.x, -direction.z)
	command.aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	command.auxiliary_held = held
	command.secondary_held = held
	return command

func run_ticks(count: int, point: Vector3, held: bool) -> Array:
	var events: Array = []
	for index: int in count:
		attacker.command = aim_at(point, held)
		attacker.combat.tick(STEP, attacker.command, true)
		tick += 1
		weapons.step(STEP, bots, tick, 1)
		events.append_array(weapons.events.duplicate(true))
	return events

func servo_and_cannon() -> void:
	setup("cannon")
	wire_records()
	await reset_case()
	run_ticks(10, SIDE_TARGET, false)
	check(absf(attacker.combat.turret_yaw - TurretTuning.settings().yaw_rate * STEP * 10) < 0.001,
		"Traverse is rate-limited toward the crosshair: %f" % attacker.combat.turret_yaw)
	var early := run_ticks(1, SIDE_TARGET, true)
	check(early.is_empty() and victim.combat.core == victim.combat.stats.core,
		"A shot fired before the turret arrives travels along the actual barrel and misses")
	check(attacker.combat.shot_sequence == 1 and attacker.combat.last_shot_tick == tick,
		"The miss still publishes an authoritative visual shot")
	run_ticks(60, SIDE_TARGET, false)
	check(absf(attacker.combat.turret_yaw - PI * 0.5) < 0.03, "Turret settles on the side target bearing (trunnion parallax)")
	var heat := attacker.combat.heat
	var hits := run_ticks(150, SIDE_TARGET, true)
	check(hits.size() == 1 and hits[0].kind == "cannon" and hits[0].attack_id == attacker.combat.shot_sequence,
		"Held fire waits for the 2.4 s reload, then lands one confirmed cannon hit: %d" % hits.size())
	check(victim.combat.core < victim.combat.stats.core, "Cannon hit damages through zone rules")
	check(attacker.combat.heat > heat, "Cannon shots generate shared heat")
	# Chassis turns under a held aim: the servo keeps the world bearing.
	await reset_case()
	run_ticks(90, SIDE_TARGET, false)
	attacker.body.global_transform = Transform3D(Basis(Vector3.UP, 0.4), ORIGIN)
	await flush_physics()
	run_ticks(20, SIDE_TARGET, false)
	var barrel := attacker.body.global_basis * AtlasGeometry.turret_direction(attacker.combat.turret_yaw, attacker.combat.gun_pitch)
	check(barrel.normalized().dot(Vector3.LEFT) > 0.99, "Turret stabilises its world aim while the hull turns")
	# Elevation stops.
	await reset_case()
	run_ticks(90, ORIGIN + Vector3(0, 200, -20), false)
	check(is_equal_approx(attacker.combat.gun_pitch, AtlasGeometry.TURRET_PITCH_MAX), "Elevation stops at +30 degrees")
	run_ticks(90, ORIGIN + Vector3(0, -40, -6), false)
	check(is_equal_approx(attacker.combat.gun_pitch, AtlasGeometry.turret_pitch_min("cannon", 0.0)), "Nose-arc depression reaches the audited floor: %f" % rad_to_deg(attacker.combat.gun_pitch))
	# Swinging a fully depressed barrel onto the flank elevates it before it can
	# sweep through the corner socket; at no step is it below the local floor.
	var lowest_margin := INF
	for index: int in 90:
		run_ticks(1, ORIGIN + Vector3(-6, -40, 0), false)
		lowest_margin = minf(lowest_margin, attacker.combat.gun_pitch - AtlasGeometry.turret_pitch_min("cannon", attacker.combat.turret_yaw))
	check(lowest_margin >= -0.0002, "Barrel never dips below the audited floor while traversing: %f" % lowest_margin)
	check(is_equal_approx(attacker.combat.gun_pitch, AtlasGeometry.turret_pitch_min("cannon", attacker.combat.turret_yaw)),
		"Flank aim settles on the flank depression floor")
	check(AtlasGeometry.turret_pitch_min("cannon", PI * 0.5) > AtlasGeometry.turret_pitch_min("cannon", 0.0),
		"Profile allows deeper frontal depression than on the flank")
	# Neutral or stale input brings the turret home.
	var neutral := BotCommand.new()
	for index: int in 120:
		attacker.command = neutral
		weapons.step(STEP, bots, tick, 1)
	check(absf(attacker.combat.turret_yaw) < 0.001 and absf(attacker.combat.gun_pitch) < 0.001,
		"Without aim the turret returns to the front")
	# Walls and allies occlude; allies take no damage.
	await reset_case()
	run_ticks(60, SIDE_TARGET, false)
	var wall := StaticBody3D.new()
	wall.collision_layer = BaselineConfig.WORLD_LAYER
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.5, 20, 20)
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(-15, 20, 0)
	await flush_physics()
	check(run_ticks(1, SIDE_TARGET, true).is_empty() and victim.combat.core == victim.combat.stats.core,
		"A wall between turret and target blocks the shell")
	check(attacker.combat.last_shot_to.x > -15.6, "Shell presentation ends on the wall")
	wall.queue_free()
	await reset_case()
	run_ticks(60, SIDE_TARGET, false)
	victim.team = attacker.team
	check(run_ticks(1, SIDE_TARGET, true).is_empty(), "Friendly target is never damaged")
	# Disabled or eliminated turrets cannot fire.
	await reset_case()
	attacker.combat.zones.weapon = 0.0
	check(run_ticks(30, SIDE_TARGET, true).is_empty() and attacker.combat.shot_sequence == 0,
		"A disabled weapon zone disables the turret")
	await reset_case()
	attacker.combat.heat = 100.0
	attacker.combat.overheated = true
	check(run_ticks(5, SIDE_TARGET, true).is_empty() and attacker.combat.failure_reason == "overheated",
		"Overheat rejects another shell and reports the thermal lock")
	# The turret trigger does not brake a lifter primary (secondary cancellation).
	await reset_case()
	var both := aim_at(SIDE_TARGET, true)
	both.primary_held = true
	for index: int in 30:
		attacker.combat.tick(STEP, both, true)
	check(attacker.combat.charge > 0.4, "Holding the turret trigger does not lower the primary lifter")

func plasma() -> void:
	setup("plasma")
	await reset_case(Vector3(-20, 20, 0))
	run_ticks(60, Vector3(-20, 20, 0), false)
	var hits := run_ticks(60, Vector3(-20, 20, 0), true)
	check(hits.size() == 5 and hits.all(func(hit: Dictionary) -> bool: return hit.kind == "plasma"),
		"One second of plasma fire lands five bolts: %d" % hits.size())
	check(attacker.combat.heat > 15.0 and attacker.combat.secondary_active, "Plasma builds heat while firing")
	await reset_case(Vector3(-20, 20, 0))
	run_ticks(60, Vector3(-20, 20, 0), false)
	attacker.combat.heat = 99.0
	var locked := run_ticks(30, Vector3(-20, 20, 0), true)
	check(locked.size() <= 1 and attacker.combat.overheated, "Plasma overheats and locks out")

func upgrades() -> void:
	# Quad sponson guns cannot depress on the flanks (audited floor about -2
	# degrees there); upgrades are verified against a frontal target.
	var target := Vector3(0, 20, -20)
	for model: String in ["cannon_dual", "cannon_quad"]:
		setup(model)
		await reset_case(target)
		run_ticks(60, target, false)
		var barrels := 2 if model.ends_with("dual") else 4
		var origins: Array = []
		var events: Array = []
		for frame: int in 30:
			var before := attacker.combat.shot_sequence
			events.append_array(run_ticks(1, target, frame == 0))
			if attacker.combat.shot_sequence > before: origins.append(attacker.combat.last_shot_from)
		check(origins.size() == barrels, "%s ripples one volley of %d shells from one press: %d" % [model, barrels, origins.size()])
		var distinct := {}
		for origin: Vector3 in origins: distinct[Vector3i(origin * 100.0)] = true
		check(distinct.size() == barrels, "%s fires every barrel from its own muzzle" % model)
		check(events.size() == barrels and victim.combat.core < victim.combat.stats.core, "%s volley lands every shell" % model)
		var reload := TurretTuning.settings().barrel("cannon", barrels, "interval")
		check(run_ticks(roundi(reload * 60.0) - 45, target, true).is_empty(), "%s reloads after the volley" % model)
	for model: String in ["plasma_dual", "plasma_quad"]:
		setup(model)
		await reset_case(target)
		run_ticks(60, target, false)
		var hits := run_ticks(60, target, true)
		# Cadence resolves on whole 60 Hz ticks.
		var interval := TurretTuning.settings().barrel("plasma", 2 if model.ends_with("dual") else 4, "interval")
		var expected := ceili(60.0 / ceili(interval * 60.0 - 0.0001))
		check(hits.size() >= expected - 1 and hits.size() <= expected, "%s alternates barrels at %d bolts/s: %d" % [model, expected, hits.size()])

func extra_target(position: Vector3, id := 3) -> MvpBot:
	var extra := MvpBot.create(id, 1, registry.starter(), registry)
	add_child(extra)
	extra.body.gravity_scale = 0
	extra.body.collision_mask = 0
	extra.body.freeze = true
	extra.body.global_position = position
	bots[id] = extra
	return extra

## Leaves a bot with the given core and no armour, so a slug kills it outright.
func weaken(bot: MvpBot, core: float) -> void:
	bot.combat.core = core
	for face: String in bot.combat.stats.plates:
		bot.combat.zones[face] = 0.0

func release_ticks(count: int, point: Vector3) -> Array:
	return run_ticks(count, point, false)

func specials() -> void:
	var front := Vector3(0, 20, -12)
	# Flamethrower: burns inside the cone, not beside it or beyond reach.
	setup("flamer")
	await reset_case(front)
	run_ticks(40, front, false)
	var burns := run_ticks(30, front, true)
	check(burns.size() >= 4 and burns.all(func(hit: Dictionary) -> bool: return hit.kind == "flamer"), "Flamer burns a target in its cone: %d" % burns.size())
	await reset_case(Vector3(14, 20, -8))
	run_ticks(40, front, false)
	check(run_ticks(30, front, true).is_empty(), "Flamer misses a target well outside the cone")
	await reset_case(Vector3(0, 20, -30))
	run_ticks(40, Vector3(0, 20, -30), false)
	check(run_ticks(30, Vector3(0, 20, -30), true).is_empty(), "Flamer cannot reach 30 m")
	# Tesla: nearest visible hostile in the seek cone, chaining to a neighbour.
	setup("tesla")
	await reset_case(front)
	var neighbour := extra_target(Vector3(7, 20, -14))
	await flush_physics()
	run_ticks(40, front, false)
	var arcs := run_ticks(40, front, true)
	var chained := arcs.filter(func(hit: Dictionary) -> bool: return hit.target == 3)
	check(arcs.size() >= 2 and victim.combat.core < victim.combat.stats.core, "Tesla arcs into the aimed target")
	check(not chained.is_empty() and neighbour.combat.core < neighbour.combat.stats.core, "Tesla chains to a nearby second enemy")
	bots.erase(3)
	neighbour.queue_free()
	# Railgun: a full charge released fires one piercing slug; early release fizzles.
	setup("railgun")
	# Both targets level with the barrel, so the straight slug line runs through both.
	var level := 20.0 + AtlasGeometry.TURRET_PITCH_PIVOT.y * 3.0
	await reset_case(Vector3(0, level, -25))
	var behind := extra_target(Vector3(0, level, -45))
	await flush_physics()
	var aim := Vector3(0, level, -25)
	run_ticks(40, aim, false)
	run_ticks(30, aim, true)
	check(release_ticks(5, aim).is_empty() and attacker.combat.shot_sequence == 0, "Releasing a partial charge fires nothing")
	run_ticks(80, aim, true)
	var slug := release_ticks(2, aim)
	check(slug.size() == 2 and slug[0].kind == "railgun", "A full charge fires one slug that pierces into a second target: %d" % slug.size())
	check(victim.combat.core < victim.combat.stats.core and behind.combat.core < behind.combat.stats.core, "Both lined-up targets take railgun damage")
	check(victim.combat.death.is_empty() and slug[1].damage < slug[0].damage, "A slug that kills nothing pierces once at the reduced share")
	bots.erase(3)
	behind.queue_free()
	await overpenetration(level)

## #72: a slug that destroys weak targets flies on with its unspent energy.
func overpenetration(level: float) -> void:
	var tuning := TurretTuning.settings()
	var aim := Vector3(0, level, -25)
	await reset_case(aim)
	var second := extra_target(Vector3(0, level, -40))
	var third := extra_target(Vector3(0, level, -55), 4)
	await flush_physics()
	weaken(victim, 5.0)
	weaken(second, 5.0)
	run_ticks(40, aim, false)
	run_ticks(80, aim, true)
	var slug := release_ticks(2, aim)
	check(slug.size() == 3, "A slug that destroys two weak bots reaches a third: %d hits" % slug.size())
	check(victim.combat.eliminated and second.combat.eliminated and not third.combat.eliminated, "Both weak bots are destroyed; the healthy one survives")
	var full := tuning.value("railgun", "damage")
	check(slug.size() == 3 and slug[2].damage > full * tuning.value("railgun", "pierce_share"),
		"Overpenetration carries more than the plain pierce share: %s" % str(slug.map(func(hit: Dictionary) -> int: return hit.damage)))
	var death := victim.combat.death
	check(death.get("kind") == "railgun" and death.axis.dot(victim.body.global_basis.inverse() * Vector3.FORWARD) > 0.99,
		"The kill records the slug's flight in the victim frame: %s" % str(death))
	var wire := WireCodec.decode_bot(WireCodec.encode_bot(victim, "m:1"), victim.combat.stats)
	check(wire.get("death", {}).get("kind") == "railgun" and wire.death.point.is_equal_approx(death.point), "The death record survives the snapshot wire")
	check(WireCodec.decode_bot(WireCodec.encode_bot(third, "m:1"), third.combat.stats).get("death") == {}, "A living bot sends an empty death record")
	for id: int in [3, 4]:
		bots[id].queue_free()
		bots.erase(id)

func run() -> void:
	catalogue_rules()
	await servo_and_cannon()
	await plasma()
	await upgrades()
	await specials()
	print("ATLAS TURRET PHYSICS PASS" if failures == 0 else "ATLAS TURRET PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
