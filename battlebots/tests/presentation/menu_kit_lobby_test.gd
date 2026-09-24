extends SceneTree
## Supplied lobby scenes over two isolated real UDP sessions; no invented players.
var failures := 0
var peers: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func until(predicate: Callable, limit := 600) -> bool:
	for index: int in range(limit):
		if predicate.call():
			return true
		await process_frame
	return false

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func make_peer(label: String) -> Dictionary:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(1920, 1080)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	set_multiplayer(SceneMultiplayer.new(), view.get_path())
	var session := MvpSession.new()
	session.name = "Session"
	view.add_child(session)
	var lobby: Control = load("res://ui/menus/screens/lobby.tscn").instantiate()
	lobby.session_override = session
	view.add_child(lobby)
	var peer := {"view":view, "session":session, "lobby":lobby}
	peers.append(peer)
	return peer

func local_slot(peer: Dictionary) -> Dictionary:
	for slot: Dictionary in peer.session.lobby_view.get("slots", []):
		if int(slot.get("entity_id", 0)) == peer.session.local_entity:
			return slot
	return {}

func run() -> void:
	if "--loading-only" in OS.get_cmdline_user_args():
		await loading_preview()
		print("MENU KIT LOADING PASS" if failures == 0 else "MENU KIT LOADING FAIL")
		quit(0 if failures == 0 else 1)
		return
	var router := root.get_node("MenuRouter")
	var profile := root.get_node("PlayerProfile")
	router.match_setup.mode = "team"
	profile.active_bot = 1
	var host := make_peer("KitHost")
	var client := make_peer("KitClient")
	var udp_port := 41000 + OS.get_process_id() % 9000
	host.lobby.port.value = udp_port
	client.lobby.port.value = udp_port
	client.lobby.address.text = "  "
	client.lobby.join_button.pressed.emit()
	check(client.session.connection_state == "offline", "Blank host address cannot open a connection")
	host.lobby.host_button.pressed.emit()
	check(host.session.player_capacity == 4 and host.session.connection_state == "hosting", "Team mode hosts actual four-player capacity")
	check(local_slot(host).get("loadout", {}).get("parts", {}).get("weapon") == "lifter", "Selected Controller loadout reaches host authority")
	client.lobby.address.text = " 127.0.0.1 "
	client.lobby.join_button.pressed.emit()
	check(client.lobby.address.text == "127.0.0.1", "Direct-IP join trims whitespace")
	var joined := await until(func() -> bool: return client.session.local_entity > 0 and client.session.lobby_view.get("slots", []).size() == 2)
	check(joined, "Kit lobby joins two real UDP peers")
	if joined:
		check(await until(func() -> bool: return local_slot(client).get("loadout", {}).get("parts", {}).get("weapon") == "lifter"), "Joined client submits selected canonical loadout")
		await ticks(3)
		client.lobby.refresh()
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var shot: Image = client.view.get_texture().get_image()
			check(shot.save_png("user://menu-kit-live-lobby.png") == OK, "Rendered lobby capture saves")
		check(client.lobby.get_node("%StatusBig").text == "2/4 PLAYERS", "Lobby reports real participant count without fake opponents")
		check(client.lobby.get_node("%Mate").get_node("%Name").text == "OPEN SLOT" and client.lobby.get_node("%Opp2").get_node("%Name").text == "OPEN SLOT", "Empty slots remain empty until connected players fill them")
		client.lobby.get_node("%Ready").pressed.emit()
		check(not local_slot(client).get("ready", false) and client.lobby.get_node("%Ready").text == "READY UP", "Ready click cannot optimistically mark local roster ready")
		check(await until(func() -> bool: return local_slot(client).get("ready", false)), "Server confirms client readiness")
		client.lobby.team_choice.item_selected.emit(0)
		check(await until(func() -> bool: return int(local_slot(client).get("team", -1)) == 0 and not local_slot(client).get("ready", true)), "Server moves client team and resets readiness")
		client.lobby.team_choice.item_selected.emit(1)
		check(await until(func() -> bool: return int(local_slot(client).get("team", -1)) == 1), "Client can return to opposing team")
		profile.active_bot = 0
		# Preset 0 is the Sawblade Tank since 312cb3a; expect whatever weapon it carries.
		var selected_weapon: String = profile.active_loadout().get("parts", {}).get("weapon", "")
		check(not selected_weapon.is_empty() and selected_weapon != "lifter", "Selected build differs from the loadout already on the server")
		client.lobby.build_button.pressed.emit()
		check(await until(func() -> bool: return local_slot(client).get("loadout", {}).get("parts", {}).get("weapon") == selected_weapon), "Use selected build updates server-accepted loadout")
		# Four-player setup must stay in lobby with two real players, even both ready.
		host.lobby.get_node("%Ready").pressed.emit()
		client.lobby.get_node("%Ready").pressed.emit()
		await ticks(60)
		check(host.session.match_state.phase == "lobby", "Two players cannot auto-start a four-player lobby")
		check(client.lobby.get_node("%StatusBig").text == "2/4 PLAYERS", "Waiting UI never invents a countdown")
		client.lobby.leave_lobby()
		check(client.session.connection_state == "offline", "Explicit menu leave closes only requested client session")
		check(host.session.connection_state == "hosting", "Other peer remains hosting after client leaves")
		host.session.leave()
		await ticks(3)
		router.match_setup.mode = "duel"
		host.lobby.host_button.pressed.emit()
		check(host.session.player_capacity == 2, "Duel selection starts two-player capacity")
		client.lobby.join_button.pressed.emit()
		check(await until(func() -> bool: return client.session.lobby_view.get("slots", []).size() == 2), "Both kit lobbies can reconnect for duel")
		await ticks(3)
		host.lobby.get_node("%Ready").pressed.emit()
		client.lobby.get_node("%Ready").pressed.emit()
		check(await until(func() -> bool: return client.session.match_view.get("phase") == "countdown"), "Two ready duel players reach actual server countdown")
		client.lobby.refresh()
		check(client.lobby.get_node("%Ready").disabled and client.lobby.team_choice.disabled and client.lobby.build_button.disabled, "Match lock disables readiness, team and build edits")
		check(not client.lobby.get_node("%Mate").visible and not client.lobby.get_node("%Opp2").visible, "Duel renders one slot per team")
	for index: int in range(peers.size() - 1, -1, -1):
		peers[index].session.leave()
	await process_frame
	for index: int in range(peers.size() - 1, -1, -1):
		var view: SubViewport = peers[index].view
		set_multiplayer(null, view.get_path())
		view.queue_free()
	await process_frame
	print("MENU KIT LOBBY PASS" if failures == 0 else "MENU KIT LOBBY FAIL")
	quit(0 if failures == 0 else 1)




