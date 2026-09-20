extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames() -> void:
	for index in range(5):
		await process_frame
func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 720)
	var board := DuelScoreboard.new()
	root.add_child(board)
	var bot := BotView.new()
	bot.entity_id = 7
	bot.team = 1
	bot.server_tick = 8
	bot.core_fraction = 0.42
	var bots: Array[BotView] = [null, bot]
	var local := {"entity_id":7, "team":1, "connected":true, "loadout":{"name":"W".repeat(48)}}
	var rival := {"entity_id":8, "team":0, "connected":true}
	var lobby := {"slots":[local, rival]}
	var state := {"phase":"active", "round":2, "remaining":91.2, "scores":[0, 1]}
	board.render(state, lobby, bots, 7, "Tab")
	check(board.cards[0].wins.text == "1" and board.cards[1].wins.text == "0", "Scores follow local team")
	check(board.cards[0].core.text == "CORE 42%", "Accepted view supplies core; null is safe")
	check(board.cards[1].core.text == "CORE —", "Missing rival health is unknown")
	bot.team = 0
	board.render(state, lobby, bots, 7, "Tab")
	check(board.cards[0].core.text == "CORE —", "Wrong-team view rejected")
	bot.team = 1
	bots.append(bot)
	board.render(state, lobby, bots, 7, "Tab")
	check(board.cards[0].core.text == "CORE —", "Duplicate accepted views rejected")
	bots.pop_back()
	board.update_hold(true, true)
	check(board.visible, "Hold shows scoreboard")
	board.suppress(true)
	board.update_hold(true, true)
	check(not board.visible, "Held key cannot reopen after modal")
	board.update_hold(false, true)
	board.update_hold(true, true)
	check(board.visible, "Release rearms scoreboard")
	for extent in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080)]:
		root.size = extent
		for factor in [1.0, 1.5]:
			board.apply_accessibility(factor, "standard", false)
			board.render(state, lobby, bots, 7, "Shift + Ctrl + Backspace", true)
			await frames()
			check(Rect2(Vector2.ZERO, Vector2(extent)).encloses(board.panel.get_global_rect()), "Scoreboard fits %s at %s" % [extent, factor])
			check(board.hint.get_line_count() <= 2, "Release binding remains fully visible")
			check(board.hint.max_lines_visible == -1, "Release binding is never ellipsized")
			for label: Node in board.find_children("*", "Label", true, false):
				check(board.panel.get_global_rect().encloses(label.get_global_rect()), "Scoreboard contains full label: " + label.text)
				check(label.size.y + 1 >= label.get_minimum_size().y, "Scoreboard label has full height: " + label.text)
			check(board.cards[0].name.text == "W".repeat(48) and board.cards[0].name.max_lines_visible == -1, "Complete maximum-length bot name is available")
			if factor == 1.5 and "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://duel-scoreboard-%d.png" % extent.x)
	board.queue_free()
	await frames()
	if failures == 0:
		print("DUEL SCOREBOARD PASS")
	quit(0 if failures == 0 else 1)
