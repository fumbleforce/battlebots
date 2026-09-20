extends SceneTree
var failures := 0
var previews: Array[HudPreferences] = []
var published: Array[HudPreferences] = []
var finishes: Array[bool] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var directory := "user://hud-panel-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_absolute(directory)
	var path := directory + "/hud.cfg"
	var original := HudPreferences.new()
	var panel := HudSettingsPanel.new()
	root.add_child(panel)
	panel.position = Vector2(30, 30)
	panel.size = Vector2(500, 520)
	panel.preview_changed.connect(func(value: HudPreferences) -> void: previews.append(value))
	panel.applied.connect(func(value: HudPreferences) -> void: published.append(value))
	panel.finished.connect(func(saved: bool) -> void: finishes.append(saved))
	panel.open_for(original, path)
	await frames()
	check(root.gui_get_focus_owner() == panel.text_scale_choice, "Opening focuses HUD text size")
	check(panel.size.y <= 660 and panel.size.x <= 560, "Panel fits 720p")
	for control: Control in [panel.text_scale_choice, panel.palette_choice, panel.contrast_toggle, panel.save_button, panel.cancel_button]:
		check(panel.get_global_rect().encloses(control.get_global_rect()), "Controls contained by actual panel")
		check(control.get_node(control.focus_next) is Control and control.get_node(control.focus_previous) is Control, "Focus cycle resolves")
	panel.text_scale_choice.select(2)
	panel.text_scale_choice.item_selected.emit(2)
	panel.palette_choice.select(1)
	panel.palette_choice.item_selected.emit(1)
	panel.contrast_toggle.button_pressed = true
	check(previews.back().text_scale == 1.5 and previews.back().palette == "deuteranopia" and previews.back().high_contrast, "All real controls preview detached values")
	await frames()
	check(panel.sample_label.get_theme_font_size("font_size") == 30 and panel.sample_label.get_theme_color("font_color") == Color("ffce75"), "Sample previews actual HUD size and palette")
	check(panel.size.y <= 660 and panel.sample_panel.get_global_rect().encloses(panel.sample_label.get_global_rect()), "Largest text sample fits 720p panel")
	check((panel.sample_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Color("080c12"), "Sample previews opaque high contrast background")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("user://a-hud-settings-720.png") == OK, "Rendered HUD settings capture")
	check(original.text_scale == 1.0 and original.palette == "standard" and not original.high_contrast, "Preview never mutates caller")
	panel.cancel_button.pressed.emit()
	check(not panel.visible and finishes == [false] and published.is_empty() and not FileAccess.file_exists(path), "Cancel closes without save/publication")
	check(previews.back().text_scale == 1.0 and previews.back().palette == "standard" and not previews.back().high_contrast, "Cancel restores original preview")
	panel.open_for(original, directory + "/missing/hud.cfg")
	panel.contrast_toggle.button_pressed = true
	panel.save_button.pressed.emit()
	check(panel.visible and panel.message.text.contains("Could not save") and published.is_empty() and finishes.size() == 1, "Failed save stays open without publishing")
	panel.cancel()
	panel.open_for(original, path)
	panel.text_scale_choice.select(1)
	panel.text_scale_choice.item_selected.emit(1)
	panel.palette_choice.select(3)
	panel.palette_choice.item_selected.emit(3)
	panel.save_button.pressed.emit()
	check(not panel.visible and published.size() == 1 and finishes.back(), "Save publishes once and closes")
	var saved := HudPreferences.load_file(path)
	check(saved.load_error == OK and saved.text_scale == 1.25 and saved.palette == "tritanopia", "Saved UI draft persists")
	panel.open_for(original, path)
	panel.contrast_toggle.button_pressed = true
	panel.open_for(saved, path)
	check(not previews.back().high_contrast, "Reopening restores prior preview before replacing draft")
	panel.contrast_toggle.button_pressed = true
	panel.queue_free()
	await frames()
	check(previews.back().text_scale == 1.25 and not previews.back().high_contrast, "Removing open panel restores original preview")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("HUD SETTINGS PASS" if failures == 0 else "HUD SETTINGS FAIL")
	quit(0 if failures == 0 else 1)
