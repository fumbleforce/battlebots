class_name PublicServiceClient
extends Node
## Credentials stay in memory. One bounded HTTP request at a time; never log bodies.
signal changed
signal assignment_ready(assignment: Dictionary)
var endpoint := ""
var state := "idle"
var message := "Choose Quick Play, create a private game, or enter a friend's code."
var region := ""
var membership: Dictionary = {}
var _http: HTTPRequest
var _token := ""
var _expires_at := 0.0
var _generation := 0
var _flight_generation := 0
var _flight := ""
var _action := ""
var _payload := {}
var _cancel_requested := false
var _cleanup_required := false
var _next_poll := 0
var _assignment_delivered := false

func _ready() -> void:
	if endpoint.is_empty():
		endpoint = str(ProjectSettings.get_setting("services/matchmaking_url", ""))
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--matchmaking-url="):
				endpoint = arg.trim_prefix("--matchmaking-url=")
	endpoint = endpoint.trim_suffix("/")
	_http = HTTPRequest.new()
	_http.name = "Request"
	_http.body_size_limit = 65536
	_http.download_chunk_size = 4096
	_http.timeout = 10.0
	_http.max_redirects = 0
	add_child(_http)
	_http.request_completed.connect(_completed)
	if endpoint.is_empty():
		message = "Online play is not configured in this build. LAN and Practice are available from the main menu."
	elif not valid_endpoint(endpoint):
		state = "failed"
		message = "The online service address must use HTTPS."

static func valid_endpoint(value: String) -> bool:
	var expression := RegEx.new()
	expression.compile("^(https://[A-Za-z0-9.-]+|http://127\\.0\\.0\\.1|http://\\[::1\\])(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~/-]*)?\\z")
	return expression.search(value) != null

func available() -> bool:
	return valid_endpoint(endpoint)

func can_start() -> bool:
	return available() and _flight.is_empty() and not _cleanup_required and state in ["idle", "failed"]

func can_cancel() -> bool:
	return _cleanup_required or not _flight.is_empty() or state in ["requesting", "waiting", "starting", "ready", "connected"]

func quick_play() -> void:
	begin("queue", {})

func create_private(mode: String, capacity: int) -> void:
	if (mode == "teams" and capacity in [2, 4, 10]) or (mode == "ffa" and capacity in range(4, 9)):
		begin("rooms", {"mode":mode, "capacity":capacity})

func join_code(code: String) -> void:
	var normalized := code.strip_edges().to_upper()
	var expression := RegEx.new()
	expression.compile("^[A-Z0-9]{8}$")
	if expression.search(normalized) == null:
		message = "Enter the eight-character game code shared by your friend."
		changed.emit()
		return
	begin("join", {"code":normalized})

func begin(action: String, payload: Dictionary) -> void:
	if not can_start():
		return
	_generation += 1
	_action = action
	_payload = payload.duplicate(true)
	_assignment_delivered = false
	membership.clear()
	state = "requesting"
	message = "Checking online service…"
	changed.emit()
	_request("health", "/healthz", HTTPClient.METHOD_GET)

func cancel() -> void:
	_generation += 1
	_assignment_delivered = false
	_cancel_requested = true
	state = "canceling"
	message = "Leaving online game…"
	changed.emit()
	# Do not race DELETE against an accepted but unfinished POST. Let the one
	# in-flight request finish, suppress its assignment, then delete membership.
	if _flight.is_empty():
		_cleanup()

func _cleanup() -> void:
	if not _token.is_empty() and _cleanup_required:
		_request("delete", "/v1/membership", HTTPClient.METHOD_DELETE)
	else:
		_cancelled()

func _cancelled() -> void:
	_cancel_requested = false
	_cleanup_required = false
	membership.clear()
	state = "idle"
	message = "Choose Quick Play, create a private game, or enter a friend's code."
	changed.emit()

func game_connected() -> void:
	if state == "ready" and not _cancel_requested:
		state = "connected"
		message = "Connected to the game. Choose your bot and Ready."
		changed.emit()

func game_failed() -> void:
	if state in ["ready", "connected"]:
		_fail("Could not connect to the game server. Cancel to leave this room, then try again.")

func _process(_delta: float) -> void:
	if state in ["waiting", "starting"] and _flight.is_empty() and Time.get_ticks_msec() >= _next_poll:
		_next_poll = Time.get_ticks_msec() + 1000
		_request("membership", "/v1/membership", HTTPClient.METHOD_GET)

