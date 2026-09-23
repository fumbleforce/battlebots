extends Node3D
## Atlas drive configurations: validation, running-gear swap, wheel spin, the
## runtime leg solver against the generator's authored poses, planted feet on
## a floor and drive-map repainting. Paint needs the native renderer.
const DRIVES := "res://assets/models/atlas_runtime/atlas_drives.glb"
const MANIFEST := "res://assets/models/atlas_runtime/atlas_drives_manifest.json"
## Tolerances in Atlas source metres (poses) and radians.
const POSE_TOLERANCE := 0.0005
const ANGLE_TOLERANCE := 0.0005
## Planted soles may sit this far from the floor (game metres).
const FLOOR_TOLERANCE := 0.02
## Wheel travel used for the spin check (source metres of tread).
const SPIN_TRAVEL := 0.35
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var registry := ContentRegistry.new()
	var base: Dictionary = registry.atlas()
	for drive: String in AtlasGeometry.DRIVE_GEAR:
		var draft := base.duplicate(true)
		draft.parts.drive = drive
		check(registry.validate(draft).valid, "Atlas accepts its %s drive" % drive)
	var agile := base.duplicate(true)
	agile.parts.drive = "agile"
	check(not registry.validate(agile).valid, "Atlas still rejects a drive it has no running gear for")
	rig_case()
	wheels_case(registry, base)
	legs_case(registry, base)
	await floor_case(registry, base)
	await foothold_case(registry, base)
	if DisplayServer.get_name() != "headless": await paint_case(registry, base)
	if failures.is_empty(): print("ATLAS DRIVES PASS")
	else:
		for message: String in failures: push_error(message)
		print("ATLAS DRIVES FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)

func rig_case() -> void:
	var rig := AtlasDriveRig.settings()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	check(is_equal_approx(rig.wheel_radius, manifest.wheels.radius) and is_equal_approx(rig.femur, manifest.legs.femur)
		and is_equal_approx(rig.tibia, manifest.legs.tibia) and is_equal_approx(rig.coxa_reach, manifest.legs.coxa_reach),
		"The runtime rig and the model manifest come from the same generator run")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AtlasDriveRig.PATH))
	data.legs.erase("femur")
	var problems: Array[String] = []
	check(AtlasDriveRig.from_json(JSON.stringify(data), problems) == null and not problems.is_empty(),
		"A rig missing a leg dimension is rejected instead of defaulted")

func assemble(registry: ContentRegistry, base: Dictionary, drive: String) -> AtlasVisual:
	var draft := base.duplicate(true)
	draft.parts.drive = drive
	var visual := AtlasVisual.new()
	add_child(visual)
	visual.assemble(draft, registry.validate(draft).stats.size)
	return visual

func wheels_case(registry: ContentRegistry, base: Dictionary) -> void:
	var tracks := assemble(registry, base, "traction")
	check(tracks.drive_gear == "tracks" and tracks.drives == null and tracks._links.size() == 80,
		"Traction keeps the approved tracks untouched")
	tracks.free()
	var visual := assemble(registry, base, "standard_wheels")
	var rig := AtlasDriveRig.settings()
	check(visual.drive_gear == "wheels" and visual.drives != null, "Standard wheels fit the large off-road running gear")
	check(not visual.nodes.DriveLeft.visible and not visual.nodes.DriveRight.visible, "The approved track assemblies are hidden")
	check(visual._links.is_empty() and visual._connectors.is_empty(), "No tread shoes animate under wheels")
	check(visual.drives.find_child("Legs", true, false) == null, "The unused leg set is freed")
	check(visual._wheels.size() == 4, "Four large wheel pivots animate")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for wheel: Dictionary in visual._wheels:
		check(is_equal_approx(wheel.radius, rig.wheel_radius), "Wheel spin uses the rig's lug-tip radius")
		var centre: Array = manifest.wheels.centers[str(wheel.node.name)]
		check(visual._relative_transform(wheel.node).origin.distance_to(Vector3(centre[0], centre[1], centre[2])) < POSE_TOLERANCE,
			"Imported wheel pivot agrees with its published centre: " + str(wheel.node.name))
	var first: Dictionary = visual._wheels[0]
	var rest: Basis = first.node.basis
	visual.advance_drive(SPIN_TRAVEL, SPIN_TRAVEL)
	var expected: Basis = rest * Basis(Vector3.RIGHT, -SPIN_TRAVEL / rig.wheel_radius)
	check(first.node.basis.is_equal_approx(expected), "Travel rolls the wheel by arc length over its radius")
	visual.advance_drive(-SPIN_TRAVEL, -SPIN_TRAVEL)
	check(first.node.basis.is_equal_approx(rest), "Wheel phase returns without drift")
	sides_case(visual, "wheels")
	visual.free()

