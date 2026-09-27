extends "res://tests/network/session_smoke.gd"
## Real ENet session on the Frozen Maelstrom (#102): older clients are turned
## away, every peer builds the ice ring without walls, the teams start across
## the eye, and a bot the host drops into the eye is eliminated for everyone.
const GROUND = preload("res://scripts/arena/maelstrom_ground.gd")

func run() -> void:
	server = make_session("MaelstromServer")
	check(server.host(port, false, 2, "teams", "*", "maelstrom") == OK, "Maelstrom host binds")
	var old := make_session("Legacy")
	old.join("127.0.0.1", port)
	old._hello_data["arena_rules"] = 3
	check(await until(func() -> bool: return old.connection_state == "offline", 300), "Pre-Maelstrom peer rejected")
	check(server.players.is_empty(), "Rejected peer occupies no slot")
	for i: int in range(2):
		var client := make_session("MaelstromClient%d" % i)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Maelstrom client connects")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0 and c.arena_id == "maelstrom")), "Maelstrom selected from host baseline")
	for client: MvpSession in clients:
		client.set_ready(true)
	check(await until(func() -> bool: return server.match_state.phase == "active"), "Maelstrom round active")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.world.bots.size() == 2)), "Maelstrom bots replicated")
	for s: MvpSession in [server, clients[0], clients[1]]:
		check(s.world.arena.has_node("MaelstromIce") and s.world.arena.get_node("MaelstromObstacles").get_child_count() == GROUND.obstacles().size(), "Peer has the Maelstrom ice and wrecks")
		check((s.world.arena.get_node("Walls/North/Collision") as CollisionShape3D).disabled, "Peer has open edges")
	var starts: Array = server.world.bots.values().map(func(b: MvpBot) -> Vector3: return b.spawn_pose.origin)
	check(Vector2(starts[0].x + starts[1].x, starts[0].z + starts[1].z).length() < 0.5, "The two players start on opposite sides of the eye")
	var victim: MvpBot = server.world.bots[clients[0].local_entity]
	victim.body.reset_pose = Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
	victim.body.sleeping = false
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		var view: MvpBot = c.world.bots.get(victim.entity_id)
		return view != null and view.remote_state.get("eliminated", false) and view.remote_state.get("elimination_reason", "") == GROUND.FALL_REASON), 400),
		"Every peer sees the bot the eye swallowed eliminated")
	await finish()
