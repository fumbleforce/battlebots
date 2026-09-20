extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := VideoSettingsPanel.new()
	center.add_child(panel)
	panel.apply_display = func(_preferences: VideoPreferences) -> Error: return OK
	panel.capture_display = func() -> VideoPreferences: return VideoPreferences.new()
	panel.capture_state = func() -> Dictionary: return {}
	for scale_value: float in [1.0, 1.5]:
		panel.open_for(VideoPreferences.new(), "user://video-layout-unsaved.cfg")
		panel.apply_text_scale(scale_value)
		for confirming: bool in [false, true]:
			if confirming:
				panel.mode_choice.select(1)
				panel.preview_changes()
			await process_frame
			await process_frame
			for control: Node in panel.find_children("*", "Control", true, false):
				if control.is_visible_in_tree() and not Rect2(Vector2.ZERO, Vector2(root.size)).encloses(control.get_global_rect()):
					failures += 1
					push_error("Video settings outside720p at scale%s: %s" % [scale_value, control.name])
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://video-settings-%d-%s.png" % [roundi(scale_value*100), "confirm" if confirming else "edit"])
		panel.cancel()
	center.queue_free()
	await process_frame
	print("Render layout only; display apply mocked")
	print("VIDEO SETTINGS LAYOUT PASS" if failures == 0 else "VIDEO SETTINGS LAYOUT FAIL")
	quit(0 if failures == 0 else 1)
