extends Node
var failures: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func settle() -> void:
	for _frame: int in 8: await get_tree().process_frame

func inspect(screen: Control, context: String) -> void:
	for node: Node in screen.find_children("*", "Control", true, false):
		check(not node is ScrollContainer, context + " does not require scroll containers")
		if not node is Label and not node is Button and not node is LineEdit and not node is RichTextLabel: continue
		var control := node as Control
		if not control.is_visible_in_tree(): continue
		var rect := control.get_global_rect()
		check(rect.position.x >= -1 and rect.end.x <= 1921, context + " horizontal " + str(screen.get_path_to(control)))
		var ancestor := control.get_parent()
		var scrollable := false
		while ancestor != null and ancestor != screen:
			if ancestor is ScrollContainer: scrollable = true
			ancestor = ancestor.get_parent()
		if not scrollable:
			check(rect.position.y >= -1 and rect.end.y <= 1081, context + " vertical " + str(screen.get_path_to(control)))
		if control is Label:
			check(control.size.y + 1 >= control.get_minimum_size().y, context + " text height " + str(screen.get_path_to(control)))
	check(screen.size.x <= 1921 and screen.size.y <= 1081, context + " root fits canvas")
	check(screen.comparison_panel.budgets.get_global_rect().end.x <= screen.comparison_panel.get_global_rect().end.x + 1, context + " budgets fit column")

func run() -> void:
	get_window().content_scale_size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var profile: Node = get_node("/root/PlayerProfile")
	var path := "user://customize-text-%d.json" % Time.get_ticks_usec()
	profile.save_path = path
	profile.reload()
	profile.rename_draft("A deliberately long forty eight character name!!!".left(48))
	var original: Dictionary = profile.loadouts[0].duplicate(true)
	var screen: Control = load("res://ui/menus/screens/customize.tscn").instantiate()
	add_child(screen)
	screen._show_preview_stats(true)
	await settle()
	var base_title: int = screen.get_node("%Title").get_theme_font_size("font_size")
	for factor: float in [1.0, 1.25, 1.5, 1.0, 1.5]:
		screen.apply_text_scale(factor)
		check(screen.get_node("%Title").get_theme_font_size("font_size") == roundi(base_title * factor), "Heading scales fully without compounding")
		for resolution: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(3840,2160)]:
			get_window().size = resolution
			await settle()
			inspect(screen, "%.2f %s" % [factor, resolution])
	get_window().size = Vector2i(1280,720)
	screen.get_node("%Categories").get_child(2).pressed.emit()
	await settle()
	for row: Control in screen.get_node("%Categories").get_children():
		check(row.get_node("%Label").get_theme_font_size("font_size") == 44, "Rebuilt category heading uses 150%")
	screen._change_choice_page(1)
	screen._change_choice_page(1)
	await settle()
	var last: Control = screen.get_node("%Items").get_child(4)
	last.grab_focus()
	await settle()
	check(last.is_visible_in_tree() and Rect2(0, 0, 1920, 1080).encloses(last.get_global_rect()), "Paging reveals last weapon tile without scrolling")
	last.pressed.emit()
	await settle()
	check(screen.get_node("%Items").get_child(4).get_node("%Name").get_theme_font_size("font_size") == 38, "Rebuilt item labels use 150%")
	check(screen.comparison_panel.budgets.get_child(0).get_theme_font_size("font_size") == 32, "Rebuilt comparison cells use 150%")
	for index: int in range(4):
		check(screen.comparison_panel.budgets.get_child(index).get_line_count() == 1, "Comparison headings remain whole at 150%")
	check(profile.loadouts[0] == original, "Text scaling and selection do not alter build")
	inspect(screen, "weapon comparison")
	screen._show_choice_details(true)
	await settle()
	inspect(screen, "selected details")
	screen._show_choice_details(false)
	screen.comparison_panel.page = 1
	screen.comparison_panel._show_page()
	await settle()
	inspect(screen, "second comparison page")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("customize-text-150.png"))
	profile.loadouts[0].parts = {}
	profile.loadouts[0].content_hash = "old-catalogue"
	profile.revalidate_active()
	screen._refresh()
	await settle()
	inspect(screen, "invalid build")
	check(screen.get_node("%Save").disabled, "Invalid draft cannot save at enlarged text")
	var backup := FileAccess.open(path + ".bak", FileAccess.WRITE)
	var review_builds: Array = []
	for index: int in 11:
		var build := original.duplicate(true)
		build.name = "Reviewed build %02d with a long descriptive name" % index
		review_builds.append(build)
	review_builds.append("Malformed entry")
	backup.store_string(JSON.stringify({"schema_version":1, "loadouts":review_builds}))
	backup.close()
	screen.recovery_button.pressed.emit()
	await settle()
	check(screen.recovery_panel.details.get_theme_font_size("normal_font_size") == 36, "Recovery details use 150%")
	inspect(screen, "recovery")
	screen.recovery_panel.review_button.pressed.emit()
	await settle()
	inspect(screen, "backup review")
	check(screen.recovery_panel.restore_button.visible and screen.recovery_panel.close_button.has_focus(), "Large backup review retains explicit confirmation and Cancel focus")
	check(not screen.recovery_panel.details.scroll_active, "Recovery text uses pages instead of scrolling")
	check(screen.recovery_panel._detail_pages.size() > 1, "Twelve-build review provides multiple readable pages")
	var all_pages := " ".join(screen.recovery_panel._detail_pages).replace("\n", " ")
	for index: int in 11: check(all_pages.contains("Reviewed build %02d" % index), "Review preserves build %d across pages" % index)
	check(all_pages.contains("Malformed entry"), "Last invalid record remains in paged review")
	for page: int in screen.recovery_panel._detail_pages.size():
		screen.recovery_panel._detail_page = page
		screen.recovery_panel._show_details_page()
		await settle()
		check(screen.recovery_panel.details.get_content_height() <= screen.recovery_panel.details.size.y, "Each recovery page fits at150%")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("recovery-text-150.png"))
	check(not FileAccess.file_exists(path), "Readability checks do not write player saves")
	DirAccess.remove_absolute(path + ".bak")
	screen.queue_free()
	await get_tree().process_frame
	if failures.is_empty(): print("CUSTOMIZE TEXT PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