func _request(operation: String, path: String, method: HTTPClient.Method, data := {}) -> void:
	if not _flight.is_empty():
		return
	_flight = operation
	_flight_generation = _generation
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if operation not in ["health", "guest"]:
		headers.append("Authorization: Bearer " + _token)
	var error := _http.request(endpoint + path, headers, method, "" if method in [HTTPClient.METHOD_GET, HTTPClient.METHOD_DELETE] else JSON.stringify(data))
	if error != OK:
		_flight = ""
		_cancel_requested = false
		_fail("Could not start the online request. Check your connection and try again.")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _flight
	var generation := _flight_generation
	_flight = ""
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if body.size() <= 65536 and not body.is_empty() else {}
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and parsed is Dictionary
	if operation == "guest" and ok:
		var token: Variant = parsed.get("access_token")
		if token is String and token.length() in range(1, 4097) and not token.contains("\n") and not token.contains("\r"):
			_token = token
			_expires_at = float(parsed.get("expires_at", 0))
		else:
			ok = false
	if operation == "delete":
		if ok or code == 401:
			if code == 401:
				_token = ""
			_cancelled()
		else:
			_cancel_requested = false
			_fail("Could not confirm leaving the room. Use Cancel to retry.")
		return
	if _cancel_requested or generation != _generation:
		_cleanup()
		return
	if not ok:
		var detail := ""
		if parsed is Dictionary and parsed.get("error") is Dictionary and parsed.error.get("message") is String:
			detail = str(parsed.error.message).left(240)
			if not _token.is_empty():
				detail = detail.replace(_token, "[hidden]")
		if code == 401:
			_token = ""
		_fail(detail if not detail.is_empty() else ("Online request failed. Check your connection and try again." if code == 0 else ("Online service is busy. Please try again shortly." if code == 429 else "Online request failed (HTTP %d). Check the code or try again." % code)))
		return
	var data: Dictionary = parsed
	if operation == "health":
		var registry := ContentRegistry.new()
		if data.get("build") != WireCodec.BUILD or data.get("protocol") != WireCodec.PROTOCOL or data.get("content_hash") != registry.content_hash:
			_fail("This game build does not match the online service. Install the current game build.")
			return
		region = str(data.get("region", "")).left(80)
		if _token.is_empty() or _expires_at <= Time.get_unix_time_from_system() + 30:
			_token = ""
			_request("guest", "/v1/guests", HTTPClient.METHOD_POST, {"build":WireCodec.BUILD, "protocol":WireCodec.PROTOCOL, "content_hash":registry.content_hash})
		else:
			_start_action()
	elif operation == "guest":
		_start_action()
	else:
		_accept_membership(data)

func _start_action() -> void:
	_cleanup_required = true # POST may commit even if its response is interrupted.
	var path := "/v1/rooms/join" if _action == "join" else "/v1/" + _action
	_request("action", path, HTTPClient.METHOD_POST, _payload)

func _accept_membership(data: Dictionary) -> void:
	var next := str(data.get("state", ""))
	if next not in ["none", "waiting", "starting", "ready", "failed"]:
		_fail("The online service returned an invalid room state.")
		return
	membership = data.duplicate(true)
	membership.erase("assignment")
	region = str(data.get("region", region)).left(80)
	state = next
	_next_poll = Time.get_ticks_msec() + 1000
	match state:
		"none":
			_cleanup_required = false
			_fail("No online game is reserved. Choose a game to try again.")
		"waiting": message = "Waiting for players… %d / %d" % [int(data.get("players", 0)), int(data.get("capacity", 4))]
		"starting": message = "Starting your game server…"
		"failed": message = "The game server could not start. Cancel to leave this room and try again."
		"ready":
			var assignment: Variant = data.get("assignment")
			if not assignment is Dictionary or not valid_assignment(assignment):
				_fail("The online service returned an invalid game assignment.")
				return
			message = "Connecting to the game server…"
			if not _assignment_delivered:
				_assignment_delivered = true
				assignment_ready.emit(assignment.duplicate(true))
	changed.emit()

static func valid_assignment(value: Dictionary) -> bool:
	var address: Variant = value.get("address")
	var ticket: Variant = value.get("admission_ticket")
	var port: Variant = value.get("port")
	return address is String and not address.is_empty() and address.length() <= 253 and not address.contains(" ") and not address.contains("\n") \
		and ticket is String and not ticket.is_empty() and ticket.length() <= 4096 and (port is int or port is float) and float(port) == int(port) and int(port) in range(1, 65536)

func _fail(text: String) -> void:
	state = "failed"
	message = text
	changed.emit()
