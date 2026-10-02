extends "res://tests/network/session_smoke.gd"
## Real ENet session on Elysium (#115): older clients are turned away, every
## peer builds the floating islands without walls, the teams start across the
## Sanctum, a column the host breaks falls for everyone, and a bot the host
## drops off the edge falls to its death for everyone.
const GROUND = preload("res://scripts/arena/elysium_ground.gd")

func run() -> void:
	server = make_session("ElysiumServer")
	check(server.host(port, false, 2, "teams", "*", "elysium") == OK, "Elysium host binds")
	var old := make_session("Legacy")
	old.join("127.0.0.1", port)
	old._hello_data["arena_rules"] = 10
	check(await until(func() -> bool: return old.connection_state == "offline", 300), "Pre-Elysium peer rejected")
	check(server.players.is_empty(), "Rejected peer occupies no slot")
	for i: int in range(2):
		var client := make_session("ElysiumClient%d" % i)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Elysium client connects")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0 and c.arena_id == "elysium")), "Elysium selected from host baseline")
	for client: MvpSession in clients:
		client.set_ready(true)
	check(await until(func() -> bool: return server.match_state.phase == "active"), "Elysium round active")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.world.bots.size() == 2)), "Elysium bots replicated")
	for s: MvpSession in [server, clients[0], clients[1]]:
		check(s.world.arena.has_node("ElysiumIslands") and s.world.arena.get_node("ElysiumStructures").get_child_count() == GROUND.bodies().size(), "Peer has the Elysium islands and architecture")
		check((s.world.arena.get_node("Walls/North/Collision") as CollisionShape3D).disabled, "Peer has open edges")
	var starts: Array = server.world.bots.values().map(func(b: MvpBot) -> Vector3: return b.spawn_pose.origin)
	check(Vector2(starts[0].x + starts[1].x, starts[0].z + starts[1].z).length() < 0.5, "The two players start across the Sanctum")
	# A column the host breaks stops colliding on every peer (#115).
	server.world.props.damage("ColumnC0_2", 1.0e6, "cannon", server.world.props.props["ColumnC0_2"].at, Vector3.LEFT)
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.world.props.destroyed.has("ColumnC0_2") and c.world.arena.get_node("ElysiumStructures/ColumnC0_2").collision_layer == 0), 300),
		"Every peer drops the column the host broke")
	var victim: MvpBot = server.world.bots[clients[0].local_entity]
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 3, 140))
	victim.body.sleeping = false
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		var view: MvpBot = c.world.bots.get(victim.entity_id)
		return view != null and view.remote_state.get("eliminated", false) and view.remote_state.get("elimination_reason", "") == MvpBot.FALL_REASON), 400),
		"Every peer sees the bot that fell off the edge eliminated")
	await finish()
