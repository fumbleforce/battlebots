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
## Other solid props burst the same way: kind -> [chunks, share of size]
## (the Frozen Maelstrom's seracs, icicles, barrels and crates, #102).
const CHUNKS := {"boulder":[ROCK_CHUNKS, ROCK_SCALE]}
## Props whose presentation ships their real parts (prop_parts) come apart into
## those instead: a serac into its shards, an icicle clump into its spikes.
const PART_SPEED := 4.0
## Pieces of shatter props (#102) sink away after this many seconds.
const SHATTER_DEBRIS_SECONDS := 4.0
const SHATTER_SINK_SECONDS := 1.5
## A new piece whose centre lies under the ground is dropped at once; one whose
## lowest corner dips more than this (m) into it stays put as a stub (frozen)
## until it sinks away, instead of being shoved out of the ice.
const GROUND_TOLERANCE := 0.05
## How far (m) below a new piece's centre the ground may lie.
const SETTLE_REACH := 60.0
## Kinds whose parts snap again into shorter lengths (a rib into a few bones):
## pieces about this long (m), at most SPLIT_MAX of them.
const SPLIT_KINDS := ["rib"]
const SPLIT_LENGTH := 2.0
const SPLIT_MAX := 4
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
	if bool(_props.settings().kinds.get(prop.kind, {}).get("shatter", false)):
		for piece: Node in record.pieces:
			_despawn_later(piece)
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
	var parts: Array = owner.prop_parts(name) if owner.has_method("prop_parts") else []
	for piece: Array in owner.prop_instances(name):
		var batch: MultiMeshInstance3D = piece[0]
		var index: int = piece[1]
		var pose := batch.multimesh.get_instance_transform(index)
		record.hidden.append([batch, index, pose])
		batch.multimesh.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), pose.origin))
		if not moving:
			continue
		var world := batch.global_transform * pose
		if not parts.is_empty():
			for part: Mesh in parts:
				for bit: Mesh in (_split(part) if prop.kind in SPLIT_KINDS else [part]):
					_keep(record, _part_debris(bit, world, blow, random))
		elif CHUNKS.has(prop.kind):
			var split: Array = CHUNKS[prop.kind]
			for chunk: int in int(split[0]):
				var offset := Vector3(random.randf_range(-1, 1), random.randf_range(0.1, 0.9), random.randf_range(-1, 1)) * world.basis.get_scale() * 0.35
				var local := Transform3D(world.basis.scaled(Vector3.ONE * float(split[1]) * random.randf_range(0.8, 1.15)).rotated(Vector3.UP, random.randf() * TAU)
					.rotated(Vector3.RIGHT, random.randf_range(-0.8, 0.8)), world.origin + offset)
				_keep(record, _debris(batch, local, (local.origin - blow.point).normalized() * ROCK_SPEED + Vector3.UP * ROCK_SPEED * 0.6, random))
		else:
			var away: Vector3 = (world.origin - blow.point).normalized() + blow.axis.normalized() * 0.5
			_keep(record, _debris(batch, world, away.normalized() * TIMBER_SPEED * random.randf_range(0.6, 1.2) + Vector3.UP * TIMBER_SPEED * 0.5, random))

