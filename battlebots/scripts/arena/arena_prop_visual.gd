extends Node3D
## Client presentation of broken arena props (#71), driven by the replicated
## ArenaProps state. A felled tree topples as physics debris and leaves a
## stump; a barricade throws its logs and beams; a boulder splits into rock
## chunks. Debris is world-only (scripts/presentation/wreck_piece.gd) and
## shares the client debris budget with bot wrecks. A prop already broken when
## this client first sees the arena (join, reconnect) just shows its remains.
const PIECE := preload("res://scripts/presentation/wreck_piece.gd")
const TUNING := preload("res://scripts/core/destruction_tuning.gd")
const GROUND := preload("res://scripts/arena/woodland_ground.gd")
## Felled trees: stump height (m), trunk collider radius share and height (m),
## and the topple kick (rad/s) away from the blow.
const STUMP_HEIGHT := 0.9
const TREE_HEIGHT := 14.0
const TOPPLE_SPIN := 0.55
const TREE_MASS := 900.0
## Boulders split into this many chunks at this share of the rock's size.
const ROCK_CHUNKS := 4
const ROCK_SCALE := 0.55
## Launch speeds (m/s) for barricade timber and rock chunks.
const TIMBER_SPEED := 6.0
const ROCK_SPEED := 4.5

var _arena: Node3D
var _props: RefCounted
var _revision := -1
var _seen := false
## name -> {hidden: Array (restore records), pieces: Array[Node]}
var _broken: Dictionary = {}
var _stump_material: StandardMaterial3D

func configure(arena: Node3D, props: RefCounted) -> void:
	_arena = arena
	_props = props
	_stump_material = StandardMaterial3D.new()
	_stump_material.albedo_color = Color(0.3, 0.21, 0.13)
	_stump_material.roughness = 0.95

func _process(_delta: float) -> void:
	if _props == null or _props.revision == _revision:
		return
	_revision = _props.revision
	var moving := _seen
	_seen = true
	for name: String in _broken.keys():
		if not _props.destroyed.has(name):
			_restore(name)
	for name: String in _props.destroyed:
		if not _broken.has(name):
			_break(name, _props.destroyed[name], moving)

func _break(name: String, blow: Dictionary, moving: bool) -> void:
	var prop: Dictionary = _props.props.get(name, {})
	if prop.is_empty():
		return
	var record := {"hidden":[], "pieces":[]}
	_broken[name] = record
	match prop.kind:
		"tree": _fell(name, prop, blow, moving, record)
		_: _scatter(name, prop, blow, moving, record)
	var tuning: RefCounted = TUNING.settings()
	PIECE.enforce_budget(get_tree(), int(tuning.value("debris", "max_pieces")), tuning.value("debris", "sink_seconds"))

func _fell(name: String, prop: Dictionary, blow: Dictionary, moving: bool, record: Dictionary) -> void:
	var pine := _arena.find_child(name.replace("Trunk", "Pine"), true, false) as MeshInstance3D
	var base: Vector3 = prop.at
	var stump := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = GROUND.TRUNK_RADIUS * 0.95
	cylinder.bottom_radius = GROUND.TRUNK_RADIUS * 1.15
	cylinder.height = STUMP_HEIGHT
	cylinder.material = _stump_material
	stump.mesh = cylinder
	add_child(stump)
	stump.global_position = base + Vector3.UP * STUMP_HEIGHT * 0.5
	record.pieces.append(stump)
	if pine == null:
		return
	pine.hide()
	record.hidden.append(pine)
	if not moving:
		return
	var body: RigidBody3D = PIECE.new()
	body.name = "FelledTree"
	var copy := MeshInstance3D.new()
	copy.mesh = pine.mesh
	copy.transform = Transform3D(pine.global_basis, pine.global_position - base)
	body.add_child(copy)
	var shape := CollisionShape3D.new()
	var trunk := CylinderShape3D.new()
	trunk.radius = GROUND.TRUNK_RADIUS
	trunk.height = TREE_HEIGHT
	shape.shape = trunk
	shape.position.y = TREE_HEIGHT * 0.5
	body.add_child(shape)
	body.mass = TREE_MASS
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = Vector3.UP * TREE_HEIGHT * 0.4
	add_child(body)
	# Rest the trunk on the stump and tip it away from the blow.
	body.global_position = base + Vector3.UP * STUMP_HEIGHT
	var away: Vector3 = blow.axis
	if blow.kind == "saw":
		# The saw's axis is its blade axle: the tree falls across the blade.
		away = away.cross(Vector3.UP)
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = (base - blow.point).slide(Vector3.UP)
	away = away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD
	# The crown swings toward away: omega x (up * height) points along away.
	body.angular_velocity = Vector3.UP.cross(away) * TOPPLE_SPIN
	body.linear_velocity = away * 0.6
	record.pieces.append(body)

