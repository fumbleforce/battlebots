extends SceneTree
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var profile: Node = root.get_node("PlayerProfile")
	var path := "user://garage-history-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	profile.reload()
	profile.active_bot = 0
	# Start with the canonical body and an explicit paint preset.
	profile.loadouts[0] = profile.registry.starter()
	profile._refresh_bots()
	var paint: Dictionary = profile.catalogue.paint[0]
	profile.equip("paint", paint, paint.items[0])
	profile._undo_history.clear()
	profile._redo_history.clear()
	var original: Dictionary = profile.loadouts[0].duplicate(true)
	profile.equip("paint", paint, paint.items[1])
	profile.undo_edit()
	check(profile.loadouts[0] == original and profile.can_redo(), "Undo restores full detached loadout")
	profile.equip("paint", paint, paint.items[0])
	check(profile.can_redo(), "No-op edit retains redo")
	profile.redo_edit()
	check(profile.loadouts[0].cosmetics.paint == "orange", "Redo restores paint")
	profile.undo_edit()
	profile.rename_draft("History test")
	check(not profile.can_redo(), "New edit invalidates redo")
	profile.active_bot = 1
	check(not profile.can_undo() and not profile.can_redo(), "Build histories are isolated")
	profile.rename_draft("Other build")
	profile.active_bot = 0
	check(profile.loadouts[0].name == "History test", "Other build edits do not leak")
	check(profile.save_active("History test") == OK, "Explicit save succeeds")
	var disk := FileAccess.get_file_as_string(path)
	profile.undo_edit()
	check(profile.loadouts[0].name == "Striker" and FileAccess.get_file_as_string(path) == disk, "Undo after Save changes draft only")
	profile.redo_edit()
	check(FileAccess.get_file_as_string(path) == disk, "Redo does not write disk")
	for selection: Array in [[1, 3], [2, 1]]:
		var category: Dictionary = profile.catalogue.parts[selection[0]]
		profile.equip("parts", category, category.items[selection[1]])
	# Armour every other area (exactly 120 kg), then heavy side skirts push it over.
	for module: Array in [["armor_top", 1], ["armor_front", 1], ["armor_rear", 1], ["armor_side", 2]]:
		for category: Dictionary in profile.catalogue.decals:
			if category.slot == module[0]: profile.equip("decals", category, category.items[module[1]])
	check(not profile.bots[0].valid, "Overweight draft remains editable")
	check(profile.save_active("Invalid") == ERR_INVALID_DATA, "Invalid draft cannot save")
	check(FileAccess.get_file_as_string(path) == disk, "Failed save preserves existing file")
	profile.undo_edit()
	check(profile.bots[0].valid and profile.can_redo(), "Undo repairs invalid combination")
	profile.redo_edit()
	check(not profile.bots[0].valid, "Redo retains invalid state for repair")
	profile.undo_edit()
	var screen: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	root.add_child(screen)
	for _frame in 4: await process_frame
	check(not screen.undo_button.disabled and not screen.redo_button.disabled, "UI reflects history availability")
	var before: Dictionary = profile.loadouts[0].duplicate(true)
	screen.undo_button.pressed.emit()
	screen.redo_button.pressed.emit()
	check(profile.loadouts[0] == before, "Buttons restore draft")
	screen.name_edit.text = "Renamed in garage"
	screen.name_edit.text_submitted.emit(screen.name_edit.text)
	check(profile.loadouts[0].name == "Renamed in garage", "Name entry commits a draft edit")
	screen.undo_button.grab_focus()
	var shortcut := InputEventKey.new()
	shortcut.physical_keycode = KEY_Z
	shortcut.ctrl_pressed = true
	shortcut.pressed = true
	screen._unhandled_input(shortcut)
	check(profile.loadouts[0].name == "History test" and screen.name_edit.text == "History test", "Ctrl+Z restores name and UI")
	screen.name_edit.grab_focus()
	var current: Dictionary = profile.loadouts[0].duplicate(true)
	screen._unhandled_input(shortcut)
	check(profile.loadouts[0] == current, "Text-field undo never changes build history")
	screen.undo_button.grab_focus()
	shortcut.shift_pressed = true
	screen._unhandled_input(shortcut)
	check(profile.loadouts[0].name == "Renamed in garage", "Ctrl+Shift+Z redoes name")
	for _frame in 4: await process_frame
	for control: Control in [screen.undo_button, screen.redo_button, screen.get_node("%Save")]:
		check(control.get_global_rect().end.x <= 1920 and control.get_global_rect().end.y <= 1080, "History/save controls fit viewport")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-garage-history.png"))
	screen.free()
	check(profile.can_undo(), "History survives leaving customization")
	for index: int in 110:
		profile.rename_draft("Revision %d" % index)
	var count := 0
	while profile.can_undo():
		profile.undo_edit()
		count += 1
	check(count == 100, "History memory is bounded")
	profile.reload()
	check(not profile.can_undo() and not profile.can_redo(), "Reload starts fresh history")
	check(profile.loadouts[profile.PRESET_COUNT].name == "History test", "Saved state survives unsaved undo/redo session")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	if failures.is_empty(): print("GARAGE HISTORY PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
