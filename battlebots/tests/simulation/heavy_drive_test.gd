extends Node3D
## Actual Jolt motion, with independent handling and bounded replay acceptance.
var failures: Array[String] = []
var bot: MvpBot
var sequence := 0
var registry := ContentRegistry.new()

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func drive(frames: int, throttle := 0.0, steering := 0.0, brake := false, send := true) -> void:
	for frame: int in frames:
		if send:
			var command := BotCommand.new()
			command.sequence = sequence
			sequence += 1
			command.throttle = throttle
			command.steering = steering
			command.brake = brake
			bot.body.accept_command(command)
		await get_tree().physics_frame
	await get_tree().process_frame

func reset_bot() -> void:
	bot.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 1.05, 0))
	bot.body.sleeping = false
	await drive(75, 0, 0, true)
	check(bot.body.grounded and absf(bot.body.global_position.y - 0.75) < 0.04,
		"Three-times taller wheel chassis settles and grounds on its actual floor")

func replay_collision_cases() -> void:
	# A tipped hull's low edge can touch the floor while its center descends as
	# it rights itself. Sweep the real shape; no mocked contact normals or casts.
	bot.body.freeze = true
	var wall := StaticBody3D.new()
	var wall_collider := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(1, 6, 20)
	wall_collider.shape = wall_shape
	wall.add_child(wall_collider)
	wall.position = Vector3(10, 3, 0)
	add_child(wall)
	await get_tree().physics_frame
	await get_tree().process_frame
	var space := get_world_3d().direct_space_state
	var half: Vector3 = bot.body.get_node("Collision").shape.size * 0.5
	var tilt := deg_to_rad(12.0)
	var tipped_height := half.y * cos(tilt) + half.z * sin(tilt)
	var origin := Transform3D(Basis(Vector3.RIGHT, tilt), Vector3(0, tipped_height + 0.001, 0))
	var descending := Transform3D(Basis.IDENTITY, Vector3(0, half.y + 0.2, 0))
	var velocity := Vector3(0, -2, -0.1)
	bot.body.correction = {"replay_from":origin, "pose":descending, "velocity":velocity}
	bot.body._constrain_replay(space)
	check(bot.body.correction.pose.origin.is_equal_approx(descending.origin),
		"Righting replay permits center descent when the final hull clears the floor")
	check(Vector3(bot.body.correction.velocity).is_equal_approx(velocity),
		"Righting replay retains downward velocity above the actual floor")
	var below_floor := Transform3D(Basis.IDENTITY, Vector3(0, 0.2, 0))
	bot.body.correction = {"replay_from":origin, "pose":below_floor, "velocity":velocity}
	bot.body._constrain_replay(space)
	check(absf(bot.body.correction.pose.origin.y - half.y) < 0.01,
		"Righting replay still clamps a destination below the physical floor")
	check(absf(bot.body.correction.velocity.y) < 0.01,
		"Actual floor collision removes downward replay velocity")
	var before_wall := Transform3D(Basis.IDENTITY, Vector3(5, half.y + 0.01, 0))
	var through_wall := Transform3D(Basis.IDENTITY, Vector3(12, half.y + 0.01, 0))
	bot.body.correction = {"replay_from":before_wall, "pose":through_wall, "velocity":Vector3(4, 0, 0)}
	bot.body._constrain_replay(space)
	var wall_limit := wall.position.x - wall_shape.size.x * 0.5 - half.x
	check(absf(bot.body.correction.pose.origin.x - wall_limit) < 0.01,
		"Static wall sweep stops the full enlarged hull before the wall")
	check(absf(bot.body.correction.velocity.x) < 0.01,
		"Static wall collision removes inward replay velocity")
	bot.body.correction.clear()
	wall.free()

