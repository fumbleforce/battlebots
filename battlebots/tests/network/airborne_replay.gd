extends Node3D
## Independent F6 scene: compare bounded input replay with a real Jolt body.
## This measures free flight after an impulse, not contact/remote-machine acceptance.
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var registry := ContentRegistry.new()
	var bot := MvpBot.create(1, 0, registry.starter(), registry)
	add_child(bot)
	var body := bot.body
	body.global_position = Vector3(0, 10, 0)
	body.linear_velocity = Vector3(3, 6, -4)
	body.angular_velocity = Vector3(4, 2, 3)
	# Let Jolt accept the initial transform/velocities before recording a snapshot.
	await get_tree().physics_frame
	await get_tree().process_frame
	var state := {"pose":body.global_transform, "velocity":body.linear_velocity,
		"angular":body.angular_velocity, "grounded":false}
	var commands: Array = []
	var position_error := 0.0
	var angle_error := 0.0
	var velocity_error := 0.0
	for frame: int in range(15):
		var command := BotCommand.new()
		command.sequence = frame
		command.throttle = 1 # No tire forces in the air, even with drive intent.
		body.accept_command(command)
		commands.append(WireCodec.command_to_array(command))
		await get_tree().physics_frame
		await get_tree().process_frame
		var predicted := DriveModel.replay(state, commands, body.model_config())
		position_error = maxf(position_error, predicted.pose.origin.distance_to(body.global_position))
		velocity_error = maxf(velocity_error, predicted.velocity.distance_to(body.linear_velocity))
		angle_error = maxf(angle_error, predicted.pose.basis.get_rotation_quaternion().angle_to(body.global_basis.get_rotation_quaternion()))
		check(not body.grounded, "Reference remains in free flight")
	print("Airborne replay 250 ms max errors: position=%.4f m velocity=%.4f m/s rotation=%.3f deg" %
		[position_error, velocity_error, rad_to_deg(angle_error)])
	check(position_error < 0.05, "Airborne replay follows Jolt position within 5 cm")
	check(velocity_error < 0.05, "Airborne replay follows Jolt velocity within 0.05 m/s")
	check(angle_error < deg_to_rad(2), "Airborne replay follows Jolt rotation within 2 degrees")
	bot.queue_free()
	await get_tree().process_frame
	print("AIRBORNE REPLAY PASS" if failures == 0 else "AIRBORNE REPLAY FAIL")
	get_tree().quit(0 if failures == 0 else 1)