## One real part of a broken prop: a world-only physics piece at its place in
## the prop (model transform world), thrown out from the blow.
## Null when the piece lies buried in the ice.
func _part_debris(mesh: Mesh, world: Transform3D, blow: Dictionary, random: RandomNumberGenerator) -> RigidBody3D:
	var body: RigidBody3D = PIECE.new()
	body.name = "PropPart"
	var box := mesh.get_aabb()
	var centre := box.get_center()
	var copy := MeshInstance3D.new()
	copy.mesh = mesh
	copy.transform = Transform3D(world.basis, -(world.basis * centre))
	body.add_child(copy)
	var points := PackedVector3Array()
	for corner: int in 8:
		points.append(copy.transform * box.get_endpoint(corner))
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	shape.shape = hull
	body.add_child(shape)
	var scale := world.basis.get_scale()
	body.mass = maxf(box.size.x * box.size.y * box.size.z * scale.x * scale.y * scale.z * 600.0, 1.0)
	add_child(body)
	body.global_position = world * centre
	if not _settle(body, points):
		return null
	if body.freeze:
		return body
	var away: Vector3 = (body.global_position - blow.point).slide(Vector3.UP).normalized() + Vector3(blow.axis).normalized() * 0.5
	body.linear_velocity = away.normalized() * PART_SPEED * random.randf_range(0.5, 1.2) + Vector3.UP * PART_SPEED * random.randf_range(0.2, 0.7)
	body.angular_velocity = Vector3(random.randf_range(-2, 2), random.randf_range(-2, 2), random.randf_range(-2, 2))
	return body

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
	if not _settle(body, points):
		return null
	if body.freeze:
		return body
	body.linear_velocity = velocity
	body.angular_velocity = Vector3(random.randf_range(-3, 3), random.randf_range(-3, 3), random.randf_range(-3, 3))
	return body

## Shatter props leave nothing lying about: each piece sinks away shortly.
func _despawn_later(piece: Node) -> void:
	get_tree().create_timer(SHATTER_DEBRIS_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(piece) and piece.has_method("sink") and not piece.sinking:
			piece.sink(SHATTER_SINK_SECONDS, piece.depth_hint()))

func _keep(record: Dictionary, piece: Node) -> void:
	if piece:
		record.pieces.append(piece)

## Seats a new piece against what lies under it. Returns false (and frees the
## piece) when its centre is buried (nothing solid below it: the ray starts
## under the ground's surface); a piece caught in the ice or a wreck is frozen
## where it is; anything else stays free to fall.
func _settle(body: RigidBody3D, points: PackedVector3Array) -> bool:
	var from := body.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * SETTLE_REACH, BaselineConfig.WORLD_LAYER, [body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		body.queue_free()
		return false
	var lowest := INF
	for point: Vector3 in points:
		lowest = minf(lowest, (body.global_transform * point).y)
	if lowest < hit.position.y - GROUND_TOLERANCE:
		body.freeze = true
	return true

## A long part snapped into up to SPLIT_MAX shorter pieces along its longest
## axis (triangles grouped by where their centres fall).
func _split(mesh: Mesh) -> Array[Mesh]:
	var box := mesh.get_aabb()
	var axis := box.get_longest_axis_index()
	var length := box.size[axis]
	var count := clampi(roundi(length / SPLIT_LENGTH), 1, SPLIT_MAX)
	var out: Array[Mesh] = []
	if count < 2:
		out.append(mesh)
		return out
	var tools: Array[SurfaceTool] = []
	var used: Array[bool] = []
	for piece: int in count:
		tools.append(null)
		used.append(false)
	var meshes: Array[ArrayMesh] = []
	for piece: int in count:
		meshes.append(ArrayMesh.new())
	for surface: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
		for piece: int in count:
			tools[piece] = SurfaceTool.new()
			tools[piece].begin(Mesh.PRIMITIVE_TRIANGLES)
			used[piece] = false
		for t: int in range(0, index.size(), 3):
			var centre := (verts[index[t]] + verts[index[t + 1]] + verts[index[t + 2]]) / 3.0
			var piece := clampi(int((centre[axis] - box.position[axis]) / length * count), 0, count - 1)
			used[piece] = true
			for k: int in 3:
				var v := index[t + k]
				tools[piece].set_normal(normals[v])
				if uvs != null:
					tools[piece].set_uv(uvs[v])
				tools[piece].add_vertex(verts[v])
		for piece: int in count:
			if used[piece]:
				tools[piece].set_material(mesh.surface_get_material(surface))
				tools[piece].commit(meshes[piece])
	for piece: ArrayMesh in meshes:
		if piece.get_surface_count() > 0:
			out.append(piece)
	return out

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
