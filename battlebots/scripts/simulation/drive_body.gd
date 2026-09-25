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
## Heft, motor authority and rise cap come from data/bot_physics.json.
var physics := BotPhysics.settings()
var geometry_scale := 1.0
var probe_depth := 0.32
const INPUT_TIMEOUT := 0.25
## Replay sweep passes: the first may slide along a surface, the second stops.
const SWEEP_PASSES := 2
## A replay sweep slides along a surface it enters at less than this cosine
## (about 12 degrees); steeper hits stop the sweep.
const GRAZING_DOT := 0.2
## Corner ground probes (also the four-legged walker's foot layout).
const PROBES: Array[Vector3] = [
	Vector3(-0.65, 0, -0.8), Vector3(0.65, 0, -0.8),
	Vector3(-0.65, 0, 0.8), Vector3(0.65, 0, 0.8),
]
## Mid-length track probes keep drive contact when the belly rides over a
## ridge with both ends in the air, so a tank does not beach.
const TRACK_MID_PROBES: Array[Vector3] = [Vector3(-0.65, 0, 0.0), Vector3(0.65, 0, 0.0)]

var grounded: bool = false
var walker := false
var walker_rows := 2
## Four-legged walker footholds (lateral, fore/aft) from the hull centre in game
## metres; zero derives them from the probe box plus WalkerDrive.FOOT_SPREAD.
var walker_footholds := Vector2.ZERO
var walker_contacts: Array[Dictionary] = []
## Held crouch intent; only the four-legged walker lowers its stance.
var crouched := false
## Nimble bot gait (#61): a NimbleBots gait name with its tuning record, or ""
## for every other drive. Phase, stance timer, lean and crouch are local
## GaitDrive state; authoritative snapshots correct the resulting pose.
var gait := ""
var gait_spec: Dictionary = {}
var gait_phase := 0.0
## Stride cadence in steps per second (GaitDrive feeds the bob forward).
var gait_rate := 0.0
var gait_timer := 0.0
## True from a pogo launch until it starts falling (GaitDrive skips support).
var gait_launched := false
var gait_lean := Vector2.ZERO
var gait_crouch := 0.0
var gait_previous_speed := 0.0
## Height of the last floor the gait stood on (NAN until the first support).
var gait_floor := NAN
## Weight multiplier where arena heft does not apply (low-gravity arenas).
var low_gravity_heft := 1.0
var drive_multiplier: float = 1.0
var nitro_equipped := false
var jump_equipped := false
var nitro_active := false
## Scales the nitro acceleration and top-speed boost. Only Practice Duel
## tuning (#84) changes it; 1 everywhere else, so prediction is unaffected.
var nitro_boost_scale := 1.0
var _jump_queued := 0.0
var steering_multiplier: float = 1.0
## Hit stagger lowers the top speed and loosens tyre grip so knockback carries the hull.
var speed_multiplier: float = 1.0
var grip_multiplier: float = 1.0
var recovery_torque: Vector3 = Vector3.ZERO
var probe_half_width: float = 0.65
var probe_half_length: float = 0.8
var contact_bodies: Array = []
## This tick's contacts with static arena geometry as [global point, normal].
## CombatWorld reads them to tell when a rammed hull is pinned against a wall.
var static_contacts: Array = []
var reset_pose: Variant = null
var correction: Dictionary = {}
var _throttle: float = 0.0
var _steering: float = 0.0
var _brake: bool = true
var _command_age: float = INPUT_TIMEOUT
var _drive_input: float = 0.0
var _turn_input: float = 0.0

## Presentation interpolation: physics advances at 60 Hz, so a model copied from
## the body each rendered frame holds still and then jumps a whole tick (0.4 m
## at nitro speed). Keep the last two tick poses and blend between them.
## Jumps larger than a tick of plausible motion (resets, respawns, large
## reconciliation snaps) are not blended.
const INTERPOLATION_SNAP_DISTANCE := 3.0
var _previous_tick_pose := Transform3D.IDENTITY
var _current_tick_pose := Transform3D.IDENTITY
var _tick_poses_valid := false

func _physics_process(_delta: float) -> void:
	# Runs before this tick's physics step: global_transform is the pose the
	# previous step produced.
	var pose := global_transform
	var teleported := pose.origin.distance_to(_current_tick_pose.origin) > INTERPOLATION_SNAP_DISTANCE
	_previous_tick_pose = pose if not _tick_poses_valid or teleported else _current_tick_pose
	_current_tick_pose = pose
	_tick_poses_valid = true

