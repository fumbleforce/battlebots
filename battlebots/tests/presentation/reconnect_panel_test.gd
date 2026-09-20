extends SceneTree
## Detached reconnect layout and action availability; no network or session mocks.
var failures: Array[String] = []
var retry_count := 0
var leave_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var panel = load("res://scripts/ui/reconnect_panel.gd").new()
	root.add_child(panel)
	panel.retry_requested.connect(func() -> void: retry_count += 1)
	panel.leave_requested.connect(func() -> void: leave_count += 1)
	for extent: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = extent
		for state: Dictionary in [{"retry":true,"connecting":false,"seconds":12.0}, {"retry":true,"connecting":true,"seconds":8.0}, {"retry":false,"connecting":false,"seconds":0.0}]:
			panel.render(state.retry, state.connecting, state.seconds)
			await process_frame
			await process_frame
			var expected := "RECONNECTING" if state.connecting else ("CONNECTION LOST" if state.retry else "UNABLE TO RECONNECT")
			_check(panel.heading.text == expected, "Heading reflects connection state")
			_check(panel.retry.disabled == (state.connecting or not state.retry), "Retry state follows eligibility and active attempt")
			_check(not panel.leave_button.disabled, "Leave remains available")
			var bounds := Rect2(Vector2.ZERO, Vector2(extent))
			for control: Control in [panel.heading, panel.status, panel.countdown, panel.retry, panel.leave_button]:
				_check(bounds.encloses(control.get_global_rect()), "Content fits %s: %s" % [extent, control.name])
			_check(not panel.retry.get_global_rect().intersects(panel.leave_button.get_global_rect()), "Actions do not overlap")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://a-reconnect-%d-%s.png" % [extent.x, expected.to_lower().replace(" ", "-")])
	panel.render(true, false, 0.0)
	_check(panel.retry.disabled, "Expired local window disables retry even before eligibility refresh")
	panel.render(true, false, NAN)
	_check(panel.retry.disabled, "Invalid timer cannot authorize retry")
	panel.render(false, false, 9.0, "The server could not restore your match.")
	_check(panel.retry.disabled and panel.status.text == "The server could not restore your match.", "Server denial overrides positive local time and shows safe message")
	panel.render(true, false, 12.0)
	panel.retry.grab_focus()
	panel.render(false, false, 0.0)
	_check(panel.leave_button.has_focus(), "Expiry moves keyboard focus to the remaining action")
	panel.render(true, false, 12.0)
	panel.retry.pressed.emit()
	panel.leave_button.pressed.emit()
	_check(retry_count == 1 and leave_count == 1, "Actions emit their integration signals")
	panel.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("RECONNECT PANEL PASS")
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