func _scatter(name: String, prop: Dictionary, blow: Dictionary, moving: bool, record: Dictionary) -> void:
	var owner := _visuals_with_instances()
	if owner == null:
		return
	var random := RandomNumberGenerator.new()
	random.seed = hash(name)
	var centre: Vector3 = prop.at
	for piece: Array in owner.prop_instances(name):
		var batch: MultiMeshInstance3D = piece[0]
		var index: int = piece[1]
		var pose := batch.multimesh.get_instance_transform(index)
		record.hidden.append([batch, index, pose])
		batch.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), pose.origin))
		if not moving:
			continue
		var world := batch.global_transform * pose
		if prop.kind == "boulder":
			for chunk: int in ROCK_CHUNKS:
				var offset := Vector3(random.randf_range(-1, 1), random.randf_range(0.1, 0.9), random.randf_range(-1, 1)) * world.basis.get_scale() * 0.35
				var local := Transform3D(world.basis.scaled(Vector3.ONE * ROCK_SCALE).rotated(Vector3.UP, random.randf() * TAU), world.origin + offset)
				record.pieces.append(_debris(batch, local, (local.origin - blow.point).normalized() * ROCK_SPEED + Vector3.UP * ROCK_SPEED * 0.6, random))
		else:
			var away: Vector3 = (world.origin - blow.point).normalized() + blow.axis.normalized() * 0.5
			record.pieces.append(_debris(batch, world, away.normalized() * TIMBER_SPEED * random.randf_range(0.6, 1.2) + Vector3.UP * TIMBER_SPEED * 0.5, random))

## A world-only physics piece drawing one batched instance's mesh.
func _debris(batch: MultiMeshInstance3D, pose: Transform3D, velocity: Vector3, random: RandomNumberGenerator) -> RigidBody3D:
	var body: RigidBody3D = PIECE.new()
	body.name = "PropDebris"
	var copy := MeshInstance3D.new()
	copy.mesh = batch.multimesh.mesh
	copy.material_override = batch.material_override
	copy.transform = Transform3D(pose.basis, Vector3.ZERO)
	body.add_child(copy)
	var points := PackedVector3Array()
	var box := copy.transform * batch.multimesh.mesh.get_aabb()
	for corner: int in 8:
		points.append(box.get_endpoint(corner))
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	shape.shape = hull
	body.add_child(shape)
	body.mass = maxf(box.size.x * box.size.y * box.size.z * 600.0, 1.0)
	add_child(body)
	body.global_position = pose.origin
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(random.randf_range(-3, 3), random.randf_range(-3, 3), random.randf_range(-3, 3))
	return body

func _visuals_with_instances() -> Node:
	for child: Node in _arena.find_children("*", "Node3D", true, false):
		if child.has_method("prop_instances"):
			return child
	return null

func _restore(name: String) -> void:
	var record: Dictionary = _broken[name]
	for hidden: Variant in record.hidden:
		if hidden is MeshInstance3D and is_instance_valid(hidden):
			hidden.show()
		elif hidden is Array and is_instance_valid(hidden[0]):
			hidden[0].multimesh.set_instance_transform(hidden[1], hidden[2])
	for piece: Node in record.pieces:
		if is_instance_valid(piece): piece.queue_free()
	_broken.erase(name)

func broken_names() -> Array:
	return _broken.keys()
