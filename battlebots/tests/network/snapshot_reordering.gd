extends "res://tests/network/contact_reconciliation.gd"
## Independent actual-ENet regression. Never invoke the receiving handler directly.
const Relay := preload("res://tests/network/fixtures/udp_relay.gd")
var relay := Relay.new()
var observer: MvpSession
var peer_id := 0
var next_tick := 10000

func run() -> void:
	server = make_session("OrderingServer")
	var port := FreePort.udp()
	if not await require(server.host(port, true, 2) == OK, "Snapshot ordering host binds"):
		return
	add_child(relay)
	if not await require(relay.start(0, port) == OK, "Ordering relay binds loopback"):
		return
	observer = make_session("OrderingClient")
	clients.append(observer)
	# Configure at transport admission, before application admission's reliable
	# replies can establish a higher RTT and reduce an unreliable packet's chance.
	server.multiplayer.peer_connected.connect(func(id: int) -> void:
		open_throttle(server.multiplayer.multiplayer_peer.get_peer(id)))
	observer.multiplayer.connected_to_server.connect(func() -> void:
		open_throttle(observer.multiplayer.multiplayer_peer.get_peer(1)))
	if not await require(observer.join("127.0.0.1", relay.bound_port) == OK, "Observer connects through raw UDP relay"):
		return
	if not await require(await until(func() -> bool: return observer.local_entity > 0), "Observer admitted"):
		return
	peer_id = server.players[observer.local_entity].peer
	var sender: ENetPacketPeer = server.multiplayer.multiplayer_peer.get_peer(peer_id)
	var receiver: ENetPacketPeer = observer.multiplayer.multiplayer_peer.get_peer(1)
	# This fixture isolates snapshot ordering with one-shot unreliable packets.
	# Keep ENet's adaptive dropper fully open before baseline/load work changes
	# measured RTT; loss/throttle behavior remains covered by whole-match tests.
	for peer: ENetPacketPeer in [sender, receiver]:
		open_throttle(peer)
		peer.ping()
	server.set_ready(true)
	observer.set_ready(true)
	if not await require(await until(func() -> bool:
		return observer.world.bots.size() == 2 and observer.match_view.get("phase") == "countdown"), "Observer receives real two-entity baseline"):
		return
	# Stop automatic input/snapshot/tick production, while SceneMultiplayer and
	# the relay continue polling actual sockets. Countdown keeps prediction frozen.
	server.set_physics_process(false)
	observer.set_physics_process(false)
	for bot: MvpBot in server.world.bots.values():
		bot.body.freeze = true
	await frames(15)
	# Admission itself can already lower throttle. Actual RTT samples restore it;
	# throttle_configure only changes adaptation parameters, not current state.
	var warmup_deadline := Time.get_ticks_usec() + 2000000
	while not full_throttle(sender, receiver) and Time.get_ticks_usec() < warmup_deadline:
		sender.ping()
		receiver.ping()
		await frames(6)
	print("Ordering throttle: sender=%.0f receiver=%.0f" % [sender.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), receiver.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE)])
	if not await require(full_throttle(sender, receiver),
		"Ordering fixture starts with full ENet unreliable delivery throttle"):
		return
	var host_entity := server.local_entity
	var client_entity := observer.local_entity
	if not await different_entities(host_entity, client_entity):
		return
	if not await same_entity(client_entity):
		return
	if not await duplicate_snapshot(host_entity):
		return
	await finish()

func full_throttle(sender: ENetPacketPeer, receiver: ENetPacketPeer) -> bool:
	return sender.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE) == ENetPacketPeer.PACKET_THROTTLE_SCALE \
		and receiver.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE) == ENetPacketPeer.PACKET_THROTTLE_SCALE

func open_throttle(peer: ENetPacketPeer) -> void:
	peer.throttle_configure(100, ENetPacketPeer.PACKET_THROTTLE_SCALE, 0)

func packet(entity: int, position: Vector3) -> PackedByteArray:
	var bot: MvpBot = server.world.bots[entity]
	next_tick += 10
	bot.server_tick = next_tick
	bot.body.reset_pose = null
	bot.body.global_transform = Transform3D(Basis.IDENTITY, position)
	bot.body.linear_velocity = Vector3.ZERO
	bot.body.angular_velocity = Vector3.ZERO
	return WireCodec.encode_bot(bot, WireCodec.snapshot_epoch(server.match_state.match_id, server.match_state.round_index))

func send_snapshot(bytes: PackedByteArray) -> void:
	server._snapshot.rpc_id(peer_id, bytes)

