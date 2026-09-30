extends SceneTree
## Every weapon on every offered body (#108): the front tools, the turrets and
## the auxiliary gun validate on the Sawblade, the Scorpion, the Atlas MX and
## the placeholder box, and their authoritative geometry follows each body's
## data/weapon_mounts.json mount on real Jolt bodies through AuthorityWorld.
const WEAPON_MOUNTS = preload("res://scripts/core/weapon_mounts.gd")
const SETTLE_FRAMES := 90
## Gap between a tool's reach at rest and a parked target's near face (m): the
## ram punch and spear thrust extend across TOUCHING, never across OUT_OF_REACH.
const TOUCHING := 0.3
const OUT_OF_REACH := 3.0
const TURRET_RANGE := 18.0
const GUN_RANGE := 9.0
var failures := 0
var world: AuthorityWorld
var free := ContentRegistry.new()

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

## A draft on the named body: "sawblade", "scorpion", "atlas" or "box".
func build(body: String, weapon := "lifter", utility := "recovery_assist") -> Dictionary:
	var draft := world.registry.starter()
	match body:
		"sawblade": draft = SawbladeConfig.starter(world.registry)
		"scorpion": draft = world.registry.scorpion()
		"atlas": draft = world.registry.atlas()
	draft.parts.weapon = weapon
	draft.parts.utility = utility
	return draft

func command(bot: MvpBot) -> BotCommand:
	var intent := BotCommand.new()
	intent.sequence = bot.last_sequence + 1
	intent.brake = true
	return intent

func catalogue() -> void:
	free.enforce_budget = false
	var weapons: Array = []
	var auxiliaries: Array = ["minigun_pod"]
	auxiliaries.append_array(AtlasGeometry.TURRET_PARTS.keys())
	for id: String in world.registry.parts:
		if world.registry.parts[id].category == "weapon": weapons.append(id)
	check(weapons.size() == 10 and auxiliaries.size() == 12, "The catalogue has ten primaries and twelve auxiliary weapons")
	for body: String in ["sawblade", "scorpion", "atlas", "box"]:
		for weapon: String in weapons:
			var result := free.validate(build(body, weapon))
			check(result.valid and result.loadout.parts.weapon == weapon, "%s mounts the %s: %s" % [body, weapon, result.reasons])
		for auxiliary: String in auxiliaries:
			var result := free.validate(build(body, "lifter", auxiliary))
			check(result.valid and result.stats.secondary_weapon != "", "%s mounts the %s: %s" % [body, auxiliary, result.reasons])
			# The power budget is a separate rule: it may refuse a build, a mount never does.
			var strict := world.registry.validate(build(body, "lifter", auxiliary))
			check(strict.valid or Array(strict.reasons) == ["Installed power exceeds 100"],
				"Only the power budget limits the %s on %s: %s" % [auxiliary, body, strict.reasons])
	# Weapons that share one mechanism still exclude each other on every body.
	for body: String in ["sawblade", "scorpion", "atlas", "box"]:
		check(not free.validate(build(body, "minigun", "minigun_pod")).valid, "%s takes one minigun" % body)
		check(not free.validate(build(body, "minigun", "turret_cannon")).valid, "A turret excludes the primary minigun on %s" % body)
	# The authored bodies use no mount; every other body has measured clearance.
	var atlas := world.registry.validate(build("atlas", "battering_ram", "turret_cannon")).stats
	check(atlas.turret_mount == Transform3D.IDENTITY and atlas.tool_mount == Transform3D.IDENTITY and atlas.turret_depression.is_empty(),
		"The Atlas MX keeps its authored frames and audit")
	check(world.registry.validate(world.registry.bracken()).stats.turret_mount == Transform3D.IDENTITY, "Bracken keeps its authored frames")
	for body: String in WEAPON_MOUNTS.BODIES:
		for model: String in AtlasGeometry.TURRET_PARTS.values():
			var draft := build(body, "lifter", AtlasGeometry.TURRET_PARTS.find_key(model))
			var stats: Dictionary = free.validate(draft).stats
			var table: Array = stats.turret_depression
			var highest := rad_to_deg(AtlasGeometry.turret_pitch_max(model))
			check(table.size() == WEAPON_MOUNTS.DEPRESSION_SAMPLES and table.all(func(value: Variant) -> bool:
				return float(value) >= -20.0 and float(value) <= highest + 0.001),
				"%s has a measured clearance table for the %s" % [body, model])
			check(stats.turret_mount != Transform3D.IDENTITY and WEAPON_MOUNTS.scale_of(stats.turret_mount) < 1.0,
				"%s carries the %s on its own, smaller race" % [body, model])
			check(is_equal_approx(AtlasGeometry.turret_pitch_min(model, 0.0, table), deg_to_rad(maxf(float(table[0]), float(table[1])))),
				"The servo floor reads the %s table on %s" % [model, body])

