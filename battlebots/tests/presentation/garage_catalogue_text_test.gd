extends Node
var failures: Array[String] = []
func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func settle() -> void:
	for _frame: int in 8: await get_tree().process_frame
func run() -> void:
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1920,1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var profile: Node = get_node("/root/PlayerProfile")
	profile.save_path = "user://garage-catalogue-text-%d.json" % Time.get_ticks_usec()
	profile.reload()
	profile.new_build()
	profile.rename_draft("A very long experimental robot name")
	for resource: String in ["garage", "upgrade_shop"]:
		var screen: Control = load("res://ui/menus/screens/%s.tscn" % resource).instantiate()
		add_child(screen)
		for factor: float in [1.0,1.25,1.5,1.5,1.0,1.5]:
			screen.apply_text_scale(factor)
			await settle()
			check(screen.get_node("%Title").get_theme_font_size("font_size") == roundi(53 * factor), resource + " exact idempotent heading scale")
			check(screen.get_node("Layout").size.x <= 1921, resource + " fits logical width")
			check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081, resource + " footer remains onscreen")
		if resource == "garage":
			screen._refresh_builds()
			await settle()
			var row: Control = screen.get_node("%BotList").get_child(0)
			check(row.get_node("%Name").get_theme_font_size("font_size") == 44,"Rebuilt build row uses current scale")
			row.grab_focus()
			check(row.has_focus(),"Garage build remains keyboard focusable")
			for slot_name: String in ["WeaponSlot", "AbilitySlot", "BoostSlot"]:
				var slot: Control = screen.get_node("%" + slot_name)
				check(slot.get_node("Pad").size.y <= slot.size.y + 1,slot_name + " contains scaled labels")
			await capture("garage")
			profile.loadouts[profile.active_bot].parts.weapon = "missing_weapon"
			profile._draft_changed()
			await settle()
			check(not screen.get_node("%Stats").visible,"Invalid build hides unavailable stats")
			await capture("garage-invalid")
			var body_scroll: ScrollContainer = screen.get_node("Layout/GarageBodyScroll")
			body_scroll.grab_focus()
			check(body_scroll.has_focus(),"Garage scroll accepts keyboard focus")
			body_scroll.scroll_vertical = int(body_scroll.get_v_scroll_bar().max_value)
			var list_scroll: ScrollContainer = screen.get_node("%BotList").get_parent()
			list_scroll.scroll_vertical = int(list_scroll.get_v_scroll_bar().max_value)
			await settle()
			var last_row: Control = screen.get_node("%BotList").get_child(3)
			check(last_row.get_node("Pad").size.y <= last_row.size.y + 1,"Long name contained in build row")
			await capture("garage-bottom")
		else:
			profile.active_bot = 0
			screen._set_tab("upgrades")
			await settle()
			await capture("catalogue-rules")
			for tab: String in ["parts","cosmetics"]:
				screen._set_tab(tab)
				await settle()
				var card: Control = screen.get_node("%ItemsView").get_child(0)
				check(card.get_node("%Name").get_theme_font_size("font_size") == 47,"Rebuilt catalogue heading uses current scale")
				check(screen.get_node("%ItemsView").size.x <= screen.get_node("%ItemsView").get_parent().size.x + 1,"Catalogue grid fits scroll width")
				await capture("catalogue-" + tab)
		for resolution: Vector2i in [Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]:
			get_window().size = resolution
			await settle()
			check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081,resource + " footer fits " + str(resolution))
			check(screen.get_node("Layout").size.x <= 1921,resource + " width fits " + str(resolution))
		get_window().size = Vector2i(1280,720)
		screen.queue_free()
		await get_tree().process_frame
	if failures.is_empty(): print("GARAGE CATALOGUE TEXT PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
func capture(label: String) -> void:
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(label + "-text.png"))
