extends Node3D
## Harpoon and mortar turrets (#52, #55): catalogue, wire grip fields, the
## tether (hit, cut, snap, reel in real Jolt) and the lobbed mortar shell
## (servo elevation, arc over a wall, delayed blast with falloff).
const STEP := 1.0 / 60.0
const ORIGIN := Vector3(0, 20, 0)
var failures := 0
var registry := ContentRegistry.new()
var attacker: MvpBot
var victim: MvpBot
var weapons: CombatWorld
var bots: Dictionary
var tick := 0
var floor_body: StaticBody3D

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func turret_build(kind: String) -> Dictionary:
	var draft := registry.atlas()
	draft.parts.utility = "turret_" + kind
	return draft

func catalogue_and_wire() -> void:
	for kind: String in ["harpoon", "mortar"]:
		var result := registry.validate(turret_build(kind))
		check(result.valid and result.stats.secondary_weapon == kind and result.stats.turret_barrels == 1,
			"Atlas accepts the %s turret: %s" % [kind, result.reasons])
		var scorpion := registry.scorpion()
		scorpion.parts.utility = "turret_" + kind
		check(not registry.validate(scorpion).valid, "The %s turret needs the Atlas roof race" % kind)
	var names := registry.atlas_showcase().map(func(draft: Dictionary) -> String: return draft.name)
	check("ATLAS MX • WHALER" in names and "ATLAS MX • ARTILLERY" in names, "Harpoon and mortar showcase presets exist")
	var old := registry.atlas()
	old.content_hash = LoadoutStore.REVISION_FIFTEEN_HASHES[0]
	var migrated := LoadoutStore.new("user://launcher_migration_unused.json").migrate({"schema_version":1, "loadouts":[old]})
	check(migrated.loadouts[0].content_hash == registry.content_hash, "Revision-fifteen saves migrate")
	var bot := MvpBot.create(9, 0, turret_build("mortar"), registry)
	add_child(bot)
	bot.combat.gun_pitch = 1.35
	bot.combat.grip_target = 4
	bot.combat.grip_point = Vector3(1, 2, 3)
	var state := WireCodec.decode_bot(WireCodec.encode_bot(bot, "m:1"), bot.combat.stats)
	check(not state.is_empty() and state.grip_target == 4 and state.grip_point == Vector3(1, 2, 3)
		and is_equal_approx(state.gun_pitch, 1.35), "Snapshot carries the grip and mortar elevation")
	bot.combat.grip_point = Vector3(NAN, 0, 0)
	check(WireCodec.decode_bot(WireCodec.encode_bot(bot, "m:1"), bot.combat.stats).is_empty(), "A non-finite grip anchor is rejected")
	bot.queue_free()

func flush_physics() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame

func setup(kind: String, frozen := true) -> void:
	for bot: MvpBot in [attacker, victim]:
		if bot != null: bot.queue_free()
	attacker = MvpBot.create(1, 0, turret_build(kind), registry)
	victim = MvpBot.create(2, 1, registry.atlas(), registry)
	for bot: MvpBot in [attacker, victim]:
		add_child(bot)
		if frozen:
			bot.body.gravity_scale = 0
			bot.body.collision_mask = 0
			bot.body.freeze = true
	bots = {1: attacker, 2: victim}

func place(target: Vector3, attacker_at := ORIGIN) -> void:
	weapons = CombatWorld.new()
	for bot: MvpBot in [attacker, victim]:
		bot.combat = CombatState.new(bot.combat.stats)
		bot.command = BotCommand.new()
		bot.body.linear_velocity = Vector3.ZERO
		bot.body.angular_velocity = Vector3.ZERO
	attacker.body.global_transform = Transform3D(Basis.IDENTITY, attacker_at)
	victim.body.global_transform = Transform3D(Basis.IDENTITY, target)
	attacker.team = 0
	victim.team = 1
	await flush_physics()

func aim_command(point: Vector3, held: bool) -> BotCommand:
	var command := BotCommand.new()
	var breech := attacker.body.global_transform * AtlasGeometry.turret_breech(attacker.combat.stats.size, attacker.combat.turret_yaw)
	var direction := point - breech
	command.aim_valid = true
	command.aim_yaw = atan2(-direction.x, -direction.z)
	command.aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	command.auxiliary_held = held
	return command

