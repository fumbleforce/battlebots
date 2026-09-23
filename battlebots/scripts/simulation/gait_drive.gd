class_name GaitDrive
extends RefCounted
## Authoritative movement of the four nimble bots (#61). Every gait hovers its
## hull on NimbleBots support rays like WalkerDrive; each then shapes the shared
## DriveModel differently:
## - stride: the target speed surges once per step, the hull bobs and sways;
## - roll: leans into turns and pitches with throttle, barely pivots at rest;
## - hop: bounds on its spring and steers in the air;
## - skate: alternating kick strokes, long glides, carving lean and crouch.
## Server and predicting client run this on their Jolt bodies; gait phase is
## local body state, so snapshots still correct the pose.

static func _forward(state: PhysicsDirectBodyState3D, normal: Vector3) -> Vector3:
	return (-state.transform.basis.z).slide(normal).normalized()

## Hull centre height above the floor for the current gait phase.
static func ride_height(body: DriveBody) -> float:
	var spec := body.gait_spec
	var ride := float(spec.ride_height)
	if body.gait == "stride":
		# Lowest at each footfall (legs spread), highest mid-stride.
		ride -= float(spec.stride.bob) * 0.5 * (1.0 + cos(TAU * body.gait_phase))
	elif body.gait == "skate":
		ride -= float(spec.skate.crouch) * body.gait_crouch
	return ride

## Vertical velocity (x) and acceleration (y) of the stride bob, fed forward so
## the spring tracks each step instead of smoothing it away.
static func _ride_feedforward(body: DriveBody) -> Vector2:
	if body.gait != "stride": return Vector2.ZERO
	var bob := float(body.gait_spec.stride.bob)
	var angle := TAU * body.gait_phase
	return Vector2(PI * bob * body.gait_rate * sin(angle), 2.0 * PI * PI * bob * body.gait_rate * body.gait_rate * cos(angle))

static func support(state: PhysicsDirectBodyState3D, body: DriveBody) -> Vector3:
	body.walker_contacts.clear()
	var spec := body.gait_spec
	var tuning := NimbleBots.support()
	var up := state.transform.basis.y
	if up.dot(Vector3.UP) < 0.45: return Vector3.ZERO
	# A launched pogo leaves its spring: no support (or rebound lift) until it falls.
	if body.gait_launched:
		if state.linear_velocity.y > 0.0: return Vector3.ZERO
		body.gait_launched = false
	var origin := state.transform.origin
	# Step ceiling measured from the supported plane; a wall face is no foothold.
	var start_y := origin.y - float(spec.ride_height) + float(spec.max_step)
	# Airborne (a pogo bound, a jump) the rays start high: only land within a
	# step of the last floor, so a bound cannot carry a bot onto an arena wall.
	var ceiling := start_y if is_nan(body.gait_floor) else minf(start_y, body.gait_floor + float(spec.max_step))
	var end_y := origin.y - float(spec.reach)
	var normal_sum := Vector3.ZERO
	var floor_height := -INF
	for foothold: Array in spec.footholds:
		var point := state.transform * Vector3(float(foothold[0]), 0, float(foothold[1]))
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, start_y, point.z),
			Vector3(point.x, end_y, point.z), BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [body.get_rid()])
		var hit := state.get_space_state().intersect_ray(query)
		if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.65: continue
		var contact: Vector3 = hit.position
		if contact.y > ceiling - 0.01: continue
		body.walker_contacts.append({"position":contact, "normal":hit.normal})
		normal_sum += Vector3(hit.normal)
		floor_height = maxf(floor_height, contact.y)
	if body.walker_contacts.size() < 2: return Vector3.ZERO
	var normal := normal_sum.normalized()
	body.gait_floor = floor_height
	var desired_y := floor_height + ride_height(body)
	# Carry DriveBody's heft weight, not only Jolt's arena gravity.
	var gravity := maxf(0.0, -state.total_gravity.y) * body.heft()
	var headroom := float(tuning.lift_headroom)
	if body.gait == "hop": headroom = float(spec.hop.landing_headroom)
	elif body.gait == "stride": headroom = float(spec.stride.lift_headroom)
	var feed := _ride_feedforward(body)
	var lift := clampf(gravity + feed.y + (desired_y - origin.y) * float(tuning.spring)
		- (state.linear_velocity.y - feed.x) * float(tuning.damping), 0.0, gravity + headroom)
	state.apply_central_force(Vector3.UP * lift * body.mass)
	_update_lean(state, body, normal)
	_hold_upright(state, body, lean_up(body, state, normal), normal, 1.0)
	return normal

