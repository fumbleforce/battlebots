class_name WalkerLegs
extends Node3D
## Planted feet, alternating diagonal steps and two-bone IK; no damage authority.
## Footholds are predicted: a step lands where the hull will carry the hip
## half a stance after touchdown, so feet reach ahead instead of trailing. With
## fewer than MIN_SUPPORT footholds in reach the legs hang under the hull.
const UPPER := 0.67
const LOWER := 0.73
const STEP_TIME := 0.24
## Swing apex (source metres) and the planted-foot drift that starts a step.
const STEP_HEIGHT := 0.25
const STEP_DISTANCE := 0.22
## Time a foot stays planted between swings; it lands half of this ahead.
const STANCE_TIME := 0.24
## Hull speed (source metres per second) and turn (rad) the prediction may lead.
const MAX_LEAD_SPEED := 4.0
const MAX_LEAD_TURN := 0.6
## 1/s smoothing of the observed hull velocity and yaw rate.
const MOTION_RESPONSE := 10.0
## Planted footholds needed to walk; fewer and the walker is airborne.
const MIN_SUPPORT := 2
## Airborne feet hang this far (source metres) below the standing stance.
const HANG_DROP := 0.3
const HANG_RESPONSE := 8.0
## Touchdown after a fall: feet reach the ground in this time without a lift arc.
const LANDING_TIME := 0.1
var legs: Array[Dictionary] = []
var exclusions: Array[RID] = []
var terrain := true
## Measured hull height (source metres) above the ground under the feet;
## drops when the walker crouches.
var stance_height := WalkerDrive.RIDE_HEIGHT / BotScale.FACTOR
var airborne := false
var _last_origin := Vector3.ZERO
var _last_forward := Vector3.FORWARD
var _velocity := Vector3.ZERO
var _yaw_rate := 0.0
var _initialized := false
var _pair := 0
var _paint: Material
var _dark: StandardMaterial3D
var _metal: StandardMaterial3D
var _rubber: StandardMaterial3D
var _geometry_scale := 1.0

func assemble(size: Vector3, paint: Material, config: Dictionary) -> void:
	_geometry_scale = BotScale.from_size(size)
	size /= _geometry_scale
	scale *= _geometry_scale
	var panel_material := StandardMaterial3D.new()
	panel_material.albedo_color = paint.get_shader_parameter("paint") if paint is ShaderMaterial else Color("c98b30")
	panel_material.metallic = 0.55
	panel_material.roughness = 0.56
	_paint = panel_material
	_dark = StandardMaterial3D.new()
	_dark.albedo_color = _color(config.paint_secondary)
	_dark.metallic = 0.75
	_dark.roughness = 0.42
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = _color(config.paint_metal)
	_metal.metallic = 0.9
	_metal.roughness = 0.25
	_rubber = StandardMaterial3D.new()
	_rubber.albedo_color = _color(config.paint_rubber)
	_rubber.roughness = 0.95
	for index: int in 4:
		var side := -1.0 if index % 2 == 0 else 1.0
		var front := -1.0 if index < 2 else 1.0
		var hip := Vector3(side * size.x * 0.34, 0.02, front * size.z * 0.30)
		var neutral := Vector3(side * (size.x * 0.40 + WalkerDrive.FOOT_SPREAD / BotScale.FACTOR),
			-WalkerDrive.RIDE_HEIGHT / BotScale.FACTOR, front * size.z * 0.40)
		var upper := Node3D.new()
		var lower := Node3D.new()
		var foot := Node3D.new()
		add_child(upper)
		add_child(lower)
		add_child(foot)
		_build_segment(upper, UPPER, false)
		_build_segment(lower, LOWER, true)
		_box(foot, Vector3(0.38, 0.10, 0.46), Vector3(0, 0.08, 0), _rubber)
		_box(foot, Vector3(0.28, 0.14, 0.30), Vector3(0, 0.18, 0), _paint)
		for toe: int in 3:
			_box(foot, Vector3(0.105, 0.08, 0.16), Vector3((toe - 1) * 0.13, 0.055, -0.21), _paint)
			_joint(foot, Vector3((toe - 1) * 0.13, 0.105, -0.18), 0.026, 0.04, _metal)
		var hip_joint := Node3D.new()
		add_child(hip_joint)
		hip_joint.position = hip
		_joint(hip_joint, Vector3.ZERO, 0.16, 0.30, _dark)
		_joint(hip_joint, Vector3(side * 0.17, 0, 0), 0.11, 0.035, _paint)
		legs.append({"hip":hip,"neutral":neutral,"side":side,"pair":0 if index in [0, 3] else 1,
			"upper":upper,"lower":lower,"foot_mesh":foot,"hip_joint":hip_joint,"foot":Vector3.ZERO,
			"start":Vector3.ZERO,"target":Vector3.ZERO,"normal":Vector3.UP,"time":1.0,
			"collider":null,"local_contact":Vector3.ZERO,"local_normal":Vector3.UP})
	reset_feet()

