class_name DriveModel
extends RefCounted
## Corners within this height of the pivot floor plane count as touching it (m).
const PIVOT_CONTACT_SLOP := 0.02
## Shared tire response for live Jolt drive and bounded client input replay.
## Vehicle steering follows travel, including reverse coasting. Near rest,
## throttle chooses direction; neutral pivots ignore tiny contact velocities.
static func steering_direction(forward_speed: float, throttle: float) -> float:
	if absf(forward_speed) > BotPhysics.settings().steering_direction_threshold:
		return signf(forward_speed)
	return -1.0 if throttle < 0.0 else 1.0

static func forces(basis: Basis, velocity: Vector3, angular: Vector3, normal: Vector3,
		throttle: float, steering: float, braking: bool, delta: float, config: Dictionary) -> Dictionary:
	var forward := (-basis.z).slide(normal).normalized()
	var right := forward.cross(normal).normalized()
	var speed := velocity.dot(forward)
	var nitro: bool = bool(config.get("nitro", false)) and not braking and throttle > 0.05
	var acceleration: float = config.brake if braking else config.acceleration * config.drive_scale * (float(config.nitro_acceleration) if nitro else 1.0)
	# Releasing the motor lets momentum carry the chassis. Explicit braking and
	# the existing stale-input failsafe remain stronger than neutral coasting.
	if not braking and is_zero_approx(throttle):
		acceleration = float(config.get("coast", config.acceleration))
	var desired: float = 0 if braking else throttle * config.speed * (float(config.nitro_speed) if nitro else 1.0)
	var longitudinal := clampf((desired - speed) / delta, -acceleration, acceleration)
	var lateral := -velocity.dot(right) / maxf(float(config.get("lateral_response", 0.12)), delta)
	var force := (forward * longitudinal + right * lateral).limit_length(config.grip * (float(config.nitro_grip) if nitro else 1.0))
	var ratio := clampf(absf(speed) / float(config.speed), 0, 1)
	var direction := steering_direction(speed, throttle)
	var yaw: float = 0 if braking else -steering * direction * config.turn * lerpf(1, 0.4, ratio)
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
	var predicted_heat: float = state.get("heat", 0.0)
	var thermal_locked: bool = state.get("overheated", false)
	var delta := 1.0 / 60
	# A hull grounded only by an edge while it moves along its own up axis (hit
	# by a weapon or launched with its tail on the floor) pivots on that edge.
	# Model the floor as a plane at its lowest corner so the fall turns into
	# rotation, as Jolt does on the server, instead of passing through it.
	var pivot_floor := NAN
	if grounded and absf(velocity.dot(pose.basis.y)) > float(config.support_release_speed):
		pivot_floor = _lowest_corner(pose, config)
	# Contact replay is approximate: authoritative snapshots always replace outcomes.
	for data: Array in commands.slice(maxi(0, commands.size() - 15)):
		var command := WireCodec.command_from_array(data)
		if command == null:
			continue
		# Keep a received thermal lock until the next authority snapshot clears it.
		# Replay only adds perk heat; it cannot reconstruct intervening weapon hits.
		config["nitro"] = bool(config.get("nitro_equipped", false)) and command.nitro_held \
			and not thermal_locked and not command.jump_cancel and not command.brake and command.throttle > 0.05
		if config.nitro:
			predicted_heat = minf(CombatState.HEAT_LIMIT, predicted_heat + CombatState.NITRO_HEAT_RATE * delta)
			thermal_locked = predicted_heat >= CombatState.HEAT_LIMIT
			config.nitro = not thermal_locked
		throttle = move_toward(throttle, 0.0 if command.brake else command.throttle, float(config.get("throttle_response", 3.0)) * delta)
		steering = move_toward(steering, 0.0 if command.brake else command.steering, float(config.get("steering_response", 4.0)) * delta)
		velocity.y = minf(velocity.y, float(config.max_rise))
		angular = angular.limit_length(12.0)
		jump_cooldown = maxf(0.0, jump_cooldown - delta)
		if command.jump_cancel or thermal_locked:
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
				predicted_heat = minf(CombatState.HEAT_LIMIT, predicted_heat + CombatState.JUMP_HEAT)
				thermal_locked = predicted_heat >= CombatState.HEAT_LIMIT
				if thermal_locked: config.nitro = false
			jump_charge = 0.0
		jump_was_held = command.jump_held and not command.jump_cancel
		var gravity_step: Vector3 = Vector3(config.get("gravity", Vector3(0, -9.8, 0))) * delta
		if grounded:
			var response := forces(pose.basis, velocity, angular, Vector3.UP, throttle, steering, command.brake, delta, config)
			velocity += response.acceleration * delta
			angular.y += float(response.yaw_acceleration) * delta
			# Drive support holds a resting hull up. Grounded also counts one edge
			# touching the floor, so a hull launched or pivoting on that edge
			# (moving along its own up axis) still falls, as on the server.
			if absf(velocity.dot(pose.basis.y)) > float(config.support_release_speed):
				velocity += gravity_step
				if not is_nan(pivot_floor):
					var pivoted := _pivot_on_floor(pose, velocity, angular, pivot_floor, config)
					velocity = pivoted.velocity
					angular = pivoted.angular
		else:
			velocity += gravity_step
		# Free-flight roll/pitch continue between snapshots after a launch or flip.
		angular *= maxf(0.0, 1.0 - float(config.get("angular_damp", 0.1)) * delta)
		# Jolt linear velocity moves the center of mass. The hull origin arcs
		# around that point when the lowered ballast pitches or rolls in flight.
		var ballast: Vector3 = config.get("center_of_mass", Vector3.ZERO)
		var center := pose * ballast
		if not angular.is_zero_approx():
			pose.basis = (Basis(angular.normalized(), angular.length() * delta) * pose.basis).orthonormalized()
		pose.origin = center + velocity * delta - pose.basis * ballast
		if not is_nan(pivot_floor):
			# Keep the pivot edge on the floor plane (positional drift only).
			pose.origin.y += maxf(0.0, pivot_floor - _lowest_corner(pose, config))
	return {"pose":pose, "velocity":velocity, "angular":angular}

