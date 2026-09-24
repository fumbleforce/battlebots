extends SceneTree
var _failures: Array[String] = []
func _initialize() -> void:
	call_deferred("_run")
func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var hud: MatchHud = load("res://scenes/ui/match_hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	var state := MatchState.new()
	state.begin()
	hud.render(state.snapshot())
	_check(hud.phase_label.text == "LOADING" and hud.round_label.text == "ROUND 1", "Loading uses server round")
	state.transition("countdown", 4.2)
	var view := state.snapshot()
	var original := view.duplicate(true)
	hud.render(view)
	_check(hud.timer_label.text == "5", "Countdown rounds up server seconds")
	_check(hud.timer_caption.text == "STARTS IN" and hud.timer_caption.visible, "Countdown explains prominent server numeral")
	for _tick in range(3):
		await process_frame
	_check(hud.timer_label.text == "5" and view == original, "No local timer or snapshot mutation")
	state.transition("active", 179.1)
	hud.render(state.snapshot())
	_check(not hud.phase_label.visible and hud.timer_label.text == "3:00", "Active timer keeps the arena clear of a permanent FIGHT heading")
	state.transition("overtime", 0)
	hud.render(state.snapshot())
	_check(hud.phase_label.text == "OVERTIME" and hud.timer_label.text == "0:00" and not hud.result_label.visible, "Zero timer never resolves round locally")
	state.resolve(1)
	hud.render(state.snapshot())
	_check(hud.score_label.text == "0" and hud.opponent_score_label.text == "1" and hud.local_name_label.text == "TEAM A" and hud.opponent_name_label.text == "TEAM B" and hud.result_label.text == "Team B wins the round", "Authoritative intermission score and winner")
	hud.render(state.snapshot(), false, 1)
	_check(hud.result_label.text == "Round won", "Round outcome uses supplied local team")
	_check(hud.score_label.text == "1" and hud.opponent_score_label.text == "0" and hud.local_name_label.text == "YOU" and hud.opponent_name_label.text == "RIVAL", "Known local team is always the left score, including team B")
	hud.render(state.snapshot(), false, 0)
	_check(hud.result_label.text == "Round lost", "Opposing local team sees round loss")
	state.round_index = 2
	state.resolve(-1)
	hud.render(state.snapshot())
	_check(hud.result_label.text == "Round drawn", "Authoritative drawn round")
	state.round_index = 3
	state.resolve(1)
	hud.render(state.snapshot())
	_check(hud.phase_label.text == "MATCH COMPLETE" and hud.result_label.text == "Team B wins the match", "Authoritative final winner")
	view = state.snapshot()
	view.winner = -1
	hud.render(view)
	_check(hud.result_label.text == "Match drawn", "Winner field trusted instead of calculating from scores")
	view.erase("winner")
	hud.render(view)
	_check(hud.result_label.text == "Match result unavailable", "Missing result is not draw")
	for bad: Variant in [null, true, "0", 0.5, NAN, INF, -2, 2]:
		view.winner = bad
		hud.render(view)
		_check(hud.result_label.text == "Match result unavailable", "Malformed winner rejected: %s" % str(bad))
	view = {"phase":"active", "remaining":NAN, "round":true, "scores":[0, -1]}
	hud.render(view)
	_check(hud.timer_label.text == "--:--" and hud.round_label.text == "ROUND —" and hud.score_label.text == "—" and hud.opponent_score_label.text == "—", "Invalid numeric values remain visibly unavailable")
	for bad: Variant in [null, true, "1", 0.5, NAN, INF, -1, 1000]:
		view.scores = [bad, 0]
		hud.render(view)
		_check(hud.score_label.text == "—" and hud.opponent_score_label.text == "—", "Both split scores reject malformed input: %s" % str(bad))
	view = {"phase":"intermission", "remaining":15, "round":2, "scores":[1, 0], "rounds":[{"round":1, "winner":0}]}
	hud.render(view)
	_check(hud.result_label.text == "Round result unavailable", "Stale previous-round result rejected")
	view.rounds = [{"round":2.0, "winner":0.0}]
	hud.render(view)
	_check(hud.result_label.text == "Team A wins the round", "Integral JSON floats accepted")
	hud.render(state.snapshot(), true)
	_check(hud.phase_label.text == "PRACTICE" and not hud.round_label.visible and not hud.score_label.visible and not hud.timer_label.visible and not hud.result_label.visible, "Practice never awards competitive score or result")
	_check(not hud.timer_caption.visible, "Practice clears previous timer caption")
	hud.render({"phase":"results", "mode":"ffa", "remaining":20, "winners":[2, 5]})
	_check(not hud.score_label.visible and hud.round_label.text == "FREE FOR ALL" and hud.result_label.text == "Player 2, Player 5 share the win", "FFA shared winners are bots, not team scores or a draw")
	hud.render({"phase":"results", "mode":"ffa", "remaining":20, "winners":[3]})
	_check(hud.result_label.text == "Player 3 wins", "FFA sole winner uses authoritative entity ID")
	hud.render({"phase":"lobby"})
	_check(not hud.score_label.visible and not hud.result_label.visible and not hud.timer_label.visible, "Lobby clears prior result")
	hud.render({"phase":123})
	_check(hud.phase_label.text == "MATCH UNAVAILABLE" and not hud.result_label.visible, "Invalid phase clears stale data")
	hud.render(state.snapshot())
	await process_frame
	for child: Node in hud.find_children("*", "Control", true, false):
		_check(child.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD cannot intercept game mouse: " + child.name)
	var panel: Control = hud.get_node("Panel")
	# Thresholds are 720p window pixels; map the logical canvas rect through the root stretch transform.
	var panel_rect: Rect2 = root.get_final_transform() * panel.get_global_rect()
	_check(panel_rect.position.x >= 440 and panel_rect.end.x <= 840 and panel_rect.end.y < 130, "Context result fits the compact centered header at 720p")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://b-match-hud.png")
	hud.queue_free()
	await process_frame
	if _failures.is_empty():
		print("MATCH HUD PASS")
	else:
		for failure in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)
