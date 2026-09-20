extends SceneTree
## Independent authored win/score panel fixture; no session or combat dependencies.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var panel := MatchResults.new()
	root.add_child(panel)
	panel.show()
	var view := {"match_id":"duel-panels", "phase":"results", "mode":"1v1", "winner":0,
		"scores":[2, 1], "remaining":20, "rounds":[{"round":1,"winner":0}, {"round":2,"winner":1}, {"round":3,"winner":0}]}
	var stats := {"damage":217,"eliminations":2,"assists":0,"component_disables":3,"recoveries":1}
	panel.render(view, 7, 0)
	panel.accept_record({"match":view, "participants":{7:stats, 4:stats}}, "duel-panels")
	check(panel.outcome.text == "VICTORY", "Authority local team determines victory, not entity parity")
	check(panel.score.text.contains("2  :  1"), "Final round score uses authority")
	check(panel.round_summary.text.contains("ROUND 3"), "Overview shows complete round history")
	panel.render(view, 7, 1)
	check(panel.outcome.text == "DEFEAT", "Opponent win is local defeat")
	panel.render(view, 7)
	check(panel.outcome.text == "MATCH COMPLETE", "Unknown local team never invents victory")
	panel.render(view, 7, 0)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await create_timer(0.15).timeout
		for details: bool in [false, true]:
			panel.show_scores(details)
			await process_frame
			await process_frame
			check(panel.overview.visible != panel.scores_page.visible, "Exactly one content page is visible")
			check(panel.leave.get_global_rect().end.x <= resolution.x and panel.leave.get_global_rect().end.y <= resolution.y, "Footer fits viewport")
			check(panel.score.get_global_rect().end.x <= resolution.x, "Score fits viewport")
			if details:
				check(panel.table.size.x <= panel.scores_page.size.x, "Duel stats fit without horizontal scrolling")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-results-%d-%s.png" % [resolution.y, "scores" if details else "overview"]))
	panel.scores_tab.grab_focus()
	panel.scores_tab.pressed.emit()
	check(panel.scores_page.visible, "Score navigation is accessible by button activation")
	panel.mark_requested()
	check(panel.rematch.disabled and panel.status.text.contains("waiting for the server"), "Rematch waits for authoritative acceptance")
	panel.render({"match_id":"next", "phase":"countdown"}, 7, 0)
	check(panel.record.is_empty() and panel.overview.visible, "New match resets details and old record")
	panel.free()
	print("RESULTS PANELS PASS" if failures == 0 else "RESULTS PANELS FAIL")
	quit(0 if failures == 0 else 1)
