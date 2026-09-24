extends "res://tests/network/contact_reconciliation.gd"
## F6 / standalone real-time ENet acceptance against the Foundry octagon walls.
## The settle clock starts once, at the local brake command after sustained push.
## It is never restarted by resting contacts. Presentation must remain within
## 0.25 m / 10 degrees of the simultaneous authority pose after 250 ms for 1 s.
var drive_throttle := 0.0
var drive_brake := true
var reported_invalid: Dictionary = {}

func frame() -> void:
	for index: int in range(clients.size()):
		var command := BotCommand.new()
		command.brake = drive_brake if index == 0 else true
		command.throttle = drive_throttle if index == 0 else 0.0
		clients[index].submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func run() -> void:
	profile = "80"
	server = make_session("Server")
	var port := FreePort.udp()
	check(server.host(port, false, 2) == OK, "Wall server binds")
	for index: int in range(2):
		var client := make_session("Client%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Wall client connects")
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)):
		check(false, "Wall clients admitted")
		await finish()
		return
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "active")):
		check(false, "Wall clients reach active round")
		await finish()
		return
	for session: MvpSession in sessions:
		session.network_simulation.delay_ms = 40
		session.network_simulation.jitter_ms = 10
		session.network_simulation.loss = 0.01
		session.network_simulation.duplicate = 0.02
	await wall_case("North", Vector3(0, 0.5, -40), 0)
	await wall_case("CornerEN", Vector3(30, 0.5, -30), -PI / 4)
	await finish()

func wall_case(wall_name: String, start: Vector3, yaw: float) -> void:
	drive_throttle = 0
	drive_brake = true
	server.world.reset_round()
	var authority: MvpBot = server.world.bots[clients[0].local_entity]
	var predicted: MvpBot = clients[0].world.bots[clients[0].local_entity]
	var wall: StaticBody3D = server.world.arena.get_node("Walls/" + wall_name)
	# Start near the current 100m Foundry walls; hull clearance sets floor height.
	authority.body.reset_pose = server.world.clear_spawn_pose(authority, Transform3D(Basis(Vector3.UP, yaw), start))
	await frames(90)
	drive_throttle = 1
	drive_brake = false
	var first_contact := -1
	var contact_ticks := 0
	var bounded := true
	var max_push_error := 0.0
	for index: int in range(480):
		await frame()
		bounded = bounded and valid_pose(authority.body) and valid_pose(predicted.body)
		if authority.body.contact_bodies.has(wall.get_instance_id()):
			contact_ticks += 1
			if first_contact < 0:
				first_contact = Engine.get_physics_frames()
		if first_contact >= 0:
			max_push_error = maxf(max_push_error, predicted.presentation.global_position.distance_to(authority.body.global_position))
			if Engine.get_physics_frames() - first_contact >= 120:
				break
	check(first_contact >= 0, "%s physically contacted by driven bot" % wall_name)
	check(contact_ticks >= 60, "%s sustains at least 60 sampled contact ticks during push" % wall_name)
	drive_throttle = 0
	drive_brake = true
	var release_tick := Engine.get_physics_frames()
	var samples: Array[int] = []
	var last_bad := -1
	var error_at_target := Vector2.INF
	for index: int in range(75):
		await frame()
		samples.append(Engine.get_physics_frames())
		bounded = bounded and valid_pose(authority.body) and valid_pose(predicted.body)
		var distance := predicted.presentation.global_position.distance_to(authority.body.global_position)
		var angle := rad_to_deg(predicted.presentation.global_basis.get_rotation_quaternion().angle_to(authority.body.global_basis.get_rotation_quaternion()))
		if samples.back() - release_tick >= 15 and error_at_target == Vector2.INF:
			error_at_target = Vector2(distance, angle)
		if distance > 0.25 or angle > 10:
			last_bad = index
	var settle := settling_ms(samples, last_bad, release_tick)
	print("Wall 80 ms %s: contact_samples=%d push_peak=%.3f m release_settle=%.1f ms error_at_250ms=%s" %
		[wall_name, contact_ticks, max_push_error, settle, error_at_target])
	check(samples.back() - release_tick >= 75, "%s observes at least 1 s beyond the 250 ms settling target" % wall_name)
	check(settle <= 250, "%s settles within 250 ms after local brake and stays within 0.25 m / 10 degrees" % wall_name)
	var push_end := authority.body.global_position
	var away := Basis(Vector3.UP, yaw).z
	drive_throttle = -1
	drive_brake = false
	for index: int in range(90):
		await frame()
		bounded = bounded and valid_pose(authority.body) and valid_pose(predicted.body)
	check((authority.body.global_position - push_end).dot(away) > 2, "%s reverse drive separates from wall by more than 2 m" % wall_name)
	check(not authority.body.contact_bodies.has(wall.get_instance_id()), "%s reverse ends physical wall contact" % wall_name)
	check(bounded, "%s server and predicted bodies stay finite and inside playable bounds throughout impact, push, release and reverse" % wall_name)
	drive_throttle = 0
	drive_brake = true
	await frames(60)

func valid_pose(body: DriveBody) -> bool:
	var at := body.global_position
	var valid := at.is_finite() and body.global_basis.is_finite() and body.linear_velocity.is_finite() \
		and body.angular_velocity.is_finite() and absf(at.x) < 50 and absf(at.z) < 50 \
		and absf(at.x)+absf(at.z) < 50.0*sqrt(2.0) \
		and at.y > -0.1 and at.y < 4
	if not valid and not reported_invalid.has(body.get_instance_id()):
		reported_invalid[body.get_instance_id()] = true
		print("Wall bounds fault: ", body.get_path(), " position=", at,
			" velocity=", body.linear_velocity, " physics_tick=", Engine.get_physics_frames())
	return valid

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("WALL CONTACT PASS" if failures == 0 else "WALL CONTACT FAIL")
	get_tree().quit(0 if failures == 0 else 1)
