extends Node
## Loopback-only HTTP fixture. Records routes/payloads, never authentication headers.
var listener := TCPServer.new()
var port := 0
var requests: Array[String] = []
var connections: Array[Dictionary] = []
var membership := {"state":"none", "region":"test-region", "players":0}
var room_delay_ms := 0
var health_delay_ms := 0
var assignment_port := 0
var guest_count := 0
var delete_count := 0
var last_payload := {}
var health_build := WireCodec.BUILD
var fail_next_action := false
var oversize_health := false

func start(requested_port := 0) -> Error:
	# Keep the bound socket: no probe/close/rebind race or PID-derived port range.
	var error := listener.listen(requested_port, "127.0.0.1")
	if error != OK:
		print("HTTP fixture bind failed: 127.0.0.1:%d, %s (%d)" % [requested_port, error_string(error), error])
		return error
	port = listener.get_local_port()
	if port <= 0:
		listener.stop()
		print("HTTP fixture bind returned no assigned port")
		return ERR_CANT_CREATE
	return OK

func url() -> String:
	return "http://127.0.0.1:%d" % port

func _process(_delta: float) -> void:
	while listener.is_connection_available():
		connections.append({"peer":listener.take_connection(), "buffer":PackedByteArray(), "at":0, "reply":"", "sent":false})
	for item: Dictionary in connections.duplicate():
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if item.sent or peer.get_status() == StreamPeerTCP.STATUS_ERROR:
			peer.disconnect_from_host()
			connections.erase(item)
			continue
		if item.at > 0:
			if Time.get_ticks_msec() >= item.at:
				peer.put_data(str(item.reply).to_utf8_buffer())
				item.sent = true
			continue
		if peer.get_available_bytes() > 0:
			var read := peer.get_data(peer.get_available_bytes())
			if read[0] != OK:
				continue
			item.buffer.append_array(read[1])
		var text: String = item.buffer.get_string_from_utf8()
		var separator := text.find("\r\n\r\n")
		if separator < 0:
			continue
		var header := text.substr(0, separator)
		var length := 0
		for line: String in header.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = line.get_slice(":", 1).strip_edges().to_int()
		var body := text.substr(separator + 4)
		if body.to_utf8_buffer().size() < length:
			continue
		var line := header.get_slice("\r\n", 0)
		var route := line.get_slice(" ", 0) + " " + line.get_slice(" ", 1)
		requests.append(route)
		var data: Variant = JSON.parse_string(body) if length > 0 else {}
		respond(item, route, data if data is Dictionary else {})

func respond(item: Dictionary, route: String, data: Dictionary) -> void:
	var response := {}
	var code := 200
	var delay := 1
	match route:
		"GET /healthz":
			response = {"build":health_build, "protocol":WireCodec.PROTOCOL, "content_hash":ContentRegistry.new().content_hash, "region":"test-region"}
			if oversize_health:
				response["padding"] = "x".repeat(70000)
			delay = maxi(1, health_delay_ms)
		"POST /v1/guests":
			guest_count += 1
			response = {"player_id":"fixture-player", "access_token":"fixture-memory-only", "expires_at":Time.get_unix_time_from_system() + 3600, "region":"test-region"}
		"DELETE /v1/membership":
			delete_count += 1
			membership = {"state":"none", "region":"test-region", "players":0}
			response = membership
		"GET /v1/membership":
			response = membership
		"POST /v1/rooms", "POST /v1/queue", "POST /v1/rooms/join":
			last_payload = data.duplicate(true)
			if fail_next_action:
				fail_next_action = false
				code = 409
				response = {"error":{"code":"room_full", "message":"This game is full. Try another code."}}
			else:
				membership = {"state":"waiting", "room_id":"fixture-room", "code":"ABCD1234", "mode":data.get("mode", "teams"), "capacity":data.get("capacity", 4), "players":1, "region":"test-region"}
				if assignment_port > 0 and route != "POST /v1/queue":
					membership.state = "ready"
					membership["assignment"] = {"address":"127.0.0.1", "port":assignment_port, "admission_ticket":"fixture-ticket", "room_id":"fixture-room"}
				response = membership
				delay = maxi(1, room_delay_ms)
		_:
			code = 404
			response = {"error":{"message":"Unknown fixture route"}}
	var body := JSON.stringify(response)
	item.reply = "HTTP/1.1 %d OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [code, body.to_utf8_buffer().size(), body]
	item.at = Time.get_ticks_msec() + delay

func _exit_tree() -> void:
	listener.stop()
	for item: Dictionary in connections:
		item.peer.disconnect_from_host()
