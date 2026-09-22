class_name DriveBody
extends RigidBody3D
signal reconciled(displacement: Vector3)
## Ground probes gate authored tire forces; chassis collision supports the weight.
## No camera, Input singleton, or UI dependency. Units are meters, seconds and kg.

@export var top_speed: float = 10.0
@export var drive_acceleration: float = 6.0
@export var grip_acceleration: float = 9.0
@export var brake_acceleration: float = 9.0
@export var turn_speed: float = 2.1
@export var coast_acceleration: float = 6.0
@export var throttle_response: float = 3.0
@export var steering_response: float = 4.0
@export var yaw_response: float = 0.15
@export var yaw_acceleration_limit: float = 5.0
@export var lateral_response: float = 0.12
var geometry_scale := 1.0
var probe_depth := 0.32
const INPUT_TIMEOUT := 0.25
const PROBES: Array[Vector3] = [
	Vector3(-0.65, 0, -0.8), Vector3(0.65, 0, -0.8),
	Vector3(-0.65, 0, 0.8), Vector3(0.65, 0, 0.8),
]

var grounded: bool = false
var walker := false
var walker_rows := 2
var walker_contacts: Array[Dictionary] = []
var drive_multiplier: float = 1.0
var nitro_equipped := false
var jump_equipped := false
var nitro_active := false
var _jump_queued := 0.0
var steering_multiplier: float = 1.0
var recovery_torque: Vector3 = Vector3.ZERO
var probe_half_width: float = 0.65
var probe_half_length: float = 0.8
var contact_bodies: Array = []
var reset_pose: Variant = null
var correction: Dictionary = {}
var _throttle: float = 0.0
var _steering: float = 0.0
var _brake: bool = true
var _command_age: float = INPUT_TIMEOUT
var _drive_input: float = 0.0
var _turn_input: float = 0.0

func accept_command(command: BotCommand) -> void:
	# Copy scalars: a caller cannot mutate accepted input after validation.
	_throttle = command.throttle
	_steering = command.steering
	_brake = command.brake
	if nitro_equipped:
		nitro_active = command.nitro_held and command.throttle > 0.05 and not command.brake
	_command_age = 0.0
	if not is_zero_approx(_throttle) or not is_zero_approx(_steering) or _brake:
		sleeping = false

func queue_jump(speed: float) -> void:
	_jump_queued = maxf(_jump_queued, speed)
	sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not correction.is_empty():
		if correction.has("replay_from"):
			_constrain_replay(state.get_space_state())
		var displacement: Vector3 = state.transform.origin - correction.pose.origin
		state.transform = correction.pose
		state.linear_velocity = correction.velocity
		state.angular_velocity = correction.angular
		correction.clear()
		reconciled.emit(displacement)
	if reset_pose is Transform3D:
		state.transform = reset_pose
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		reset_pose = null
		_drive_input = 0
		_turn_input = 0
		_jump_queued = 0.0
	contact_bodies.clear()
	for index: int in range(state.get_contact_count()):
		contact_bodies.append(state.get_contact_collider_id(index))
	if not recovery_torque.is_zero_approx():
		state.apply_torque(recovery_torque)
	state.linear_velocity.y = minf(state.linear_velocity.y, 8.0)
	state.angular_velocity = state.angular_velocity.limit_length(12.0)
	_command_age += state.step
	var stale := _command_age >= INPUT_TIMEOUT
	var braking := _brake or stale
	_drive_input = move_toward(_drive_input, 0.0 if braking else _throttle, throttle_response * state.step)
	_turn_input = move_toward(_turn_input, 0.0 if braking else _steering, steering_response * state.step)
	var normal := WalkerDrive.support(state, self) if walker else _ground_normal(state)
	grounded = not normal.is_zero_approx()
	if grounded and _jump_queued > 0.0:
		state.linear_velocity.y = maxf(state.linear_velocity.y, _jump_queued)
		_jump_queued = 0.0
		grounded = false
		return
	_jump_queued = 0.0
	if not grounded:
		return
	var response := DriveModel.forces(state.transform.basis, state.linear_velocity, state.angular_velocity,
		normal, _drive_input, _turn_input, braking, state.step, model_config())
	state.apply_central_force(response.acceleration * mass)
	var yaw_acceleration: float = response.yaw_acceleration
	var inverse_yaw_inertia := normal.dot(state.inverse_inertia_tensor * normal)
	if inverse_yaw_inertia > 0.0:
		# Motor torque grows with hull inertia so enlarged machines retain the
		# power to pivot sharply; the response model still bounds angular buildup.
		var torque_scale := geometry_scale * geometry_scale
		var torque := clampf(yaw_acceleration / inverse_yaw_inertia,
			-mass * grip_acceleration * 0.65 * torque_scale * steering_multiplier,
			mass * grip_acceleration * 0.65 * torque_scale * steering_multiplier)
		state.apply_torque(normal * torque)

