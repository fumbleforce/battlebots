extends SceneTree
## Atlas MX front tools (#53, #54, #56) on real Jolt bodies through
## AuthorityWorld: ram prow multiplier and punch, spear impale/hold/throw,
## grinder drum shredding armour. Tuning: data/front_tools.json.
const RUN_UP := 14.0
const RAM_FRAMES := 240
const SETTLE_FRAMES := 60
var failures := 0
var world: AuthorityWorld
var tuning := FrontToolTuning.settings()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func frames(count: int, active := false) -> void:
	for index: int in range(count):
		world.step(1.0 / 60, active, 1)
		await physics_frame
	await process_frame

func atlas(weapon: String) -> Dictionary:
	var draft := world.registry.atlas()
	draft.parts.weapon = weapon
	return draft

func drive(bot: MvpBot, throttle: float, primary := false, secondary := false, nitro := false) -> void:
	var command := BotCommand.new()
	command.sequence = bot.last_sequence + 1
	command.throttle = throttle
	command.brake = throttle == 0.0
	command.primary_held = primary
	command.primary_pressed = primary
	command.secondary_held = secondary
	command.nitro_held = nitro
	bot.submit_command(command)

func catalogue() -> void:
	for weapon: String in ["battering_ram", "spear_fork", "grinder_drum"]:
		var result := world.registry.validate(atlas(weapon))
		check(result.valid and result.stats.weapon == weapon, "Atlas fits the %s: %s" % [weapon, result.reasons])
		var other := world.registry.starter()
		other.parts.weapon = weapon
		check(not world.registry.validate(other).valid, "%s needs the Atlas front coupler" % weapon)
	for preset: Dictionary in world.registry.atlas_showcase():
		check(world.registry.validate(preset).valid, "Preset %s is legal" % preset.name)
	var bot := world.spawn(9, 0, 0, atlas("grinder_drum"))
	bot.combat.tool_pose = 0.75
	var state := WireCodec.decode_bot(WireCodec.encode_bot(bot, "m:1"), bot.combat.stats)
	check(not state.is_empty() and is_equal_approx(state.tool_pose, 0.75), "Snapshot carries the tool pose")
	world.clear_bots()

## The rammer runs up into the victim's rear; returns [damage dealt, damage taken].
func ram_run(weapon: String) -> Array:
	world.clear_bots()
	await frames(2)
	var a := world.spawn(1, 0, 0, atlas(weapon))
	var b := world.spawn(2, 1, 0, atlas("lifter"))
	var length: float = b.combat.stats.size.z
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, length + RUN_UP))
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	await frames(SETTLE_FRAMES)
	var dealt := 0
	var taken := 0
	for index: int in range(RAM_FRAMES):
		drive(a, 1.0, false, false, true)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		var done := false
		for event: Dictionary in world.weapons.events:
			if event.kind != "ram": continue
			if event.target == b.entity_id: dealt += int(event.damage)
			if event.target == a.entity_id: taken += int(event.damage)
			done = true
		if done: break
	return [dealt, taken]

func ram() -> void:
	var plain: Array = await ram_run("lifter")
	var armed: Array = await ram_run("battering_ram")
	print("RAM plain dealt %d taken %d | battering ram dealt %d taken %d" % [plain[0], plain[1], armed[0], armed[1]])
	check(plain[0] > 0 and armed[0] >= plain[0] * 1.8, "The ram prow multiplies ram damage: %s vs %s" % [armed, plain])
	check(armed[1] < armed[0] * 0.5, "The ram prow absorbs most of the return blow: %s" % [armed])
	# Hydraulic punch against a parked target just ahead of the prow.
	world.clear_bots()
	await frames(2)
	var a := world.spawn(1, 0, 0, atlas("battering_ram"))
	var b := world.spawn(2, 1, 0, atlas("lifter"))
	var reach := -AtlasGeometry.RAM_NOSE_Z * BotScale.from_size(a.combat.stats.size)
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -reach - b.combat.stats.size.z * 0.5 - 0.4))
	await frames(SETTLE_FRAMES)
	var start := b.body.global_position
	var punched := false
	for index: int in range(30):
		drive(a, 0.0, index < 2)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		punched = punched or world.weapons.events.any(func(event: Dictionary) -> bool: return event.kind == "ram_punch" and event.target == b.entity_id)
	await frames(30, true)
	print("RAM punch moved the target %.2f m" % start.distance_to(b.body.global_position))
	check(punched, "The hydraulic punch strikes a target ahead of the prow")
	check(b.body.global_position.z < start.z - 1.0, "The punch shoves the target away")

