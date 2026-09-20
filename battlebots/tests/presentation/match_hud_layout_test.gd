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
		for text_scale: float in [1.0, 1.25, 1.5]:
			hud.apply_accessibility(text_scale, "standard", false)
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
				if phase not in ["practice", "unavailable"]:
					_check(is_equal_approx(bounds.size.x / ratio, 380.0 * text_scale), phase + ": compact width grows with text")
					_check(bounds.size.y / ratio < 94 * text_scale, phase + ": shallow strip with contextual result")
				if phase == "active":
					_check(bounds.size.y / ratio <= 70 * text_scale, "Active match occupies one slim strip")
					_check(absf(hud.timer_label.get_global_rect().get_center().x - extent.x * 0.5) <= 0.5 * ratio, "Timer remains centered within container pixel rounding")
					_check(not hud.phase_label.is_visible_in_tree() and not hud.result_label.is_visible_in_tree(), "No redundant phase/result text during combat")
				_check(is_equal_approx(bounds.get_center().x, extent.x * 0.5), phase + ": header centered")
				_check(is_equal_approx(bounds.position.y / ratio, 24.0), phase + ": logical top margin")
				if phase == "practice":
					_check(is_equal_approx(bounds.size.x / ratio, 108 * text_scale) and bounds.size.y / ratio <= 32 * text_scale, "Practice collapses to a small pill after full results and resize")
				_check(bounds.position.x > 300 * ratio and bounds.end.x < extent.x - 280 * ratio, phase + ": diagnostics remain clear")
				_check(hud.timer_label.get_theme_font_size("font_size") == roundi(34 * text_scale), "Accessibility grows fonts without reducing canvas scale")
				_check_labels(hud, bounds, phase)
				if captures and viewport_size.x == 1280 and text_scale in [1.0, 1.5] and phase in ["countdown", "active", "intermission", "practice"]:
					await RenderingServer.frame_post_draw
					var path := "user://a-match-hud-%d-%s.png" % [roundi(text_scale * 100), phase]
					root.get_texture().get_image().save_png(path)
					print("CAPTURE " + ProjectSettings.globalize_path(path))
			# Boundary values and eight shared FFA winners must remain legible.
			for view: Dictionary in [
				{"phase":"active", "round":999, "remaining":86400, "scores":[999, 999]},
				{"phase":"results", "mode":"ffa", "remaining":20, "winners":[1, 2, 3, 4, 5, 6, 7, 2147483647]},
			]:
				hud.render(view)
				await process_frame
				await process_frame
				_check_labels(hud, hud.get_node("Panel").get_global_rect(), "Bounded values")
	hud.queue_free()
	background.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error(failure)
	if _failures.is_empty():
		print("MATCH HUD LAYOUT PASS")
	quit(0 if _failures.is_empty() else 1)

func _check_labels(hud: MatchHud, bounds: Rect2, phase: String) -> void:
	var viewport_bounds := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
	_check(viewport_bounds.encloses(bounds), phase + ": entire header stays inside viewport")
	for node: Node in hud.find_children("*", "Label", true, false):
		var label := node as Label
		if label.is_visible_in_tree():
			_check(bounds.grow(0.5).encloses(label.get_global_rect()), phase + ": label inside header: " + label.name)
			_check(label.get_visible_line_count() >= label.get_line_count(), phase + ": wrapped result lines never clip: " + label.name)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
