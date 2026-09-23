class_name DriveModel
extends RefCounted
## Shared tire response for live Jolt drive and bounded client input replay.
static func forces(basis: Basis, velocity: Vector3, angular: Vector3, normal: Vector3,
		throttle: float, steering: float, braking: bool, delta: float, config: Dictionary) -> Dictionary:
	var forward := (-basis.z).slide(normal).normalized()
	var right := forward.cross(normal).normalized()
	var speed := velocity.dot(forward)
	var nitro: bool = bool(config.get("nitro", false)) and not braking and throttle > 0.05
	var acceleration: float = config.brake if braking else config.acceleration * config.drive_scale * (1.7 if nitro else 1.0)
	# Releasing the motor lets momentum carry the chassis. Explicit braking and
	# the existing stale-input failsafe remain stronger than neutral coasting.
	if not braking and is_zero_approx(throttle):
		acceleration = float(config.get("coast", config.acceleration))
	var desired: float = 0 if braking else throttle * config.speed * (1.35 if nitro else 1.0)
	var longitudinal := clampf((desired - speed) / delta, -acceleration, acceleration)
	var lateral := -velocity.dot(right) / maxf(float(config.get("lateral_response", 0.12)), delta)
	var force := (forward * longitudinal + right * lateral).limit_length(config.grip * (1.5 if nitro else 1.0))
	var ratio := clampf(absf(speed) / float(config.speed), 0, 1)
	var yaw: float = 0 if braking else -steering * config.turn * lerpf(1, 0.4, ratio)
	var yaw_limit := float(config.get("yaw_acceleration_limit", 5.0))
	var yaw_acceleration := clampf((yaw - angular.dot(normal)) / float(config.get("yaw_response", 0.15)), -yaw_limit, yaw_limit)
	if config.steering_scale == 0:
		yaw_acceleration = 0
	return {"acceleration":force, "yaw_acceleration":yaw_acceleration}

static func replay(state: Dictionary, commands: Array, config: Dictionary) -> Dictionary:
	var pose: Transform3D = state.pose
	var velocity: Vector3 = state.velocity
	var angular: Vector3 = state.angular
	var throttle: float = state.get("drive_input", 0.0)
	var steering: float = state.get("turn_input", 0.0)
	var jump_charge: float = state.get("jump_charge", 0.0)
	var jump_cooldown: float = state.get("jump_cooldown", 0.0)
	var jump_was_held := jump_charge > 0.0
	var grounded: bool = state.get("grounded", false)
	var delta := 1.0 / 60
	# Contact replay is approximate: authoritative snapshots always replace outcomes.
	for data: Array in commands.slice(maxi(0, commands.size() - 15)):
		var command := WireCodec.command_from_array(data)
		if command == null:
			continue
		config["nitro"] = bool(config.get("nitro_equipped", false)) and command.nitro_held
		throttle = move_toward(throttle, 0.0 if command.brake else command.throttle, float(config.get("throttle_response", 3.0)) * delta)
		steering = move_toward(steering, 0.0 if command.brake else command.steering, float(config.get("steering_response", 4.0)) * delta)
		velocity.y = minf(velocity.y, 8.0)
		angular = angular.limit_length(12.0)
		jump_cooldown = maxf(0.0, jump_cooldown - delta)
		if command.jump_cancel:
			jump_charge = 0.0
			jump_was_held = false
		elif command.jump_held and bool(config.get("charged_jump", false)) and grounded and jump_cooldown <= 0.0:
			jump_charge = minf(1.0, jump_charge + delta / 1.2)
		elif not command.jump_held:
			if jump_was_held and jump_charge > 0.0 and grounded and jump_cooldown <= 0.0 and bool(config.get("charged_jump", false)):
				var gravity: Vector3 = config.get("gravity", Vector3(0, -9.8, 0))
				velocity.y = maxf(velocity.y, lerpf(3.5, 7.5, jump_charge) * sqrt(gravity.length() / 9.8))
				grounded = false
				jump_cooldown = 4.0
			jump_charge = 0.0
		jump_was_held = command.jump_held and not command.jump_cancel
		if grounded:
			var response := forces(pose.basis, velocity, angular, Vector3.UP, throttle, steering, command.brake, delta, config)
			velocity += response.acceleration * delta
			angular.y += float(response.yaw_acceleration) * delta
		else:
			velocity += Vector3(config.get("gravity", Vector3(0, -9.8, 0))) * delta
		# Free-flight roll/pitch continue between snapshots after a launch or flip.
		angular *= maxf(0.0, 1.0 - float(config.get("angular_damp", 0.1)) * delta)
		# Jolt linear velocity moves the center of mass. The hull origin arcs
		# around that point when the lowered ballast pitches or rolls in flight.
		var ballast: Vector3 = config.get("center_of_mass", Vector3.ZERO)
		var center := pose * ballast
		if not angular.is_zero_approx():
			pose.basis = (Basis(angular.normalized(), angular.length() * delta) * pose.basis).orthonormalized()
		pose.origin = center + velocity * delta - pose.basis * ballast
	return {"pose":pose, "velocity":velocity, "angular":angular}
