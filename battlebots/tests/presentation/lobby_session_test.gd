extends SceneTree
## Real UDP lobby requests through B's adapter; authority remains in MvpSession.
var failures := 0
var peers: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, limit := 900) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await process_frame
	return false

func make_peer(label: String) -> Dictionary:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	root.add_child(view)
	set_multiplayer(SceneMultiplayer.new(), view.get_path())
	var container := Node.new()
	container.name = "Fixture"
	var session := MvpSession.new()
	session.name = "Session"
	container.add_child(session)
	var panel = preload("res://scenes/ui/lobby_panel.tscn").instantiate()
	container.add_child(panel)
	var coordinator := LobbyCoordinator.new()
	container.add_child(coordinator)
	view.add_child(container)
	coordinator.bind(session, panel)
	var peer := {"view":view, "session":session, "panel":panel, "coordinator":coordinator}
	peers.append(peer)
	return peer

func local_slot(peer: Dictionary) -> Dictionary:
	for slot: Dictionary in peer.session.lobby_view.get("slots", []):
		if slot.get("entity_id") == peer.session.local_entity:
			return slot
	return {}

func ready(peer: Dictionary) -> bool:
	return local_slot(peer).get("ready", false)

func same_build(actual: Dictionary, expected: Dictionary) -> bool:
	return int(actual.get("schema_version", -1)) == int(expected.get("schema_version", -2)) \
		and actual.get("name") == expected.get("name") and actual.get("parts") == expected.get("parts") \
		and actual.get("cosmetics") == expected.get("cosmetics") and actual.get("content_hash") == expected.get("content_hash")

