extends SceneTree
## Independent read-only layout fixture for authoritative round presentation.
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var background := ColorRect.new()
	background.color = Color("343b42")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var hud: MatchHud = load("res://scenes/ui/match_hud.tscn").instantiate()
	root.add_child(hud)
	var captures := "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	# Exercise native viewport pixels, including the 4K client path without stretch.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = viewport_size
		for phase: String in ["loading", "countdown", "active", "overtime", "intermission", "results", "practice", "unavailable"]:
			var view := {"phase":phase, "mode":"duel", "round":2, "remaining":4.2 if phase == "countdown" else 15.0, "scores":[1, 0], "winner":0, "rounds":[{"round":2, "winner":0}]}
			hud.render(view, phase == "practice", 0)
			# Containers settle asynchronously after label visibility/minimum size changes.
			await process_frame
			await process_frame
			var panel: Control = hud.get_node("Panel")
			var bounds := panel.get_global_rect()
			var extent := hud.get_viewport_rect().size
			var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
			_check(is_equal_approx(bounds.size.x / ratio, 416.0) and bounds.end.y / ratio < 220, phase + ": compact logical match header")
			_check(is_equal_approx(bounds.get_center().x, extent.x * 0.5), phase + ": header centered")
			_check(is_equal_approx(bounds.position.y / ratio, 24.0), phase + ": logical top margin")
			if phase == "practice":
				_check(bounds.size.y / ratio <= 60, "Practice shrinks after full results and viewport resize")
			_check(bounds.position.x > 300 * ratio and bounds.end.x < extent.x - 280 * ratio, phase + ": diagnostics remain clear")
			for label: Label in [hud.phase_label, hud.round_label, hud.timer_label, hud.timer_caption, hud.score_label, hud.result_label]:
				if label.is_visible_in_tree():
					_check(bounds.encloses(label.get_global_rect()), phase + ": label inside header: " + label.name)
			if captures and phase in ["countdown", "active", "intermission", "practice"]:
				await RenderingServer.frame_post_draw
				var path := "user://a-match-hud-%d-%s.png" % [viewport_size.y, phase]
				root.get_texture().get_image().save_png(path)
				print("CAPTURE " + ProjectSettings.globalize_path(path))
	hud.queue_free()
	background.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("MATCH HUD LAYOUT PASS")
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