## Parks a target just ahead of the attacker's weapon reach; both settle.
func park(attacker: Dictionary, reach: float, gap: float, victim := {}) -> Array:
	world.clear_bots()
	await frames(2)
	var a := world.spawn(1, 0, 0, attacker)
	var b := world.spawn(2, 1, 0, victim if not victim.is_empty() else world.registry.starter())
	var height := a.ground_clearance() + 0.3
	a.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, height, 0))
	b.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1, -reach - b.combat.stats.size.z * 0.5 - gap))
	await frames(SETTLE_FRAMES)
	return [a, b]

func hits(kind: String, target: MvpBot) -> int:
	var count := 0
	for event: Dictionary in world.weapons.events:
		if event.kind == kind and event.target == target.entity_id: count += 1
	return count

## The tool's forward reach from the hull centre, through its body mount.
func tool_reach(draft: Dictionary, atlas_z: float) -> float:
	var stats: Dictionary = world.registry.validate(draft).stats
	return -(stats.tool_mount * Vector3(0, 0, atlas_z * BotScale.from_size(stats.size))).z

func front_tools() -> void:
	for body: String in ["sawblade", "scorpion"]:
		var ram := build(body, "battering_ram")
		var nose := tool_reach(ram, AtlasGeometry.RAM_NOSE_Z)
		var atlas_nose := tool_reach(build("atlas", "battering_ram"), AtlasGeometry.RAM_NOSE_Z)
		check(nose > 0.0 and nose < atlas_nose - 1.0, "%s carries a shorter ram than the Atlas: %.2f vs %.2f m" % [body, nose, atlas_nose])
		for gap: float in [TOUCHING, OUT_OF_REACH]:
			var pair: Array = await park(ram, nose, gap)
			var a: MvpBot = pair[0]
			var b: MvpBot = pair[1]
			# The resting prow is solid where the mount puts it (#112).
			var prow: Transform3D = AtlasGeometry.ram_volume(a.combat.stats.size, 0.0)[0]
			check(a.weapon_collision != null and a.weapon_collision.transform.origin.is_equal_approx((a.combat.stats.tool_mount as Transform3D) * prow.origin),
				"%s ram collider sits on its mounted prow" % body)
			var punched := 0
			for index: int in range(30):
				var intent := command(a)
				intent.primary_held = index < 2
				intent.primary_pressed = index < 2
				a.submit_command(intent)
				world.step(1.0 / 60, true, 1)
				await physics_frame
				punched += hits("ram_punch", b)
			check((punched > 0) == (gap == TOUCHING), "%s ram punch at %.1f m past its prow: %d hits" % [body, gap, punched])
		var spear := build(body, "spear_fork")
		var pair: Array = await park(spear, tool_reach(spear, AtlasGeometry.SPEAR_TIP_Z), -TOUCHING)
		var a: MvpBot = pair[0]
		var b: MvpBot = pair[1]
		var stabbed := 0
		for index: int in range(25):
			var intent := command(a)
			intent.primary_held = true
			intent.primary_pressed = index < 2
			a.submit_command(intent)
			world.step(1.0 / 60, true, 1)
			await physics_frame
			stabbed += hits("spear", b)
		check(stabbed == 1 and a.combat.grip_target == b.entity_id, "%s spear impales a target at its tines: %d, grip %d" % [body, stabbed, a.combat.grip_target])
		var hold: Vector3 = a.body.global_transform * (a.combat.stats.tool_mount as Transform3D) * AtlasGeometry.spear_hold(a.combat.stats.size, a.combat.tool_pose)
		check(a.combat.grip_point.distance_to(hold) < 2.5, "%s holds its catch at its own tines, %.2f m off" % [body, a.combat.grip_point.distance_to(hold)])
		var grinder := build(body, "grinder_drum")
		pair = await park(grinder, tool_reach(grinder, AtlasGeometry.GRINDER_AXLE.z - AtlasGeometry.GRINDER_REACH), -0.3)
		a = pair[0]
		b = pair[1]
		var grinds := 0
		for index: int in range(120):
			var intent := command(a)
			intent.primary_held = true
			intent.primary_pressed = index == 0
			a.submit_command(intent)
			world.step(1.0 / 60, true, 1)
			await physics_frame
			grinds += hits("grinder", b)
		check(grinds >= 3, "%s grinder drum grinds a target in its spikes: %d" % [body, grinds])