func run() -> void:
	var host := make_peer("LobbyHost")
	var client := make_peer("LobbyClient")
	var port := 28000 + OS.get_process_id() % 10000
	client.coordinator.request_join("   ", port)
	check(client.session.connection_state == "offline", "Blank join preserves offline session")
	check(not client.coordinator.notice.is_empty(), "Blank join offers visible guidance")
	host.coordinator.request_host(port, 4)
	check(host.session.connection_state == "hosting", "Adapter starts real UDP host")
	check(host.session.lobby_view.get("capacity") == 4, "Standard host exposes four authoritative slots")
	var host_team: int = local_slot(host).team
	for invalid_team: Variant in [true, "1", 0.5, -1, 2, null]:
		# Exercise the authority's request validator, never write its player state.
		host.session._handle_request(1, {"kind":"team", "value":invalid_team})
		check(local_slot(host).team == host_team, "Malformed team value is rejected: %s" % str(invalid_team))
	client.coordinator.request_join(" 127.0.0.1 ", port)
	check(client.session.connection_state == "connecting", "Trimmed IP enters actual connecting state")
	var admitted := await until(func() -> bool: return client.session.local_entity > 0 and local_slot(client).size() > 0)
	check(admitted, "Adapter joins real ENet lobby")
	if admitted:
		client.coordinator.request_ready_state(true)
		check(not ready(client), "Ready request does not optimistically rewrite client lobby")
		check(await until(func() -> bool: return ready(client)), "Server acknowledgement makes client ready")
		check(not ready(host) and client.session.match_view.get("phase", "lobby") == "lobby",
			"One ready player cannot start an incomplete four-player lobby")
		var original_team: int = local_slot(client).team
		client.coordinator.request_team(1 - original_team)
		check(await until(func() -> bool: return local_slot(client).get("team") == 1 - original_team),
			"Team request reaches server when target team has space")
		check(not ready(client), "Authoritative team change clears readiness")
		client.coordinator.request_ready_state(true)
		check(await until(func() -> bool: return ready(client)), "Client can ready after team switch")
		var controller: Dictionary = client.session.registry.starter(true)
		client.coordinator.request_loadout(controller)
		check(await until(func() -> bool: return same_build(local_slot(client).get("loadout", {}), controller)),
			"Validated Controller build is acknowledged over UDP")
		check(not ready(client), "Authoritative loadout change clears readiness")
		client.coordinator.request_ready_state(true)
		check(await until(func() -> bool: return ready(client)), "Client can ready with Controller")
		var invalid := controller.duplicate(true)
		invalid.parts.weapon = "missing_weapon"
		client.coordinator.request_loadout(invalid)
		check(client.coordinator.pending_kind.is_empty(), "Invalid draft is rejected before sending")
		check(not client.coordinator.notice.is_empty(), "Invalid draft explains validation failure")
		check(same_build(local_slot(client).loadout, controller) and ready(client),
			"Invalid draft preserves confirmed build and readiness")
		client.coordinator.refresh()
		check(client.panel.notice_label.text == client.coordinator.notice, "Validation failure reaches visible panel")
		# Suspend actual network polling: no synthetic lobby records or acknowledgements.
		multiplayer_poll = false
		client.coordinator.request_ready_state(false)
		check(client.coordinator.pending_kind == "ready", "Unacknowledged change enters pending state")
		check(await until(func() -> bool: return client.coordinator.pending_kind.is_empty(), 300),
			"Missing server acknowledgement times out in real time")
		check(ready(client) and not client.coordinator.notice.is_empty(),
			"Timeout preserves confirmed readiness and explains missing confirmation")
		multiplayer_poll = true
		check(await until(func() -> bool: return not ready(client)), "Late authoritative acknowledgement still updates lobby")
		client.coordinator.request_ready_state(true)
		check(await until(func() -> bool: return ready(client)), "Readiness can be requested again after timeout")
		# A UI adapter has no ownership of its session or transport lifetime.
		client.coordinator.free()
		check(client.session.connection_state == "connected", "Removing lobby presentation leaves session connected")
		client.coordinator = LobbyCoordinator.new()
		client.view.get_node("Fixture").add_child(client.coordinator)
		client.coordinator.bind(client.session, client.panel)
		check(ready(client), "Rebinding reads existing authoritative readiness")
	client.coordinator.request_leave()
	host.coordinator.request_leave()
	check(client.session.connection_state == "offline" and host.session.connection_state == "offline",
		"Explicit leave closes both sessions")
	await process_frame
	host.coordinator.request_host(port, 2)
	check(host.session.lobby_view.get("capacity") == 2, "Explicit 1v1 rehost has two authoritative slots")
	client.coordinator.request_join("127.0.0.1", port)
	admitted = await until(func() -> bool: return client.session.local_entity > 0 and local_slot(client).size() > 0)
	check(admitted, "Same adapters reconnect after leave")
	if admitted:
		host.coordinator.request_ready_state(true)
		client.coordinator.request_ready_state(true)
		check(await until(func() -> bool: return client.session.match_view.get("phase") == "active"),
			"Two ready players enter actual active match")
		var confirmed := local_slot(client).duplicate(true)
		client.coordinator.request_team(1 - int(confirmed.get("team", 0)))
		check(client.coordinator.pending_kind.is_empty(), "Active match team edits are rejected locally")
		client.coordinator.request_loadout(client.session.registry.starter(true))
		check(client.coordinator.pending_kind.is_empty(), "Active match build edits are rejected locally")
		client.coordinator.request_ready_state(false)
		check(client.coordinator.pending_kind.is_empty(), "Active match ready edits are rejected locally")
		check(local_slot(client) == confirmed, "Rejected active-match edits preserve confirmed roster")
		client.coordinator.refresh()
		check(client.panel.ready_button.disabled and client.panel.team_choice.disabled and client.panel.loadout_choice.disabled,
			"Actual match phase disables lobby edit controls")
	for peer: Dictionary in peers:
		peer.coordinator.request_leave()
		peer.coordinator.bind(null, peer.panel)
		check(peer.panel.status_label.text.to_lower().contains("unavailable"),
			"Detached adapter renders unavailable without accessing a missing session")
		peer.view.free()
	await process_frame
	print("LOBBY SESSION PASS" if failures == 0 else "LOBBY SESSION FAIL")
	quit(0 if failures == 0 else 1)
