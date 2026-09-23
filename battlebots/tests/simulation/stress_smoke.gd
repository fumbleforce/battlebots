extends SceneTree
var world: AuthorityWorld
var samples: Array[float] = []
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	world = AuthorityWorld.new()
	root.add_child(world)
	for id: int in range(1, 11):
		var bot := world.spawn(id, id % 2, id % 2, world.registry.starter(id % 3 == 0))
		bot.body.reset_pose = Transform3D(Basis(Vector3.UP, PI if id % 2 else 0), Vector3((id / 2) * 3 - 8, 0.5, 5 if id % 2 == 0 else -5))
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	var half := ArenaBounds.half_extent(world.arena_id)
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(x * half * 1.2, 1, z * half * 1.2), 1))
			if hit.is_empty() or absf(absf(hit.position.x) - half / sqrt(2.0)) > 0.01:
				failures += 1
	for id: int in world.bots:
		# reset_pose is consumed on the first physics step; check where it placed the body.
		if not ArenaBounds.contains(world.bots[id].body.global_position, half, 2.0):
			failures += 1
	for frame: int in range(900):
		var started := Time.get_ticks_usec()
		for id: int in world.bots:
			var command := BotCommand.new()
			command.sequence = frame
			command.throttle = 1
			command.steering = sin(frame * 0.02 + id) * 0.3
			command.primary_held = frame % 120 < 100
			world.bots[id].submit_command(command)
			# Keep all ten bodies participating throughout the budget measurement.
			world.bots[id].combat.core = world.bots[id].combat.stats.core
		world.step(1.0 / 60, true, 1)
		await physics_frame
		if frame > 180:
			samples.append((Time.get_ticks_usec() - started) / 1000.0)
	for id: int in world.bots:
		if not world.bots[id].body.global_position.is_finite():
			failures += 1
	samples.sort()
	print("Ten-body headless frame wall-time p95 ms: ", samples[int(samples.size() * 0.95)])
	# Timing is reported, not a flaky shared-CI pass/fail hardware promise.
	world.queue_free()
	await process_frame
	print("STRESS PASS" if failures == 0 else "STRESS FAIL")
	quit(0 if failures == 0 else 1)