## The Ramp off the Sawblade body and the Lifter on it (#108): both flip a
## target that stands against the nose, over the tool.
func lifting_tools() -> void:
	for case: Array in [["atlas", "ramp"], ["scorpion", "ramp"], ["box", "ramp"], ["sawblade", "lifter"]]:
		var draft := build(case[0], case[1])
		var stats: Dictionary = world.registry.validate(draft).stats
		check(stats.weapon == "lifter", "%s %s follows the lifter rules" % [case[0], case[1]])
		if case[1] == "ramp":
			var plate: Transform3D = SawbladeGeometry.ramp_volume(draft, stats.size, 0.0)[0]
			check(-plate.origin.z > stats.size.z * 0.5, "%s carries the Ramp ahead of its nose: plate centre %.2f m" % [case[0], -plate.origin.z])
		var pair: Array = await park(draft, stats.size.z * 0.5, TOUCHING)
		var a: MvpBot = pair[0]
		var b: MvpBot = pair[1]
		check(a.weapon_collision != null and a._weapon_solid_when_active == (case[1] == "ramp"), "%s %s carries its collider" % [case[0], case[1]])
		if case[1] == "ramp":
			# The plate is a solid wedge from the hinge ahead of the nose down to the floor.
			var lowest := INF
			var foremost := INF
			for point: Vector3 in (a.weapon_collision.shape as ConvexPolygonShape3D).points:
				lowest = minf(lowest, point.y)
				foremost = minf(foremost, point.z)
			check(foremost < -stats.size.z * 0.5 - 2.0 and absf(lowest + a.ground_clearance()) < 0.05,
				"%s Ramp wedge lies ahead of the nose on the floor: front %.2f, bottom %.2f" % [case[0], foremost, lowest])
		var ground := b.body.global_position.y
		var flipped := 0
		var highest := ground
		for index: int in range(150):
			var intent := command(a)
			intent.primary_held = index < 70
			intent.primary_pressed = index == 0
			a.submit_command(intent)
			world.step(1.0 / 60, true, 1)
			await physics_frame
			flipped += hits("lifter", b)
			highest = maxf(highest, b.body.global_position.y)
		check(flipped == 1, "%s %s flips a target in its reach once: %d" % [case[0], case[1], flipped])
		check(highest > ground + 0.5, "%s %s throws the target up %.2f m" % [case[0], case[1], highest - ground])

