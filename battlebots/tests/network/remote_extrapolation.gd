extends Node
## Independent deterministic presentation-clock probes; no network impairment claim.
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var session := MvpSession.new()
	add_child(session)
	session.set_process(false)
	session.set_physics_process(false)
	session._make_world()
	session.local_entity = 1
	session.interpolation_delay = 0.1
	var bot := session.world.spawn(2, 1, 0, session.registry.starter())
	bot.simulated = false
	bot.body.freeze = true
	bot.body.reset_pose = null
	var latest_pose := Transform3D(Basis.IDENTITY, Vector3(-6, 0.25, 19))
	var older_pose := latest_pose
	older_pose.origin.x -= 1
	var falling_velocity := Vector3(3, -2.1, 0)
	var latest := {"tick":106, "arrival":0.0, "pose":latest_pose,
		"velocity":falling_velocity, "eliminated":false}
	var older := {"tick":100, "arrival":-0.1, "pose":older_pose,
		"velocity":falling_velocity, "eliminated":false}
	session._remote_buffers[2] = [older, latest]
	for phase: String in ["loading", "countdown", "intermission", "results", "lobby"]:
		session.match_view = {"phase":phase}
		var holds := true
		for age: float in [0.15, 0.5, 2.0]:
			session._time = age
			session._process(0)
			holds = holds and bot.presentation.global_transform.is_equal_approx(latest_pose)
		check(holds, "%s holds latest remote pose despite stale downward velocity" % phase)
		# Countdown/intermission can still interpolate legitimate received poses.
		session._time = 0.05
		session._process(0)
		check(bot.presentation.global_transform.is_equal_approx(older_pose.interpolate_with(latest_pose, 0.5)),
			"%s still interpolates within snapshot history" % phase)
	for phase: String in ["active", "overtime"]:
		session.match_view = {"phase":phase}
		latest.eliminated = false
		for age: float in [0.1, 0.15, 0.2, 0.5, 2.0]:
			session._time = age
			session._process(0)
			var expected := latest_pose.origin + falling_velocity * minf(0.1, age - session.interpolation_delay)
			check(bot.presentation.global_position.is_equal_approx(expected),
				"%s live bot extrapolates %.2f s arrival age with a 100 ms cap" % [phase, age])
		latest.eliminated = true
		for age: float in [0.15, 0.5, 2.0]:
			session._time = age
			session._process(0)
			check(bot.presentation.global_transform.is_equal_approx(latest_pose),
				"%s eliminated bot holds latest pose at %.2f s arrival age" % [phase, age])
	check(session.diagnostics.degraded, "Stale remote arrivals still report degraded networking")
	session.queue_free()
	await get_tree().process_frame
	print("REMOTE EXTRAPOLATION PASS" if failures == 0 else "REMOTE EXTRAPOLATION FAIL")
	get_tree().quit(0 if failures == 0 else 1)
