extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func settle() -> void:
	for frame: int in 8:
		await process_frame
func inspect(screen: Control, context: String) -> void:
	check(screen.size.x <= 1921 and screen.size.y <= 1081, context + " root remains within design canvas")
	for node: Node in screen.find_children("*", "Control", true, false):
		if not node is Label and not node is Button and not node is LineEdit:
			continue
		var control := node as Control
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		check(rect.position.x >= -1 and rect.end.x <= 1921, context + " horizontal bounds " + str(screen.get_path_to(control)))
		var ancestor := control.get_parent()
		var scrollable := false
		while ancestor != screen and ancestor != null:
			if ancestor is ScrollContainer:
				scrollable = true
			ancestor = ancestor.get_parent()
		if not scrollable:
			check(rect.position.y >= -1 and rect.end.y <= 1081, context + " vertical bounds " + str(screen.get_path_to(control)))
		if control is Label:
			check(control.size.y + 1 >= control.get_minimum_size().y, context + " text height " + str(screen.get_path_to(control)))
func run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var router := root.get_node("MenuRouter")
	router.match_setup.mode = "duel"
	var session := MvpSession.new()
	root.add_child(session)
	router.session = session
	var service := PublicServiceClient.new()
	service.endpoint = "https://fixture.invalid"
	root.add_child(service)
	service.set_process(false)
	for screen_name: String in ["main_menu", "online", "lobby", "mode_select", "arena_select", "loading"]:
		var screen: Control = load("res://ui/menus/screens/" + screen_name + ".tscn").instantiate()
		if screen_name == "online":
			screen.service_override = service
		if screen_name == "lobby":
			screen.session_override = session
		root.add_child(screen)
		var baseline_sizes := {}
		for label: Node in screen.find_children("*", "Label", true, false):
			baseline_sizes[label] = label.get_theme_font_size("font_size")
		for factor: float in [1.0, 1.25, 1.5, 1.0]:
			screen.apply_text_scale(factor)
			for label: Label in baseline_sizes:
				check(label.get_theme_font_size("font_size") == roundi(baseline_sizes[label] * factor), screen_name + " scales each heading/body from its baseline")
			for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(3840,2160)]:
				root.size = resolution
				await settle()
				inspect(screen, "%s %.2f %s" % [screen_name, factor, resolution])
		if screen_name == "main_menu":
			screen.apply_text_scale(1.5)
			screen.get_node("%Quit").grab_focus()
			await settle()
			check(Rect2(0, 0, 1920, 1080).encloses(screen.get_node("%Quit").get_global_rect()), "Last main-menu action remains visible without scrolling")
			screen.get_node("%PlayOnline").grab_focus()
		if screen_name == "arena_select":
			screen.apply_text_scale(1.5)
			screen._select(0)
			await settle()
			for row: Node in screen.get_node("%Hazards").get_children():
				if not row.is_queued_for_deletion():
					check(row.get_child(1).get_theme_font_size("font_size") == 30, "New hazard rows inherit enlarged text")
		if screen_name == "online":
			screen.apply_text_scale(1.5)
			for state: String in ["failed", "waiting", "canceling"]:
				service.state = state
				service.message = "Could not connect to the online service. Check your connection and try again."
				service.membership = {"code":"DUEL1234"} if state != "failed" else {}
				service.changed.emit()
				await settle()
				inspect(screen, "online " + state)
		if screen_name == "lobby":
			screen.apply_text_scale(1.5)
			for intent: String in ["join", "host"]:
				router.lobby_intent = intent
				screen.refresh()
				await settle()
				inspect(screen, "lobby " + intent)
			session.connection_state = "connected"
			session.local_entity = 1
			session.lobby_view = {"mode":"teams", "capacity":2, "slots":[{"entity_id":1, "team":0, "connected":true, "ready":false, "loadout":root.get_node("PlayerProfile").active_loadout()}]}
			screen.refresh()
			await settle()
			inspect(screen, "lobby connected")
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			root.size = Vector2i(1920, 1080)
			screen.apply_text_scale(1.5)
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://menu-text-" + screen_name + ".png")
		screen.queue_free()
		await settle()
	router.session = null
	session.queue_free()
	service.queue_free()
	await settle()
	print("MENU TEXT SCREENS PASS" if failures == 0 else "MENU TEXT SCREENS FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