func loading_preview() -> void:
	# Presentation-only fixture: no transport or match simulation is advanced.
	var router := root.get_node("MenuRouter")
	var fixture := MvpSession.new()
	fixture.name = "LoadingFixture"
	root.add_child(fixture)
	fixture.local_entity = 7
	fixture.lobby_view = {"capacity":4, "slots":[
		{"entity_id":7,"team":0,"loadout":fixture.registry.starter()},
		{"entity_id":8,"team":0,"loadout":fixture.registry.starter(true)},
		{"entity_id":9,"team":1,"loadout":fixture.registry.starter(true)}]}
	fixture.match_view = {"phase":"loading"}
	router.session = fixture
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920,1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var loading: Control = load("res://ui/menus/screens/loading.tscn").instantiate()
	viewport.add_child(loading)
	await ticks(3)
	check(loading.get_node("%BlueImage1").visible and loading.get_node("%BlueImage1").texture.resource_path.ends_with("bot_chevron.jpg"), "Spinner participant receives supplied spinner concept thumbnail")
	check(loading._blue_image2.visible and loading._blue_image2.texture.resource_path.ends_with("bot_rivetrex.jpg"), "Second blue participant receives lifter concept thumbnail")
	check(loading.get_node("%RedImage1").visible and not loading.get_node("%RedImage2").visible, "Populated red slot gets art while empty slot stays empty")
	check(loading.get_node("%BlueSub1").text.contains("YOU") and loading.get_node("%BlueSub1").text.contains("CONCEPT ART"), "Preview clearly labels local player and concept art")
	check(not loading.get_node("%Progress").visible, "Loading does not invent progress")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(viewport.get_texture().get_image().save_png("user://menu-kit-loading-populated.png") == OK, "Populated loading capture saves")
	fixture.lobby_view.slots.clear()
	loading._refresh()
	check(not loading.get_node("%BlueImage1").visible and not loading._blue_image2.visible and not loading.get_node("%RedImage1").visible, "Removed participants cannot leave stale concept images")
	router.session = null
	loading._refresh()
	check(loading.get_node("%ModeLine").text == "SESSION UNAVAILABLE", "Missing session shows unavailable instead of fake match")
	viewport.queue_free()
	fixture.queue_free()
	await process_frame