func schedule_slow(bytes: PackedByteArray) -> bool:
	relay.downlink = {"delay_ms":250.0}
	var received_before: int = relay.stats.downlink.packets_in
	send_snapshot(bytes)
	if not await require(await until(func() -> bool:
		return relay.stats.downlink.packets_in > received_before and relay.pending_packets() > 0), "Slow raw datagram reaches relay queue"):
		return false
	# Separate ENet flushes prevent both entity RPCs sharing one UDP datagram.
	await frames(2)
	relay.downlink = {}
	return true

func different_entities(first: int, second: int) -> bool:
	var first_position := Vector3(-7, 2, 3)
	var second_position := Vector3(8, 2, -4)
	var slow := packet(first, first_position)
	var first_tick := next_tick
	var fast := packet(second, second_position)
	var second_tick := next_tick
	var accepted_before: int = observer.diagnostics.snapshots_received
	if not await schedule_slow(slow):
		return false
	send_snapshot(fast)
	if not await require(await until(func() -> bool:
		return observer.world.bots[second].remote_state.tick == second_tick), "Second entity arrives first over actual ENet"):
		return false
	if not await require(observer.world.bots[first].remote_state.tick != first_tick,
		"Receipt order is demonstrably reversed, not coalesced into one datagram"):
		return false
	if not await require(await until(func() -> bool:
		return observer.world.bots[first].remote_state.tick == first_tick, 120), "Delayed first-entity state is still accepted after second entity"):
		return false
	check(observer.world.bots[first].body.global_position.is_equal_approx(first_position), "First entity installs its delayed authoritative pose")
	check(observer.world.bots[second].body.global_position.is_equal_approx(second_position), "Second entity retains its independent authoritative pose")
	check(observer.diagnostics.snapshots_received == accepted_before + 2, "Each distinct entity snapshot is accepted exactly once")
	print("Snapshot ordering: later entity arrived while earlier entity remained unchanged; both eventually accepted")
	return true

func same_entity(entity: int) -> bool:
	var older := packet(entity, Vector3(2, 2, 2))
	var older_tick := next_tick
	var latest_position := Vector3(11, 2, 6)
	var latest := packet(entity, latest_position)
	var latest_tick := next_tick
	var accepted_before: int = observer.diagnostics.snapshots_received
	if not await schedule_slow(older):
		return false
	send_snapshot(latest)
	if not await require(await until(func() -> bool:
		return observer.world.bots[entity].remote_state.tick == latest_tick), "Newer same-entity snapshot overtakes older packet"):
		return false
	var deadline := Time.get_ticks_usec() + 400000
	while Time.get_ticks_usec() < deadline:
		await frame()
		check(observer.world.bots[entity].remote_state.tick == latest_tick,
			"Late older same-entity packet cannot rewind accepted state")
	check(observer.diagnostics.snapshots_received == accepted_before + 1, "Per-entity tick guard rejects the older packet")
	check(observer.world.bots[entity].body.global_position.is_equal_approx(latest_position), "Newest entity pose survives delayed old state")
	check(relay.pending_packets() == 0, "Delayed old datagram was delivered before the rejection assertion")
	print("Snapshot ordering: stale tick%d rejected after tick%d for same entity" % [older_tick, latest_tick])
	return true

func duplicate_snapshot(entity: int) -> bool:
	var position := Vector3(-3, 2, -7)
	var bytes := packet(entity, position)
	var tick := next_tick
	var accepted_before: int = observer.diagnostics.snapshots_received
	var raw_before: int = relay.stats.downlink.packets_out
	relay.downlink = {"duplicate":1.0}
	send_snapshot(bytes)
	if not await require(await until(func() -> bool:
		return observer.world.bots[entity].remote_state.tick == tick), "Duplicated snapshot first copy arrives"):
		return false
	await frames(3)
	relay.downlink = {}
	# A new RPC datagram with identical snapshot content also exercises the
	# application guard even when ENet itself rejects the raw duplicated packet.
	send_snapshot(bytes)
	await frames(12)
	check(relay.stats.downlink.packets_out >= raw_before + 3 and relay.stats.downlink.duplicated > 0,
		"Duplicate raw datagram and repeated snapshot RPC both traverse the relay")
	check(observer.diagnostics.snapshots_received == accepted_before + 1, "Duplicate snapshot content is counted only once")
	check(observer.world.bots[entity].body.global_position.is_equal_approx(position), "Duplicate delivery preserves accepted pose")
	return true

func require(ok: bool, message: String) -> bool:
	check(ok, message)
	if not ok:
		await finish()
	return ok

func finish() -> void:
	for session: MvpSession in sessions:
		session.leave()
	if not relay.stats.is_empty():
		check(relay.stats.downlink.queue_dropped == 0 and relay.stats.downlink.send_errors == 0,
			"Reordering relay forwards without overflow or send errors")
	relay.stop()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	print("SNAPSHOT REORDERING PASS" if failures == 0 else "SNAPSHOT REORDERING FAIL")
	get_tree().quit(0 if failures == 0 else 1)
