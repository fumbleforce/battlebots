extends "res://tests/network/session_smoke.gd"
## Woodland LAN/online matches include the roaming giant (#79) as a neutral
## hazard: real ENet peers build the same scaled replica, see it move, and it
## never decides a round or appears in results. Its drop reaches every peer.
func run() -> void:
	server = make_session("WoodlandServer")
	check(server.host(port, false, 2, "teams", "*", "woodland") == OK, "Woodland host binds")
	for i: int in range(2):
		var client := make_session("WoodlandClient%d" % i)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Woodland client connects")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0 and c.arena_id == "woodland")),
		"Woodland selected from host baseline")
	for client: MvpSession in clients:
		client.set_ready(true)
	check(await until(func() -> bool: return server.match_state.phase == "active", 1800), "Woodland round active")
	var boss := server.woodland_boss
	check(boss != null and is_instance_valid(boss.boss) and server.world.bots.size() == 3, "The server adds the giant to the match")
	if boss == null or not is_instance_valid(boss.boss):
		await finish()
		return
	var giant: MvpBot = boss.boss
	check(giant.team == WoodlandBoss.TEAM and not server.players.has(boss.boss_id), "The giant is neutral, not a player")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.world.bots.has(boss.boss_id))),
		"Every client builds the giant from the baseline")
	for client: MvpSession in clients:
		var copy: MvpBot = client.world.bots.get(boss.boss_id)
		if copy == null: continue
		check(copy.combat.stats.size.is_equal_approx(giant.combat.stats.size) and copy.team == WoodlandBoss.TEAM
			and is_equal_approx(copy.body.mass, giant.body.mass), "Client replica has the giant's scaled size, mass and team")
	var start := giant.body.global_position
	await frames(360)
	check(giant.body.global_position.distance_to(start) > 2.0, "The giant roams during the round")
	for client: MvpSession in clients:
		var copy: MvpBot = client.world.bots.get(boss.boss_id)
		if copy == null: continue
		check(copy.presentation.global_position.distance_to(giant.body.global_position) < 8.0,
			"Client shows the giant near its server position (%.1f m)" % copy.presentation.global_position.distance_to(giant.body.global_position))
	# Hitting and killing the giant never scores (#82), but the kill vents heat.
	var killer: int = clients[0].local_entity
	var hunter: MvpBot = server.world.bots[killer]
	var health_before := total_health(giant)
	server.world.weapons._apply_hit(hunter, giant, giant.body.global_position, 60.0, Vector3.ZERO, server.world.tick, 1)
	check(total_health(giant) < health_before, "Damage to the giant lands (%.0f -> %.0f)" % [health_before, total_health(giant)])
	check(hunter.combat.effective_damage == 0 and hunter.combat.component_disables == 0, "Damage to the giant is never scored (%d)" % hunter.combat.effective_damage)
	giant.combat.recent_attackers[killer] = server.world.weapons.time
	giant.combat.eliminate("test")
	await frames(30)
	check(hunter.combat.eliminations == 0 and hunter.combat.assists == 0, "Killing the giant is not an elimination")
	check(hunter.combat.spree == 1, "Killing the giant still credits a kill spree (heat vent) like any kill")
	check(server.match_state.phase == "active", "Destroying the giant does not decide the round")
	var drop_id := 9000 + boss.boss_id
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return has_item(c, drop_id))),
		"The giant's drop reaches every client")
	# One team eliminated ends the round for the other team, giant or not.
	var loser: int = clients[1].local_entity
	server.world.bots[loser].combat.eliminate("test")
	check(await until(func() -> bool: return server.match_state.phase in ["intermission", "results"], 600),
		"Eliminating a team ends the round while the giant is still in the world")
	check(server.match_state.rounds.back().get("winner", -1) == server.players[killer].team, "The surviving player's team wins the round")
	check(not server.match_state.rounds.back().get("participants", {}).has(boss.boss_id), "Round stats never list the giant")
	await finish()

func has_item(session: MvpSession, id: int) -> bool:
	for item: Dictionary in session.pickup_view.get("items", []):
		if int(item.id) == id:
			return true
	return false

## Core plus every zone: the giant's hardened plates absorb hits before the core.
func total_health(bot: MvpBot) -> float:
	var total := bot.combat.core
	for zone: String in bot.combat.zones:
		total += float(bot.combat.zones[zone])
	return total