func sides_case(visual: AtlasVisual, gear: String) -> void:
	var groups := visual.component_meshes()
	check(not groups.drive_left.is_empty() and not groups.drive_right.is_empty(), "%s register both sides for damage" % gear)
	for mesh: Node in groups.drive_left:
		check(not groups.drive_right.has(mesh), "%s sides never share damage surfaces" % gear)

## The GLB stores each leg in the generator's neutral pose. The runtime solver
## must reproduce those transforms exactly from the same rig and footholds.
func legs_case(registry: ContentRegistry, base: Dictionary) -> void:
	var authored := {}
	var reference: Node3D = load(DRIVES).instantiate()
	for node: Node in reference.find_children("Leg*", "Node3D", true, false):
		authored[str(node.name)] = _hull_transform(node, reference)
	reference.free()
	var draft := base.duplicate(true)
	draft.parts.drive = "walker"
	var size: Vector3 = registry.validate(draft).stats.size
	var rig := AtlasDriveRig.settings()
	var legs := AtlasLegs.new()
	var dummy := {}
	for key: String in authored: dummy[key] = Node3D.new()
	legs.attach(size, dummy)
	check(legs.legs.size() == 4, "Four hydraulic legs")
	for leg: Dictionary in legs.legs:
		var frames := AtlasLegs.solve(rig, leg.side, leg.end, Vector3(leg.neutral) + Vector3.UP * rig.ankle, Vector3.UP, leg.neutral_yaw)
		for part: String in AtlasLegs.PARTS:
			var label := "Leg%s_%s" % [part, leg.tag]
			var expected: Transform3D = authored.get(label, Transform3D())
			check(authored.has(label), "The GLB exports " + label)
			check(frames[part].origin.distance_to(expected.origin) < POSE_TOLERANCE and _basis_close(frames[part].basis, expected.basis),
				"Runtime solver reproduces the authored neutral pose of " + label)
		check((frames.Femur * Vector3(0, rig.femur, 0)).distance_to(frames.Tibia.origin) < POSE_TOLERANCE, "Femur ends at the knee pin")
		check((frames.Tibia * Vector3(0, rig.tibia, 0)).distance_to(frames.Foot.origin) < POSE_TOLERANCE, "Tibia ends at the ankle ball")
		var horn: Vector3 = frames.Tibia * Vector3(rig.knee_tibia.x, rig.knee_tibia.y, 0)
		check(frames.KneeRod.origin.distance_to(horn) < POSE_TOLERANCE
			and (frames.KneeBarrel.basis.y).dot((horn - frames.KneeBarrel.origin).normalized()) > 1.0 - ANGLE_TOLERANCE,
			"The knee ram barrel aims at its rod eye on the tibia horn")
		# A stride beyond the inboard stop keeps the coxa on its limit.
		var inboard := Vector3(leg.neutral) + Vector3(-leg.side * 0.3, rig.ankle, 0)
		var clamped := AtlasLegs.solve(rig, leg.side, leg.end, inboard, Vector3.UP, leg.neutral_yaw)
		var heading: Vector3 = clamped.Coxa.basis.x
		check(atan2(leg.side * heading.x, leg.end * heading.z) >= rig.coxa_yaw_min - ANGLE_TOLERANCE,
			"The coxa respects its inboard slewing stop")
		var stance := Vector3(leg.neutral) + Vector3.UP * rig.ankle
		var ledge := AtlasLegs.solve(rig, leg.side, leg.end, stance + Vector3.UP * (rig.ankle_rise_limit * 2.0), Vector3.UP, leg.neutral_yaw)
		check(absf(ledge.Foot.origin.y - (stance.y + rig.ankle_rise_limit)) < POSE_TOLERANCE,
			"A foothold above the rise limit folds the leg only to the limit")
	for node: Node in dummy.values(): node.free()
	legs.free()
	var visual := assemble(registry, base, "walker")
	check(visual.drive_gear == "legs" and visual.legs != null and visual._wheels.is_empty(), "The walker drive fits hydraulic legs")
	check(visual.drives.find_child("WheelsLarge", true, false) == null, "The unused wheel set is freed")
	sides_case(visual, "legs")
	visual.free()