## Pose blended between the last two physics ticks for the current render frame.
func interpolated_transform() -> Transform3D:
	if not _tick_poses_valid:
		return global_transform
	var fraction := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	return _previous_tick_pose.interpolate_with(_current_tick_pose, fraction)

func accept_command(command: BotCommand) -> void:
	# Copy scalars: a caller cannot mutate accepted input after validation.
	_throttle = command.throttle
	_steering = command.steering
	_brake = command.brake
	crouched = command.crouch_held
	if nitro_equipped:
		nitro_active = command.nitro_held and command.throttle > 0.05 and not command.brake
	_command_age = 0.0
	if not is_zero_approx(_throttle) or not is_zero_approx(_steering) or _brake:
		sleeping = false

## Gravity multiplier over this arena's gravity (1 on the low-gravity Moon,
## unless the body carries its own low_gravity_heft, like the Hellwheel).
func heft() -> float:
	var arena := physics.heft_for(gravity_scale)
	return maxf(arena, low_gravity_heft) if arena <= 1.0 else arena

## Launch/jump speed multiplier that keeps apex height under heft gravity.
func launch_scale() -> float:
	return physics.launch_scale_for(gravity_scale)

## Jolt material friction against the arena. On its drive the tracks carry the
## weight and the drive model owns grip, so the hull must not drag (it would
## stall climbs under heft weight). Stranded on its roof or side, the hull
## grinds against the floor instead of skating.
func hull_friction() -> float:
	return physics.track_hull_friction if grounded else physics.stranded_hull_friction

func _update_hull_friction() -> void:
	if physics_material_override != null and not is_equal_approx(physics_material_override.friction, hull_friction()):
		physics_material_override.friction = hull_friction()

## Grounded tracks hold against the downhill pull (up to the grip limit), so a
## heavy machine parks on hills and its full motor authority drives the climb.
func _hold_slope(state: PhysicsDirectBodyState3D, normal: Vector3) -> void:
	var weight := state.total_gravity * heft()
	var downhill := weight - normal * weight.dot(normal)
	var hold := (-downhill * physics.slope_hold_fraction).limit_length(grip_acceleration * physics.grip_multiplier)
	state.apply_central_force(hold * mass)

func max_rise() -> float:
	return physics.rise_speed_cap_at_1g * launch_scale()

func queue_jump(speed: float) -> void:
	# Callers scale by arena gravity; heft adds its own factor so height holds.
	_jump_queued = maxf(_jump_queued, speed * launch_scale())
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
		# Re-base the blend onto the corrected path; the owner smooths the
		# snap itself (visual_error), so interpolation must not smooth it too.
		_previous_tick_pose.origin -= displacement
		_current_tick_pose.origin -= displacement
		reconciled.emit(displacement)
	if reset_pose is Transform3D:
		state.transform = reset_pose
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		reset_pose = null
		_drive_input = 0
		_turn_input = 0
		_jump_queued = 0.0
		gait_phase = 0.0
		gait_rate = 0.0
		gait_timer = 0.0
		gait_launched = false
		gait_lean = Vector2.ZERO
		gait_crouch = 0.0
		gait_previous_speed = 0.0
		gait_floor = NAN
	contact_bodies.clear()
	static_contacts.clear()
	for index: int in range(state.get_contact_count()):
		contact_bodies.append(state.get_contact_collider_id(index))
		if state.get_contact_collider_object(index) is StaticBody3D:
			static_contacts.append([state.get_contact_local_position(index), state.get_contact_local_normal(index)])
	_grip_bot_contacts(state)
	# Extra weight on top of Jolt's arena gravity (total_gravity already
	# includes gravity_scale). Walker lift supports the same heavier weight.
	var extra_weight_fraction := heft() - 1.0
	state.apply_central_force(state.total_gravity * extra_weight_fraction * mass)
	if not recovery_torque.is_zero_approx():
		# Self-righting lifts the hull against the heavier weight.
		state.apply_torque(recovery_torque * heft())
	state.linear_velocity.y = minf(state.linear_velocity.y, max_rise())
	state.angular_velocity = state.angular_velocity.limit_length(12.0)
	_command_age += state.step
	var stale := _command_age >= INPUT_TIMEOUT
	var braking := _brake or stale
	_drive_input = move_toward(_drive_input, 0.0 if braking else _throttle, throttle_response * state.step)
	_turn_input = move_toward(_turn_input, 0.0 if braking else _steering, steering_response * state.step)
	var normal: Vector3
	if walker: normal = WalkerDrive.support(state, self)
	elif gait != "": normal = GaitDrive.support(state, self)
	else: normal = _ground_normal(state)
	grounded = not normal.is_zero_approx()
	_update_hull_friction()
	if grounded and _jump_queued > 0.0:
		state.linear_velocity.y = maxf(state.linear_velocity.y, _jump_queued)
		_jump_queued = 0.0
		grounded = false
		return
	_jump_queued = 0.0
	if GaitDrive.hop(state, self, braking):
		grounded = false
		return
	if not grounded:
		GaitDrive.airborne(state, self, braking)
		return
	if GaitDrive.stance(state, self, normal): return
	_hold_slope(state, normal)
	var config := model_config()
	if gait != "": GaitDrive.tune(config, self, state, normal, braking)
	var response := DriveModel.forces(state.transform.basis, GaitDrive.grip_velocity(self, state), state.angular_velocity,
		normal, _drive_input, _turn_input, braking, state.step, config)
	state.apply_central_force(response.acceleration * mass)
	var yaw_acceleration: float = response.yaw_acceleration
	var inverse_yaw_inertia := normal.dot(state.inverse_inertia_tensor * normal)
	if inverse_yaw_inertia > 0.0:
		# Motor torque grows with hull inertia so enlarged machines retain the
		# power to pivot sharply; the response model still bounds angular buildup.
		var torque_scale := geometry_scale * geometry_scale
		var torque_limit := mass * grip_acceleration * physics.grip_multiplier \
			* physics.yaw_torque_grip_fraction * torque_scale * steering_multiplier
		var torque := clampf(yaw_acceleration / inverse_yaw_inertia, -torque_limit, torque_limit)
		state.apply_torque(normal * torque)

