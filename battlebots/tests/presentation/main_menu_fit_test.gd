extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames() -> void:
	for frame: int in 8:
		await process_frame
func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var host := Control.new()
	root.add_child(host)
	var screen: Control = load("res://ui/menus/screens/main_menu.tscn").instantiate()
	host.add_child(screen)
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(1280,1024)]:
		root.size = resolution
		var ratio := minf(resolution.x / 1920.0, resolution.y / 1080.0)
		host.scale = Vector2.ONE * ratio
		host.size = Vector2(resolution) / ratio
		for factor: float in [1.0,1.25,1.5,1.0]:
			screen.apply_text_scale(factor)
			await frames()
			var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
			for control: Node in screen.find_children("*", "Control", true, false):
				if not control.is_visible_in_tree():
					continue
				check(not control is ScrollContainer, "Main menu contains no scrolling surface")
				if control is Label or control is Button:
					check(bounds.grow(1).encloses(control.get_global_rect()), "%s %.2f contains %s %s" % [resolution, factor, screen.get_path_to(control), control.get_global_rect()])
			check(screen.get_node("Bg").get_global_rect().is_equal_approx(bounds), "Background fills " + str(resolution))
			check(screen.get_node("%Play").theme_type_variation == &"MenuItem", "Host LAN is secondary")
			check(screen.get_node("%PlayOnline").theme_type_variation == &"MenuItemPrimary", "Online is primary")
			check(screen.get_node("%PlayOnline").get_theme_font_size("font_size") == roundi(40 * factor), "Accessible text scales without accumulating")
			check(screen.get_node("%Play").get_theme_stylebox("hover").bg_color.a < 0.1, "Secondary hover remains subtle")
			if factor == 1.5 and "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://main-fit-%dx%d.png" % [resolution.x,resolution.y])
	host.queue_free()
	await frames()
	print("MAIN MENU FIT PASS" if failures == 0 else "MAIN MENU FIT FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
