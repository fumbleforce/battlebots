extends Node
const FreePort := preload("res://tests/fixtures/free_port.gd")
## Real ENet regression: clock sync must survive an unreliable throttle of zero.
## ENet's actual throttle statistic proves that unreliable traffic is suppressed.
const Relay = preload("res://tests/network/fixtures/udp_relay.gd")

class ObservedSession extends MvpSession:
	var baseline_count := 0

	@rpc("authority", "call_remote", "reliable", 0)
	func _baseline(packet: PackedByteArray) -> void:
		super._baseline(packet)
		baseline_count += 1

var failures := 0
var server: ObservedSession
var client: ObservedSession
var relay: Node

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func mount(label: String, session: MvpSession) -> void:
	var viewport := SubViewport.new()
	viewport.name = label
	viewport.own_world_3d = true
	add_child(viewport)
	get_tree().set_multiplayer(SceneMultiplayer.new(), viewport.get_path())
	session.name = "Session"
	viewport.add_child(session)

func frame() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame

func until(predicate: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_usec() + int(seconds * 1000000)
	while Time.get_ticks_usec() < deadline:
		if predicate.call():
			return true
		await frame()
	return false

func run() -> void:
	await clock_case()
	print("CLOCK DELIVERY PASS" if failures == 0 else "CLOCK DELIVERY FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func clock_case() -> void:
	server = ObservedSession.new()
	client = ObservedSession.new()
	mount("Server", server)
	mount("Client", client)
	var port := FreePort.udp()
	check(server.host(port, false, 2) == OK, "Clock fixture server binds")
	relay = Relay.new()
	add_child(relay)
	check(relay.start(0, port) == OK, "Clock fixture relay binds")
	check(client.join("127.0.0.1", relay.bound_port) == OK, "Clock fixture client joins")
	if not await until(func() -> bool: return client.local_entity > 0 and client._clock_ready):
		check(false, "Clock synchronizes before congestion")
		await cleanup()
		return
	var peer: ENetPacketPeer = client.multiplayer.multiplayer_peer.get_peer(1)
	# A real RTT increase causes ENet to drop unreliable traffic. Freeze throttle
	# recovery only for this regression so behavior is deterministic, not luck.
	peer.throttle_configure(5000, 0, ENetPacketPeer.PACKET_THROTTLE_SCALE)
	relay.uplink.delay_ms = 100.0
	relay.downlink.delay_ms = 100.0
	peer.ping()
	if not await until(func() -> bool: return peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE) == 0):
		check(false, "Actual ENet throttle reaches zero after the delayed reliable RTT sample")
		await cleanup()
		return
	var baselines := client.baseline_count
	client._ping_ticks.clear()
	client._last_ping = client._time # Next fresh app-clock request follows baseline.
	server._send_baseline(server.players[client.local_entity].peer)
	if not await until(func() -> bool: return client.baseline_count > baselines):
		check(false, "Reliable baseline still traverses zero unreliable throttle")
		await cleanup()
		return
	check(not client._clock_ready, "Baseline resets clock readiness before a fresh reply")
	var synchronized := await until(func() -> bool: return client._clock_ready, 3.5)
	check(peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE) == 0, "Congestion case retains zero unreliable throttle")
	check(synchronized, "Production reliable clock synchronizes despite unreliable traffic starvation")
	check(client.diagnostics.rtt_ms >= 200, "Fresh clock sample includes actual injected round-trip delay")
	print("Clock delivery: throttle=%.0f ready=%s pending=%d lastRTT=%.1fms" %
		[peer.get_statistic(ENetPacketPeer.PEER_PACKET_THROTTLE), client._clock_ready,
		client._ping_ticks.size(), client.diagnostics.rtt_ms])
	await cleanup()

func cleanup() -> void:
	client.leave()
	server.leave()
	relay.stop()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