## Same aim as the gunner's artillery view: bearing plus steep-arc elevation.
func mortar_command(point: Vector3, held: bool) -> BotCommand:
	var command := aim_command(point, held)
	var state := attacker.combat
	var muzzle := attacker.body.global_transform * AtlasGeometry.turret_muzzle(state.stats.size, "mortar", state.turret_yaw, state.gun_pitch)
	var offset := point - muzzle
	command.aim_yaw = atan2(-offset.x, -offset.z)
	var elevation := AtlasGeometry.mortar_elevation(Vector2(offset.x, offset.z).length(), offset.y)
	command.aim_pitch = elevation if not is_nan(elevation) else TurretTuning.settings().value("mortar", "min_elevation")
	return command

## Physics-driven steps: combat state, world resolution, then a Jolt frame.
func run_ticks(count: int, make: Callable, live := false) -> Array:
	var events: Array = []
	for index: int in count:
		attacker.command = make.call()
		attacker.combat.tick(STEP, attacker.command, true)
		victim.combat.tick(STEP, victim.command, true)
		tick += 1
		weapons.step(STEP, bots, tick, 1)
		events.append_array(weapons.events.duplicate(true))
		if live: await get_tree().physics_frame
	return events

func harpoon_frozen() -> void:
	setup("harpoon")
	var front := Vector3(0, 20, -20)
	await place(front)
	await run_ticks(40, func() -> BotCommand: return aim_command(front, false))
	var hits := await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	check(hits.size() == 1 and hits[0].kind == "harpoon" and attacker.combat.grip_target == 2,
		"A harpoon hit tethers the target: %s grip %d" % [hits, attacker.combat.grip_target])
	check(attacker.combat.grip_point.distance_to(hits[0].position) < 0.01 if not hits.is_empty() else false, "The tether anchors at the struck point")
	await run_ticks(10, func() -> BotCommand: return aim_command(front, true))
	check(attacker.combat.secondary_active and attacker.combat.grip_target == 2, "Holding the trigger reels while tethered")
	await run_ticks(2, func() -> BotCommand: return aim_command(front, false))
	check(attacker.combat.grip_target == 2, "Releasing the trigger keeps the tether (slack)")
	await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	check(attacker.combat.grip_target == 0, "A fresh press cuts the cable")
	check((await run_ticks(20, func() -> BotCommand: return aim_command(front, true))).is_empty(), "The tube reloads before the next harpoon")
	# The tether follows the victim and snaps past max_length.
	await place(front)
	await run_ticks(40, func() -> BotCommand: return aim_command(front, false))
	await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	victim.body.global_position = Vector3(0, 20, -30)
	await flush_physics()
	await run_ticks(1, func() -> BotCommand: return aim_command(front, false))
	print("RIDE grip %d point %s" % [attacker.combat.grip_target, attacker.combat.grip_point])
	check(attacker.combat.grip_target == 2 and attacker.combat.grip_point.z < -24.0, "The anchor rides the moving victim")
	victim.body.global_position = Vector3(0, 20, -20 - TurretTuning.settings().value("harpoon", "max_length"))
	await flush_physics()
	await run_ticks(1, func() -> BotCommand: return aim_command(front, false))
	check(attacker.combat.grip_target == 0, "Stretching past max_length snaps the tether")
	# A wall cutting the line snaps it; a miss never tethers.
	await place(front)
	await run_ticks(40, func() -> BotCommand: return aim_command(front, false))
	await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	var wall := _box(Vector3(0, 20, -10), Vector3(20, 20, 0.5))
	await flush_physics()
	await run_ticks(1, func() -> BotCommand: return aim_command(front, false))
	check(attacker.combat.grip_target == 0, "A wall between gun and anchor cuts the tether")
	wall.queue_free()
	await place(Vector3(30, 20, 0))
	await run_ticks(40, func() -> BotCommand: return aim_command(front, false))
	await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	check(attacker.combat.grip_target == 0 and attacker.combat.shot_sequence == 1, "A miss fires but never tethers")
	# Eliminating the victim releases the grip.
	await place(front)
	await run_ticks(40, func() -> BotCommand: return aim_command(front, false))
	await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	victim.combat.eliminated = true
	await run_ticks(1, func() -> BotCommand: return aim_command(front, true))
	check(attacker.combat.grip_target == 0, "An eliminated victim frees the harpoon")

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = BaselineConfig.WORLD_LAYER
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	return body