## Box hull corners in body space: config.hull_half_extents around config.hull_offset.
static func _corners(config: Dictionary) -> Array[Vector3]:
	var half: Vector3 = config.get("hull_half_extents", Vector3.ZERO)
	var offset: Vector3 = config.get("hull_offset", Vector3.ZERO)
	var corners: Array[Vector3] = []
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				corners.append(offset + Vector3(half.x * x, half.y * y, half.z * z))
	return corners

static func _lowest_corner(pose: Transform3D, config: Dictionary) -> float:
	var lowest := INF
	for corner: Vector3 in _corners(config):
		lowest = minf(lowest, (pose * corner).y)
	return lowest

## Frictionless contact impulses at hull corners touching the floor plane and
## moving into it. Box inertia about the hull center; the mass cancels.
static func _pivot_on_floor(pose: Transform3D, velocity: Vector3, angular: Vector3, floor_y: float, config: Dictionary) -> Dictionary:
	var half: Vector3 = config.get("hull_half_extents", Vector3.ZERO)
	if half.is_zero_approx():
		return {"velocity":velocity, "angular":angular}
	var size := half * 2.0
	var inverse_local := Basis.from_scale(Vector3(12.0 / (size.y * size.y + size.z * size.z),
		12.0 / (size.x * size.x + size.z * size.z), 12.0 / (size.x * size.x + size.y * size.y)))
	var inverse_inertia := pose.basis * inverse_local * pose.basis.transposed()
	var center := pose * Vector3(config.get("center_of_mass", Vector3.ZERO))
	for corner: Vector3 in _corners(config):
		var point := pose * corner
		if point.y > floor_y + PIVOT_CONTACT_SLOP:
			continue
		var arm := point - center
		var approach := (velocity + angular.cross(arm)).y
		if approach >= 0.0:
			continue
		var effective := 1.0 + Vector3.UP.dot((inverse_inertia * arm.cross(Vector3.UP)).cross(arm))
		var impulse := -approach / effective
		velocity.y += impulse
		angular += inverse_inertia * arm.cross(Vector3.UP * impulse)
	return {"velocity":velocity, "angular":angular}