func run() -> void:
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300, 1, 300)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -0.5
	add_child(ground)
	var draft := SawbladeConfig.starter(registry)
	draft.parts.drive = "standard_wheels"
	bot = MvpBot.create(1, 0, draft, registry)
	add_child(bot)
	bot.set_process(false)
	check(bot.combat.stats.size.is_equal_approx(Vector3(4.8, 1.5, 6.0)), "Balanced hull is exactly3x its original dimensions")
	check(bot.body.scale.is_equal_approx(Vector3.ONE), "Jolt body transform is unscaled")
	check(bot.body.get_node("Collision").shape.size.is_equal_approx(Vector3(4.8, 1.5, 6.0)), "Physical collider uses the larger hull")
	await reset_bot()
	await drive(60, 1)
	var speed_one := -bot.body.linear_velocity.z
	check(speed_one > 7.5 and speed_one < 9.6, "Strong motors deliver a decisive launch while momentum still builds during the first second")
	await drive(24, 1)
	var speed_launch := -bot.body.linear_velocity.z
	check(speed_launch > 9.7 and speed_launch < 10.2, "Powerful chassis reaches its 10m/s cruising speed within 1.4 seconds")
	await drive(156, 1)
	check(absf(bot.body.linear_velocity.length() - 10.0) < 0.2, "Standard drive retains its10m/s cruising speed")
	await drive(60)
	var coast_speed := -bot.body.linear_velocity.z
	check(coast_speed > 6.7 and coast_speed < 9.4, "Released throttle coasts without an instant stop")
	await reset_bot()
	await drive(240, 1)
	var before_brake := bot.body.global_position
	await drive(120, 1, 1, true)
	var brake_distance := bot.body.global_position.distance_to(before_brake)
	check(brake_distance > 4.5 and brake_distance < 6.5, "Strong brakes stop from 10m/s in about one hull length while retaining real stopping distance")
	check(bot.body.linear_velocity.length() < 0.15 and bot.body.angular_velocity.length() < 0.15, "Brakes override drive and steering")
	await reset_bot()
	await drive(45, 0, -1)
	var yaw := bot.body.angular_velocity.y
	check(yaw > 1.3 and yaw < 1.8, "Strong steering torque reaches a decisive pivot within three quarters of a second")
	# The authored rear pack offsets the center of mass, so the body origin
	# follows a small arc around it even with no translational propulsion.
	check(bot.body.linear_velocity.length() < 0.1, "Pivot turning adds no forward propulsion")
	await reset_bot()
	await drive(180, 1)
	await drive(30, -1)
	var reverse_speed_half := -bot.body.linear_velocity.z
	check(reverse_speed_half > 1.0 and reverse_speed_half < 8.0, "Half a second of reverse noticeably slows forward travel without instantly reversing momentum")
	await drive(150, -1)
	check(bot.body.linear_velocity.z > 9.3, "Strong reverse torque reaches backward cruising speed within three seconds")
	await drive(150, 0, 0, false, false)
	check(bot.body.linear_velocity.length() < 0.15, "Missing commands still trigger the brake failsafe")
	await reset_bot()
	await drive(70, 0.6, 0.45)
	var state := {"pose":bot.body.global_transform, "velocity":bot.body.linear_velocity,
		"angular":bot.body.angular_velocity, "grounded":true,
		"drive_input":bot.body._drive_input, "turn_input":bot.body._turn_input}
	var commands: Array = []
	var position_error := 0.0
	var rotation_error := 0.0
	for frame: int in 15:
		var command := BotCommand.new()
		command.sequence = sequence
		sequence += 1
		command.throttle = 0.6
		command.steering = -0.35
		commands.append(WireCodec.command_to_array(command))
		bot.body.accept_command(command)
		await get_tree().physics_frame
		await get_tree().process_frame
		var replay := DriveModel.replay(state, commands, bot.body.model_config())
		position_error = maxf(position_error, replay.pose.origin.distance_to(bot.body.global_position))
		rotation_error = maxf(rotation_error, rad_to_deg(replay.pose.basis.get_rotation_quaternion().angle_to(bot.body.global_basis.get_rotation_quaternion())))
	check(position_error < 0.08 and rotation_error < 2.0, "250ms heavy steering replay agrees with live Jolt within8cm/2degrees")
	# Larger moment of inertia must not remove the existing paid recovery ability.
	bot.body.reset_pose = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, 3.5, 0))
	bot.body.sleeping = false
	await drive(90, 0, 0, true)
	bot.combat.recovery_remaining = 2.0
	for frame: int in 120:
		var command := BotCommand.new()
		command.sequence = sequence
		sequence += 1
		command.brake = true
		bot.submit_command(command)
		bot.step(1.0 / 60.0, true)
		await get_tree().physics_frame
	await get_tree().process_frame
	check(bot.body.global_basis.y.dot(Vector3.UP) > 0.5, "Scaled recovery torque rights the enlarged chassis")
	await replay_collision_cases()
	print("HEAVY DRIVE measured: speed1s=%.3f speed1.4s=%.3f coast1s=%.3f brake=%.3fm pivot.75s=%.3frad/s reverse.5s=%.3fm/s replay=%.4fm/%.3fdeg" %
		[speed_one, speed_launch, coast_speed, brake_distance, yaw, reverse_speed_half, position_error, rotation_error])
	bot.free()
	ground.free()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("HEAVY DRIVE PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
