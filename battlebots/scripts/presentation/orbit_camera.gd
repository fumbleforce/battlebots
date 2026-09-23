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
@export var arena_half_extent: float = ArenaBounds.FOUNDRY_HALF
@export var corner_chamfer: float = 2.0
@export var camera_radius: float = 0.25
## Nitro FOV kick, rumble and speed streaks plus impact shake. Presentation only.
@export var speed_effects: bool = true
@export_range(0.0, 30.0, 0.5) var nitro_fov_boost: float = 14.0
var source: BotSource
var yaw: float = 0.0
var pitch: float = deg_to_rad(24.0)
var desired_distance: float = 6.0
var actual_distance: float = 6.0
var seconds_since_orbit: float = 0.0
var driving: bool = false
var _initialized: bool = false
var _bot_scale := 1.0
var _boom_scale := 1.0
var _probe := SphereShape3D.new()
var nitro_blend := 0.0
var shake_trauma := 0.0
var base_fov := 70.0
var _shake_time := 0.0
var _speed_lines: ColorRect
## Smoothed ground speed of the followed bot; drives the tank-like engine rumble.
var ground_speed := 0.0
var _last_anchor := Vector3.INF
@onready var camera: Camera3D = $Camera

func _ready() -> void:
	add_to_group(&"bot_orbit_cameras")
	base_fov = camera.fov
	if DisplayServer.get_name() == "headless": return
	# Below every HUD layer, above the 3D view.
	var layer := CanvasLayer.new()
	layer.name = "SpeedLines"
	layer.layer = -8
	add_child(layer)
	_speed_lines = ColorRect.new()
	_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speed_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/speed_lines.gdshader")
	_speed_lines.material = material
	_speed_lines.hide()
	layer.add_child(_speed_lines)

func bind_source(value: BotSource) -> void:
	source = value
	if is_instance_valid(source): _sync_anchor_scale(source.camera_anchor())
	_initialized = false
	_last_anchor = Vector3.INF
	ground_speed = 0.0
	recenter()

func _sync_anchor_scale(anchor: Node3D) -> void:
	if not is_instance_valid(anchor): return
	if anchor.has_meta(&"arena_half_extent"):
		arena_half_extent = float(anchor.get_meta(&"arena_half_extent"))
		corner_chamfer = arena_half_extent * (2.0 - sqrt(2.0))
	var value: Variant = anchor.get_meta(&"bot_scale", 1.0)
	if not (value is int or value is float) or not is_finite(float(value)) or float(value) <= 0.0: return
	var next_scale := float(value)
	if is_equal_approx(next_scale, _bot_scale): return
	# Grow the boom less than the hull so bigger machines remain imposing while
	# preserving arena awareness and the player's relative zoom when rebound.
	var next_boom_scale := (1.0 + next_scale) * 0.5
	desired_distance *= next_boom_scale / _boom_scale
	actual_distance *= next_boom_scale / _boom_scale
	_bot_scale = next_scale
	_boom_scale = next_boom_scale
	_initialized = false

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
	desired_distance = clampf(desired_distance + steps * 0.5 * _boom_scale, 4.0 * _boom_scale, 9.0 * _boom_scale)

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
		_apply_speed_feel(delta, false)
		return
	var anchor := source.camera_anchor()
	if not is_instance_valid(anchor):
		_apply_speed_feel(delta, false)
		return
	_sync_anchor_scale(anchor)
	_track_speed(anchor.global_position, delta)
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
	# Nitro stretches the boom slightly so the chassis appears to surge ahead.
	var distance_limit := _boundary_distance(pivot, direction, desired_distance * (1.0 + 0.1 * nitro_blend))
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
	var view := source.read_view()
	_apply_speed_feel(delta, view != null and view.nitro_active and not view.eliminated)

## Shake from a nearby confirmed hammer blow, attenuated by distance to the rig.
func add_impact_shake(origin: Vector3, strength: float) -> void:
	if not speed_effects or not origin.is_finite() or not is_finite(strength) or strength <= 0.0: return
	var reach := 14.0 * _bot_scale
	var falloff := clampf(1.0 - global_position.distance_to(origin) / reach, 0.0, 1.0)
	shake_trauma = minf(1.0, shake_trauma + strength * 0.5 * falloff)

func _track_speed(at: Vector3, delta: float) -> void:
	if not at.is_finite() or not is_finite(delta) or delta <= 0.0: return
	var measured := 0.0
	if _last_anchor.is_finite():
		var travel := at - _last_anchor
		travel.y = 0.0
		measured = travel.length() / delta
		# Respawns and teleports are not driving.
		if measured > 40.0 * _bot_scale: measured = 0.0
	_last_anchor = at
	ground_speed = lerpf(ground_speed, measured, 1.0 - exp(-delta * 6.0))
	if ground_speed < 0.01: ground_speed = 0.0

