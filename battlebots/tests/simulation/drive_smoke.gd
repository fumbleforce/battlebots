extends SceneTree
## Exercise the actual Jolt body without arena, camera, UI, or Input adapters.

var failures: int = 0
var world: Node3D
var source: BotSource
var body: DriveBody
var sequence: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var obstacle := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	obstacle.add_child(collision)
	obstacle.position = position
	world.add_child(obstacle)
	return obstacle

func _spawn(position := Vector3.ZERO, flipped := false) -> void:
	if is_instance_valid(source):
		source.queue_free()
		await physics_frame
		await process_frame
	source = load("res://scenes/bots/baseline_bot.tscn").instantiate() as BotSource
	source.position = position
	body = source.get_node("Body") as DriveBody
	if flipped:
		body.rotation.z = PI
	world.add_child(source)
	await process_frame

func _step(frames: int, throttle := 0.0, steering := 0.0, brake := false, send := true) -> void:
	for frame: int in range(frames):
		if send:
			var command := BotCommand.new()
			command.sequence = sequence
			sequence += 1
			command.throttle = throttle
			command.steering = steering
			command.brake = brake
			source.submit_command(command)
		await physics_frame
	await process_frame

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	_box(Vector3(200, 1, 200), Vector3(0, -0.5, 0))
	await _spawn()
	await _step(90)
	_check(body.grounded and absf(body.position.y - 0.25) < 0.05, "Bot must settle with ground contact")
	body.sleeping = true
	await _step(120, 1.0)
	var speed_at_two_seconds := -body.linear_velocity.z
	print("Forward speed at 2 seconds: ", speed_at_two_seconds)
	# Cruise speed includes the BotPhysics top-speed multiplier.
	var cruise: float = body.model_config().speed
	_check(speed_at_two_seconds > cruise * 0.9 and speed_at_two_seconds <= cruise + 0.1, "Acceleration target: near cruise speed in 2 seconds")
	_check(body.position.z < -8.0, "Positive throttle must move along -Z")
	await _step(120, 1.0)
	_check(absf(body.linear_velocity.length() - cruise) < 0.15, "Drive must settle at speed limit")
	var brake_start := body.position
	await _step(90, 1.0, 1.0, true)
	print("Braking distance: ", body.position.distance_to(brake_start))
	_check(body.linear_velocity.length() < 0.15 and body.angular_velocity.length() < 0.15, "Brake overrides throttle and steering")
	_check(body.position.distance_to(brake_start) < 7.0, "Full-speed braking must stop within 7 meters")

	await _spawn()
	await _step(60)
	await _step(60, -1.0)
	_check(body.position.z > 1.0 and body.linear_velocity.z > 3.0, "Reverse must drive +Z")
	await _step(30, -1.0, 1.0)
	_check(body.angular_velocity.y > 0.5, "Right steering must produce positive yaw while reversing")
	for direction: float in [-1.0, 1.0]:
		for turn: float in [-1.0, 1.0]:
			await _spawn()
			await _step(60)
			await _step(60, direction)
			await _step(30, direction, turn)
			_check(body.angular_velocity.y * turn * direction < -0.5,
				"Live Jolt yaw follows vehicle steering for forward/reverse and left/right")
	await _spawn()
	await _step(60)
	await _step(45, 0.0, -1.0)
	_check(body.angular_velocity.y > 1.0, "Left input must turn in place with positive yaw")
	_check(Vector2(body.position.x, body.position.z).length() < 0.2, "Turning in place must not propel chassis")

	await _spawn()
	await _step(60)
	await _step(60, 1.0)
	await _step(120, 0.0, 0.0, false, false)
	_check(body.linear_velocity.length() < 0.15, "Missing input must brake after 250 ms")
	var invalid := BotCommand.new()
	invalid.throttle = NAN
	source.submit_command(invalid)
	source.submit_command(null)
	await _step(20, 0.0, 0.0, false, false)
	_check(body.linear_velocity.is_finite(), "Invalid input must not corrupt physics")
	var accepted := BotCommand.new()
	source.submit_command(accepted)
	accepted.throttle = 1.0
	await _step(10, 0.0, 0.0, false, false)
	_check(body.linear_velocity.length() < 0.15, "Mutating a submitted command must not change intent")

	await _spawn(Vector3(0, 20, 0))
	await _step(30, 1.0, 1.0)
	_check(not body.grounded and absf(body.linear_velocity.z) < 0.01
		and absf(body.angular_velocity.y) < 0.01, "No drive or steering while airborne")
	await _spawn(Vector3.ZERO, true)
	await _step(60)
	await _step(60, 1.0, 1.0)
	_check(not body.grounded and Vector2(body.position.x, body.position.z).length() < 0.1,
		"Upside-down chassis must not drive")

	await _spawn()
	var wall := _box(Vector3(12, 3, 0.5), Vector3(0, 1.5, -8))
	await _step(60)
	await _step(240, 1.0)
	_check(body.position.z > -7.2 and body.position.z < -6.5, "Bot must reach wall without tunneling")
	_check(body.position.is_finite() and body.linear_velocity.length() < 0.5
		and absf(body.position.y - 0.25) < 0.1, "Sustained wall contact must remain stable")
	var wall_position := body.position.z
	await _step(90, -1.0)
	print("Wall retreat after 1.5 seconds: ", body.position.z - wall_position)
	_check(body.position.z - wall_position > 2.0 and body.linear_velocity.z > 3.0,
		"Bot must reverse away from a wall after throttle changes direction")
	wall.queue_free()
	var view := source.read_view()
	_check(view.pose.is_equal_approx(body.global_transform), "BotView must expose physical pose")
	_check(source.camera_anchor().get_parent() == body and source.camera_exclusions().has(body.get_rid()),
		"Camera anchor and exclusions must remain compatible")
	world.queue_free()
	await process_frame
	print("DRIVE PASS" if failures == 0 else "DRIVE FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