func turrets() -> void:
	for body: String in ["sawblade", "scorpion"]:
		var pair: Array = await park(build(body, "lifter", "turret_cannon"), TURRET_RANGE, 0.0)
		var a: MvpBot = pair[0]
		var b: MvpBot = pair[1]
		var mount: Transform3D = a.combat.stats.turret_mount
		var size: Vector3 = a.combat.stats.size
		var struck := 0
		var muzzle_error := INF
		for index: int in range(150):
			var intent := command(a)
			var breech := a.body.global_transform * mount * AtlasGeometry.turret_breech(size, a.combat.turret_yaw)
			var direction := b.body.global_position - breech
			intent.aim_valid = true
			intent.aim_yaw = atan2(-direction.x, -direction.z)
			intent.aim_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
			intent.auxiliary_held = index > 60
			a.submit_command(intent)
			var sequence := a.combat.shot_sequence
			world.step(1.0 / 60, true, 1)
			if a.combat.shot_sequence != sequence:
				var muzzle := a.previous_pose * mount * AtlasGeometry.turret_muzzle(size, "cannon", a.combat.turret_yaw, a.combat.gun_pitch)
				muzzle_error = minf(muzzle_error, a.combat.last_shot_from.distance_to(muzzle))
			await physics_frame
			struck += hits("cannon", b)
		check(struck >= 1, "%s turret cannon hits a target %d m ahead: %d" % [body, TURRET_RANGE, struck])
		check(muzzle_error < 0.05, "%s fires from its mounted muzzle, %.3f m off" % [body, muzzle_error])
		var authored := a.body.global_transform * AtlasGeometry.turret_muzzle(size, "cannon", 0.0, 0.0)
		var mounted := a.body.global_transform * mount * AtlasGeometry.turret_muzzle(size, "cannon", 0.0, 0.0)
		check(authored.distance_to(mounted) > 0.5, "%s mount differs from the Atlas frame by %.2f m" % [body, authored.distance_to(mounted)])
		# The servo stops at this body's measured clearance, not the Atlas audit.
		for index: int in range(240):
			var intent := command(a)
			intent.aim_valid = true
			intent.aim_yaw = a.body.global_rotation.y + PI * 0.5
			intent.aim_pitch = -1.2
			a.submit_command(intent)
			world.step(1.0 / 60, true, 1)
			await physics_frame
		var table: Array = a.combat.stats.turret_depression
		check(is_equal_approx(a.combat.gun_pitch, AtlasGeometry.turret_pitch_min("cannon", a.combat.turret_yaw, table)),
			"%s barrel stops at its measured flank clearance: %.1f deg" % [body, rad_to_deg(a.combat.gun_pitch)])

func auxiliary_gun() -> void:
	for body: String in ["sawblade", "box"]:
		var pair: Array = await park(build(body, "lifter", "minigun_pod"), GUN_RANGE, 0.0)
		var a: MvpBot = pair[0]
		var b: MvpBot = pair[1]
		check(a.combat.stats.secondary_weapon == "minigun", "%s publishes its auxiliary gun" % body)
		var struck := 0
		for index: int in range(90):
			var intent := command(a)
			intent.auxiliary_held = true
			intent.secondary_held = true
			a.submit_command(intent)
			world.step(1.0 / 60, true, 1)
			await physics_frame
			struck += hits("minigun", b)
		check(struck >= 3, "%s auxiliary gun hits a target %d m ahead: %d" % [body, GUN_RANGE, struck])

func run() -> void:
	world = AuthorityWorld.new()
	root.add_child(world)
	await frames(2)
	catalogue()
	await front_tools()
	await lifting_tools()
	await turrets()
	await auxiliary_gun()
	print("WEAPON MOUNTS PHYSICS PASS" if failures == 0 else "WEAPON MOUNTS PHYSICS FAIL")
	quit(mini(failures, 1))
