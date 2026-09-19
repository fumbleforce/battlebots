extends Node
## Independent real-time scene. Exercise opaque bytes, both directions and cleanup.
const Relay := preload("res://tests/network/fixtures/udp_relay.gd")
var failures := 0
var relay := Relay.new()
var server := PacketPeerUDP.new()
var client := PacketPeerUDP.new()
var received: Array[Dictionary] = []
var server_received: Array[Dictionary] = []
var extra_client := PacketPeerUDP.new()
var extra_received: Array[Dictionary] = []

func _ready() -> void:
	add_child(relay)
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _process(_delta: float) -> void:
	if server.is_bound():
		while server.get_available_packet_count() > 0:
			var bytes := server.get_packet()
			server_received.append({"bytes":bytes, "at":Time.get_ticks_usec()})
			server.set_dest_address(server.get_packet_ip(), server.get_packet_port())
			check(server.put_packet(bytes) == OK, "Echo server sends raw reply")
	_read_client(client, received)
	_read_client(extra_client, extra_received)

func _read_client(socket: PacketPeerUDP, output: Array[Dictionary]) -> void:
	if not socket.is_bound():
		return
	while socket.get_available_packet_count() > 0:
		var bytes := socket.get_packet()
		output.append({"bytes":bytes, "at":Time.get_ticks_usec(), "port":socket.get_packet_port()})

func until(predicate: Callable, timeout_ms := 2000) -> bool:
	var deadline := Time.get_ticks_usec() + timeout_ms * 1000
	while Time.get_ticks_usec() < deadline:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()

func wait_ms(duration: int) -> void:
	var deadline := Time.get_ticks_usec() + duration * 1000
	while Time.get_ticks_usec() < deadline:
		await get_tree().process_frame

func restart(up: Dictionary = {}, down: Dictionary = {}, listen_port := 0) -> bool:
	relay.stop()
	for socket: PacketPeerUDP in [client, extra_client, server]:
		while socket.is_bound() and socket.get_available_packet_count() > 0:
			socket.get_packet()
	received.clear()
	extra_received.clear()
	server_received.clear()
	relay.uplink = up
	relay.downlink = down
	var error := relay.start(listen_port, server.get_local_port())
	check(error == OK, "Relay binds loopback sockets")
	if error != OK:
		return false
	check(client.set_dest_address("127.0.0.1", relay.bound_port) == OK, "Client addresses relay front")
	return true

func send(bytes: PackedByteArray) -> void:
	check(client.put_packet(bytes) == OK, "Raw client sends datagram")

func run() -> void:
	check(server.bind(0, "127.0.0.1") == OK, "Raw echo server binds loopback")
	check(client.bind(0, "127.0.0.1") == OK, "Raw client binds loopback")
	check(extra_client.bind(0, "127.0.0.1") == OK, "Replacement client binds loopback")
	if failures > 0:
		await finish()
		return
	if not restart():
		await finish()
		return
	var payload := PackedByteArray()
	payload.resize(1200)
	for index: int in range(payload.size()):
		payload[index] = (index * 73) % 256
	send(payload)
	check(await until(func() -> bool: return received.size() == 1), "Opaque payload completes round trip")
	if not received.is_empty():
		check(received[0].bytes == payload and received[0].port == relay.bound_port,
			"Raw binary bytes and relay return endpoint are preserved")
	check(relay.stats.uplink.bytes_out == 1200 and relay.stats.downlink.bytes_out == 1200,
		"Byte counters include both directions")
	check(relay.start(0, server.get_local_port()) == ERR_ALREADY_IN_USE, "Running relay cannot be restarted accidentally")
	await timing_case()
	await loss_case()
	await duplicate_case()
	await forced_loss_case()
	await seeded_impairment_case()
	await destination_case()
	await queue_and_rebind_case()
	await finish()

func timing_case() -> void:
	if not restart({"delay_ms":45, "jitter_ms":10, "seed":819}, {"delay_ms":55, "jitter_ms":15, "seed":204}):
		return
	var sent_at := {}
	for id: int in range(8):
		sent_at[id] = Time.get_ticks_usec()
		send(PackedByteArray([id, 0, 255, 128]))
		await get_tree().process_frame
	check(await until(func() -> bool: return received.size() == 8), "Delayed and jittered payloads all return")
	var round_trips: Array[float] = []
	for packet: Dictionary in server_received:
		var elapsed_ms: float = (packet.at - int(sent_at[packet.bytes[0]])) / 1000.0
		check(elapsed_ms >= 35, "Uplink never delivers before minimum injected delay")
	for packet: Dictionary in received:
		var id: int = packet.bytes[0]
		check(packet.bytes == PackedByteArray([id, 0, 255, 128]), "Jitter leaves payload bytes intact")
		var elapsed_ms: float = (packet.at - int(sent_at[id])) / 1000.0
		round_trips.append(elapsed_ms)
		check(elapsed_ms >= 75 and elapsed_ms < 1000, "Round-trip wall time includes both bounded delays")
	if not round_trips.is_empty():
		round_trips.sort()
		print("Raw relay injected 45+55 ms with jitter: observed RTT %.1f..%.1f ms" % [round_trips.front(), round_trips.back()])
	check(relay.stats.uplink.dropped == 0 and relay.stats.downlink.dropped == 0, "Zero-loss profile drops nothing")

