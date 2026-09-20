extends SceneTree
## Detached menu presentation fixture. Runtime networking is covered by menu_kit_lobby_test.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for index: int in range(5):
		await process_frame

func run() -> void:
	var router := root.get_node("MenuRouter")
	router.match_setup.mode = "duel"
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var view := SubViewport.new()
		view.size = resolution
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var fixture := MvpSession.new()
		root.add_child(fixture)
		for intent: String in ["host", "join"]:
			router.lobby_intent = intent
			var lobby: Control = load("res://ui/menus/screens/lobby.tscn").instantiate()
			lobby.session_override = fixture
			view.add_child(lobby)
			# The application shell uses this exact reference canvas and scaling.
			lobby.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			lobby.size = Vector2(1920, 1080)
			lobby.scale = Vector2.ONE * (float(resolution.x) / 1920.0)
			await settle()
			check(lobby._connection_panel.visible, "Offline direct connection exposes endpoint panel")
			check(lobby._address_field.visible == (intent == "join"), "Address field is labelled and only shown for join")
			check(lobby.host_button.visible == (intent == "host"), "Only intended connection action is visible")
			check(lobby.get_node("Layout/Body/Row/Blue").visible == false, "Offline connection has no empty player columns")
			await inspect(lobby, view, intent, resolution)
			fixture.connection_state = "connecting"
			lobby.refresh()
			await settle()
			check(not lobby._connection_panel.visible and lobby.get_node("%Back").text == "CANCEL CONNECTION", "Connecting keeps explicit cancellation available")
			check(lobby.get_node("%StatusBig").text == "CONNECTING…", "Connecting has clear pending state")
			await inspect(lobby, view, "connecting", resolution)
			fixture.connection_state = "offline"
			lobby._notice = "Connection failed. Check the host address and public UDP port, then try again."
			lobby.refresh()
			await settle()
			check(lobby._connection_panel.visible and not lobby.join_button.disabled, "Failure permits retry using the same endpoint controls")
			await inspect(lobby, view, "retry", resolution)
			fixture.connection_state = "connected"
			fixture.local_entity = 1
			fixture.lobby_view = {"mode":"1v1", "capacity":2, "phase":"lobby", "slots":[
				{"entity_id":1,"team":0,"connected":true,"ready":false,"loadout":fixture.registry.starter()},
				{"entity_id":2,"team":1,"connected":true,"ready":true,"loadout":fixture.registry.starter(true)}]}
			lobby._notice = "Connected. Choose your build, then ready up."
			lobby.refresh()
			await settle()
			check(not lobby._connection_panel.visible, "Connected lobby hides networking setup")
			check(lobby.get_node("%StatusBig").text == "2/2 PLAYERS", "Connected duel reports authoritative capacity")
			check(not lobby.get_node("%Mate").visible and not lobby.get_node("%Opp2").visible, "Duel shows one player per team")
			check(lobby.get_node("%Ready").visible and not lobby.get_node("%Ready").disabled, "Connected player can ready")
			await inspect(lobby, view, "connected", resolution)
			lobby.queue_free()
			await process_frame
			fixture.connection_state = "offline"
			fixture.lobby_view = {}
		router.lobby_intent = "online"
		var online: Control = load("res://ui/menus/screens/lobby.tscn").instantiate()
		online.session_override = fixture
		view.add_child(online)
		online.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		online.size = Vector2(1920, 1080)
		online.scale = Vector2.ONE * (float(resolution.x) / 1920.0)
		for text_scale in [1.0, 1.5]:
			online.apply_text_scale(text_scale)
			fixture.connection_state = "connecting"
			online.refresh()
			await settle()
			check(online.get_node("%Eyebrow").text == "ONLINE MATCH · CONNECTION" and online.get_node("%StatusBig").text == "CONNECTING TO YOUR GAME…", "Hosted admission uses online connection language")
			check(not online._connection_panel.visible and online.get_node("%Back").text == "CANCEL CONNECTION", "Hosted connection has cancellation without direct endpoint controls")
			await inspect(online, view, "online-connecting-%d" % roundi(text_scale * 100), resolution)
			fixture.connection_state = "connected"
			online.refresh()
			check(online.get_node("%StatusBig").text == "WAITING FOR GAME DETAILS…", "Connected transport without baseline waits for actual game data")
			fixture.connection_state = "offline"
			online._session_event("error", {"message":"Admission expired. Return to Play Online and try again."})
			await settle()
			check(online.get_node("%StatusBig").text == "ONLINE CONNECTION UNAVAILABLE" and online.get_node("%StatusSub").text.contains("Admission expired"), "Hosted failure preserves reason and never suggests hosting locally")
			check(not online._connection_panel.visible, "Hosted failure does not expose direct host controls")
			await inspect(online, view, "online-failed-%d" % roundi(text_scale * 100), resolution)
			online._session_event("left", {})
			check(online.get_node("%StatusSub").text.contains("Return to Play Online"), "Hosted leave directs the player back to online admission")
		online.queue_free()
		await process_frame
		fixture.queue_free()
		view.queue_free()
		await process_frame
	print("LOBBY PANEL LAYOUT PASS" if failures == 0 else "LOBBY PANEL LAYOUT FAIL")
	quit(0 if failures == 0 else 1)

func inspect(lobby: Control, view: SubViewport, state: String, resolution: Vector2i) -> void:
	var scale_factor := float(resolution.x) / 1920.0
	for path: String in ["Layout/Header", "Layout/Footer", "Layout/Body/Row/Match", "%Back", "%Ready"]:
		var control := lobby.get_node(path) as Control
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		check(rect.end.x <= resolution.x + 1 and rect.end.y <= resolution.y + 1, "%s fits %s in %s: %s" % [path, resolution, state, rect])
	check(lobby.get_node("Layout").size.y <= 1081, "Content stays within reference canvas at %s" % state)
	check(lobby.port.size.y * scale_factor >= 40.0, "Endpoint input remains readable at %s" % resolution)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var output := "user://lobby-%s-%d.png" % [state, resolution.x]
		check(view.get_texture().get_image().save_png(output) == OK, "Capture saved")
		print(ProjectSettings.globalize_path(output))
