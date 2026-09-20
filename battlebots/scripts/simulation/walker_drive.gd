class_name WalkerDrive
extends RefCounted
## Four ray-supported legs. Forces, clearance and climb limits are authoritative.
const RIDE_HEIGHT := 0.95 * BotScale.FACTOR
const MAX_STEP := 0.45 * BotScale.FACTOR
const REACH := 1.45 * BotScale.FACTOR
const FOOT_SPREAD := 0.18 * BotScale.FACTOR

static func support(state: PhysicsDirectBodyState3D, body: DriveBody) -> Vector3:
	body.walker_contacts.clear()
	var up := state.transform.basis.y
	var scale_ratio := body.geometry_scale / BotScale.FACTOR
	if up.dot(Vector3.UP) < 0.45: return Vector3.ZERO
	var forward := -state.transform.basis.z.slide(Vector3.UP).normalized()
	var lead := forward * clampf(body._drive_input, -1.0, 1.0) * 0.45 * body.geometry_scale
	var normal_sum := Vector3.ZERO
	var floor_height := -INF
	var probes: Array[Vector3] = DriveBody.PROBES
	if body.walker_rows == 3:
		probes = [Vector3(-1,0,-1), Vector3(1,0,-1), Vector3(-1,0,0), Vector3(1,0,0), Vector3(-1,0,1), Vector3(1,0,1)]
	for probe: Vector3 in probes:
		var local_support := Vector3(signf(probe.x) * (body.probe_half_width + FOOT_SPREAD * scale_ratio), 0, signf(probe.z) * body.probe_half_length)
		if body.walker_rows == 3:
			local_support = ScorpionStance.foot(int(probe.z) + 1, int(probe.x)) * body.geometry_scale
			local_support.y = 0.0
		var hip := state.transform * local_support
		var foot := hip + lead
		var start := Vector3(foot.x, state.transform.origin.y - (RIDE_HEIGHT - MAX_STEP) * scale_ratio + 0.08 * body.geometry_scale, foot.z)
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
	var desired_y := floor_height + RIDE_HEIGHT * scale_ratio
	var gravity := maxf(0.0, -state.total_gravity.y)
	var lift := clampf(gravity + (desired_y - state.transform.origin.y) * 80.0 - state.linear_velocity.y * 16.0, 0, 45)
	state.apply_central_force(Vector3.UP * lift * body.mass)
	# Damped stance correction is bounded and requires live footholds. In air or
	# upside down the walker obeys normal rigid-body gravity/recovery mechanics.
	var tilt_velocity := state.angular_velocity - normal * state.angular_velocity.dot(normal)
	var torque := (up.cross(normal) * 55.0 - tilt_velocity * 10.0) * body.mass
	state.apply_torque(torque.limit_length(body.mass * 35.0) * body.geometry_scale * body.geometry_scale)
	return normal