func loss_case() -> void:
	if not restart({"loss":1.0}, {}):
		return
	send(PackedByteArray([10]))
	check(await until(func() -> bool: return relay.stats.uplink.packets_in == 1), "Uplink loss receives the original datagram")
	await wait_ms(80)
	check(server_received.is_empty() and received.is_empty() and relay.stats.uplink.dropped == 1,
		"Full uplink loss prevents server delivery")
	if not restart({}, {"loss":1.0}):
		return
	send(PackedByteArray([11]))
	check(await until(func() -> bool: return relay.stats.downlink.packets_in == 1), "Server response reaches downlink loss stage")
	await wait_ms(80)
	check(server_received.size() == 1 and received.is_empty() and relay.stats.downlink.dropped == 1,
		"Full downlink loss prevents client delivery")

func duplicate_case() -> void:
	if not restart({"duplicate":1.0}, {"duplicate":1.0}):
		return
	var payload := PackedByteArray([12, 0, 255])
	send(payload)
	check(await until(func() -> bool: return received.size() == 4), "Duplication in both directions yields four replies")
	check(server_received.size() == 2 and relay.stats.uplink.duplicated == 1 and relay.stats.downlink.duplicated == 2,
		"Duplicate counters distinguish injected copies from received originals")
	for packet: Dictionary in received:
		check(packet.bytes == payload, "Every duplicate retains the original bytes")

func forced_loss_case() -> void:
	if not restart():
		return
	relay.drop_next_uplink = 1
	relay.drop_next_downlink = 1
	send(PackedByteArray([13]))
	check(await until(func() -> bool: return relay.stats.uplink.forced_dropped == 1), "First client datagram is explicitly dropped")
	send(PackedByteArray([14]))
	check(await until(func() -> bool: return relay.stats.downlink.forced_dropped == 1), "First server reply is explicitly dropped")
	send(PackedByteArray([15]))
	check(await until(func() -> bool: return received.size() == 1), "Delivery resumes after forced losses")
	check(not received.is_empty() and received[0].bytes == PackedByteArray([15]), "Forced loss does not alter later packets")
	check(relay.stats.uplink.dropped == 1 and relay.stats.downlink.dropped == 1, "Forced drops are included in total drops")

func destination_case() -> void:
	if not restart({}, {"delay_ms":100}):
		return
	send(PackedByteArray([16]))
	check(await until(func() -> bool: return relay.stats.downlink.queued == 1), "Old client's reply is queued")
	extra_client.set_dest_address("127.0.0.1", relay.bound_port)
	check(extra_client.put_packet(PackedByteArray([17])) == OK, "Replacement endpoint sends a datagram")
	check(await until(func() -> bool: return received.size() == 1 and extra_received.size() == 1),
		"Queued replies retain their original destination endpoints")
	check(not received.is_empty() and received[0].bytes == PackedByteArray([16]), "Old reply stays with old client")
	check(not extra_received.is_empty() and extra_received[0].bytes == PackedByteArray([17]), "New reply goes to new client")

func seeded_impairment_case() -> void:
	var outcomes: Array = []
	for attempt: int in range(2):
		if not restart({"delay_ms":20, "jitter_ms":10, "loss":0.3, "duplicate":0.5, "seed":519}, {}):
			return
		for id: int in range(24):
			send(PackedByteArray([id]))
		check(await until(func() -> bool:
			return (relay.stats.uplink.packets_in == 24 and relay.pending_packets() == 0
				and server_received.size() == relay.stats.uplink.packets_out
				and received.size() == server_received.size())),
			"Seeded profile completes its entire burst through both socket directions")
		var ids: Array[int] = []
		for packet: Dictionary in received:
			ids.append(packet.bytes[0])
		ids.sort()
		outcomes.append({"ids":ids, "dropped":relay.stats.uplink.dropped, "duplicated":relay.stats.uplink.duplicated})
	check(outcomes[0] == outcomes[1], "Same seed reproduces dropped/duplicated payloads across runs")
	check(outcomes[0].dropped > 0 and outcomes[0].duplicated > 0,
		"Fractional seeded profile exercises both loss and duplication")

func queue_and_rebind_case() -> void:
	relay.queue_limit = 2
	relay.queue_byte_limit = 5
	if not restart({"delay_ms":500}, {}):
		return
	for id: int in range(3):
		send(PackedByteArray([id, 1, 2, 3]))
	check(await until(func() -> bool: return relay.stats.uplink.packets_in == 3), "Queue capacity probe is received")
	check(relay.pending_packets() == 1 and relay.pending_bytes() == 4 and relay.stats.uplink.queue_dropped == 2,
		"Queue bounds count bytes and record overflow drops")
	var port := relay.bound_port
	relay.stop()
	check(not relay.is_running() and relay.pending_packets() == 0 and relay.pending_bytes() == 0, "Stop clears sockets and queued payloads")
	check(relay.stats.uplink.queue_dropped == 2, "Stopped relay retains counters for reporting")
	if not restart({}, {}, port):
		return
	await wait_ms(550)
	check(server_received.is_empty(), "Stopped relay does not leak queued traffic into a new run")
	send(PackedByteArray([18]))
	check(await until(func() -> bool: return received.size() == 1), "Same front port rebinds and forwards again")
	check(relay.stats.uplink.queue_dropped == 0, "New run starts with fresh counters")

func finish() -> void:
	relay.stop()
	server.close()
	client.close()
	extra_client.close()
	relay.queue_free()
	await get_tree().process_frame
	print("RAW DATAGRAM RELAY PASS" if failures == 0 else "RAW DATAGRAM RELAY FAIL")
	get_tree().quit(0 if failures == 0 else 1)
