extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func capture(path: String) -> void:
	for frame: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path) == OK, "Capture diagnostics layout")
	print("CAPTURE: ", ProjectSettings.globalize_path(path))

func run() -> void:
	root.size = Vector2i(1280, 720)
	var scene: Control = load("res://scenes/dev/b_network_diagnostics.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for index: int in range(8):
		scene.show_scenario(index)
		await process_frame
		check(not scene.panel.title_label.text.is_empty(), "Scenario has status")
		# Global rects are in the root's logical canvas (canvas_items stretch), not physical pixels.
		check(root.get_visible_rect().encloses(scene.panel.get_global_rect()),
			"Expanded scenario fits the viewport")
	scene.show_scenario(1)
	if "--capture" in OS.get_cmdline_user_args():
		await capture("user://b-network-diagnostics-preview.png")
	scene.queue_free()
	await process_frame
	set_meta("start_mode", "multiplayer")
	var app: Node3D = load("res://scenes/app/mvp.tscn").instantiate()
	root.add_child(app)
	if DisplayServer.get_name() == "headless":
		app._build_console()
	app.preview.release_controls()
	app.preview.network_diagnostics.expanded = true
	for frame: int in range(3):
		await process_frame
	check(app.preview.network_diagnostics.visible, "A's offline menu includes network status")
	check(not app.preview.network_diagnostics.get_global_rect().intersects(app.console_panel.get_global_rect()),
		"Diagnostics do not cover A's session menu")
	if "--capture" in OS.get_cmdline_user_args():
		await capture("user://b-network-diagnostics-app.png")
	app.session.leave()
	app.queue_free()
	await process_frame
	print("NETWORK DIAGNOSTICS SANDBOX PASS" if failures == 0 else "NETWORK DIAGNOSTICS SANDBOX FAIL")
	quit(0 if failures == 0 else 1)
