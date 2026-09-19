extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count: int) -> void:
	for index: int in range(count):
		await process_frame
func run() -> void:
	var app = preload("res://scenes/app/mvp.tscn").instantiate()
	root.add_child(app)
	current_scene = app
	if app.preview == null:
		app._build_console()
	await frames(3)
	app.preview.release_controls()
	var event := InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	root.push_input(event)
	await frames(2)
	check(current_scene == app and app.session.connection_state == "practice", "Escape never removes the current game scene")
	root.push_input(event)
	await frames(2)
	check(current_scene == app and not app.preview.controls_enabled, "Second Escape opens menu without leaving")
	app.preview.open_settings()
	root.push_input(event)
	await frames(2)
	check(current_scene == app and not app.preview.settings_panel.visible, "Escape cancels settings without leaving")
	app.return_to_main_menu()
	app.return_to_main_menu()
	check(current_scene == app and app.is_inside_tree(), "Main-menu transition is deferred and idempotent")
	await frames(5)
	check(not is_instance_valid(app) and current_scene.name == "Battlebots", "Explicit Main menu safely replaces and frees the session scene")
	print("NAVIGATION PASS" if failures == 0 else "NAVIGATION FAIL")
	quit(0 if failures == 0 else 1)
