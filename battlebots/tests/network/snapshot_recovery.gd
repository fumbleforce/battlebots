extends "res://tests/network/contact_reconciliation.gd"
## Deterministic diagnostic: snapshot loss must not lose a reliable round reset.
## Two real peers retain the production reliable control channel throughout.
func run() -> void:
	server = make_session("RecoveryServer")
	var port := 51000 + OS.get_process_id() % 7000
	check(server.host(port, false, 2) == OK, "Recovery server binds")
	for index: int in range(2):
		var client := make_session("RecoveryClient%d" % index)
		clients.append(client)
		check(client.join("127.0.0.1", port) == OK, "Recovery peer joins")
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.local_entity > 0)):
		check(false, "Both peers admitted")
		await finish()
		return
	server.network_simulation.loss = 1.0
	for client: MvpSession in clients:
		client.set_ready(true)
	if not await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool: return c.match_view.get("phase") == "active")):
		check(false, "Both peers reach active")
		await finish()
		return
	await frames(2)
	for client: MvpSession in clients:
		for entity: int in server.world.bots:
			var observed: MvpBot = client.world.bots[entity]
			var authority: MvpBot = server.world.bots[entity]
			var error := observed.presentation.global_position.distance_to(authority.body.global_position)
			print("Snapshot starvation spawn: observer=", client.local_entity, " entity=", entity,
				" observed=", observed.presentation.global_position, " authority=", authority.body.global_position,
				" error=", error, " frozen=", observed.body.freeze)
			check(error < 0.15, "Reliable active transition presents settled authoritative spawns")
		check(not client.world.bots[client.local_entity].body.freeze,
			"Reliable active transition enables the living local physics body")
	server.network_simulation.loss = 0.0
	var id := clients[0].local_entity
	var bot: MvpBot = server.world.bots[id]
	bot.combat.damage("top", 30)
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return is_equal_approx(c.world.bots[id].remote_state.core, bot.combat.core))),
		"Initial damage reaches both peers before impairment")
	var old_epoch := WireCodec.snapshot_epoch(server.match_state.match_id, 1)
	server.network_simulation.loss = 1.0
	bot.combat.damage("top", 30)
	bot.combat.zones.drive_left = 0
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return (is_equal_approx(c.world.bots[id].remote_state.core, bot.combat.core)
			and c.world.bots[id].remote_state.zones.drive_left == 0)), 90),
		"Reliable heartbeat restores active health within 1.5 seconds of snapshot starvation")
	for client: MvpSession in clients:
		print("Snapshot starvation active: observer=", client.local_entity,
			" core=", client.world.bots[id].remote_state.core, " authority=", bot.combat.core,
			" age_ticks=", server.world.tick - client.world.bots[id].remote_state.tick,
			" clock_ready=", client._clock_ready, " phase=", client.match_view.get("phase"),
			" degraded=", client.diagnostics.get("degraded"))
	for other: MvpBot in server.world.bots.values():
		if other.team == 1:
			other.combat.eliminate("snapshot recovery fixture")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "intermission")), "Reliable intermission arrives through snapshot loss")
	for client: MvpSession in clients:
		for other: MvpBot in server.world.bots.values():
			if other.team == 1:
				check(client.world.bots[other.entity_id].remote_state.eliminated,
					"Reliable intermission carries the eliminated team's final state")
	server.match_state.remaining = 0
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "countdown" and c.match_view.get("round") == 2)),
		"Reliable round-two transition arrives through snapshot loss")
	var new_epoch := WireCodec.snapshot_epoch(server.match_state.match_id, 2)
	check(await until(func() -> bool: return all_reset(new_epoch), 90),
		"Reliable reset restores every bot's epoch, health, elimination and settled spawn")
	for client: MvpSession in clients:
		var observed: Dictionary = client.world.bots[id].remote_state
		print("Snapshot starvation reset: observer=", client.local_entity, " epoch=", observed.epoch,
			" required_epoch=", new_epoch, " core=", observed.core, " authority=", bot.combat.core,
			" phase=", client.match_view.get("phase"), " prior_epoch=", old_epoch)
		check(observed.epoch == new_epoch and is_equal_approx(observed.core, bot.combat.stats.core),
			"Reliable round reset carries repaired bot state even when unreliable snapshots are lost")
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return c.match_view.get("phase") == "active")), "Round two becomes active under snapshot starvation")
	await frames(2)
	check(all_reset(new_epoch), "Round-two active checkpoint preserves restored spawn and health")
	for client: MvpSession in clients:
		check(not client.world.bots[client.local_entity].body.freeze,
			"Round-two active checkpoint enables each local physics body")
	var delayed_states := server._bot_snapshots()
	var checkpoint_tick := server.world.tick
	server.network_simulation.loss = 0.0
	check(await until(func() -> bool: return clients.all(func(c: MvpSession) -> bool:
		return (c.world.bots[id].remote_state.epoch == new_epoch and c.world.bots[id].remote_state.tick > checkpoint_tick
			and is_equal_approx(c.world.bots[id].remote_state.core, bot.combat.stats.core)))),
		"Resumed snapshot transport recovers current state")
	for client: MvpSession in clients:
		var latest_tick: int = client.world.bots[id].remote_state.tick
		client._match(var_to_bytes({"view":client.match_view, "results":{}, "bots":delayed_states}))
		check(client.world.bots[id].remote_state.tick == latest_tick,
			"A delayed reliable checkpoint cannot rewind a newer unreliable entity snapshot")
	await finish()

func all_reset(epoch: String) -> bool:
	for client: MvpSession in clients:
		for id: int in server.world.bots:
			var observed: MvpBot = client.world.bots[id]
			var state := observed.remote_state
			if state.get("epoch") != epoch or state.get("eliminated", true):
				return false
			if not is_equal_approx(state.core, observed.combat.stats.core):
				return false
			if state.zones != observed.combat.zones:
				return false
			if observed.presentation.global_position.distance_to(server.world.bots[id].body.global_position) >= 0.15:
				return false
	return true

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("SNAPSHOT RECOVERY PASS" if failures == 0 else "SNAPSHOT RECOVERY FAIL")
	get_tree().quit(0 if failures == 0 else 1)