func _constrain_replay(space: PhysicsDirectSpaceState3D) -> void:
	# Snapshots remain authoritative: only their forward extrapolation is swept,
	# never the displacement from the client's old (possibly wrong) body pose.
	# Other bots have delayed poses on this peer, so this query uses static world
	# collision only. Jolt/server snapshots still resolve dynamic bot contacts.
	var origin: Transform3D = correction.replay_from
	var motion: Vector3 = correction.pose.origin - origin.origin
	if motion.is_zero_approx():
		return
	var collider := get_node("Collision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	# Replay already advances rotation. Sweep that resulting hull orientation:
	# a tipped chassis can lower its center while rotating upright, whereas its
	# obsolete snapshot orientation would falsely stop that descent on the floor.
	var sweep_pose := Transform3D(correction.pose.basis, origin.origin)
	query.transform = sweep_pose * collider.transform
	query.collision_mask = BaselineConfig.WORLD_LAYER
	query.exclude = [get_rid()]
	# cast_motion ignores initial overlaps. Keep extrapolation from pushing deeper
	# into contacts already present in an authoritative resting snapshot.
	var contacts := space.collide_shape(query)
	for index: int in range(0, contacts.size(), 2):
		var normal := (contacts[index + 1] - contacts[index]).normalized()
		motion -= normal * minf(motion.dot(normal), 0.0)
		correction.velocity -= normal * minf(Vector3(correction.velocity).dot(normal), 0.0)
	query.motion = motion
	var fractions := space.cast_motion(query)
	if fractions[0] < 1.0:
		# Ignore the existing floor/rest contacts when finding the newly hit normal.
		var excluded: Array[RID] = [get_rid()]
		for hit: Dictionary in space.intersect_shape(query):
			excluded.append(hit.rid)
		query.exclude = excluded
		query.transform.origin += motion * fractions[1]
		query.margin = 0.002
		var hit := space.get_rest_info(query)
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			correction.velocity -= normal * minf(Vector3(correction.velocity).dot(normal), 0.0)
		else:
			# A conservative stop is safer than carrying velocity through an
			# obstruction whose contact normal lies on a numerical boundary.
			correction.velocity = Vector3.ZERO
		motion *= fractions[0]
	correction.pose.origin = origin.origin + motion

func model_config() -> Dictionary:
	return {"speed":top_speed, "acceleration":drive_acceleration, "grip":grip_acceleration,
		"coast":coast_acceleration, "throttle_response":throttle_response,
		"steering_response":steering_response, "yaw_response":yaw_response,
		"yaw_acceleration_limit":yaw_acceleration_limit, "lateral_response":lateral_response,
		"walker":walker, "nitro":nitro_active, "nitro_equipped":nitro_equipped,
		"charged_jump":jump_equipped,
		"brake":brake_acceleration, "turn":turn_speed, "drive_scale":drive_multiplier,
		"steering_scale":steering_multiplier, "angular_damp":angular_damp,
		"gravity":Vector3(ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN))
			* float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale}

func _ground_normal(state: PhysicsDirectBodyState3D) -> Vector3:
	var normal_sum := Vector3.ZERO
	var contacts := 0
	var up := state.transform.basis.y
	for probe: Vector3 in PROBES:
		var local_probe := Vector3(signf(probe.x) * probe_half_width, 0, signf(probe.z) * probe_half_length)
		var origin := state.transform * local_probe
		var query := PhysicsRayQueryParameters3D.create(origin, origin - up * probe_depth,
			BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [get_rid()])
		var hit := state.get_space_state().intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		# Walls and an upside-down chassis are not usable wheel contact.
		if normal.dot(Vector3.UP) > 0.5 and normal.dot(up) > 0.5:
			normal_sum += normal
			contacts += 1
	return normal_sum.normalized() if contacts >= 2 else Vector3.ZERO
