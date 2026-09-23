extends SceneTree
## Steering convention at the shared authoritative/replay force boundary.
var failures := 0
var config: Dictionary

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func response(speed: float, throttle: float, steering: float, braking := false, basis := Basis.IDENTITY, normal := Vector3.UP) -> float:
	var forward := (-basis.z).slide(normal).normalized()
	return DriveModel.forces(basis, forward * speed, Vector3.ZERO, normal,
		throttle, steering, braking, 1.0 / 60.0, config).yaw_acceleration

func run() -> void:
	var body := DriveBody.new()
	config = body.model_config()
	body.free()
	for turn: float in [-1.0, 1.0]:
		check(response(4.0, 1.0, turn) * turn < 0.0, "Forward steering keeps its original yaw sign")
		check(response(-4.0, -1.0, turn) * turn > 0.0, "Reverse steering inverts yaw for both left and right")
		check(response(-4.0, 0.0, turn) * turn > 0.0, "Reverse coasting keeps reverse steering")
		check(response(4.0, -1.0, turn) * turn < 0.0, "Reverse throttle does not flip steering before forward momentum reverses")
		check(response(-4.0, 1.0, turn) * turn > 0.0, "Forward throttle keeps reverse steering while still travelling backwards")
		check(response(0.0, -1.0, turn) * turn > 0.0, "Reverse launch uses reverse steering from standstill")
		check(response(0.0, 0.0, turn) * turn < 0.0, "Neutral pivot keeps the original turn direction")
		check(response(-0.01, 0.0, turn) * turn < 0.0, "Tiny resting velocity cannot flip neutral pivot")
		check(response(0.01, -1.0, turn) * turn > 0.0, "Near-rest reverse intent wins over tiny residual forward velocity")
		check(response(-4.0, -1.0, turn, true) == 0.0, "Brakes continue to suppress steering")
		var heading := Basis(Vector3.UP, 1.7)
		check(response(-4.0, -1.0, turn, false, heading) * turn > 0.0, "Reversing uses chassis-local direction, not world Z")
		var slope := Basis(Vector3.RIGHT, 0.3)
		check(response(-4.0, -1.0, turn, false, slope, slope.y) * turn > 0.0, "Reverse convention holds on a sloped support plane")
		for speed: float in [-4.0, 4.0]:
			var command := BotCommand.new()
			command.sequence = 1
			command.throttle = signf(speed)
			command.steering = turn
			var state := {"pose":Transform3D.IDENTITY, "velocity":Vector3(0,0,-speed), "angular":Vector3.ZERO,
				"drive_input":command.throttle, "turn_input":turn, "grounded":true}
			var replay := DriveModel.replay(state, [WireCodec.command_to_array(command)], config.duplicate())
			check(replay.angular.y * turn * signf(speed) < 0.0, "Client replay uses the same forward/reverse yaw convention")
	config.steering_scale = 0.0
	check(response(-4.0, -1.0, 1.0) == 0.0, "Disabled steering remains disabled in reverse")
	config.steering_scale = 1.0
	var registry := ContentRegistry.new()
	var pilot_bot := MvpBot.create(1, 1, registry.starter(), registry)
	var target := MvpBot.create(2, 0, registry.starter(), registry)
	root.add_child(pilot_bot)
	root.add_child(target)
	pilot_bot.body.freeze = true
	target.body.freeze = true
	pilot_bot.body.global_transform = Transform3D.IDENTITY
	pilot_bot.body.linear_velocity = Vector3(0, 0, 4)
	var director := PracticeBotDirector.new()
	for side: float in [-1.0, 1.0]:
		target.body.global_position = Vector3(side * 0.5, 0, -4)
		var intent := BotCommand.new()
		director._pilot(pilot_bot, target, {"index":1, "home":Transform3D.IDENTITY, "patrol":0}, intent)
		check(intent.throttle < 0.0 and response(-4.0, intent.throttle, intent.steering) * side < 0.0,
			"Practice pilot preserves heading correction toward either side of its target while retreating")
	pilot_bot.queue_free()
	target.queue_free()
	await process_frame
	print("REVERSE STEERING PASS" if failures == 0 else "REVERSE STEERING FAIL")
	quit(0 if failures == 0 else 1)
