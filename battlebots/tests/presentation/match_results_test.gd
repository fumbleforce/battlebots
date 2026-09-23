extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var panel := MatchResults.new()
	root.add_child(panel)
	panel.show()
	var view := {"match_id":"fixture", "phase":"results", "mode":"ffa", "winners":[1, 2], "remaining":20,
		"placements":[{"entity_id":1, "place":1}, {"entity_id":2, "place":1}, {"entity_id":3, "place":3}]}
	panel.render(view, 1)
	check(panel.heading.text.contains("share the win"), "Shared FFA winners are not a draw")
	check(panel.status.text.contains("Waiting"), "Missing record is explicit")
	panel.accept_record({"match":{"match_id":"stale", "phase":"results"}}, "fixture")
	check(panel.record.is_empty(), "Stale record rejected")
	for bad: Variant in [null, [], "bad", 4]:
		panel.accept_record({"match":bad}, "fixture")
	check(panel.record.is_empty(), "Malformed record rejected")
	var participants := {}
	for id: int in range(1, 11):
		participants[id] = {"damage":100 + id, "eliminations":1, "assists":2, "component_disables":3, "recoveries":4}
	participants[3].damage = NAN
	participants[4].assists = -1
	var final_match := view.duplicate(true)
	final_match.rounds = [{"round":1, "participants":{1:{"damage":37}}}]
	var details := {"match":final_match, "participants":participants}
	panel.accept_record(details, "fixture")
	panel.render(view, 1)
	check(panel.table.get_child_count() == 66, "All ten participants shown")
	check(panel.table.get_child(6).text == "Player 1 (you) · #1", "Local player and authoritative place labelled")
	check(panel.table.get_child(19).text == "—", "Invalid damage shown unavailable")
	check(panel.table.get_child(27).text == "—", "Negative count shown unavailable")
	details.participants[1].damage = 9999
	check(panel.record.participants[1].damage == 101, "Detached record is immutable by producer")
	panel.accept_record(details, "fixture")
	check(panel.record.participants[1].damage == 101, "Duplicate event does not replace completed record")
	panel.scope.select(1)
	panel.scope.item_selected.emit(1)
	check(panel.table.get_child(7).text == "37" and panel.table.get_child(8).text == "—", "Per-round source and missing stats respected")
	panel.scope.select(0)
	panel.scope.item_selected.emit(0)
	panel.mark_requested()
	check(panel.rematch.disabled and panel.status.text.contains("waiting for the server"), "Request never pretends vote accepted")
	await process_frame
	await process_frame
	check(panel.leave.get_global_rect().end.x <= 1280 and panel.leave.get_global_rect().end.y <= 720, "Actions fit 720p")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-b-results.png"))
	panel.render({"match_id":"new", "phase":"countdown"}, 1)
	check(panel.record.is_empty() and panel.rematch.disabled, "New match clears old record and gates rematch")
	panel.render({"match_id":"new", "phase":"results", "winner":-1}, 1)
	check(panel.heading.text.ends_with("Draw") and not panel.rematch.disabled, "Team draw uses authority and vote resets")
	var duel := {"match_id":"duel", "phase":"results", "mode":"1v1", "winner":0, "remaining":20,
		"scores":[2, 1], "rounds":[{"round":1,"winner":0}, {"round":2,"winner":1}, {"round":3,"winner":-1}]}
	for team in [0, 1]:
		for winner in [0, 1, -1]:
			duel.winner = winner
			panel.render(duel, 1, team)
			check(panel.score.text == ("YOU   2  :  1   OPPONENT" if team == 0 else "YOU   1  :  2   OPPONENT"), "Duel score preserves values oriented to authoritative local team")
			check(panel.heading.text.ends_with("Draw" if winner == -1 else ("You won" if winner == team else "You lost")), "Duel heading identifies local win, loss and draw")
			check(panel.outcome.text == ("DRAW" if winner == -1 else ("VICTORY" if winner == team else "DEFEAT")), "Duel overview agrees with heading")
			check(panel.round_summary.text == ("ROUND 1  ·  You won\nROUND 2  ·  You lost\nROUND 3  ·  Draw" if team == 0 else "ROUND 1  ·  You lost\nROUND 2  ·  You won\nROUND 3  ·  Draw"), "Round language uses authoritative local team")
	duel.winner = 1
	panel.render(duel, 1, -1)
	check(panel.score.text == "TEAM A   2  :  1   TEAM B" and panel.heading.text.ends_with("Team B wins"), "Unknown local team retains neutral score and result")
	check(panel.round_summary.text.contains("Team A wins") and not panel.round_summary.text.contains("You"), "Unknown identity never invents local round outcome")
	duel.mode = "2v2"
	panel.render(duel, 1, 1)
	check(panel.score.text.begins_with("TEAM A") and panel.heading.text.ends_with("Team B wins"), "Deferred team modes retain legacy presentation")
	duel.mode = "1v1"
	duel.winner = null
	panel.render(duel, 1, 0)
	check(panel.heading.text.ends_with("Result unavailable"), "Malformed winner does not imply a local result")
	duel.winner = 1
	duel.scores = [1, 2]
	duel.rounds[2].winner = 1
	panel.render(duel, 1, 1)
	panel.apply_text_scale(1.5)
	await process_frame
	await process_frame
	check(panel.score.get_global_rect().end.x <= 1280 and panel.leave.get_global_rect().end.y <= 720, "Enlarged local result fits 720p")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-duel-local-results-720.png"))
	panel.queue_free()
	await process_frame
	print("MATCH RESULTS PASS" if failures == 0 else "MATCH RESULTS FAIL")
	quit(0 if failures == 0 else 1)
