extends Node
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func page_text(panel: GarageRecoveryPanel) -> String:
	return " ".join(panel._detail_pages).replace("\n", " ")

func run() -> void:
	var profile: Node = get_node("/root/PlayerProfile")
	var saved_start: int = profile.PRESET_COUNT
	var path := "user://garage-recovery-test-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	var store := LoadoutStore.new(path)
	var original := store.registry.starter()
	original.name = "Saved bot"
	check(store.save([original]) == OK, "Seed saved file")
	profile.reload()
	profile.active_bot = saved_start
	profile.rename_draft("My local edit")
	var external := original.duplicate(true)
	external.cosmetics.paint = "white"
	check(store.save([external]) == OK, "External editor changes saved bot")
	check(profile.save_active("My local edit") == ERR_BUSY, "Stale save rejected")
	var before := FileAccess.get_file_as_string(path)
	get_window().size = Vector2i(1280, 720)
	get_window().content_scale_size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var screen: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	add_child(screen)
	for _frame: int in 4: await get_tree().process_frame
	check(screen.recovery_button.get_global_rect().end.x <= 1920 and screen.recovery_button.get_global_rect().end.y <= 1080, "Saved File action fits Customize at 720p")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("garage-recovery-customize.png"))
	screen.recovery_button.grab_focus()
	screen.recovery_button.pressed.emit()
	var panel: GarageRecoveryPanel = screen.recovery_panel
	check(panel.visible and panel.close_button.has_focus(), "Saved file panel opens with safe focus")
	for direction: String in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		for step: int in 6:
			var event := InputEventAction.new()
			event.action = direction
			event.pressed = true
			Input.parse_input_event(event)
			await get_tree().process_frame
			event = InputEventAction.new()
			event.action = direction
			Input.parse_input_event(event)
			check(panel.is_ancestor_of(get_viewport().gui_get_focus_owner()), "Modal focus contains " + direction)
	panel.reload_button.pressed.emit()
	check(profile.loadouts.size() == saved_start + 2 and profile.active_bot == saved_start + 1, "Reload retains local edit as active unsaved copy")
	check(profile.loadouts[saved_start].cosmetics.paint == "white" and profile.loadouts[saved_start + 1].cosmetics.paint == "cyan", "Disk refresh and retained draft remain separate")
	check(profile.can_undo() and profile.bots[saved_start + 1].retained, "Retained copy identified and keeps Undo")
	check(FileAccess.get_file_as_string(path) == before, "Reload never writes")
	profile.undo_edit()
	check(profile.loadouts[saved_start + 1].name == "Saved bot", "Retained undo restores original draft")
	check(profile.save_active("Saved bot") == ERR_INVALID_DATA, "Retained draft cannot overwrite externally refreshed slot")
	profile.redo_edit()
	check(profile.save_active("My local edit") == OK, "Explicit distinct-name save appends retained draft")
	check(store.load_saved().loadouts[0].cosmetics.paint == "white", "Saving retained draft preserves external build")
	var cancel_event := InputEventAction.new()
	cancel_event.action = "ui_cancel"
	cancel_event.pressed = true
	Input.parse_input_event(cancel_event)
	await get_tree().process_frame
	check(not panel.visible, "Escape closes only recovery panel")
	check(screen.recovery_button.has_focus(), "Closing returns keyboard focus")
	profile.new_build()
	var count: int = profile.reload_retaining_drafts()
	check(count == 1 and profile.loadouts.size() == saved_start + 3, "Unedited new build retained; saved draft not duplicated")
	check(profile.reload_retaining_drafts() == 1 and profile.loadouts.size() == saved_start + 3, "Repeated reload does not multiply unsaved copies")
	profile.active_bot = saved_start
	profile.rename_draft("Pending redo")
	profile.undo_edit()
	profile.reload_retaining_drafts()
	check(profile.can_redo(), "Reload retains redo when current draft equals disk baseline")
	profile.redo_edit()
	check(profile.loadouts[profile.active_bot].name == "Pending redo", "Redo after reload still restores the edit")
	screen.queue_free()
	await get_tree().process_frame
	# A corrupt primary and a readable backup with one malformed sibling.
	var backup := JSON.stringify({"schema_version":1, "loadouts":[external, "malformed sibling"]})
	put(path + ".bak", backup)
	put(path, "broken primary bytes")
	profile.reload()
	profile.active_bot = saved_start
	profile.rename_draft("Recovered local edit")
	screen = load("res://ui/menus/screens/garage.tscn").instantiate()
	add_child(screen)
	for _frame: int in 4: await get_tree().process_frame
	check(screen.get_node("%BotList").is_ancestor_of(get_viewport().gui_get_focus_owner()), "Garage initially focuses selected build")
	screen.recovery_button.pressed.emit()
	panel = screen.recovery_panel
	check(not panel.review_button.disabled, "Garage exposes available backup")
	panel.review_button.pressed.emit()
	for _frame: int in 3: await get_tree().process_frame
	check(panel.restore_button.visible and panel.close_button.text == "CANCEL" and panel.close_button.has_focus(), "Restore requires reviewed confirmation, Cancel default")
	check(page_text(panel).contains("Malformed entry") and page_text(panel).contains("needs repair"), "Review pages identify invalid sibling without dropping it")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("garage-recovery-review.png"))
	panel.dismiss()
	check(FileAccess.get_file_as_string(path) == "broken primary bytes" and FileAccess.get_file_as_string(path + ".bak") == backup, "Cancel makes no file changes")
	screen.recovery_button.pressed.emit()
	panel.review_button.pressed.emit()
	put(path, "changed after review")
	panel.restore_button.pressed.emit()
	for _frame: int in 3: await get_tree().process_frame
	check(page_text(panel).contains("refused") and FileAccess.get_file_as_string(path) == "changed after review", "Changed source refuses stale confirmation")
	panel.review_button.pressed.emit()
	panel.restore_button.pressed.emit()
	for _frame: int in 3: await get_tree().process_frame
	check(page_text(panel).contains("Backup restored"), "Reviewed restore succeeds")
	check(FileAccess.get_file_as_string(path) == backup and FileAccess.get_file_as_string(path + ".bak") == backup, "Recovery restores exact backup and retains backup")
	check(profile.loadouts[profile.active_bot].name == "Recovered local edit" and profile.can_undo(), "Backup recovery retains dirty draft and Undo")
	check(screen.get_node("%Bays").text.contains(str(profile.loadouts.size())) and screen.get_node("%BotList").get_children().any(func(row): return row.visible and row.button_pressed), "Garage count and active build page refresh after retained recovery")
	check(profile.save_active("Recovered local edit") == OK, "Successful recovery unblocks save despite invalid sibling")
	check(store.load_saved().loadouts[1] == "malformed sibling", "Post-recovery save retains malformed sibling")
	for _frame: int in 3: await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("garage-recovery-result.png"))
	screen.queue_free()
	await get_tree().process_frame
	var directory := DirAccess.open("user://")
	for file: String in directory.get_files():
		if file.begins_with(path.get_file()): directory.remove(file)
	if failures.is_empty(): print("GARAGE RECOVERY PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