## Bounded, damped torque turning the hull's up axis toward target.
static func _hold_upright(state: PhysicsDirectBodyState3D, body: DriveBody, target: Vector3, axis: Vector3, strength: float) -> void:
	var tuning := NimbleBots.support()
	var up := state.transform.basis.y
	var tilt_velocity := state.angular_velocity - axis * state.angular_velocity.dot(axis)
	var torque := (up.cross(target) * float(tuning.upright_gain) - tilt_velocity * float(tuning.upright_damping)) * body.mass * strength
	# A leaned hull tilts the correction axis; its vertical part would yaw the
	# bot (a braking monowheel spun up to 10 rad/s). Only the drive steers.
	torque -= axis * torque.dot(axis)
	state.apply_torque(torque.limit_length(body.mass * float(tuning.upright_torque_limit) * strength)
		* body.geometry_scale * body.geometry_scale)

## The floor normal tilted by the gait's current roll (about forward) and pitch
## (about right). Positive roll leans right; negative pitch dips the nose.
static func lean_up(body: DriveBody, state: PhysicsDirectBodyState3D, normal: Vector3) -> Vector3:
	var forward := _forward(state, normal)
	if forward.is_zero_approx(): return normal
	var right := forward.cross(normal).normalized()
	return (Basis(forward, body.gait_lean.x) * Basis(right, body.gait_lean.y) * normal).normalized()

static func _update_lean(state: PhysicsDirectBodyState3D, body: DriveBody, normal: Vector3) -> void:
	var spec := body.gait_spec
	var forward := _forward(state, normal)
	var speed := state.linear_velocity.dot(forward)
	var yaw_rate := state.angular_velocity.dot(normal)
	# Centripetal acceleration toward the right of travel.
	var lateral := -yaw_rate * speed
	var acceleration := (speed - body.gait_previous_speed) / state.step
	body.gait_previous_speed = speed
	var target := Vector2.ZERO
	match body.gait:
		"stride":
			# Weight shifts over each planted foot in turn.
			target.x = deg_to_rad(float(spec.stride.sway_degrees)) * sin(PI * body.gait_phase)
		"roll":
			var roll: Dictionary = spec.roll
			target.x = clampf(atan(lateral / 9.8) * float(roll.lean_scale), -deg_to_rad(roll.max_lean_degrees), deg_to_rad(roll.max_lean_degrees))
			target.y = -clampf(acceleration * deg_to_rad(roll.pitch_per_acceleration), -deg_to_rad(roll.max_pitch_degrees), deg_to_rad(roll.max_pitch_degrees))
		"skate":
			var skate: Dictionary = spec.skate
			target.x = clampf(atan(lateral / 9.8) * float(skate.lean_scale), -deg_to_rad(skate.max_lean_degrees), deg_to_rad(skate.max_lean_degrees))
			var top := body.top_speed * body.physics.top_speed_multiplier
			body.gait_crouch = move_toward(body.gait_crouch, clampf(absf(speed) / maxf(top, 0.1), 0.0, 1.0), state.step * 2.0)
	var response := 1.0 - exp(-float(NimbleBots.support().lean_response) * state.step)
	body.gait_lean = body.gait_lean.lerp(target, response)

