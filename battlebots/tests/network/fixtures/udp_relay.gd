extends Node
## Test-only opaque UDP relay. One client per instance; bind loopback interfaces only.
## Configure profiles before start(). Deadlines use wall time, never simulation delta.
## Reconnect tests should create a fresh relay to avoid mixing transport identities.
const LOOPBACK := "127.0.0.1"
const RECEIVE_BUFFER_BYTES := 1048576
const RECEIVE_LIMIT_PER_FRAME := 512

var uplink := {"delay_ms":0.0, "jitter_ms":0.0, "loss":0.0, "duplicate":0.0, "seed":12345}
var downlink := {"delay_ms":0.0, "jitter_ms":0.0, "loss":0.0, "duplicate":0.0, "seed":54321}
var drop_next_uplink := 0
var drop_next_downlink := 0
var queue_limit := 2048
var queue_byte_limit := 4194304
var bound_port := 0
var stats: Dictionary = {}

var _front := PacketPeerUDP.new()
var _back := PacketPeerUDP.new()
var _server_port := 0
var _client_port := 0
var _pending: Array[Dictionary] = []
var _pending_bytes := 0
var _random := {"uplink":RandomNumberGenerator.new(), "downlink":RandomNumberGenerator.new()}
var _running := false

func _ready() -> void:
	set_process(_running)

func start(listen_port: int, server_port: int) -> Error:
	if _running:
		return ERR_ALREADY_IN_USE
	if listen_port < 0 or listen_port > 65535 or server_port < 1 or server_port > 65535:
		return ERR_INVALID_PARAMETER
	if not _valid_profile(uplink) or not _valid_profile(downlink) or queue_limit < 1 or queue_byte_limit < 1:
		return ERR_INVALID_PARAMETER
	var error := _front.bind(listen_port, LOOPBACK, RECEIVE_BUFFER_BYTES)
	if error != OK:
		return error
	error = _back.bind(0, LOOPBACK, RECEIVE_BUFFER_BYTES)
	if error != OK:
		_front.close()
		return error
	_server_port = server_port
	_client_port = 0
	bound_port = _front.get_local_port()
	_pending.clear()
	_pending_bytes = 0
	stats = {"uplink":_empty_stats(), "downlink":_empty_stats()}
	_random.uplink.seed = int(uplink.get("seed", 12345))
	_random.downlink.seed = int(downlink.get("seed", 54321))
	_running = true
	set_process(true)
	return OK

func stop() -> void:
	_running = false
	set_process(false)
	_front.close()
	_back.close()
	_pending.clear()
	_pending_bytes = 0
	_client_port = 0
	_server_port = 0
	bound_port = 0
	# Keep the last run's counters available after shutdown; start resets them.

func is_running() -> bool:
	return _running

func pending_packets() -> int:
	return _pending.size()

func pending_bytes() -> int:
	return _pending_bytes

func _exit_tree() -> void:
	stop()

func _process(_delta: float) -> void:
	if not _running:
		return
	_receive(_front, "uplink")
	_receive(_back, "downlink")
	var now := Time.get_ticks_usec()
	var ready: Array[Dictionary] = []
	for index: int in range(_pending.size() - 1, -1, -1):
		if _pending[index].due_us <= now:
			var packet: Dictionary = _pending[index]
			_pending_bytes -= packet.bytes.size()
			ready.append(packet)
			_pending.remove_at(index)
	# Jitter may reorder packets. Equal deadlines preserve arrival/duplicate order.
	ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.due_us < b.due_us or (a.due_us == b.due_us and a.order < b.order))
	for packet: Dictionary in ready:
		var socket := _back if packet.direction == "uplink" else _front
		var error := socket.set_dest_address(packet.ip, packet.port)
		if error == OK:
			error = socket.put_packet(packet.bytes)
		var counters: Dictionary = stats[packet.direction]
		if error == OK:
			counters.packets_out += 1
			counters.bytes_out += packet.bytes.size()
		else:
			counters.send_errors += 1

func _receive(socket: PacketPeerUDP, direction: String) -> void:
	for index: int in range(RECEIVE_LIMIT_PER_FRAME):
		if socket.get_available_packet_count() == 0:
			break
		var bytes := socket.get_packet()
		if socket.get_packet_error() != OK:
			stats[direction].receive_errors += 1
			continue
		var ip := socket.get_packet_ip()
		var port := socket.get_packet_port()
		var counters: Dictionary = stats[direction]
		counters.packets_in += 1
		counters.bytes_in += bytes.size()
		if ip != LOOPBACK or (direction == "downlink" and (port != _server_port or _client_port == 0)):
			counters.unroutable += 1
			continue
		if direction == "uplink":
			_client_port = port
		# Capture the destination now, including replies queued before a new front
		# sender appears. Queued replies must never be retargeted during delivery.
		_schedule(direction, bytes, LOOPBACK, _server_port if direction == "uplink" else _client_port)

func _schedule(direction: String, bytes: PackedByteArray, ip: String, port: int) -> void:
	var counters: Dictionary = stats[direction]
	if (direction == "uplink" and drop_next_uplink > 0) or (direction == "downlink" and drop_next_downlink > 0):
		if direction == "uplink":
			drop_next_uplink -= 1
		else:
			drop_next_downlink -= 1
		counters.dropped += 1
		counters.forced_dropped += 1
		return
	var profile: Dictionary = uplink if direction == "uplink" else downlink
	var random: RandomNumberGenerator = _random[direction]
	if random.randf() < float(profile.get("loss", 0.0)):
		counters.dropped += 1
		return
	var delay := maxf(0.0, float(profile.get("delay_ms", 0.0)) + random.randf_range(-float(profile.get("jitter_ms", 0.0)), float(profile.get("jitter_ms", 0.0))))
	var due := Time.get_ticks_usec() + roundi(delay * 1000.0)
	_enqueue(direction, bytes, ip, port, due)
	if random.randf() < float(profile.get("duplicate", 0.0)):
		counters.duplicated += 1
		_enqueue(direction, bytes, ip, port, due + 1000)

func _enqueue(direction: String, bytes: PackedByteArray, ip: String, port: int, due_us: int) -> void:
	var counters: Dictionary = stats[direction]
	if _pending.size() >= queue_limit or _pending_bytes + bytes.size() > queue_byte_limit:
		counters.queue_dropped += 1
		return
	counters.queued += 1
	_pending.append({"direction":direction, "bytes":bytes, "ip":ip, "port":port,
		"due_us":due_us, "order":stats.uplink.queued + stats.downlink.queued})
	_pending_bytes += bytes.size()

func _valid_profile(profile: Dictionary) -> bool:
	for field: String in ["delay_ms", "jitter_ms", "loss", "duplicate"]:
		var value: Variant = profile.get(field, 0.0)
		if (not value is float and not value is int) or not is_finite(float(value)) or value < 0:
			return false
		if field in ["loss", "duplicate"] and value > 1:
			return false
	return profile.get("seed", 0) is int

func _empty_stats() -> Dictionary:
	return {"packets_in":0, "bytes_in":0, "packets_out":0, "bytes_out":0,
		"dropped":0, "forced_dropped":0, "duplicated":0, "queue_dropped":0,
		"send_errors":0, "receive_errors":0, "unroutable":0, "queued":0}