## Presentation references only; leg ownership is stable while feet cross terrain.
func component_meshes() -> Dictionary:
	var result := {"weapon": [], "drive_left": [], "drive_right": []}
	for leg: Dictionary in legs:
		var group: Array = result.drive_left if leg.side < 0 else result.drive_right
		for key: String in ["upper", "lower", "foot_mesh", "hip_joint"]:
			for mesh: MeshInstance3D in leg[key].find_children("*", "MeshInstance3D", true, false):
				group.append(mesh)
	return result

func _color(rgba: Array) -> Color:
	return Color(rgba[0], rgba[1], rgba[2], 1).linear_to_srgb()

func _build_segment(node: Node3D, length: float, armored: bool) -> void:
	_box(node, Vector3(0.17, length, 0.19), Vector3(0, length * 0.5, 0), _dark)
	_box(node, Vector3(0.29 if armored else 0.23, length * 0.66, 0.28), Vector3(0, length * 0.48, -0.02), _paint)
	_box(node, Vector3(0.05, length * 0.49, 0.018), Vector3(0, length * 0.48, -0.17), _dark)
	for end: float in [0.0, length]:
		_joint(node, Vector3(0, end, 0), 0.12, 0.33, _dark)
		for side: float in [-1.0, 1.0]:
			_joint(node, Vector3(side * 0.18, end, 0), 0.075, 0.025, _metal)
			_joint(node, Vector3(side * 0.20, end, 0), 0.035, 0.03, _dark)
	for side: float in [-1.0, 1.0]:
		var barrel := CylinderMesh.new()
		barrel.top_radius = 0.043
		barrel.bottom_radius = 0.043
		barrel.height = length * 0.46
		barrel.radial_segments = 12
		_mesh(node, barrel, Vector3(side * 0.18, length * 0.32, 0.09), _dark)
		var rod := CylinderMesh.new()
		rod.top_radius = 0.024
		rod.bottom_radius = 0.024
		rod.height = length * 0.56
		rod.radial_segments = 10
		_mesh(node, rod, Vector3(side * 0.18, length * 0.65, 0.09), _metal)

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	parent.add_child(instance)
	return instance

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	if material == _paint:
		_mesh(parent, _armor_mesh(size), at, material)
		return
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(parent, mesh, at, material)

