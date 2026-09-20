extends SceneTree
const FakeApi := preload("res://tests/fixtures/fake_public_api.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return false

func run() -> void:
	var api := FakeApi.new()
	root.add_child(api)
	if api.start() != OK:
		quit(1)
		return
	var client := PublicServiceClient.new()
	client.endpoint = api.url()
	root.add_child(client)
	for capabilities: Variant in [null, [4], "2", {"2":true}]:
		api.queue_capacities = capabilities
		client.quick_play()
		check(await until(func() -> bool: return client.state == "failed"), "Unsupported duel queue fails clearly")
		check(client.can_start() and not client.can_cancel() and api.guest_count == 0 and not api.requests.has("POST /v1/queue"), "Capability rejection creates no guest or membership and permits retry")
	client.create_private("teams", 2)
	check(await until(func() -> bool: return client.state == "waiting"), "Private duel remains compatible with older service health")
	client.cancel()
	check(await until(func() -> bool: return client.state == "idle"), "Private membership cleans up")
	api.queue_capacities = [2, 4]
	api.unauthorized_route = "POST /v1/queue"
	client.quick_play()
	check(await until(func() -> bool: return client.state == "failed"), "Expired guest on allocation fails visibly")
	check(client.can_start() and not client.can_cancel() and client.membership.is_empty() and client._token.is_empty(), "Expired allocation clears credentials and cleanup lock")
	check(api.requests.count("POST /v1/queue") == 1 and api.guest_count == 1, "Expired allocation does not silently reauthenticate or replay")
	client.quick_play()
	check(await until(func() -> bool: return client.state == "waiting"), "Explicit retry gets a fresh guest and queues")
	check(api.guest_count == 2 and api.last_payload.size() == 1 and api.last_payload.get("capacity") == 2 and client.membership.get("code") == "" and client.message.contains("opponent"), "Duel queue requests two players with appropriate waiting text")
	api.unauthorized_route = "GET /v1/membership"
	client._next_poll = 0
	check(await until(func() -> bool: return client.state == "failed"), "Expired polling session fails visibly")
	check(client.can_start() and not client.can_cancel() and client.membership.is_empty() and client.message.contains("expired"), "Expired polling membership leaves an actionable menu")
	api.room_delay_ms = 200
	api.unauthorized_route = "POST /v1/queue"
	client.quick_play()
	check(await until(func() -> bool: return api.requests.count("POST /v1/queue") == 3), "Cancellation test reaches pending allocation")
	client.cancel()
	check(await until(func() -> bool: return client.state == "idle"), "Cancellation wins over late unauthorized allocation")
	check(client.can_start() and client.membership.is_empty(), "Canceled expired operation cannot revive membership")
	client.queue_free()
	api.queue_free()
	await process_frame
	print("DUEL QUICK PLAY CLIENT PASS" if failures == 0 else "DUEL QUICK PLAY CLIENT FAIL")
	quit(0 if failures == 0 else 1)
