class_name ScorpionLegs
extends WalkerLegs
## Six authored mechanical limbs use the shared planted-foot solver in two tripods.

func assemble(size: Vector3, _paint_material: Material, _config: Dictionary) -> void:
	_geometry_scale = BotScale.from_size(size)
	size /= _geometry_scale
	scale *= _geometry_scale
	var upper_scene: PackedScene = load("res://assets/models/scorpion_runtime/leg_upper.glb")
	var lower_scene: PackedScene = load("res://assets/models/scorpion_runtime/leg_lower.glb")
	var foot_scene: PackedScene = load("res://assets/models/scorpion_runtime/leg_foot.glb")
	for row: int in 3:
		for side: int in [-1, 1]:
			var hip := ScorpionStance.hip(row, side)
			var neutral := ScorpionStance.foot(row, side)
			var upper := Node3D.new()
			var lower := Node3D.new()
			var foot := Node3D.new()
			upper.name = "Upper_%d_%d" % [row, side]
			lower.name = "Lower_%d_%d" % [row, side]
			foot.name = "Foot_%d_%d" % [row, side]
			add_child(upper)
			add_child(lower)
			add_child(foot)
			upper.add_child(upper_scene.instantiate())
			lower.add_child(lower_scene.instantiate())
			foot.add_child(foot_scene.instantiate())
			var shoulder := Node3D.new()
			add_child(shoulder)
			shoulder.position = hip
			legs.append({"hip":hip, "neutral":neutral, "side":side, "outward":ScorpionStance.outward(row, side),
				"pair":(row + (1 if side < 0 else 0)) % 2,
				"upper":upper, "lower":lower, "foot_mesh":foot, "hip_joint":shoulder,
				"foot":Vector3.ZERO, "start":Vector3.ZERO, "target":Vector3.ZERO,
				"normal":Vector3.UP, "time":1.0, "collider":null,
				"local_contact":Vector3.ZERO, "local_normal":Vector3.UP})
	reset_feet()

## Every limb bends in its own radial plane. Its broad shin plate and toes
## face away from the body, following the angled sockets around the hexagon.
func _pose() -> void:
	for leg: Dictionary in legs:
		var hip: Vector3 = leg.hip
		var foot := to_local(leg.foot)
		var ankle := foot + global_basis.inverse() * Vector3(leg.normal) * (0.18 * _geometry_scale)
		ankle = hip + (ankle - hip).limit_length(ScorpionStance.UPPER_LENGTH + ScorpionStance.LOWER_LENGTH - 0.01)
		var outward: Vector3 = leg.outward
		var knee := ScorpionStance.knee(hip, ankle, outward)
		_radial_segment(leg.upper, hip, knee, outward)
		_radial_segment(leg.lower, knee, ankle, outward)
		var normal: Vector3 = leg.normal
		var forward := (global_basis * outward).slide(normal).normalized()
		if forward.is_zero_approx(): forward = Vector3.FORWARD
		var basis := Basis(forward.cross(normal).normalized(), normal, -forward)
		leg.foot_mesh.global_transform = Transform3D(basis.scaled(global_basis.get_scale()),
			to_global(ankle) - normal * (0.18 * _geometry_scale))

func _radial_segment(node: Node3D, start: Vector3, end: Vector3, outward: Vector3) -> void:
	var direction := (end - start).normalized()
	var tangent := Vector3.UP.cross(outward).normalized()
	var right := tangent.slide(direction).normalized()
	node.transform = Transform3D(Basis(right, direction, right.cross(direction)), start)