func _armor_mesh(size: Vector3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x := size.x * 0.5
	var z := size.z * 0.5
	var bevel := minf(x, z) * 0.25
	var ring: Array[Vector3] = [Vector3(-x + bevel, 0, -z), Vector3(x - bevel, 0, -z),
		Vector3(x, 0, -z + bevel), Vector3(x, 0, z - bevel), Vector3(x - bevel, 0, z),
		Vector3(-x + bevel, 0, z), Vector3(-x, 0, z - bevel), Vector3(-x, 0, -z + bevel)]
	for index: int in 8:
		var a := ring[index] + Vector3.DOWN * size.y * 0.5
		var b := ring[(index + 1) % 8] + Vector3.DOWN * size.y * 0.5
		var c := ring[(index + 1) % 8] * 0.92 + Vector3.UP * size.y * 0.5
		var d := ring[index] * 0.92 + Vector3.UP * size.y * 0.5
		for point: Vector3 in [a, b, c, a, c, d, Vector3.DOWN * size.y * 0.5, b, a, Vector3.UP * size.y * 0.5, d, c]:
			surface.add_vertex(point)
	surface.generate_normals()
	return surface.commit()

func _joint(parent: Node3D, at: Vector3, radius: float, width: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = width
	mesh.radial_segments = 12
	_mesh(parent, mesh, at, material).rotation.z = PI * 0.5

static func solve_knee(hip: Vector3, ankle: Vector3, outward: Vector3) -> Vector3:
	var direction := (ankle - hip).normalized()
	var distance := clampf(hip.distance_to(ankle), absf(UPPER - LOWER) + 0.001, UPPER + LOWER - 0.001)
	var along := (UPPER * UPPER - LOWER * LOWER + distance * distance) / (2.0 * distance)
	var bend := outward.slide(direction).normalized()
	if bend.is_zero_approx(): bend = Vector3.FORWARD.slide(direction).normalized()
	return hip + direction * along + bend * sqrt(maxf(0, UPPER * UPPER - along * along))

## Ground under the leg's neutral foothold, after the hull moves by ahead and
## turns by turn (rad about world up). Misses fall back without a collider.
func _contact(leg: Dictionary, ahead := Vector3.ZERO, turn := 0.0) -> Dictionary:
	var target := global_position + (global_basis * Vector3(leg.neutral)).rotated(Vector3.UP, turn) + ahead
	if not terrain or global_basis.y.normalized().dot(Vector3.UP) < 0.45:
		return {"position":target, "normal":global_basis.y.normalized(), "collider":null}
	var start := Vector3(target.x, global_position.y + 0.20 * _geometry_scale, target.z)
	var end := Vector3(target.x, global_position.y - WalkerDrive.REACH * _geometry_scale / BotScale.FACTOR, target.z)
	var query := PhysicsRayQueryParameters3D.create(start, end,
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclusions)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.65:
		return {"position":target, "normal":Vector3.UP, "collider":null}
	return hit

## Foothold for a step that touches down after `swing` seconds: the hip's
## position half a stance later, so the planted foot straddles the hip.
func _predicted_contact(leg: Dictionary, swing: float) -> Dictionary:
	var lead := swing + STANCE_TIME * 0.5
	return _contact(leg, _velocity * lead, clampf(_yaw_rate * lead, -MAX_LEAD_TURN, MAX_LEAD_TURN))

func reset_feet() -> void:
	if not is_inside_tree(): return
	for leg: Dictionary in legs:
		var hit := _contact(leg)
		leg.foot = hit.position
		leg.target = hit.position
		leg.normal = hit.normal
		leg.time = 1.0
		leg.duration = STEP_TIME
		leg.arc = STEP_HEIGHT
		_set_contact(leg, hit)
	_last_origin = global_position
	_last_forward = _planar_forward()
	_velocity = Vector3.ZERO
	_yaw_rate = 0.0
	airborne = false
	_initialized = true
	_pose()

func _set_contact(leg: Dictionary, hit: Dictionary) -> void:
	var collider: Variant = hit.get("collider")
	leg.collider = weakref(collider) if collider is Node3D else null
	if collider is Node3D:
		leg.local_contact = collider.to_local(hit.position)
		leg.local_normal = collider.global_basis.inverse() * Vector3(hit.normal)

func _planar_forward() -> Vector3:
	var forward := (-global_basis.z).slide(Vector3.UP)
	return forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD

func _process(delta: float) -> void:
	if legs.is_empty(): return
	if not terrain:
		reset_feet()
		return
	if global_basis.y.normalized().dot(Vector3.UP) < 0.45:
		reset_feet()
		return
	if not _initialized or global_position.distance_to(_last_origin) > 2.0 * _geometry_scale:
		reset_feet()
		return
	var step := maxf(delta, 0.001)
	var response := 1.0 - exp(-MOTION_RESPONSE * delta)
	var velocity := ((global_position - _last_origin) / step).slide(Vector3.UP)
	_velocity = _velocity.lerp(velocity.limit_length(MAX_LEAD_SPEED * _geometry_scale), response)
	var forward := _planar_forward()
	_yaw_rate = lerpf(_yaw_rate, _last_forward.signed_angle_to(forward, Vector3.UP) / step, response)
	_last_origin = global_position
	_last_forward = forward
	if _measure_support(response) < MIN_SUPPORT:
		_hang(delta)
	else:
		if airborne: _land()
		_walk(delta)
	_pose()

## Counts legs with ground in reach under their neutral footholds and tracks
## the hull height above that ground (crouching lowers it).
func _measure_support(response: float) -> int:
	var supported := 0
	var height := 0.0
	for leg: Dictionary in legs:
		var hit := _contact(leg)
		if hit.get("collider") == null: continue
		supported += 1
		height -= to_local(hit.position).y
	if supported > 0:
		stance_height = lerpf(stance_height, height / supported, response)
	return supported

## Nothing to stand on: the feet leave the ground and hang, extended, under the
## hull in its own frame instead of stepping onto air.
func _hang(delta: float) -> void:
	if not airborne:
		airborne = true
		for leg: Dictionary in legs:
			leg.air = to_local(leg.foot)
			leg.time = 1.0
			leg.collider = null
	var response := 1.0 - exp(-HANG_RESPONSE * delta)
	for leg: Dictionary in legs:
		var hang := Vector3(leg.neutral)
		hang.y -= HANG_DROP
		leg.air = Vector3(leg.air).lerp(hang, response)
		leg.foot = to_global(leg.air)
		leg.normal = global_basis.y.normalized()

## Every hanging foot reaches for the ground it is about to land on.
func _land() -> void:
	airborne = false
	for leg: Dictionary in legs:
		var hit := _predicted_contact(leg, LANDING_TIME)
		leg.start = leg.foot
		leg.target = hit.position
		leg.normal = hit.normal
		leg.time = 0.0
		leg.duration = LANDING_TIME
		leg.arc = 0.0
		_set_contact(leg, hit)

func _walk(delta: float) -> void:
	var stepping := false
	for leg: Dictionary in legs:
		if leg.time < 1.0:
			leg.time = minf(1.0, leg.time + delta / leg.duration)
			if leg.arc > 0.0:
				# Keep steering the swing toward where the hull will be at touchdown.
				var hit := _predicted_contact(leg, (1.0 - leg.time) * leg.duration)
				if hit.get("collider") != null:
					leg.target = hit.position
					leg.normal = hit.normal
					_set_contact(leg, hit)
			leg.foot = Vector3(leg.start).lerp(leg.target, smoothstep(0, 1, leg.time)) \
				+ Vector3.UP * sin(leg.time * PI) * leg.arc * _geometry_scale
			stepping = true
		elif leg.collider != null:
			var collider: Node3D = leg.collider.get_ref()
			if is_instance_valid(collider):
				leg.foot = collider.to_global(leg.local_contact)
				leg.normal = (collider.global_basis * Vector3(leg.local_normal)).normalized()
	if stepping: return
	var needs_step := false
	var targets := {}
	for index: int in legs.size():
		var leg := legs[index]
		if leg.pair != _pair: continue
		var hit := _predicted_contact(leg, STEP_TIME)
		targets[index] = hit
		if Vector3(leg.foot).distance_to(hit.position) > STEP_DISTANCE * _geometry_scale: needs_step = true
	if needs_step:
		for index: int in targets:
			var leg := legs[index]
			var hit: Dictionary = targets[index]
			leg.start = leg.foot
			leg.target = hit.position
			leg.normal = hit.normal
			leg.time = 0.0
			leg.duration = STEP_TIME
			leg.arc = STEP_HEIGHT
			_set_contact(leg, hit)
	# Alternate diagonals; an idle pair also lets the other check while turning.
	_pair = 1 - _pair

func _pose() -> void:
	for leg: Dictionary in legs:
		var hip: Vector3 = leg.hip
		var foot := to_local(leg.foot)
		var ankle := foot + global_basis.inverse() * Vector3(leg.normal) * (0.18 * _geometry_scale)
		var offset := (ankle - hip).limit_length(UPPER + LOWER - 0.01)
		ankle = hip + offset
		var knee := solve_knee(hip, ankle, Vector3(leg.side, 0, 0.12 * signf(hip.z)))
		_segment(leg.upper, hip, knee)
		_segment(leg.lower, knee, ankle)
		var normal: Vector3 = leg.normal
		var forward := -global_basis.z.slide(normal).normalized()
		if forward.is_zero_approx(): forward = Vector3.FORWARD
		var basis := Basis(forward.cross(normal).normalized(), normal, -forward)
		leg.foot_mesh.global_transform = Transform3D(basis.scaled(global_basis.get_scale()),
			to_global(ankle) - normal * (0.18 * _geometry_scale))

func _segment(node: Node3D, start: Vector3, end: Vector3) -> void:
	var direction := (end - start).normalized()
	var right := direction.cross(Vector3.FORWARD).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	node.transform = Transform3D(Basis(right, direction, right.cross(direction)), start)
