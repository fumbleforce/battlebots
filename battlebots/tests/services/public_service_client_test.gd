extends SceneTree
const FakeApi := preload("res://tests/fixtures/fake_public_api.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, seconds := 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func run() -> void:
	check(PublicServiceClient.valid_endpoint("https://games.example.com") and PublicServiceClient.valid_endpoint("http://127.0.0.1:1234") and PublicServiceClient.valid_endpoint("http://[::1]:1234"), "HTTPS and literal-loopback testing endpoints are accepted")
	for endpoint: String in ["http://games.example.com", "http://localhost:1234", "https://user:pass@example.com", "https://example.com?token=x", "https://example.com\n"]:
		check(not PublicServiceClient.valid_endpoint(endpoint), "Unsafe or credential-bearing endpoint is rejected")
	var api := FakeApi.new()
	root.add_child(api)
	check(api.start() == OK, "HTTP fixture binds loopback")
	var client := PublicServiceClient.new()
	client.endpoint = api.url()
	root.add_child(client)
	var assignments: Array = []
	client.assignment_ready.connect(func(value: Dictionary) -> void: assignments.append(value))
	api.assignment_port = 24567
	api.room_delay_ms = 250
	client.create_private("ffa", 5)
	check(await until(func() -> bool: return api.requests.has("POST /v1/rooms")), "Create performs health and guest handshake before room request")
	check(api.guest_count == 1 and api.last_payload.get("mode") == "ffa" and int(api.last_payload.get("capacity", 0)) == 5, "Private room carries selected mode and capacity")
	client.cancel()
	client.quick_play()
	check(await until(func() -> bool: return client.state == "idle" and api.delete_count == 1), "Cancel serializes DELETE after pending room response")
	check(assignments.is_empty() and api.membership.state == "none", "Cancelled late assignment never connects or leaves membership behind")
	check(not api.requests.has("POST /v1/queue"), "New action cannot race membership cleanup")
	api.room_delay_ms = 0
	client.quick_play()
	check(await until(func() -> bool: return client.state == "waiting"), "Quick Play waits for four-player matchmaking")
	check(client.membership.capacity == 4 and client.region == "test-region", "Quick Play displays four slots and region")
	check(await until(func() -> bool: return api.requests.has("GET /v1/membership"), 2.5), "Waiting membership polls through actual HTTP")
	client.cancel()
	check(await until(func() -> bool: return client.state == "idle"), "Queue cancellation clears actual membership")
	client.join_code(" abcd1234 ")
	check(await until(func() -> bool: return client.state == "ready"), "Room code joins and produces assignment")
	check(api.last_payload.code == "ABCD1234" and assignments.size() == 1, "Normalized code yields exactly one assignment")
	check(not client.membership.has("assignment") and client.state != "connected", "Public room view excludes admission credentials and assignment does not claim ENet connection")
	client.game_connected()
	check(client.state == "connected", "Only explicit multiplayer welcome marks game connected")
	client.cancel()
	check(await until(func() -> bool: return client.state == "idle"), "Connected room cleanup completes")
	api.fail_next_action = true
	client.join_code("ABCD1234")
	check(await until(func() -> bool: return client.state == "failed"), "HTTP room errors are handled")
	check(client.message.contains("This game is full"), "Nested service errors are actionable in the UI")
	client.cancel()
	check(await until(func() -> bool: return client.state == "idle"), "Error cleanup permits a clean retry")
	api.health_build = "different-build"
	var previous := api.requests.count("POST /v1/rooms")
	client.create_private("teams", 2)
	check(await until(func() -> bool: return client.state == "failed"), "Incompatible service fails before allocation")
	check(api.requests.count("POST /v1/rooms") == previous, "Build mismatch cannot create a room")
	api.health_build = WireCodec.BUILD
	api.oversize_health = true
	client.quick_play()
	check(await until(func() -> bool: return client.state == "failed"), "Oversized response is rejected by bounded HTTP request")
	api.oversize_health = false
	api.health_delay_ms = 600
	client._http.timeout = 0.1
	client.quick_play()
	check(await until(func() -> bool: return client.state == "failed"), "HTTP timeout produces recoverable failure")
	client.queue_free()
	api.queue_free()
	await process_frame
	print("PUBLIC SERVICE CLIENT PASS" if failures == 0 else "PUBLIC SERVICE CLIENT FAIL")
	quit(0 if failures == 0 else 1)
