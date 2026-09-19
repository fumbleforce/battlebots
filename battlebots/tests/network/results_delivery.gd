extends Node
## Real ENet delivery to one observer of a server-local ten-participant fixture.
## This isolates legal five-round payload size, not ten-client gameplay/stress.
class ObservedSession extends MvpSession:
	var received_matches: Array[Dictionary] = []
	var received_baselines: Array[int] = []

	@rpc("authority", "call_remote", "reliable", 0)
	func _match(packet: PackedByteArray) -> void:
		received_matches.append({"bytes":packet.size(), "data":bytes_to_var(packet)})
		super._match(packet)

	@rpc("authority", "call_remote", "reliable", 0)
	func _baseline(packet: PackedByteArray) -> void:
		received_baselines.append(packet.size())
		super._baseline(packet)

var failures := 0
var server: MvpSession
var client: ObservedSession
var result_events := 0
var last_result: Dictionary = {}

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func mount_session(label: String, session: MvpSession) -> void:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	add_child(viewport)
	get_tree().set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	session.name = "Session"
	viewport.add_child(session)

func frame() -> void:
	var command := BotCommand.new()
	command.brake = true
	client.submit_local(command)
	await get_tree().physics_frame
	await get_tree().process_frame

func frames(count: int) -> void:
	for index: int in range(count):
		await frame()

func until(predicate: Callable, limit := 600) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await frame()
	return false

func on_event(kind: String, details: Dictionary) -> void:
	if kind == "results":
		result_events += 1
		last_result = details

