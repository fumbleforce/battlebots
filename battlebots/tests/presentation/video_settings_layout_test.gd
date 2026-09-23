extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames() -> void:
	for i: int in 4: await process_frame
func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var center := SettingsCategoryFrame.new()
	root.add_child(center)
	var panel := VideoSettingsPanel.new()
	center.add_child(panel)
	panel.apply_display = func(_preferences: VideoPreferences) -> Error: return OK
	panel.capture_display = func() -> VideoPreferences: return VideoPreferences.new()
	panel.capture_state = func() -> Dictionary: return {}
	for extent: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
		root.size = extent
		var bounds := Rect2(Vector2.ZERO,Vector2(extent))
		for scale_value: float in [1.0,1.5]:
			panel.open_for(VideoPreferences.new(),"user://video-layout-unsaved.cfg")
			panel.apply_text_scale(scale_value)
			for tab: String in ["Display","Quality","Effects"]:
				panel.select_tab(tab)
				await frames()
				check(bounds.encloses(panel.get_global_rect()),"Settings page fits viewport")
				for control: Control in [panel.message,panel.apply_button,panel.cancel_button,panel.defaults_button]:
					check(bounds.encloses(control.get_global_rect()),"Stationary footer fits: "+str(control.name))
				for item: Node in panel._groups[tab].find_children("*","Control",true,false):
					if not (item is BaseButton or item is HSlider): continue
					panel._page.scroll.ensure_control_visible(item)
					await frames()
					# Scroll offsets use integer logical pixels; allow one scaled pixel of rounding.
					check(panel._page.scroll.get_global_rect().grow(center.scale.x + 0.1).encloses(item.get_global_rect()),"Every option reachable by scrolling: %s viewport=%s item=%s size=%s scale=%s" % [item.name,panel._page.scroll.get_global_rect(),item.get_global_rect(),extent,scale_value])
					if item is OptionButton:
						var text_width: float = item.get_theme_font("font").get_string_size(item.text,HORIZONTAL_ALIGNMENT_LEFT,-1,item.get_theme_font_size("font_size")).x
						check(text_width+34 <= item.size.x,"Selected value fits without clipping: "+item.text)
				panel._page.scroll.scroll_vertical = 0
				await frames()
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("user://graphics-%s-%d-%d.png" % [tab.to_lower(),extent.x,roundi(scale_value*100)])
			panel.select_tab("Display")
			panel.mode_choice.select(1)
			panel.preview_changes()
			await frames()
			check(bounds.encloses(panel.keep_button.get_global_rect()) and bounds.encloses(panel.revert_button.get_global_rect()),"Recovery actions remain visible")
			panel.cancel()
	center.queue_free()
	await frames()
	print("Render layout and scroll reachability; physical display apply mocked")
	print("VIDEO SETTINGS LAYOUT PASS" if failures == 0 else "VIDEO SETTINGS LAYOUT FAIL")
	quit(0 if failures == 0 else 1)