func floor_case(registry: ContentRegistry, base: Dictionary) -> void:
	var visual := assemble(registry, base, "walker")
	var scale_factor := BotScale.from_size(registry.validate(visual_draft(base, "walker")).stats.size)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = BaselineConfig.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	add_child(floor_body)
	var floor_y := -WalkerDrive.RIDE_HEIGHT * scale_factor / BotScale.FACTOR
	floor_body.position = Vector3(0, floor_y - 0.5, 0)
	for frame: int in 3: await get_tree().physics_frame
	visual.legs.reset_feet()
	var rig := AtlasDriveRig.settings()
	for leg: Dictionary in visual.legs.legs:
		var foot: Node3D = leg.nodes.Foot
		var sole := foot.global_position.y - rig.ankle * scale_factor
		check(absf(sole - floor_y) < FLOOR_TOLERANCE, "Leg %s plants its sole on the floor (%.3f)" % [leg.tag, sole - floor_y])
	visual.free()
	floor_body.free()

## An Atlas on legs is supported at the rig footholds its legs are drawn on;
## other walkers keep the chassis-derived footholds.
func foothold_case(registry: ContentRegistry, base: Dictionary) -> void:
	var bot := MvpBot.create(1, 0, visual_draft(base, "walker"), registry)
	add_child(bot)
	await get_tree().process_frame
	check(bot.body.walker and bot.body.walker_footholds.is_equal_approx(AtlasDriveRig.settings().foothold * bot.body.geometry_scale),
		"WalkerDrive supports the Atlas at the rig footholds")
	bot.free()
	var scorpion := MvpBot.create(2, 0, registry.scorpion(), registry)
	add_child(scorpion)
	await get_tree().process_frame
	check(scorpion.body.walker_footholds == Vector2.ZERO, "Other walkers keep their own footholds")
	scorpion.free()

func visual_draft(base: Dictionary, drive: String) -> Dictionary:
	var draft := base.duplicate(true)
	draft.parts.drive = drive
	return draft

## Repainting the primary channel tints only enamel on the new drive maps.
func paint_case(registry: ContentRegistry, base: Dictionary) -> void:
	for drive: String in ["standard_wheels", "walker"]:
		var draft := visual_draft(base, drive)
		var paint: Dictionary = AtlasGeometry.paint_defaults()
		paint.paint_primary = [0.02, 0.35, 0.6, 1.0]
		draft.cosmetics["sawblade"] = paint
		var visual := AtlasVisual.new()
		add_child(visual)
		visual.assemble(draft, registry.validate(draft).stats.size)
		var repainted := 0
		for mesh: MeshInstance3D in visual.drives.find_children("*", "MeshInstance3D", true, false):
			for index: int in mesh.mesh.get_surface_count():
				var material := mesh.get_surface_override_material(index) as ShaderMaterial
				if material == null: continue
				var coverage: Texture2D = material.get_shader_parameter("surface_coverage")
				if coverage != null and "Atlas_DrivePrimary" in coverage.resource_path: repainted += 1
		check(repainted > 0, "%s enamel repaints through the drive coverage map" % drive)
		visual.free()
		await get_tree().process_frame

func _hull_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null and parent != root:
		result = parent.transform * result
		parent = parent.get_parent() as Node3D
	return result

func _basis_close(a: Basis, b: Basis) -> bool:
	for axis: int in 3:
		if a[axis].distance_to(b[axis]) > ANGLE_TOLERANCE: return false
	return true
