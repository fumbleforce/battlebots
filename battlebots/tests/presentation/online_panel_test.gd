extends SceneTree
## Detached online panel: no live hosting, HTTP or gameplay world required.
class RecordingService extends PublicServiceClient:
	var requested_mode := ""
	var requested_capacity := 0
	var requested_code := ""
	var quick_requests := 0
	func quick_play() -> void:
		quick_requests += 1
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
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = resolution
		for text_scale in [1.0, 1.5]:
			screen.apply_text_scale(text_scale)
			screen.quick_button.grab_focus()
			await frames()
			check(screen.quick_button.text.contains("1V1") and screen.quick_button.has_focus() and screen.quick_button.theme_type_variation == &"PrimaryButton", "Quick Play 1v1 is the primary keyboard action")
			check(screen.quick_button.find_next_valid_focus() == screen.create_button and screen.create_button.find_next_valid_focus() == screen.code_input and screen.code_input.find_next_valid_focus() == screen.join_button, "Tab order reaches queue, private creation and invite entry")
			for item: Node in screen.header_panel.find_children("*", "Label", true, false):
				check(screen.header_panel.get_global_rect().encloses(item.get_global_rect()), "Enlarged header text stays inside the header")
			var bounds := Rect2(Vector2.ZERO, Vector2(root.content_scale_size))
			for control: Control in [screen.quick_button, screen.create_button, screen.join_button, screen.code_input, screen.back_button]:
				control.grab_focus()
				await frames()
				check(control.has_focus() and bounds.encloses(control.get_global_rect()), "Online action is reachable at %s/%s: %s" % [resolution, text_scale, control.get_class()])
				var scroll: Node = control.get_parent()
				while scroll != screen and not scroll is ScrollContainer:
					scroll = scroll.get_parent()
				if scroll is ScrollContainer:
					check(scroll.get_global_rect().encloses(control.get_global_rect()), "Keyboard focus scrolls the action fully into view")
			for item: Node in screen.find_children("*", "Label", true, false):
				var label := item as Label
				if label.is_visible_in_tree():
					check(label.get_visible_line_count() == label.get_line_count(), "All wrapped label lines remain visible")
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				for target: Control in [screen.quick_button, screen.join_button]:
					target.grab_focus()
					await frames()
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("user://online-panel-%d-%d-%s.png" % [resolution.x, roundi(text_scale * 100), "quick" if target == screen.quick_button else "private"])
	screen.quick_button.pressed.emit()
	check(service.quick_requests == 1, "Quick Play calls the public service queue action")
	screen.create_button.pressed.emit()
	check(service.requested_mode == "teams" and service.requested_capacity == 2, "Primary action requests a real two-player teams room")
	screen.code_input.text = "ABCD1234"
	screen.code_input.grab_focus()
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
	service.membership = {"code": ""}
	service.message = "Finding an opponent for your 1v1 duel."
	service.changed.emit()
	check(screen.state_heading.text == "FINDING YOUR OPPONENT" and not screen.code_label.visible and not screen.copy_button.visible, "Queue waiting has no private code affordance")
	check(screen.quick_button.disabled and not screen.actions.visible, "Active search prevents duplicate queue requests")
	screen.quick_play()
	check(service.quick_requests == 1, "Direct repeat activation while searching is ignored")
	service.state = "canceling"
	service.changed.emit()
	check(screen.cancel_button.disabled and screen.back_button.has_focus(), "Cleanup disables repeat cancellation while preserving back navigation")
	service.state = "failed"
	service.membership.clear()
	service.message = "Could not connect. Try again."
	service.changed.emit()
	check(screen.actions.visible and not screen.create_button.disabled and not screen.copy_button.visible, "Clean failure restores retry actions and removes stale code")
	check(not screen.quick_button.disabled and screen.status_label.has_focus(), "Failure focuses its reason while keeping Quick Play enabled")
	check(screen.status_label.text == service.message, "Failure reason comes from the service")
	for resolution: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		for text_scale in [1.0, 1.5]:
			screen.apply_text_scale(text_scale)
			service.message = "This game build does not match the online service. Install the current game build."
			service.changed.emit()
			await frames()
			var scroll: Node = screen.status_label.get_parent()
			while not scroll is ScrollContainer:
				scroll = scroll.get_parent()
			check(scroll.get_global_rect().encloses(screen.status_label.get_global_rect()), "Compatibility failure remains inside the visible scroll area at %s/%s" % [resolution, text_scale])
	service.endpoint = ""
	service.state = "idle"
	service.changed.emit()
	check(screen.quick_button.disabled and screen.create_button.disabled and screen.join_button.disabled and screen.state_heading.text == "ONLINE UNAVAILABLE", "Unconfigured deployment cannot advertise working hosted play")
	screen.queue_free()
	service.queue_free()
	await frames()
	print("ONLINE PANEL PASS" if failures == 0 else "ONLINE PANEL FAIL")
	quit(0 if failures == 0 else 1)
