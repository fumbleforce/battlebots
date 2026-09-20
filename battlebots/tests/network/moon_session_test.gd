extends "res://tests/network/session_smoke.gd"
## Real ENet handshake, terrain selection, reset and reconnect under lunar rules.
func run() -> void:
	server = make_session("MoonServer")
	check(server.host(port,false,2,"teams","*","moon")==OK,"Moon host binds")
	var old := make_session("Legacy")
	old.join("127.0.0.1",port)
	old._hello_data.erase("arena_rules")
	check(await until(func() -> bool: return old.connection_state=="offline",300),"Legacy Moon peer rejected")
	check(server.players.is_empty(),"Legacy peer occupies no slot")
	for i: int in range(2):
		var client := make_session("LunarClient%d" % i)
		clients.append(client)
		check(client.join("127.0.0.1",port)==OK,"Moon client connects")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity>0 and c.arena_id=="moon")),"Moon selected from host baseline")
	for client: MvpSession in clients:
		client.set_ready(true)
	check(await until(func() -> bool: return server.match_state.phase=="active"),"Lunar round active")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.world.bots.size()==2)),"Moon bots replicated")
	for s: MvpSession in [server,clients[0],clients[1]]:
		check(s.world.arena.has_node("LunarSurface"),"Peer has lunar collision")
		for bot: MvpBot in s.world.bots.values():
			check(absf(bot.body.model_config().gravity.y+1.62)<0.001,"Peer replay uses lunar gravity")
	var id := clients[0].local_entity
	var token := clients[0].reconnect_token
	clients[0].leave()
	check(await until(func() -> bool: return server.players[id].peer==0,180),"Lunar disconnect reserves slot")
	clients[0].join("127.0.0.1",port,token)
	check(await until(func() -> bool: return clients[0].local_entity==id and clients[0].world.arena_id=="moon" and clients[0].world.bots.size()==2),"Reconnect rebuilds Moon")
	server.world.reset_round()
	await frames(5)
	for bot: MvpBot in server.world.bots.values():
		check(absf(bot.body.gravity_scale-1.62/9.8)<0.001,"Round reset retains lunar gravity")
	# Reject unknown server rules without trying to load an arbitrary resource.
	clients[0]._baseline(var_to_bytes({"arena":"res://invalid.tscn"}))
	check(clients[0].connection_state=="offline","Unknown arena rejected")
	clients[1].leave()
	server.leave()
	await frames(5)
	check(server.host(port,false,2)==OK,"Foundry default retained")
	clients[0].join("127.0.0.1",port)
	clients[0]._hello_data.erase("arena_rules")
	check(await until(func() -> bool: return clients[0].local_entity>0),"Legacy hello still joins Foundry")
	clients[0]._baseline(var_to_bytes({"lobby":server._public_lobby(),"match":server._public_match(),"bots":server._bot_snapshots(),"server_tick":server.world.tick}))
	check(clients[0].world.arena_id=="foundry","Baseline without arena defaults to Foundry")
	await finish()
