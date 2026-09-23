extends SceneTree
## Native menu canvas, all actions visible together; no focus-induced scrolling.
var failures := 0
var capture := "--capture" in OS.get_cmdline_user_args()

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func settle() -> void:
	for tick: int in 8: await process_frame

func inspect(screen: Control, context: String) -> void:
	var bounds := root.get_visible_rect().grow(1)
	for node: Node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree(): continue
		if control is ScrollContainer:
			check(control.get_v_scroll_bar().max_value <= control.get_v_scroll_bar().page + 1,
				context + " needs no vertical scrolling")
		if control is Label or control is Button or control is LineEdit:
			check(bounds.encloses(control.get_global_rect()), context + " visible: " + str(control.get_path()))
			check(control.size.y + 1 >= control.get_minimum_size().y, context + " full text height")
		if control is Button:
			var font := control.get_theme_font("font")
			var width := font.get_string_size(control.text, HORIZONTAL_ALIGNMENT_LEFT, -1, control.get_theme_font_size("font_size")).x
			var style := control.get_theme_stylebox("normal")
			check(control.size.x + 1 >= width + style.get_minimum_size().x, context + " full action text: " + control.text)

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var service := PublicServiceClient.new()
	service.endpoint = "https://fixture.invalid"
	root.add_child(service)
	service.set_process(false)
	var host := Control.new()
	root.add_child(host)
	var screen: Control = load("res://ui/menus/screens/online.tscn").instantiate()
	screen.service_override = service
	host.add_child(screen)
	for extent: Vector2i in ([Vector2i(1280,720)] if capture else [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080)]):
		root.size = extent
		# Match MenuGame._resize_menu, including the wider ultrawide canvas.
		var ratio := minf(extent.x / 1920.0, extent.y / 1080.0)
		host.scale = Vector2.ONE * ratio
		host.size = Vector2(extent) / ratio
		for factor: float in ([1.5] if capture else [1.0, 1.5]):
			screen.apply_text_scale(factor)
			for state: String in (["idle", "failed", "waiting"] if capture else ["idle", "failed", "long_error", "unavailable", "requesting", "waiting", "starting", "canceling"]):
				service.state = "failed" if state == "long_error" else ("idle" if state == "unavailable" else state)
				service.endpoint = "" if state == "unavailable" else "https://fixture.invalid"
				service.message = "Could not connect to the online service. Check your connection and try again." if state == "failed" else "Waiting for your opponent. Share the friend code to invite them."
				if state == "long_error":
					service.message = ("The server is running a different game version. Update your client before joining this match. If you already have the latest client, wait for the server update and try again. Your saved builds remain available in the garage. Please try later.").left(240)
				service.region = "Europe — Amsterdam"
				service.membership = {"code":"ABCD1234", "id":"fixture"} if state in ["waiting", "starting", "canceling"] else {}
				service.changed.emit()
				await settle()
				var context := "%s/%s/%s" % [extent, factor, state]
				inspect(screen, context)
				# Tab reaches every enabled action without moving it off-screen.
				screen.back_button.grab_focus()
				var visited: Array[Control] = []
				for step: int in 16:
					var focus := root.gui_get_focus_owner()
					if focus != null and not visited.has(focus): visited.append(focus)
					var event := InputEventAction.new()
					event.action = "ui_focus_next"
					event.pressed = true
					root.push_input(event)
					await process_frame
				for action: Control in [screen.quick_button, screen.create_button, screen.join_button, screen.back_button, screen.copy_button, screen.cancel_button]:
					if action.is_visible_in_tree() and not action.disabled:
						check(visited.has(action), context + " Tab reaches " + action.text)
				inspect(screen, context + " after Tab")
				if capture and extent == Vector2i(1280,720) and factor == 1.5 and state in ["idle", "failed", "waiting"]:
					await RenderingServer.frame_post_draw
					var folder := "res://exports/menu-flow-review"
					DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
					check(root.get_texture().get_image().save_png(folder + "/online-" + state + ".png") == OK, "Native capture saved")
	host.queue_free()
	service.queue_free()
	await settle()
	print("ONLINE MENU FIT PASS" if failures == 0 else "ONLINE MENU FIT FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)