## Shape the shared tyre model before DriveModel.forces reads config.
static func tune(config: Dictionary, body: DriveBody, state: PhysicsDirectBodyState3D, normal: Vector3, braking: bool) -> void:
	var spec := body.gait_spec
	var forward := _forward(state, normal)
	var speed := state.linear_velocity.dot(forward)
	var yaw_rate := state.angular_velocity.dot(normal)
	match body.gait:
		"stride":
			var stride: Dictionary = spec.stride
			# Two steps per cycle; walking and pivoting both advance the feet.
			var steps := absf(speed) / float(stride.step_length) + absf(yaw_rate) * float(stride.pivot_steps_per_radian)
			body.gait_rate = steps
			body.gait_phase = fposmod(body.gait_phase + steps * state.step, 2.0)
			config.speed = float(config.speed) * (1.0 + float(stride.speed_surge) * cos(TAU * body.gait_phase))
		"roll":
			var roll: Dictionary = spec.roll
			# A monowheel steers by leaning: it needs speed to turn.
			config.turn = float(config.turn) * lerpf(float(roll.pivot_fraction), 1.0,
				clampf(absf(speed) / float(roll.full_turn_speed), 0.0, 1.0))
		"skate":
			var skate: Dictionary = spec.skate
			if not braking and body._drive_input > 0.05:
				body.gait_phase = fposmod(body.gait_phase + state.step / float(skate.stroke_seconds), 2.0)
				var pushing := fmod(body.gait_phase, 1.0) * float(skate.stroke_seconds) < float(skate.push_seconds)
				config.drive_scale = float(config.drive_scale) * float(skate.push_drive if pushing else skate.glide_drive)

## Pogo launch after its stance on the spring. Returns true when it left the ground.
static func hop(state: PhysicsDirectBodyState3D, body: DriveBody, braking: bool) -> bool:
	if body.gait != "hop": return false
	if not body.grounded:
		body.gait_timer = 0.0
		return false
	body.gait_timer += state.step
	var tuning: Dictionary = body.gait_spec.hop
	var driving := absf(body._drive_input) > 0.05 or absf(body._turn_input) > 0.05
	# Wrecked drive pods cannot load the spring.
	if braking or not driving or body.drive_multiplier <= 0.0: return false
	if body.gait_timer < float(tuning.stance_seconds) or state.linear_velocity.y < -0.25: return false
	var planar := state.linear_velocity.slide(Vector3.UP)
	var launch := planar.lerp(_desired_planar(state, body), float(tuning.carry))
	var rise := minf(float(tuning.hop_speed) * sqrt(body.gravity_scale) * body.launch_scale(), body.max_rise())
	state.linear_velocity = launch + Vector3.UP * rise
	body.gait_timer = 0.0
	body.gait_launched = true
	return true

## Driven horizontal velocity: throttle times top speed along the hull heading.
static func _desired_planar(state: PhysicsDirectBodyState3D, body: DriveBody) -> Vector3:
	var forward := (-state.transform.basis.z).slide(Vector3.UP).normalized()
	var top := body.top_speed * body.physics.top_speed_multiplier
	if body.nitro_active: top *= body.physics.nitro_top_speed_multiplier
	return forward * body._drive_input * top * minf(1.0, body.drive_multiplier)

## Air control while the pogo is between bounds: yaw, heading trim, level hull.
static func airborne(state: PhysicsDirectBodyState3D, body: DriveBody, braking: bool) -> void:
	if body.gait != "hop": return
	# Tumbling after a hit: ordinary rigid-body mechanics and recovery apply.
	if state.transform.basis.y.dot(Vector3.UP) < 0.3: return
	var tuning: Dictionary = body.gait_spec.hop
	var yaw_target := 0.0 if braking else -body._turn_input * float(tuning.air_turn_rate)
	var inverse_yaw_inertia := Vector3.UP.dot(state.inverse_inertia_tensor * Vector3.UP)
	if inverse_yaw_inertia > 0.0:
		var yaw_acceleration := (yaw_target - state.angular_velocity.y) / body.yaw_response
		var limit := body.mass * body.grip_acceleration * body.physics.grip_multiplier \
			* body.physics.yaw_torque_grip_fraction * body.geometry_scale * body.geometry_scale * body.steering_multiplier
		state.apply_torque(Vector3.UP * clampf(yaw_acceleration / inverse_yaw_inertia, -limit, limit))
	if not braking and absf(body._drive_input) > 0.05:
		var planar := state.linear_velocity.slide(Vector3.UP)
		state.linear_velocity += (_desired_planar(state, body) - planar).limit_length(float(tuning.air_acceleration) * state.step)
	_hold_upright(state, body, Vector3.UP, Vector3.UP, 0.5)