func run() -> void:
	server = MvpSession.new()
	client = ObservedSession.new()
	mount_session("Server", server)
	mount_session("Client", client)
	client.session_event.connect(on_event)
	var port := 53000 + OS.get_process_id() % 8000
	check(server.host(port, false, 10) == OK, "Results server binds")
	check(client.join("127.0.0.1", port) == OK, "Results observer connects")
	if not await until(func() -> bool: return client.local_entity > 0):
		check(false, "Results observer admitted")
		await finish()
		return
	var real_id := client.local_entity
	# Nine server-local fixture participants have no transport peer. Their real
	# CombatState snapshots generate the same data shape as ten-player gameplay.
	for index: int in range(9):
		var id := server._admit(0, server.registry.starter())
		server.players[id].deadline = server._time + 600
	server.peer_entities.erase(0)
	server.match_state.begin(10)
	server.match_state.transition("countdown", 0)
	var slots := [0, 0]
	for id: int in server.players:
		var player: Dictionary = server.players[id]
		var bot := server.world.spawn(id, player.team, slots[player.team], player.loadout, 5)
		slots[player.team] += 1
		bot.owner_id = player.peer
	server._send_baseline(server.players[real_id].peer)
	if not await until(func() -> bool: return client.world.bots.size() == 10 and client.match_view.get("phase") == "active"):
		check(false, "Observer receives real ten-bot baseline")
		await finish()
		return
	for round_number: int in range(1, 6):
		for bot: MvpBot in server.world.bots.values():
			# Equal statistics on both teams retain a tie while making every
			# archived round distinguishable and aggregate totals checkable.
			bot.combat.effective_damage = round_number * 7
			bot.combat.assists = round_number
		server.match_state.transition("overtime", 0)
		var target_phase := "results" if round_number == 5 else "intermission"
		if not await until(func() -> bool: return server.match_state.phase == target_phase and client.match_view.get("phase") == target_phase):
			check(false, "Observer receives five-round fixture transition %d" % round_number)
			await finish()
			return
		if round_number < 5:
			server.match_state.remaining = 0
			check(await until(func() -> bool: return server.match_state.phase == "countdown"), "Fixture advances to next countdown")
			server.match_state.remaining = 0
			check(await until(func() -> bool: return client.match_view.get("phase") == "active" and client.match_view.get("round") == round_number + 1),
				"Observer starts next fixture round")
	# Extend the fixture's results window while testing heartbeat/reconnect paths.
	server.match_state.remaining = 120
	check(await until(func() -> bool: return result_events == 1), "Five-round results arrive once")
	check_results("Initial delivery")
	var complete_packets := 0
	var largest_result_packet := 0
	for receipt: Dictionary in client.received_matches:
		check_public_view(receipt.data.view)
		if not receipt.data.results.is_empty():
			complete_packets += 1
			largest_result_packet = maxi(largest_result_packet, receipt.bytes)
	check(complete_packets == 1, "Only initial results publication sends the detailed result")
	check(largest_result_packet > 32768 and largest_result_packet <= 128 * 1024,
		"Legal ten-player five-round result exercises old 32 KiB rejection and fits 128 KiB bound")
	var before_heartbeats := client.received_matches.size()
	await frames(130)
	check(client.received_matches.size() > before_heartbeats, "Results heartbeat actually arrives over ENet")
	var largest_heartbeat := 0
	for index: int in range(before_heartbeats, client.received_matches.size()):
		var receipt: Dictionary = client.received_matches[index]
		largest_heartbeat = maxi(largest_heartbeat, receipt.bytes)
		check(receipt.data.results.is_empty(), "Results heartbeats omit detailed results")
		check_public_view(receipt.data.view)
	check(largest_heartbeat > 0 and largest_heartbeat < 4096, "Five-round match heartbeat stays compact")
	check(result_events == 1, "Heartbeats do not duplicate the results event")
	var previous_baselines := client.received_baselines.size()
	server._send_baseline(server.players[real_id].peer)
	check(await until(func() -> bool: return client.received_baselines.size() > previous_baselines), "Repeated results baseline arrives over ENet")
	check(result_events == 1, "Repeated baseline does not duplicate the results event")
	check_results("Repeated baseline")
	var token := client.reconnect_token
	client.leave()
	check(await until(func() -> bool: return server.players[real_id].peer == 0), "Authority observes results disconnect")
	previous_baselines = client.received_baselines.size()
	check(client.join("127.0.0.1", port, token) == OK, "Results reconnect begins")
	check(await until(func() -> bool: return client.local_entity == real_id and result_events == 2), "Reconnect receives its result once through baseline")
	check(client.reconnect_token != token, "Results reconnect rotates credential")
	check(client.received_baselines.size() > previous_baselines and client.received_baselines.back() > 32768,
		"Reconnect receives large detailed baseline over actual ENet")
	check_results("Reconnect")
	await frames(70)
	check(result_events == 2, "Reconnect heartbeat does not duplicate result delivery")
	print("Results delivery: detailed_packet=%d bytes heartbeat=%d bytes reconnect_baseline=%d bytes" %
		[largest_result_packet, largest_heartbeat, client.received_baselines.back()])
	await finish()

func check_public_view(view: Dictionary) -> void:
	check(view.mode == "5v5" and view.capacity == 10, "Public match keeps mode and capacity")
	for round_result: Dictionary in view.rounds:
		check(not round_result.has("participants"), "Public match omits detailed per-round participants")
		check(round_result.has("round") and round_result.has("winner"), "Public match keeps round outcomes")

func check_results(label: String) -> void:
	check(not last_result.is_empty() and last_result == client._results and client._results == server._results,
		"%s preserves full authoritative result" % label)
	if last_result.is_empty():
		return
	check(last_result.participants.size() == 10 and last_result.match.rounds.size() == 5,
		"%s has ten aggregate participants and five detailed rounds" % label)
	for round_result: Dictionary in last_result.match.rounds:
		check(round_result.participants.size() == 10, "%s retains all ten round participants" % label)
		for state: Dictionary in round_result.participants.values():
			check(state.damage == int(round_result.round) * 7, "%s preserves per-round statistics" % label)
	for state: Dictionary in last_result.participants.values():
		check(state.damage == 105 and state.assists == 15, "%s preserves five-round aggregate totals" % label)

func finish() -> void:
	client.leave()
	server.leave()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("RESULTS DELIVERY PASS" if failures == 0 else "RESULTS DELIVERY FAIL")
	get_tree().quit(0 if failures == 0 else 1)