func _apply_speed_feel(delta: float, boosting: bool) -> void:
	if not is_finite(delta) or delta < 0.0: delta = 0.0
	var target := 1.0 if boosting and speed_effects else 0.0
	# Punch in quickly on ignition; ease out more gently on release.
	nitro_blend = lerpf(nitro_blend, target, 1.0 - exp(-delta * (5.0 if target > nitro_blend else 2.6)))
	if nitro_blend < 0.001: nitro_blend = 0.0
	shake_trauma = maxf(0.0, shake_trauma - delta * 1.6)
	if not speed_effects: shake_trauma = 0.0
	_shake_time += delta
	var eased := nitro_blend * nitro_blend * (3.0 - 2.0 * nitro_blend)
	camera.fov = base_fov + nitro_fov_boost * eased
	var impact := shake_trauma * shake_trauma
	var rumble := 0.005 * eased + 0.06 * impact
	var t := _shake_time
	var jitter := Vector2(sin(t * 53.0) * 0.6 + sin(t * 91.0 + 1.3) * 0.4,
		sin(t * 61.0 + 0.7) * 0.6 + sin(t * 83.0 + 2.1) * 0.4) * rumble * _boom_scale
	# Heavy-machine feel: a low engine thrum plus a slower track sway, both
	# scaled by how fast the chassis is moving. Mostly vertical, like a hull.
	var drive := clampf(ground_speed / (5.0 * _bot_scale), 0.0, 1.0) if speed_effects else 0.0
	if drive > 0.0:
		var thrum := (sin(t * 38.0) * 0.55 + sin(t * 23.0 + 0.9) * 0.45) * 0.006
		var sway := sin(t * 7.3 + 0.4) * 0.004
		jitter += Vector2(sway * 0.5, thrum + sway) * drive * _boom_scale
	camera.position = Vector3(jitter.x, jitter.y, actual_distance)
	camera.rotation = Vector3(0.0, 0.0, sin(t * 47.0 + 0.4) * 0.01 * impact)
	if _speed_lines != null:
		_speed_lines.visible = eased > 0.01
		if _speed_lines.visible:
			(_speed_lines.material as ShaderMaterial).set_shader_parameter(&"intensity", eased)

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
		pivot = _clear_ground_pivot(pivot)
		query.transform.origin = pivot
		if not space.intersect_shape(query, 1).is_empty(): return pivot
	query.collision_mask = BaselineConfig.BOT_LAYER
	if space.intersect_shape(query, 1).is_empty():
		return pivot
	query.collision_mask = BaselineConfig.WORLD_LAYER
	query.motion = Vector3.UP * 4.0 * _bot_scale
	var maximum_rise := maxf(0.0, 4.0 * _bot_scale * space.cast_motion(query)[0] - 0.03)
	query.motion = Vector3.ZERO
	query.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	for step: int in range(1, 17):
		var rise := float(step) * 0.25 * _bot_scale
		if rise > maximum_rise:
			break
		query.transform.origin = pivot + Vector3.UP * rise
		if space.intersect_shape(query, 1).is_empty():
			return query.transform.origin
	return pivot

func _clear_ground_pivot(pivot: Vector3) -> Vector3:
	# A rolled anchor may be below raised terrain while the chassis is above it.
	# Read supporting ground from chassis height; never escape through an overhead surface.
	var view := source.read_view()
	if view == null or not view.pose.origin.is_finite(): return pivot
	var start := Vector3(pivot.x, maxf(pivot.y, view.pose.origin.y), pivot.z)
	var reach := maxf(2.0 * _bot_scale, start.y - pivot.y + camera_radius + 0.05)
	var ray := PhysicsRayQueryParameters3D.create(start, start + Vector3.DOWN * reach, BaselineConfig.WORLD_LAYER)
	ray.hit_from_inside = true
	var space := get_world_3d().direct_space_state
	var floor_hit := space.intersect_ray(ray)
	if floor_hit.is_empty() or floor_hit.normal.y <= 0.25: return pivot
	var corrected := pivot
	corrected.y = floor_hit.position.y + (camera_radius + 0.05) / floor_hit.normal.y
	if corrected.y <= pivot.y: return pivot
	var top := corrected.y + camera_radius + 0.05
	if top > start.y:
		ray.to = Vector3(start.x, top, start.z)
		if not space.intersect_ray(ray).is_empty(): return pivot
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _probe
	query.transform = Transform3D(Basis.IDENTITY, corrected)
	query.collision_mask = BaselineConfig.WORLD_LAYER
	query.margin = 0.02
	return corrected if space.intersect_shape(query, 1).is_empty() else pivot
