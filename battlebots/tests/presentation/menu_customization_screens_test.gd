extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var profile = root.get_node("PlayerProfile")
	profile.save_path = "user://menu-screens-test-%d.json" % Time.get_ticks_usec()
	profile.reload()
	for name: String in ["garage","customize","upgrade_shop"]:
		var screen: Control = load("res://ui/menus/screens/"+name+".tscn").instantiate()
		root.add_child(screen)
		for _frame in 5: await process_frame
		if name == "garage":
			check(screen.build_preview.model != null, "Garage shows live selected build")
			check(screen.get_node("%BotName").text == "Striker","Garage canonical starter")
			check(screen.get_node("%BotHp").text == "260 core HP","Garage core HP")
		if name == "customize":
			check(screen.build_preview.weapon_visual.kind == "vertical_spinner", "Customization shows equipped weapon")
			var paint: Dictionary = profile.catalogue.paint[0]
			profile.equip("paint", paint, paint.items[1])
			var chassis: MeshInstance3D = screen.build_preview.model.get_node("Chassis")
			check(chassis.material_override.albedo_color.is_equal_approx(GarageBotPreview.PAINTS.orange), "Unsaved paint updates live preview")
			profile.undo_edit()
			chassis = screen.build_preview.model.get_node("Chassis")
			check(chassis.material_override.albedo_color.is_equal_approx(GarageBotPreview.PAINTS.cyan), "Undo refreshes live preview")
			check(screen.get_node("%Categories").get_child_count() == 5,"Five canonical categories")
			screen._set_tab("paint")
			check(screen.get_node("%Items").get_child_count() == 4,"Four canonical paints")
			screen._set_tab("decals")
			check(screen.get_node("%Action").disabled,"Unsupported decals disabled")
			screen._set_tab("parts")
		if name == "upgrade_shop":
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://b-kit-build-rules.png")
			screen._set_tab("parts")
			var registry := ContentRegistry.new()
			var displayed_parts: Array[String] = []
			for card: Node in screen.get_node("%ItemsView").get_children():
				displayed_parts.append(card.get_node("%Name").text)
			check(displayed_parts.size() == registry.parts.size(),"Full canonical part catalogue")
			for part_id: String in registry.parts:
				check(displayed_parts.count(part_id.capitalize()) == 1,
					"Canonical part appears exactly once: " + part_id)
			for weapon_id: String in ["vertical_spinner", "horizontal_spinner", "hammer", "saw", "lifter"]:
				check(displayed_parts.has(weapon_id.capitalize()),"Implemented weapon is available: " + weapon_id)
			check(screen.get_node("%ItemsView").get_parent() is ScrollContainer,"Catalogue scrolls")
		for _frame in 4: await process_frame
		var footer: Control = screen.get_node("Layout/Footer")
		check(footer.get_global_rect().end.y <= 1081,"Footer remains within viewport: "+name)
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://b-kit-"+name+".png")
		screen.free()
		await process_frame
	if failures.is_empty(): print("MENU CUSTOMIZATION SCREENS PASS")
	else:
		for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