## Real Jolt: both machines on a floor; reeling drags the victim in.
func harpoon_reel() -> void:
	setup("harpoon", false)
	floor_body = _box(Vector3(0, -0.5, -20), Vector3(120, 1, 120))
	var ground := AtlasGeometry.GROUND_DEPTH * BotScale.from_size(attacker.combat.stats.size) + 0.05
	var start := Vector3(0, ground, -28)
	await place(start, Vector3(0, ground, 0))
	for index: int in 60: await get_tree().physics_frame
	var aim := func() -> BotCommand: return aim_command(victim.body.global_position, false)
	await run_ticks(60, aim, true)
	var before := victim.body.global_position.distance_to(attacker.body.global_position)
	await run_ticks(1, func() -> BotCommand: return aim_command(victim.body.global_position, true), true)
	check(attacker.combat.grip_target == 2, "Harpoon tethers a grounded target")
	for second: int in 3:
		await run_ticks(60, func() -> BotCommand: return aim_command(victim.body.global_position, true), true)
		print("REEL t=%d attacker %s victim %s grip %d heat %.0f" % [second + 1, attacker.body.global_position, victim.body.global_position, attacker.combat.grip_target, attacker.combat.heat])
	var after := victim.body.global_position.distance_to(attacker.body.global_position)
	print("HARPOON REEL distance %.1f -> %.1f m, attacker moved %.1f m" % [before, after, attacker.body.global_position.length()])
	check(after < before - 6.0, "Three seconds of reeling drags the victim well closer: %.1f -> %.1f" % [before, after])
	check(attacker.body.global_position.z < 3.0, "The reeled target arrives without shoving the shooter away: %s" % attacker.body.global_position)
	check(attacker.combat.heat > 5.0, "Reeling builds shared heat")
	var slack_from := victim.body.global_position
	await run_ticks(60, func() -> BotCommand: return aim_command(victim.body.global_position, false), true)
	check(victim.body.global_position.distance_to(slack_from) < 3.0, "Slack cable no longer pulls")
	floor_body.queue_free()

func mortar() -> void:
	setup("mortar")
	var ground := _box(Vector3(0, 18.5, -30), Vector3(160, 1, 160))
	var target := Vector3(0, 20, -40)
	await place(target)
	var tuning := TurretTuning.settings()
	# The servo holds the lowest lobbing elevation for flat aim.
	await run_ticks(90, func() -> BotCommand: return aim_command(target, false))
	check(attacker.combat.gun_pitch >= tuning.value("mortar", "min_elevation") - 0.001, "Flat aim is lifted to the lowest lobbing elevation")
	await run_ticks(120, func() -> BotCommand: return mortar_command(target, false))
	check(attacker.combat.gun_pitch > 0.8 and attacker.combat.gun_pitch <= AtlasGeometry.turret_pitch_max("mortar") + 0.001,
		"The servo elevates for the steep arc: %.2f" % attacker.combat.gun_pitch)
	var wall := _box(Vector3(0, 22, -20), Vector3(20, 8, 0.5))
	await flush_physics()
	var shot := await run_ticks(1, func() -> BotCommand: return mortar_command(target, true))
	check(shot.is_empty() and attacker.combat.shot_sequence == 1, "The shell leaves without an instant hit")
	var landing := attacker.combat.last_shot_to
	check(landing.distance_to(Vector3(target.x, landing.y, target.z)) < 4.0, "The shell lobs over the wall to the aimed point: %s" % landing)
	var flight := AtlasGeometry.mortar_flight(attacker.combat.last_shot_from, landing)
	check(flight > 1.0 and flight < 4.0, "Presentation flight time is plausible: %.2f s" % flight)
	var blast := await run_ticks(ceili(flight * 60.0) + 10, func() -> BotCommand: return mortar_command(target, false))
	var on_target := blast.filter(func(hit: Dictionary) -> bool: return hit.kind == "mortar" and hit.target == 2)
	check(on_target.size() == 1, "The blast hits the target once after the flight: %s" % [blast])
	check(victim.combat.core < victim.combat.stats.core or victim.combat.zones.values().any(func(value: float) -> bool: return value < 100.0), "The blast deals damage")
	# Out of the blast radius: no damage.
	wall.queue_free()
	await place(Vector3(0, 20, -40))
	await run_ticks(150, func() -> BotCommand: return mortar_command(Vector3(20, 20, -40), false))
	await run_ticks(1, func() -> BotCommand: return mortar_command(Vector3(20, 20, -40), true))
	var miss := await run_ticks(240, func() -> BotCommand: return mortar_command(Vector3(20, 20, -40), false))
	check(miss.is_empty(), "A shell landing 20 m away leaves the target unharmed")
	ground.queue_free()

func run() -> void:
	catalogue_and_wire()
	await harpoon_frozen()
	await harpoon_reel()
	await mortar()
	print("ATLAS LAUNCHER PHYSICS PASS" if failures == 0 else "ATLAS LAUNCHER PHYSICS FAIL")
	get_tree().quit(0 if failures == 0 else 1)
