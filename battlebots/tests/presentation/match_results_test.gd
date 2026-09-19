extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
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
	panel.queue_free()
	await process_frame
	print("MATCH RESULTS PASS" if failures == 0 else "MATCH RESULTS FAIL")
	quit(0 if failures == 0 else 1)
