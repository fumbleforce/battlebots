extends SceneTree
const FakeApi := preload("res://tests/fixtures/fake_public_api.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var first := FakeApi.new()
	var second := FakeApi.new()
	root.add_child(first)
	root.add_child(second)
	check(first.start() == OK and first.port > 0, "OS assigns a real loopback listener")
	check(second.start() == OK and second.port > 0 and second.port != first.port,
		"Concurrent fixture avoids an occupied listener without retries")
	# Occupy a throwaway listener, never the one the health request below uses:
	# on Windows a refused bind on a port can disturb that port's listener.
	var holder := FakeApi.new()
	root.add_child(holder)
	check(holder.start() == OK, "A throwaway listener binds")
	var occupied := FakeApi.new()
	root.add_child(occupied)
	var bind_error: Error = occupied.start(holder.port)
	check(bind_error != OK and occupied.port == 0 and not occupied.listener.is_listening(),
		"Explicit occupied port returns actual bind failure without inventing an endpoint")
	occupied.queue_free()
	holder.queue_free()
	check(first.url() == "http://127.0.0.1:%d" % first.listener.get_local_port(), "Advertised endpoint matches bound socket")
	var request := HTTPRequest.new()
	root.add_child(request)
	var reply: Array = []
	# The same request timeout as PublicServiceClient: a cold Windows runner can
	# take several seconds to connect and build the first health reply (#13).
	request.timeout = PublicServiceClient.REQUEST_TIMEOUT
	request.request_completed.connect(func(result: int, status: int, headers: PackedStringArray, body: PackedByteArray) -> void:
		var text := body.get_string_from_utf8()
		reply.assign([result, status, JSON.parse_string(text) if not text.is_empty() else null, headers, body.size()]))
	check(request.request(first.url() + "/healthz") == OK, "Assigned endpoint accepts a real HTTP request")
	var started := Time.get_ticks_msec()
	var deadline := started + int(request.timeout * 1000.0) + 1000
	while reply.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	var healthy: bool = reply.size() == 5 and reply[0] == HTTPRequest.RESULT_SUCCESS and reply[1] == 200 and reply[2] is Dictionary
	print("Health reply after %d ms" % (Time.get_ticks_msec() - started))
	if not healthy:
		print("Health reply: ", reply, " fixture requests: ", first.requests, " open connections: ", first.connections.size())
	check(healthy, "Real loopback health request succeeds")
	var released_port: int = second.port
	second.queue_free()
	await process_frame
	var reused := FakeApi.new()
	root.add_child(reused)
	check(reused.start(released_port) == OK, "Fixture cleanup releases its bound port for reuse")
	request.queue_free()
	first.queue_free()
	reused.queue_free()
	await process_frame
	print("HTTP FIXTURE PORT PASS" if failures == 0 else "HTTP FIXTURE PORT FAIL")
	quit(0 if failures == 0 else 1)