## Hull materials are slick so wheels, not the chassis, drive against the
## floor; that also let clashing hulls glance off each other like ice. Apply
## Coulomb friction against the other bot's contact velocity so clashes bite.
## Each body of a pair applies its half, so together they can at most cancel
## (never reverse) the relative sliding velocity.
func _grip_bot_contacts(state: PhysicsDirectBodyState3D) -> void:
	const PAIR_SHARE := 0.5
	for index: int in range(state.get_contact_count()):
		if not state.get_contact_collider_object(index) is DriveBody:
			continue
		var normal := state.get_contact_local_normal(index)
		var relative := state.get_contact_local_velocity_at_position(index) \
			- state.get_contact_collider_velocity_at_position(index)
		var sliding := relative - normal * relative.dot(normal)
		var sliding_speed := sliding.length()
		if is_zero_approx(sliding_speed):
			continue
		var normal_impulse := state.get_contact_impulse(index).dot(normal)
		var grip := minf(physics.bot_contact_friction * absf(normal_impulse), mass * sliding_speed * PAIR_SHARE)
		var offset := state.get_contact_local_position(index) - state.transform.origin
		state.apply_impulse(-sliding / sliding_speed * grip, offset)

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
		_block_velocity(normal)
	var start := query.transform
	# Collide and slide: for a hull on its drive grazing a surface, a hit removes
	# only the motion into it. A hull knocked back with a slight tilt meets the
	# floor it rests on at the start of the sweep; it keeps sliding along it
	# instead of being held at the snapshot pose. A second pass stops at walls.
	for attempt: int in range(SWEEP_PASSES):
		query.transform = start
		query.exclude = [get_rid()]
		query.margin = 0.0
		query.motion = motion
		var fractions := space.cast_motion(query)
		if fractions[0] >= 1.0:
			break
		var normals := _sweep_hit_normals(space, query, motion * fractions[1])
		if normals.is_empty():
			# No normal at all: a conservative stop is safer than carrying
			# velocity through an obstruction on a numerical boundary.
			correction.velocity = Vector3.ZERO
			motion *= fractions[0]
			break
		var slide := motion
		var grazing := true
		for normal: Vector3 in normals:
			_block_velocity(normal)
			grazing = grazing and -motion.normalized().dot(normal) < GRAZING_DOT
			slide -= normal * minf(slide.dot(normal), 0.0)
		# Only a hull on its drive grazing a surface slides; landings and
		# tumbling or righting hulls stop at the hit as before.
		if not grounded or not grazing or attempt == SWEEP_PASSES - 1 or slide.is_equal_approx(motion):
			# Still blocked after sliding (or nothing to remove): stop at the hit.
			motion *= fractions[0]
			break
		motion = slide
	correction.pose.origin = origin.origin + motion

