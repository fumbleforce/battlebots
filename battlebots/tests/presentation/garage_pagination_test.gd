extends Node
var failures: Array[String] = []
func _ready() -> void: run.call_deferred()
func settle() -> void:
	for frame in 12: await get_tree().process_frame
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	get_window().size = Vector2i(1280,720)
	get_window().content_scale_size = Vector2i(1920,1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	PlayerProfile.save_path = "user://garage-pagination-%d.json" % Time.get_ticks_usec()
	PlayerProfile.reload()
	for i in 8:
		PlayerProfile.new_build()
		if i == 3: PlayerProfile.rename_draft("A long experimental demonstration robot name")
	for resource: String in ["customize", "garage"]:
		var screen: Control = load("res://ui/menus/screens/%s.tscn" % resource).instantiate()
		add_child(screen)
		for factor: float in [1.0,1.25,1.5,1.0]:
			screen.apply_text_scale(factor)
			await settle()
			if resource == "customize":
				for tab: String in ["parts","paint"]:
					screen._set_tab(tab)
					await settle()
					print("PAGINATION ",tab," scale ",factor," categories ",screen._category_capacity)
					if tab == "paint": check(screen._category_ranges.size() == 1 and not screen._category_pager.visible,
						"Every paint layer fits on one page at text scale %s" % factor)
					for category: int in PlayerProfile.catalogue[tab].size():
						screen._cat[tab] = category
						screen._category_page[tab] = screen._page_for_item(screen._category_ranges, category)
						screen._refresh()
						await settle()
						check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081,"Customize footer contained")
						check_full_page(screen.get_node("%Categories"), screen._category_pager, screen._category_ranges[screen._category_page[tab]], 1)
						var scroll: ScrollContainer = screen._choice_scroll
						check(scroll.get_global_rect().end.y <= screen.get_node("Layout/Footer").get_global_rect().position.y + 1, "Choice list scrolls within the body")
						for tile: Control in screen.get_node("%Items").get_children():
							if tile.has_node("Inner"): check(tile.get_global_rect().end.x <= scroll.get_global_rect().end.x - scroll.get_v_scroll_bar().size.x + 1 or not scroll.get_v_scroll_bar().visible, "Scrollbar does not cover choices")
						for row: Control in screen.get_node("%Categories").get_children():
							if row.visible: check(row.get_global_rect().end.y <= 970,"Category contained")
						for tile: Control in screen.get_node("%Items").get_children():
							if tile.visible and tile.has_node("Inner"): check(tile.get_node("Inner").size.y <= tile.size.y + 1,"Tile content contained %s %d %s tile%s inner%s" % [tab, category, factor, tile.size, tile.get_node("Inner").size])
			else:
				print("PAGINATION garage scale ",factor," capacity ",screen._build_capacity)
				check(screen._build_ranges[0].y > 2,"Garage uses available height")
				for page in screen._build_ranges.size():
					screen._build_page = page
					screen._refresh_builds()
					await settle()
					check(screen.get_node("%BotList").get_child(screen._build_ranges[page].x).visible,"Every build page reachable")
					check_full_page(screen.get_node("%BotList"), screen._build_pager, screen._build_ranges[page], 1)
				check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081,"Garage footer contained")
				for row: Control in screen.get_node("%BotList").get_children():
					if row.visible: check(row.get_node("Pad").size.y <= row.size.y + 1,"Build content contained")
		for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]:
			get_window().size = resolution
			screen.apply_text_scale(1.5)
			await settle()
			check(screen.get_node("Layout/Footer").get_global_rect().end.y <= 1081,"Footer fits resolution " + str(resolution))
			if resource == "customize":
				screen._set_tab("paint")
				screen._cat.paint = 0
				screen._refresh()
				await settle()
				var key := "paint:0"
				var last: int = PlayerProfile.catalogue.paint[0].items.size() - 1
				screen._item[key] = last
				screen._refresh()
				await settle()
				var tile: Control = screen.get_node("%Items").get_child(last)
				tile.grab_focus()
				await settle()
				check(screen._choice_scroll.get_global_rect().grow(1).encloses(tile.get_global_rect()),"Focused choice scrolls into view")
			else:
				check(screen.get_node("%BotList").get_child(PlayerProfile.active_bot).visible,"Selected build visible after resize")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("%s-pagination-%d-150.png" % [resource, resolution.y]))

		get_window().size = Vector2i(1920,1440)
		await settle()
		if resource == "customize":
			var bar: VScrollBar = screen._choice_scroll.get_v_scroll_bar()
			check(bar.max_value <= bar.page + 1,"Taller aspect fits every paint choice without scrolling")
		else:
			check(screen._build_ranges[0].y > 4,"Taller aspect adds build rows")
		get_window().size = Vector2i(1920,1080)
		await settle()

		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(resource + "-pagination.png"))
		screen.queue_free()
		await settle()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("GARAGE PAGINATION PASS")
	get_tree().quit(0 if failures.is_empty() else 1)




func check_full_page(list: Container, pager: Control, page: Vector2i, columns: int) -> void:
	if page.y >= list.get_child_count(): return
	var bottom := 0.0
	for i in range(page.x, page.y): bottom = maxf(bottom, list.get_child(i).get_global_rect().end.y)
	var next_height := 0.0
	for i in range(page.y, mini(page.y + columns, list.get_child_count())):
		next_height = maxf(next_height, list.get_child(i).get_combined_minimum_size().y)
	var gap := list.get_theme_constant("v_separation" if list is GridContainer else "separation")
	# A section heading only moves with its first row of choices.
	if list.get_child(page.y) is Label and page.y + columns < list.get_child_count():
		next_height += gap + list.get_child(page.y + columns).get_combined_minimum_size().y
	var available_end: float = pager.get_global_rect().position.y - list.get_parent().get_theme_constant("separation")
	check(bottom + gap + next_height > available_end + 1, "Next row cannot fit unused vertical space: " + str(list.get_path()))
