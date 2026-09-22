extends Node

var failures: Array[String] = []
var launches := 0

func _ready() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func settle() -> void:
	for frame: int in 8: await get_tree().process_frame

func run() -> void:
	get_window().content_scale_size = Vector2i(1920,1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var profile: Node = get_node("/root/PlayerProfile")
	profile.save_path = "user://test-drive-entry-%d.json" % Time.get_ticks_usec()
	profile.reload()
	var initial: Dictionary = profile.loadouts[profile.active_bot].duplicate(true)
	for screen_name: String in ["garage", "customize"]:
		var screen: Control = load("res://ui/menus/screens/%s.tscn" % screen_name).instantiate()
		add_child(screen)
		var entry := GarageTestDriveEntry.install(screen, func(): launches += 1)
		entry.pressed.emit()
		check(launches == 0, "Unrendered entry cannot launch")
		entry.render(initial, true)
		if screen_name == "customize" and "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			get_window().size = Vector2i(1920, 1080)
			screen.apply_text_scale(1.0)
			await settle()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("customize-immediate-1920.png"))
		entry.pressed.emit()
		check(launches == 1, "Valid enabled entry invokes caller")
		entry.render(initial, false)
		entry.pressed.emit()
		check(launches == 1 and entry.disabled, "Disallowed direct signal cannot launch")
		var invalid := initial.duplicate(true)
		invalid.parts.weapon = "missing_weapon"
		entry.render(invalid, true)
		entry.pressed.emit()
		check(launches == 1 and entry.disabled, "Invalid draft cannot launch")
		invalid.parts.weapon = initial.parts.weapon
		entry.render(invalid, true)
		check(not entry.disabled, "In-place draft repair refreshes cached validation")
		for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080)]:
			get_window().size = resolution
			for factor: float in [1.0,1.5,1.0]:
				screen.apply_text_scale(factor)
				await settle()
				check(entry.get_theme_font_size("font_size") == roundi((30 if screen_name == "customize" else 20) * factor), "Full noncompounding test-drive text scale")
				if screen_name == "customize":
					var save: Button = screen.get_node("%Save")
					check(entry.custom_minimum_size.y == save.custom_minimum_size.y and entry.get_index() + 1 == save.get_index(), "Test Drive matches Save height and Save is rightmost")
				var footer: Control = screen.get_node("Layout/Footer/Row")
				var previous_end := -1.0
				for child: Control in footer.get_children():
					if not child.visible: continue
					var rect := get_viewport().get_stretch_transform() * child.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, child.size)
					check(rect.position.x >= previous_end - 1.0, screen_name + " footer actions do not overlap")
					check(rect.end.x <= resolution.x + 1 and rect.end.y <= resolution.y + 1, screen_name + " footer fits " + str(resolution))
					previous_end = rect.end.x
				check(entry.is_visible_in_tree(), "Entry remains visible")
				check(screen.find_children("*", "ScrollContainer", true, false).is_empty(), "No scrolling entry layout")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				screen.apply_text_scale(1.5)
				await settle()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("test-drive-entry-%s-%d.png" % [screen_name,resolution.x]))
		entry.hide()
		entry.pressed.emit()
		check(launches == 1, "Hidden entry cannot launch")
		check(profile.loadouts[profile.active_bot] == initial, "Component leaves profile draft untouched")
		check(not FileAccess.file_exists(profile.save_path), "Component does not persist")
		launches = 0
		screen.queue_free()
		await settle()
	if failures.is_empty(): print("GARAGE TEST DRIVE ENTRY PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
