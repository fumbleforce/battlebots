class_name BotOrbitCamera
extends Node3D
## Presentation only. Positive pitch looks down; yaw never inherits chassis roll.

@export_range(0.0005, 0.02, 0.0005) var sensitivity_x: float = 0.003
@export_range(0.0005, 0.02, 0.0005) var sensitivity_y: float = 0.003
# Compatibility: reading returns X; assigning sets both axes.
var sensitivity: float:
	get:
		return sensitivity_x
	set(value):
		sensitivity_x = value
		sensitivity_y = value
@export var invert_y: bool = false
@export var auto_recenter: bool = true
@export_range(0.1, 8.0, 0.1) var recenter_speed: float = 2.0
@export var arena_half_extent: float = 25.0
@export var corner_chamfer: float = 2.0
@export var camera_radius: float = 0.25
var source: BotSource
var yaw: float = 0.0
var pitch: float = deg_to_rad(24.0)
var desired_distance: float = 6.0
var actual_distance: float = 6.0
var seconds_since_orbit: float = 0.0
var driving: bool = false
var _initialized: bool = false
var _probe := SphereShape3D.new()
@onready var camera: Camera3D = $Camera

func bind_source(value: BotSource) -> void:
	source = value
	_initialized = false
	recenter()

func recenter() -> void:
	if is_instance_valid(source):
		yaw = _heading()
	pitch = deg_to_rad(24.0)
	seconds_since_orbit = 0.0

func orbit(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * sensitivity_x, -PI, PI)
	var direction := -1.0 if invert_y else 1.0
	pitch = clampf(pitch + relative.y * sensitivity_y * direction,
		deg_to_rad(-15.0), deg_to_rad(70.0))
	seconds_since_orbit = 0.0

func zoom(steps: float) -> void:
	desired_distance = clampf(desired_distance + steps * 0.5, 4.0, 9.0)

func _heading() -> float:
	var forward := -source.read_view().pose.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return yaw
	return atan2(-forward.x, -forward.z)

func _physics_process(delta: float) -> void:
	update_camera(delta)

func update_camera(delta: float) -> void:
	if not is_instance_valid(source):
		return
	var anchor := source.camera_anchor()
	if not is_instance_valid(anchor):
		return
	seconds_since_orbit += delta
	if auto_recenter and driving and seconds_since_orbit >= 1.5:
		yaw = lerp_angle(yaw, _heading(), 1.0 - exp(-recenter_speed * delta))
	# Inverted chassis markers can be below the floor. Correct only the camera pivot.
	var pivot := anchor.global_position
	pivot.y = maxf(pivot.y, camera_radius + 0.05)
	pivot = _inside_arena(pivot)
	pivot = _clear_contact_pivot(pivot)
	var camera_basis := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	var direction := camera_basis.z
	var distance_limit := _boundary_distance(pivot, direction, desired_distance)
	_probe.radius = camera_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = direction * distance_limit
	query.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	query.exclude = source.camera_exclusions()
	query.margin = 0.02
	var space := get_world_3d().direct_space_state
	# cast_motion ignores starting overlaps; do not cast out through a wall.
	if not space.intersect_shape(query, 1).is_empty():
		distance_limit = 0.0
	else:
		var fractions := space.cast_motion(query)
		distance_limit = maxf(0.0, distance_limit * fractions[0] - 0.03)
	if not _initialized or distance_limit < actual_distance:
		actual_distance = distance_limit
	else:
		actual_distance = minf(distance_limit,
			lerpf(actual_distance, distance_limit, 1.0 - exp(-10.0 * delta)))
	_initialized = true
	global_transform = Transform3D(camera_basis, pivot)
	camera.position = Vector3(0.0, 0.0, actual_distance)

func _inside_arena(point: Vector3) -> Vector3:
	var result := point
	var edge := arena_half_extent - camera_radius - 0.05
	result.x = clampf(result.x, -edge, edge)
	result.z = clampf(result.z, -edge, edge)
	var diagonal_limit := 2.0 * arena_half_extent - corner_chamfer \
		- (camera_radius + 0.05) * sqrt(2.0)
	var excess := absf(result.x) + absf(result.z) - diagonal_limit
	if excess > 0.0:
		result.x -= signf(result.x) * excess * 0.5
		result.z -= signf(result.z) * excess * 0.5
	return result

func _boundary_distance(pivot: Vector3, direction: Vector3, length: float) -> float:
	# Also keep the camera inside when the boom could pass over the 3m walls.
	var edge := arena_half_extent - camera_radius - 0.05
	var diagonal_limit := 2.0 * arena_half_extent - corner_chamfer \
		- (camera_radius + 0.05) * sqrt(2.0)
	var normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT,
		Vector3.BACK, Vector3.FORWARD, Vector3(1, 0, 1),
		Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1),
		Vector3.DOWN]
	for index: int in range(normals.size()):
		var normal := normals[index]
		var limit := edge if index < 4 else diagonal_limit
		if index == 8:
			limit = -camera_radius - 0.05
		var outward := normal.dot(direction)
		if outward > 0.00001:
			length = minf(length, maxf(0.0, (limit - normal.dot(pivot)) / outward))
	return length

func _clear_contact_pivot(pivot: Vector3) -> Vector3:
	# A lifted opponent can cover the anchor. Collapsing the boom to that anchor
	# puts the view inside our chassis. Seek a clear higher pivot, keeping walls
	# and ceilings solid throughout the vertical movement.
	_probe.radius = camera_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.exclude = source.camera_exclusions()
	query.margin = 0.02
	var space := get_world_3d().direct_space_state
	query.collision_mask = BaselineConfig.WORLD_LAYER
	if not space.intersect_shape(query, 1).is_empty():
		return pivot
	query.collision_mask = BaselineConfig.BOT_LAYER
	if space.intersect_shape(query, 1).is_empty():
		return pivot
	query.collision_mask = BaselineConfig.WORLD_LAYER
	query.motion = Vector3.UP * 4.0
	var maximum_rise := maxf(0.0, 4.0 * space.cast_motion(query)[0] - 0.03)
	query.motion = Vector3.ZERO
	query.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	for step: int in range(1, 17):
		var rise := float(step) * 0.25
		if rise > maximum_rise:
			break
		query.transform.origin = pivot + Vector3.UP * rise
		if space.intersect_shape(query, 1).is_empty():
			return query.transform.origin
	return pivot