func spear() -> void:
	world.clear_bots()
	await frames(2)
	var a := world.spawn(1, 0, 0, atlas("spear_fork"))
	var b := world.spawn(2, 1, 0, world.registry.starter())
	var linear := BotScale.from_size(a.combat.stats.size)
	var tip := -AtlasGeometry.SPEAR_TIP_Z * linear
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -tip - b.combat.stats.size.z * 0.5 + 0.6))
	await frames(SETTLE_FRAMES)
	var ground := b.body.global_position.y
	var stabbed := false
	for index: int in range(20):
		drive(a, 0.0, true)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		stabbed = stabbed or world.weapons.events.any(func(event: Dictionary) -> bool: return event.kind == "spear" and event.target == b.entity_id)
	check(stabbed and a.combat.grip_target == b.entity_id, "The thrust impales the target: stabbed %s grip %d" % [stabbed, a.combat.grip_target])
	var highest := ground
	for index: int in range(90):
		drive(a, 0.0, true)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		highest = maxf(highest, b.body.global_position.y)
	print("SPEAR hold lifted the target %.2f m, grip %d, heat %.0f" % [highest - ground, a.combat.grip_target, a.combat.heat])
	check(a.combat.grip_target == b.entity_id, "Holding primary keeps the target on the tines")
	check(highest > ground + 0.4, "The forklift lifts the impaled target")
	# Carry it: drive forward while holding, it comes along.
	var carried_from := b.body.global_position
	for index: int in range(60):
		drive(a, 0.6, true)
		world.step(1.0 / 60, true, 1)
		await physics_frame
	check(b.body.global_position.z < carried_from.z - 1.0 and a.combat.grip_target == b.entity_id, "The tank carries its impaled target")
	drive(a, 0.0, false)
	world.step(1.0 / 60, true, 1)
	await physics_frame
	check(a.combat.grip_target == 0, "Releasing primary throws the target off")

func grinder() -> void:
	world.clear_bots()
	await frames(2)
	var a := world.spawn(1, 0, 0, atlas("grinder_drum"))
	# The victim wears its chin plate and meets the drum off-centre, on its
	# armoured front face rather than the central weapon mount.
	var plated := atlas("lifter")
	plated.cosmetics.sawblade.armor_front = 1
	var b := world.spawn(2, 1, 0, plated)
	var linear := BotScale.from_size(a.combat.stats.size)
	var drum := -(AtlasGeometry.GRINDER_AXLE.z - AtlasGeometry.GRINDER_REACH) * linear
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	b.body.reset_pose = Transform3D(Basis(Vector3.UP, PI), Vector3(2.0, 1, -drum - b.combat.stats.size.z * 0.5 + 0.3))
	await frames(SETTLE_FRAMES)
	var core_before := b.combat.core
	var grinds := 0
	var plate_damage := 0
	for index: int in range(150):
		drive(a, 0.25, true)
		world.step(1.0 / 60, true, 1)
		await physics_frame
		for event: Dictionary in world.weapons.events:
			if event.kind == "grinder" and event.target == b.entity_id:
				grinds += 1
				plate_damage += int(event.damage)
	print("GRINDER %d contacts, %d damage, front plate %.0f, core %.0f -> %.0f, heat %.0f" % [grinds, plate_damage, b.combat.zones.front, core_before, b.combat.core, a.combat.heat])
	check(grinds >= 5, "The spinning drum grinds on a cadence: %d" % grinds)
	check(b.combat.zones.get("front", 0.0) < float(b.combat.stats.plates.get("front", 0.0)) - 15.0, "The spikes shred the front armour plate")
	check(a.combat.heat > 10.0, "Grinding builds heat")
	# Raising the arms lifts the drum.
	var low := AtlasGeometry.grinder_drum(a.combat.stats.size, 0.0)
	for index: int in range(40):
		drive(a, 0.0, false, true)
		world.step(1.0 / 60, true, 1)
		await physics_frame
	check(a.combat.tool_pose > 0.99 and AtlasGeometry.grinder_drum(a.combat.stats.size, a.combat.tool_pose).y > low.y + 0.5, "Secondary raises the grinder arms")

func run() -> void:
	world = AuthorityWorld.new()
	root.add_child(world)
	await frames(2)
	catalogue()
	await ram()
	await spear()
	await grinder()
	print("ATLAS TOOLS PHYSICS PASS" if failures == 0 else "ATLAS TOOLS PHYSICS FAIL")
	quit(mini(failures, 1))
