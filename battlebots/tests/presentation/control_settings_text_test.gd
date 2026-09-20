extends Node
var failures := 0

func check(condition: bool, detail: String) -> void:
	if not condition:
		failures += 1
		push_error(detail)

func settle() -> void:
	for frame: int in range(5):
		await get_tree().process_frame

func _ready() -> void:
	var path := "user://control_text_%d.cfg" % Time.get_ticks_usec()
	var rig := BotOrbitCamera.new()
	var camera := Camera3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	add_child(rig)
	var panel: CameraSettingsPanel = load("res://scenes/ui/camera_settings_panel.tscn").instantiate()
	add_child(panel)
	panel.configure_inputs(InputPreferences.new(), path + ".inputs")
	var extra := Button.new()
	extra.text = "Audio and accessibility…"
	panel.form.add_child(extra)
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(3840, 2160)]:
		get_window().size = dimensions
		get_window().content_scale_size = dimensions
		for factor: float in [1.0, 1.25, 1.5, 1.0]:
			panel.open_for(rig, path)
			panel.apply_text_scale(factor)
			await settle()
			var bounds: Rect2 = panel.get_node("Center/Panel").get_global_rect()
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(bounds), "Modal fits viewport")
			check(panel.form.get_node("Title").get_theme_font_size("font_size") == roundi(26 * factor), "Full requested camera font")
			check(extra.get_theme_font_size("font_size") == roundi(16 * factor), "Injected navigation scales")
			check(panel.controls_button.get_node(panel.controls_button.focus_next) == extra,
				"Camera keyboard cycle includes injected settings")
			var original := rig.sensitivity_x
			panel.sensitivity.value = 2.0
			check(is_equal_approx(rig.sensitivity_x, 0.006), "Scaled camera slider edits live")
			panel.cancel()
			check(is_equal_approx(rig.sensitivity_x, original), "Scaled camera cancel restores")
			panel.open_for(rig, path)
			panel.open_controls()
			await settle()
			var controls := panel.input_panel
			check(controls.binding_buttons[&"drive_forward"].get_theme_font_size("font_size") == roundi(16 * factor), "Full requested binding font")
			controls.begin_capture(&"drive_forward")
			panel.apply_text_scale(factor)
			check(controls.capture_action == &"drive_forward", "Scale preserves capture")
			var key := InputEventKey.new()
			key.physical_keycode = KEY_I
			key.pressed = true
			controls._input(key)
			check(controls.draft.label_for(&"drive_forward") == "I", "Binding capture remains functional")
			controls.save_button.grab_focus()
			await settle()
			check(panel.find_children("*", "ScrollContainer", true, false).is_empty(), "Settings navigation has no scroll containers")
			for group: int in range(controls.GROUPS.size()):
				controls.show_page(group)
				await settle()
				check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel.get_node("Center/Panel").get_global_rect()), "Every binding page fits viewport")
				for action: StringName in controls.GROUPS[group]:
					var binding: Button = controls.binding_buttons[action]
					check(binding.is_visible_in_tree(), "Every grouped action remains available")
					check(panel.get_global_rect().encloses(binding.get_global_rect()), "Binding is onscreen without scrolling")
			check(controls.draft.label_for(&"drive_forward") == "I", "Page changes preserve binding draft")
			controls.begin_capture(&"scoreboard")
			controls.show_page(0)
			check(controls.capture_action.is_empty() and controls.draft.label_for(&"scoreboard") == "Tab",
				"Changing group cancels pending capture without changing its binding")
			controls.show_page(2)
			controls.save_button.grab_focus()
			await settle()
			if "--capture" in OS.get_cmdline_user_args() and dimensions.x == 1280 and factor == 1.5:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/controls-text-150.png")
			controls.save()
			check(panel.form.visible and not controls.visible, "Controls save returns to camera")
			panel.form.get_node("Buttons/Save").grab_focus()
			await settle()
			check(panel.get_global_rect().encloses(panel.form.get_node("Buttons/Save").get_global_rect()), "Camera save visible without scrolling")
			if "--capture" in OS.get_cmdline_user_args() and dimensions.x == 1280 and factor == 1.5:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP") + "/camera-text-150.png")
			panel.save_and_close()
			check(not panel.visible, "Camera saves and closes")
	for file: String in [path, path + ".inputs"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	print("CONTROL SETTINGS TEXT PASS" if failures == 0 else "CONTROL SETTINGS TEXT FAIL: %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
