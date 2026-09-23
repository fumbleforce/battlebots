class_name WalkerDrive
extends RefCounted
## Four ray-supported legs. Forces, clearance and climb limits are authoritative.
const RIDE_HEIGHT := 0.95 * BotScale.FACTOR
const MAX_STEP := 0.45 * BotScale.FACTOR
const REACH := 1.45 * BotScale.FACTOR
const FOOT_SPREAD := 0.18 * BotScale.FACTOR
## Height above the floor under a bottomed-out hull where foot rays start.
const BOTTOMED_PROBE_CLEARANCE := 0.08 * BotScale.FACTOR
## Damped stance spring (per second squared / per second) holding the ride height.
const STANCE_STIFFNESS := 80.0
const STANCE_DAMPING := 16.0

## Only the four-legged walker crouches; the six-legged Scorpion keeps its stance.
static func crouching(body: DriveBody) -> bool:
	return body.crouched and body.walker_rows == 2

## Canonical-scale ride height.
static func ride_height(body: DriveBody) -> float:
	return body.physics.crouch_ride_height if crouching(body) else RIDE_HEIGHT

static func support(state: PhysicsDirectBodyState3D, body: DriveBody) -> Vector3:
	body.walker_contacts.clear()
	var up := state.transform.basis.y
	var scale_ratio := body.geometry_scale / BotScale.FACTOR
	if up.dot(Vector3.UP) < 0.45: return Vector3.ZERO
	var forward := -state.transform.basis.z.slide(Vector3.UP).normalized()
	var lead := forward * clampf(body._drive_input, -1.0, 1.0) * 0.45 * body.geometry_scale
	var ride := ride_height(body)
	var normal_sum := Vector3.ZERO
	var floor_height := -INF
	var start_y := state.transform.origin.y - (ride - MAX_STEP) * scale_ratio + 0.08 * body.geometry_scale
	# A hard landing can bottom the hull out, which leaves that start below the
	# floor under it. Start rays just above the floor under the hull centre until
	# the rising stance lifts the nominal start clear again. Footholds must still
	# lie below the start, so wall faces and step ceilings stay excluded.
	var clearance := BOTTOMED_PROBE_CLEARANCE * scale_ratio
	var below := PhysicsRayQueryParameters3D.create(state.transform.origin,
		Vector3(state.transform.origin.x, start_y - clearance, state.transform.origin.z),
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [body.get_rid()])
	var under := state.get_space_state().intersect_ray(below)
	if not under.is_empty() and Vector3(under.normal).dot(Vector3.UP) >= 0.65:
		start_y = maxf(start_y, Vector3(under.position).y + clearance)
	var probes: Array[Vector3] = DriveBody.PROBES
	if body.walker_rows == 3:
		probes = [Vector3(-1,0,-1), Vector3(1,0,-1), Vector3(-1,0,0), Vector3(1,0,0), Vector3(-1,0,1), Vector3(1,0,1)]
	for probe: Vector3 in probes:
		var local_support := Vector3(signf(probe.x) * (body.probe_half_width + FOOT_SPREAD * scale_ratio), 0, signf(probe.z) * body.probe_half_length)
		if body.walker_rows == 3:
			local_support = ScorpionStance.foot(int(probe.z) + 1, int(probe.x)) * body.geometry_scale
			local_support.y = 0.0
		elif body.walker_footholds != Vector2.ZERO:
			local_support = Vector3(signf(probe.x) * body.walker_footholds.x, 0, signf(probe.z) * body.walker_footholds.y)
		var hip := state.transform * local_support
		var foot := hip + lead
		var start := Vector3(foot.x, start_y, foot.z)
		var end := Vector3(foot.x, state.transform.origin.y - REACH * scale_ratio, foot.z)
		var query := PhysicsRayQueryParameters3D.create(start, end,
			BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, [body.get_rid()])
		var hit := state.get_space_state().intersect_ray(query)
		if hit.is_empty() or Vector3(hit.normal).dot(Vector3.UP) < 0.65: continue
		# A wall face cannot masquerade as a foothold. Step ceilings are measured
		# from the current supported plane; no teleporting the collision body.
		var point: Vector3 = hit.position
		if point.y > start.y - 0.01: continue
		body.walker_contacts.append({"position":point, "normal":hit.normal})
		normal_sum += Vector3(hit.normal)
		floor_height = maxf(floor_height, point.y)
	if body.walker_contacts.size() < 2: return Vector3.ZERO
	var normal := normal_sum.normalized()
	var desired_y := floor_height + ride * scale_ratio
	# Support DriveBody's heft weight, not only Jolt's arena gravity.
	var gravity := maxf(0.0, -state.total_gravity.y) * body.heft()
	var error := desired_y - state.transform.origin.y
	if crouching(body):
		# The spring settles at error * STIFFNESS / DAMPING m/s; cap the crouch descent.
		error = maxf(error, -body.physics.crouch_lower_speed * scale_ratio * STANCE_DAMPING / STANCE_STIFFNESS)
	var lift := clampf(gravity + error * STANCE_STIFFNESS - state.linear_velocity.y * STANCE_DAMPING, 0, gravity + body.physics.lift_headroom_acceleration)
	state.apply_central_force(Vector3.UP * lift * body.mass)
	# Damped stance correction is bounded and requires live footholds. In air or
	# upside down the walker obeys normal rigid-body gravity/recovery mechanics.
	var tilt_velocity := state.angular_velocity - normal * state.angular_velocity.dot(normal)
	var torque := (up.cross(normal) * 55.0 - tilt_velocity * 10.0) * body.mass
	state.apply_torque(torque.limit_length(body.mass * 35.0) * body.geometry_scale * body.geometry_scale)
	return normal
