class_name DriveModel
extends RefCounted
## Shared tire response for live Jolt drive and bounded client input replay.
static func forces(basis: Basis, velocity: Vector3, angular: Vector3, normal: Vector3,
		throttle: float, steering: float, braking: bool, delta: float, config: Dictionary) -> Dictionary:
	var forward := (-basis.z).slide(normal).normalized()
	var right := forward.cross(normal).normalized()
	var speed := velocity.dot(forward)
	var acceleration: float = config.brake if braking else config.acceleration * config.drive_scale
	var desired: float = 0 if braking else throttle * config.speed
	var longitudinal := clampf((desired - speed) / delta, -acceleration, acceleration)
	var lateral := -velocity.dot(right) / maxf(0.12, delta)
	var force := (forward * longitudinal + right * lateral).limit_length(config.grip)
	var ratio := clampf(absf(speed) / float(config.speed), 0, 1)
	var yaw: float = 0 if braking else -steering * config.turn * lerpf(1, 0.4, ratio)
	var yaw_acceleration := clampf((yaw - angular.dot(normal)) / 0.15, -5, 5)
	if config.steering_scale == 0:
		yaw_acceleration = 0
	return {"acceleration":force, "yaw_acceleration":yaw_acceleration}

static func replay(state: Dictionary, commands: Array, config: Dictionary) -> Dictionary:
	var pose: Transform3D = state.pose
	var velocity: Vector3 = state.velocity
	var angular: Vector3 = state.angular
	var throttle: float = state.get("drive_input", 0.0)
	var steering: float = state.get("turn_input", 0.0)
	var delta := 1.0 / 60
	# Contact replay is approximate: authoritative snapshots always replace outcomes.
	for data: Array in commands.slice(maxi(0, commands.size() - 15)):
		var command := WireCodec.command_from_array(data)
		if command == null:
			continue
		throttle = move_toward(throttle, 0.0 if command.brake else command.throttle, 3 * delta)
		steering = move_toward(steering, 0.0 if command.brake else command.steering, 4 * delta)
		velocity.y = minf(velocity.y, 8.0)
		angular = angular.limit_length(12.0)
		if state.get("grounded", false):
			var response := forces(pose.basis, velocity, angular, Vector3.UP, throttle, steering, command.brake, delta, config)
			velocity += response.acceleration * delta
			angular.y += float(response.yaw_acceleration) * delta
		else:
			velocity += Vector3(config.get("gravity", Vector3(0, -9.8, 0))) * delta
		# Free-flight roll/pitch continue between snapshots after a launch or flip.
		angular *= maxf(0.0, 1.0 - float(config.get("angular_damp", 0.1)) * delta)
		if not angular.is_zero_approx():
			pose.basis = (Basis(angular.normalized(), angular.length() * delta) * pose.basis).orthonormalized()
		pose.origin += velocity * delta
	return {"pose":pose, "velocity":velocity, "angular":angular}
