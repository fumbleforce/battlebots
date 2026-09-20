extends SceneTree
## Detached online panel: no live hosting, HTTP or gameplay world required.
class RecordingService extends PublicServiceClient:
	var requested_mode := ""
	var requested_capacity := 0
	var requested_code := ""
	func create_private(mode: String, capacity: int) -> void:
		requested_mode = mode
		requested_capacity = capacity
	func join_code(code: String) -> void:
		requested_code = code

var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func frames() -> void:
	for index: int in 6:
		await process_frame
func run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var service := RecordingService.new()
	service.endpoint = "https://fixture.invalid"
	root.add_child(service)
	service.set_process(false)
	var screen = load("res://ui/menus/screens/online.tscn").instantiate()
	screen.service_override = service
	root.add_child(screen)
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		await frames()
		check(screen.create_button.text.contains("1V1") and screen.create_button.has_focus(), "Private 1v1 is the initial primary action")
		var bounds := Rect2(Vector2.ZERO, Vector2(root.content_scale_size))
		for control: Control in [screen.create_button, screen.join_button, screen.code_input, screen.back_button, screen.status_label]:
			check(bounds.encloses(control.get_global_rect()), "Online panel fits %s: %s" % [resolution, control.get_class()])
		if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("user://online-panel-%d.png" % resolution.x)
	screen.create_button.pressed.emit()
	check(service.requested_mode == "teams" and service.requested_capacity == 2, "Primary action requests a real two-player teams room")
	screen.code_input.text = "ABCD1234"
	screen.code_input.text_submitted.emit(screen.code_input.text)
	check(service.requested_code == "ABCD1234", "Enter submits the code through the service")
	service.state = "waiting"
	service.message = "Waiting for players: 1 / 2"
	service.region = "test-region"
	service.membership = {"code": "DUEL1234"}
	service.changed.emit()
	await frames()
	check(not screen.actions.visible and screen.cancel_button.visible and screen.cancel_button.has_focus(), "Waiting hides duplicate actions and transfers focus to cancel")
	check(screen.code_label.text.contains("DUEL1234") and screen.copy_button.visible and screen.status_label.text.contains("1 / 2"), "Waiting preserves the real service count and shareable code")
	service.state = "canceling"
	service.changed.emit()
	check(screen.cancel_button.disabled and screen.back_button.has_focus(), "Cleanup disables repeat cancellation while preserving back navigation")
	service.state = "failed"
	service.membership.clear()
	service.message = "Could not connect. Try again."
	service.changed.emit()
	check(screen.actions.visible and not screen.create_button.disabled and not screen.copy_button.visible, "Clean failure restores retry actions and removes stale code")
	check(screen.status_label.text == service.message, "Failure reason comes from the service")
	service.endpoint = ""
	service.state = "idle"
	service.changed.emit()
	check(screen.create_button.disabled and screen.join_button.disabled and screen.state_heading.text == "ONLINE UNAVAILABLE", "Unconfigured deployment cannot advertise working hosted play")
	screen.queue_free()
	service.queue_free()
	await frames()
	print("ONLINE PANEL PASS" if failures == 0 else "ONLINE PANEL FAIL")
	quit(0 if failures == 0 else 1)