## Contact normals where a replay sweep first touches static world geometry.
func _sweep_hit_normals(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, travel: Vector3) -> Array[Vector3]:
	var normals: Array[Vector3] = []
	# Ignore the existing floor/rest contacts when finding the newly hit normal.
	var excluded: Array[RID] = [get_rid()]
	for hit: Dictionary in space.intersect_shape(query):
		excluded.append(hit.rid)
	query.exclude = excluded
	query.transform.origin += travel
	query.margin = 0.002
	var hit := space.get_rest_info(query)
	if not hit.is_empty():
		normals.append(hit.normal)
		return normals
	# Rest info can miss a tumbling hull's corner touching the floor; find
	# the contact normals at the hit pose instead.
	query.exclude = [get_rid()]
	var touching := space.collide_shape(query)
	for index: int in range(0, touching.size(), 2):
		normals.append((touching[index + 1] - touching[index]).normalized())
	return normals

## Contacts cancel replayed velocity into them so extrapolation never tunnels,
## except the floor under an airborne hull: a tumbling hull's low corner meets
## the floor while its center keeps falling as it pivots, so the fall must
## continue and Jolt resolves that contact (and rotation) on its next step, as
## on the server. Once the drive probes find ground, landings stop as before.
func _block_velocity(normal: Vector3) -> void:
	const FLOOR_NORMAL_Y := 0.5
	if normal.y > FLOOR_NORMAL_Y and not grounded:
		return
	correction.velocity -= normal * minf(Vector3(correction.velocity).dot(normal), 0.0)

func model_config() -> Dictionary:
	return {"speed":top_speed * physics.top_speed_multiplier * speed_multiplier, "acceleration":drive_acceleration * physics.acceleration_multiplier,
		"grip":grip_acceleration * physics.grip_multiplier * grip_multiplier,
		"coast":coast_acceleration * physics.rolling_resistance_multiplier, "throttle_response":throttle_response,
		"steering_response":steering_response, "yaw_response":yaw_response,
		"yaw_acceleration_limit":yaw_acceleration_limit * physics.yaw_acceleration_multiplier, "lateral_response":lateral_response,
		"walker":walker, "nitro":nitro_active, "nitro_equipped":nitro_equipped,
		"charged_jump":jump_equipped, "max_rise":max_rise(), "support_release_speed":physics.support_release_speed,
		"hull_half_extents":_hull_box().size * 0.5 if _hull_box() != null else Vector3.ZERO,
		"hull_offset":(get_node("Collision") as CollisionShape3D).position if _hull_box() != null else Vector3.ZERO,
		"nitro_acceleration":physics.nitro_acceleration_multiplier * nitro_boost_scale,
		"nitro_speed":physics.nitro_top_speed_multiplier * nitro_boost_scale,
		"nitro_grip":physics.nitro_grip_multiplier,
		"brake":brake_acceleration * physics.brake_multiplier, "turn":turn_speed, "drive_scale":drive_multiplier,
		"steering_scale":steering_multiplier, "angular_damp":angular_damp,
		"center_of_mass":center_of_mass if center_of_mass_mode == CENTER_OF_MASS_MODE_CUSTOM else Vector3.ZERO,
		"gravity":Vector3(ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN))
			* float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * gravity_scale * heft()}

## The main hull collider when it is a box (replay pivots on its corners).
func _hull_box() -> BoxShape3D:
	var collision := get_node_or_null("Collision") as CollisionShape3D
	return collision.shape as BoxShape3D if collision != null else null

func _ground_normal(state: PhysicsDirectBodyState3D) -> Vector3:
	var normal_sum := Vector3.ZERO
	var contacts := 0
	var up := state.transform.basis.y
	for probe: Vector3 in PROBES + TRACK_MID_PROBES:
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
	# Tracks run the full hull length: when the hull bridges a transition (rear
	# edge on the ground, nose on a ramp, belly in the air) the probes hang just
	# clear, but the underside still touches walkable world geometry. Count
	# those real contacts as track contact so the tank keeps driving.
	for index: int in range(state.get_contact_count()):
		if state.get_contact_collider_object(index) is DriveBody:
			continue
		var normal := state.get_contact_local_normal(index)
		var below := (state.get_contact_local_position(index) - state.transform.origin).dot(up) < 0.0
		if below and normal.dot(Vector3.UP) > 0.5 and normal.dot(up) > 0.5:
			normal_sum += normal
			contacts += 1
	return normal_sum.normalized() if contacts >= 2 else Vector3.ZERO
