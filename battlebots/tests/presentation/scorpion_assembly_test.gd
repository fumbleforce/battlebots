extends Node3D
var failures: Array[String] = []
var world: AuthorityWorld
var bot: MvpBot
var throttle := 0.0
var sequence := 0

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func _physics_process(delta: float) -> void:
	if bot == null: return
	var command := BotCommand.new()
	sequence += 1
	command.sequence = sequence
	command.throttle = throttle
	command.brake = is_zero_approx(throttle)
	bot.submit_command(command)
	world.step(delta, true, 1)

func frames(count: int) -> void:
	for index: int in count: await get_tree().physics_frame

func run() -> void:
	var registry := ContentRegistry.new()
	var draft := registry.scorpion()
	check(registry.validate(draft).valid, "Complete hammer + minigun walker starter is canonical and legal")
	check(registry.validate(draft).stats.mass == 106, "Both modules and default side covers contribute installed mass")
	check(registry.validate(draft).stats.power == 95, "Both modules contribute installed power")
	var invalid := draft.duplicate(true)
	invalid.parts.drive = "traction"
	check(not registry.validate(invalid).valid, "Hex leg sockets reject incompatible wheeled drive")
	for weapon: String in ["hammer", "saw", "lifter", "vertical_spinner", "horizontal_spinner", "minigun"]:
		var variant := draft.duplicate(true)
		variant.parts.weapon = weapon
		variant.parts.utility = "cooling_pack"
		check(registry.validate(variant).valid, "Interchangeable primary part " + weapon)
		var visual := ScorpionVisual.new()
		add_child(visual)
		visual.assemble(variant, registry.validate(variant).stats.size)
		check(visual.nodes.TailBase.visible == (weapon == "hammer"), "Only equipped hammer arch renders")
		check(visual.nodes.GunMount.visible == (weapon == "minigun"), "Removed gun leaves socket free")
		check(visual.walker_legs.legs.size() == 6, "Six authored articulated limbs")
		visual.free()
	var donor := registry.starter()
	donor.parts.weapon = "minigun"
	var standard := MvpWeaponVisual.new()
	add_child(standard)
	standard.assemble("minigun", registry.validate(donor).stats.size)
	check(standard.gun_effects != null and standard.mechanism.find_child("GunRotor", true, false) != null, "Standalone gun fits other canonical bodies")
	standard.free()
	world = AuthorityWorld.new()
	add_child(world)
	bot = world.spawn(1, 0, 0, draft)
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 2.9, 10))
	bot.spawn_pose = bot.body.reset_pose
	var visual := bot.scorpion_visual
	if visual == null:
		visual = ScorpionVisual.new()
		bot.presentation.add_child(visual)
		visual.assemble(draft, bot.combat.stats.size)
		visual.walker_legs.exclusions = [bot.body.get_rid()]
	await frames(90)
	check(bot.body.walker_contacts.size() == 6, "All six physical feet support the settled hull")
	check(bot.get_node("Body/Collision").shape is ConvexPolygonShape3D, "Hexagonal collision envelope")
	check(bot.body.scale.is_equal_approx(Vector3.ONE), "Physics body remains unscaled")
	check(absf(bot.body.position.y - WalkerDrive.RIDE_HEIGHT) < 0.08, "Six-leg Jolt suspension holds ride height")
	var limbs := visual.walker_legs.legs
	check(absf(limbs[2].hip.x) > absf(limbs[0].hip.x) + 0.25, "Middle hips follow the wide side facets of the hex hull")
	check(absf(limbs[2].neutral.x) > absf(limbs[0].neutral.x) + 0.40, "Six feet form a radial stance rather than parallel rows")
	for leg: Dictionary in limbs:
		var facing: Vector3 = -leg.foot_mesh.global_basis.z.normalized()
		var expected_facing := (visual.walker_legs.global_basis * Vector3(leg.outward)).normalized()
		check(facing.dot(expected_facing) > 0.99, "Toes face out from their own radial leg socket")
	var collision: ConvexPolygonShape3D = bot.get_node("Body/Collision").shape
	var roof_width := 0.0
	var skirt_width := 0.0
	for point: Vector3 in collision.points:
		if point.y > 0.0: roof_width = maxf(roof_width, absf(point.x))
		else: skirt_width = maxf(skirt_width, absf(point.x))
	check(roof_width < skirt_width * 0.75, "Collision follows the strongly inward-sloping armor facets")
	var planted: Array[Vector3] = []
	for leg: Dictionary in visual.walker_legs.legs: planted.append(leg.foot)
	await frames(20)
	for index: int in 6:
		check(planted[index].distance_to(visual.walker_legs.legs[index].foot) < 0.02, "Idle feet remain planted")
	var start := bot.body.global_position
	throttle = 1.0
	var peak_step := 0.0
	var moved := {}
	for frame: int in 180:
		await frames(1)
		for index: int in 6:
			var foot: Vector3 = visual.walker_legs.legs[index].foot
			peak_step = maxf(peak_step, planted[index].distance_to(foot))
			if planted[index].distance_to(foot) > 0.01: moved[index] = true
			planted[index] = foot
	check(bot.body.global_position.distance_to(start) > 7.0, "Actual Jolt commands move the walking machine")
	check(moved.size() == 6, "Each of the six limbs takes a step")
	check(peak_step < 0.8, "Walking trajectories remain smooth at sixty physics ticks")
	throttle = 0.0
	await frames(60)
	for fraction: float in [0.0, 0.5, 1.0]:
		visual.set_hammer_fraction(fraction)
		var actual: Vector3 = visual.nodes.HammerHead.global_transform * (ScorpionGeometry.HEAD_CENTER - ScorpionGeometry.HEAD_PIVOT)
		var expected: Vector3 = bot.presentation.global_transform * ScorpionGeometry.hammer_transform(bot.combat.stats.size, fraction).origin
		check(actual.distance_to(expected) < 0.01, "Imported articulated hammer exactly follows authority geometry")
	print("SCORPION WALK distance=", bot.body.global_position.distance_to(start), " max_foot_step=", peak_step)
	bot = null
	world.queue_free()
	await get_tree().process_frame
	if failures.is_empty(): print("SCORPION ASSEMBLY PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
