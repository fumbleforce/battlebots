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
	for name: String in ["garage","customize"]:
		var screen: Control = load("res://ui/menus/screens/"+name+".tscn").instantiate()
		root.add_child(screen)
		for _frame in 5: await process_frame
		if name == "garage":
			check(screen.build_preview.model != null, "Garage shows live selected build")
			check(screen.get_node("%BotName").text == profile.bots[profile.active_bot].name,"Garage displays the selected build")
			check(screen.get_node("%BotHp").text == "260 core HP","Garage core HP")
		if name == "customize":
			check(screen.get_node_or_null("%ShopLink") == null, "Customize has no catalogue link")
			check(screen.build_preview.sawblade_visual != null and screen.build_preview.sawblade_visual.kind == profile.loadouts[profile.active_bot].parts.weapon, "Customization shows equipped authored weapon")
			var paint: Dictionary = profile.catalogue.paint[0]
			var original_color: Array = profile.loadouts[profile.active_bot].cosmetics.sawblade.paint_primary.duplicate()
			var original_model: Node3D = screen.build_preview.model
			profile.equip("paint", paint, paint.items[1])
			check(profile.loadouts[profile.active_bot].cosmetics.sawblade.paint_primary != original_color and screen.build_preview.model != original_model, "Unsaved paint rebuilds the authored preview")
			var painted_model: Node3D = screen.build_preview.model
			profile.undo_edit()
			check(profile.loadouts[profile.active_bot].cosmetics.sawblade.paint_primary == original_color and screen.build_preview.model != painted_model, "Undo restores authored preview paint")
			check(screen.get_node("%Categories").get_child_count() == ContentRegistry.SLOTS.size(),"Every canonical category is available")
			screen._set_tab("paint")
			check(screen.get_node("%Items").get_child_count() == 4,"Four canonical paints")
			screen._set_tab("decals")
			check(screen.get_node("%Items").get_child_count() > 0 and screen.get_node("%Action").text in ["EQUIPPED", "EQUIP"], "Vehicle options remain available in Customize")
			screen._set_tab("parts")
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
