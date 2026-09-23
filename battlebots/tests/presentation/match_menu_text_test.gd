extends SceneTree
## Detached match-flow layouts: enlarged text, dynamic records and keyboard actions.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _frames() -> void:
	for index: int in range(5):
		await process_frame

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

func _capture(label: String, extent: Vector2i) -> void:
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-match-text-%s-%d.png" % [label, extent.y]))

func _run() -> void:
	var extents: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560,1080)]
	if DisplayServer.get_name() == "headless":
		extents.append(Vector2i(3840, 2160))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var results := MatchResults.new()
	root.add_child(results)
	var view := {"match_id":"text-fixture", "phase":"results", "mode":"1v1", "winner":0,
		"scores":[2, 1], "remaining":20, "rounds":[{"round":1,"winner":0}, {"round":2,"winner":1}, {"round":3,"winner":-1}, {"round":4,"winner":-1}, {"round":5,"winner":0}]}
	var stats := {"damage":2147483647,"eliminations":2,"assists":0,"component_disables":3,"recoveries":1,"credits":{"total":250,"performance":150,"pickups":100}}
	results.render(view, 2147483647, 0)
	results.accept_record({"match":view, "participants":{2147483647:stats, 2147483646:stats}}, "text-fixture")
	results.mark_requested()
	for extent: Vector2i in extents:
		root.size = extent
		results.show()
		results.apply_text_scale(1.5)
		results.apply_text_scale(1.5)
		for details: bool in [false, true]:
			results.show_scores(details)
			await _frames()
			var bounds := Rect2(Vector2.ZERO, Vector2(extent))
			for control: Control in [results.heading, results.status, results.rematch, results.leave]:
				_check(bounds.encloses(control.get_global_rect()), "Results footer/header fits %s: %s" % [extent, control.name])
			_check(results.heading.get_theme_font_size("font_size") == 54, "Results heading scales once")
			if not details:
				_check(results.round_summary.get_parent().size.y >= 80, "Round history retains a readable scroll area")
			if details:
				_check(results.table.size.x <= results.scores_page.size.x, "Enlarged score table fits without horizontal scroll")
				var first_size: int = results.table.get_child(0).get_theme_font_size("font_size")
				results.scope.item_selected.emit(0)
				await _frames()
				_check(results.table.get_child(0).get_theme_font_size("font_size") == first_size, "Rebuilt table retains enlarged font")
			for node: Node in results.find_children("*", "ScrollContainer", true, false):
				if node.is_visible_in_tree():
					_check(node.get_v_scroll_bar().max_value <= node.get_v_scroll_bar().page + 1, "Duel results fit without scrolling %s/%s max=%s page=%s" % [extent, details, node.get_v_scroll_bar().max_value,node.get_v_scroll_bar().page])
			await _capture("scores" if details else "win", extent)
		results.apply_text_scale(1.25)
		_check(results.heading.get_theme_font_size("font_size") == 45, "Results supports intermediate scale")
		results.apply_text_scale(1.0)
		_check(results.heading.get_theme_font_size("font_size") == 36, "Results font restores")
	results.free()
	var reconnect := ReconnectPanel.new()
	root.add_child(reconnect)
	for extent: Vector2i in extents:
		root.size = extent
		reconnect.apply_text_scale(1.5)
		reconnect.render(true, false, 12.0)
		reconnect.retry.grab_focus()
		reconnect.apply_text_scale(1.5)
		_check(reconnect.retry.has_focus(), "Enlarging reconnect preserves keyboard focus")
		reconnect.render(true, true, 8.0)
		await _frames()
		_check(reconnect.retry.disabled and reconnect.heading.text == "RECONNECTING", "Enlarged reconnect reports active retry")
		await _capture("connecting", extent)
		reconnect.render(true, false, 8.0)
		reconnect.retry.grab_focus()
		reconnect.render(false, false, 0.0, "The server could not restore your match. Return to the main menu and start a new match.")
		await _frames()
		_check(reconnect.leave_button.has_focus(), "Reconnect expiry transfers focus")
		var body_scroll := reconnect.status.get_parent().get_parent() as ScrollContainer
		body_scroll.grab_focus()
		_check(body_scroll.has_focus(), "Reconnect explanatory body is keyboard reachable")
		reconnect.leave_button.grab_focus()
		for control: Control in [reconnect.heading, reconnect.retry, reconnect.leave_button]:
			_check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(control.get_global_rect()), "Reconnect fixed action/header fits %s" % extent)
		_check(not reconnect.retry.get_global_rect().intersects(reconnect.leave_button.get_global_rect()), "Reconnect actions remain separate")
		await _capture("reconnect", extent)
		reconnect.apply_text_scale(1.0)
		_check(reconnect.heading.get_theme_font_size("font_size") == 56, "Reconnect font restores")
	reconnect.free()
	var panel := PanelContainer.new()
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	panel.add_child(margin)
	var actions := VBoxContainer.new()
	actions.name = "Content"
	margin.add_child(actions)
	for label_name: String in ["Title", "Description"]:
		var label := Label.new()
		label.name = label_name
		actions.add_child(label)
	for action: String in ["Resume", "Settings", "Return"]:
		var button := Button.new()
		button.name = action
		actions.add_child(button)
	var page = load("res://scripts/ui/game_menu_page.gd").new()
	page.configure(panel)
	for action: String in ["Restart practice", "Audio settings", "HUD and menu settings"]:
		var button := Button.new()
		button.text = action
		button.add_theme_font_size_override("font_size", 34)
		button.custom_minimum_size.y = 76
		actions.add_child(button)
	for extent: Vector2i in extents:
		root.size = extent
		page.apply_text_scale(1.5)
		page.render({}, true)
		await _frames()
		var scroll := actions.get_parent() as ScrollContainer
		_check(scroll != null and scroll.follow_focus, "Game menu actions scroll with keyboard focus")
		var last := actions.get_child(actions.get_child_count() - 1) as Button
		last.grab_focus()
		await _frames()
		_check(scroll.get_global_rect().encloses(last.get_global_rect()), "Last enlarged game action scrolls into view")
		_check(page.context.get_theme_font_size("font_size") == 45, "Game context enlarged")
		await _capture("game", extent)
		page.apply_text_scale(1.0)
		_check(page.context.get_theme_font_size("font_size") == 30, "Game font restores")
	page.free()
	await _frames()
	for failure: String in failures:
		push_error(failure)
	print("MATCH MENU TEXT PASS" if failures.is_empty() else "MATCH MENU TEXT FAIL")
	quit(0 if failures.is_empty() else 1)
