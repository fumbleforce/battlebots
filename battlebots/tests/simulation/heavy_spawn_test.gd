extends SceneTree
## Real Jolt shape queries validate enlarged hulls against both arenas and peers.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func check_shapes(world: AuthorityWorld, label: String) -> void:
	for bot: MvpBot in world.bots.values():
		check(bot.body.scale.is_equal_approx(Vector3.ONE), label + " preserves unscaled rigid body")
		check(bot.last_floor.is_equal_approx(bot.spawn_pose.origin), label + " initializes safe fallback floor position")
		for child: Node in bot.body.get_children():
			if child is not CollisionShape3D: continue
			var collider := child as CollisionShape3D
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = collider.shape
			query.transform = bot.spawn_pose * collider.transform
			query.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
			query.exclude = [bot.body.get_rid()]
			var hits := world.get_world_3d().direct_space_state.intersect_shape(query)
			check(hits.is_empty(), "%s bot%d %s starts clear of terrain, walls and peer hulls: %s" % [label, bot.entity_id, child.name, hits])
		var half: Vector3 = bot.combat.stats.size * 0.5
		for x: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				var corner := bot.spawn_pose * Vector3(x * half.x, -half.y, z * half.z)
				check(absf(corner.x) <= 24.75 and absf(corner.z) <= 24.75
					and absf(corner.x) + absf(corner.z) <= 24.75 * sqrt(2.0) + 0.001,
					label + " entire hull clears octagonal wall planes")

func run() -> void:
	for arena_id: String in ["foundry", "moon"]:
		var world := AuthorityWorld.new()
		world.arena_id = arena_id
		root.add_child(world)
		for count: int in [2, 4, 10, 8]:
			var ffa := count == 8
			for index: int in range(count):
				# Widest hull and tall rear pack stress both peer and wall clearance.
				var build := world.registry.starter(true)
				build.cosmetics.sawblade = SawbladeConfig.defaults()
				if index % 3 == 0: build.parts.drive = "walker"
				var slot: int = index if ffa else index % (count / 2)
				var team: int = index + 1 if ffa else index / (count / 2)
				var bot := world.spawn(index + 1, team, slot, build, count / 2, "ffa" if ffa else "teams")
				check(bot != null, "Largest build is valid")
				if bot != null:
					bot.body.global_transform = bot.spawn_pose
					bot.body.reset_pose = null
					bot.body.freeze = true
			await frames(2)
			check_shapes(world, "%s/%d" % [arena_id, count])
			world.clear_bots()
			await frames(2)
		world.free()
		await frames(2)
	# The public practice flow uses the same clearance after its custom placement.
	for arena_id: String in ["foundry", "moon"]:
		var session := MvpSession.new()
		root.add_child(session)
		var build := session.registry.starter(true)
		build.parts.drive = "walker"
		check(session.practice(build, arena_id) == OK, arena_id + " practice starts")
		session.set_physics_process(false)
		for bot: MvpBot in session.world.bots.values():
			bot.body.global_transform = bot.spawn_pose
			bot.body.reset_pose = null
			bot.body.freeze = true
		await frames(2)
		check_shapes(session.world, arena_id + "/practice")
		var own := session.local_source() as MvpBot
		var target := session.practice_target() as MvpBot
		var gap: float = absf(own.spawn_pose.origin.z - target.spawn_pose.origin.z) - (own.combat.stats.size.z + target.combat.stats.size.z) * 0.5
		check(gap >= 2.0 * BotScale.FACTOR - 0.001, "Practice gives enlarged weapons approach space")
		session.leave()
		session.free()
		await frames(2)
	print("HEAVY SPAWN PASS" if failures == 0 else "HEAVY SPAWN FAIL")
	quit(0 if failures == 0 else 1)
