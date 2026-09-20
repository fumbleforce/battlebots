extends Node
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	var host := Control.new()
	host.size = Vector2(600, 440)
	add_child(host)
	var preview := GarageBotPreview.new()
	preview.show_loadout(ContentRegistry.new().starter())
	host.add_child(preview)
	preview.set_process(false)
	await get_tree().process_frame
	var turntable: Node3D = preview.model.get_parent()
	var original_model := preview.model.get_instance_id()
	preview._process(1.0)
	check(is_zero_approx(turntable.rotation.y), "Default garage remains manually controlled")
	check(not preview.rotation_button.visible, "Manual garage has no auto-rotation control")
	preview.set_auto_rotate(true)
	var camera_transform := preview.camera.global_transform
	var model_transform := preview.model.global_transform
	preview._process(1.0)
	check(is_equal_approx(turntable.rotation.y, 0.22), "Showcase slowly rotates its assembly")
	check(not preview.model.global_transform.is_equal_approx(model_transform), "Actual assembled geometry rotates")
	check(preview.camera.global_transform.is_equal_approx(camera_transform), "Automatic rotation does not orbit camera")
	check(turntable.get_child(0) is MeshInstance3D, "Pedestal shares rotating parent with model")
	check(preview.model.get_instance_id() == original_model, "Animation preserves assembled model")
	var angle := turntable.rotation.y
	host.hide()
	preview._process(2.0)
	check(is_equal_approx(turntable.rotation.y, angle), "Hidden ancestor suspends animation")
	host.show()
	preview.grab_focus()
	preview._process(2.0)
	check(is_equal_approx(turntable.rotation.y, angle), "Focused manual preview suspends animation")
	preview.release_focus()
	preview.rotation_button.pressed.emit()
	preview._process(2.0)
	check(is_equal_approx(turntable.rotation.y, angle), "Explicit Pause stops animation")
	preview.show_loadout(ContentRegistry.new().duelist())
	preview._process(2.0)
	check(is_equal_approx(turntable.rotation.y, angle), "Build selection preserves reduced-motion choice")
	check(preview.rotation_button.text == "RESUME ROTATION", "Paused control clearly offers Resume")
	preview.rotation_button.grab_focus()
	check(preview.rotation_button.has_focus(), "Rotation toggle is keyboard focusable")
	preview.rotation_button.pressed.emit()
	preview._process(1.0)
	check(not is_equal_approx(turntable.rotation.y, angle), "Resume works while its button retains focus")
	angle = turntable.rotation.y
	preview.rotate_view(Vector2(0.2, 0.1))
	preview._process(1.0)
	check(is_equal_approx(turntable.rotation.y, angle), "Manual orbit pauses automatic motion")
	preview.rotation_button.pressed.emit()
	preview.zoom_view(0.1)
	preview._process(1.0)
	check(is_equal_approx(turntable.rotation.y, angle), "Manual zoom pauses automatic motion")
	host.size.y = 150
	for factor: float in [1.0, 1.25, 1.5, 1.0]:
		preview.apply_text_scale(factor)
		await get_tree().process_frame
		check(preview.rotation_button.get_theme_font_size("font_size") == roundi(18 * factor), "Rotation control uses full noncompounding text factor")
		check(preview.get_global_rect().encloses(preview.rotation_button.get_global_rect()), "Rotation control fits preview at every text factor")
		check(preview.status.size.y <= 54, "Showcase status stays compact at 150px preview height")
	preview.show_loadout({})
	preview.rotation_button.pressed.emit()
	preview._process(1.0)
	check(preview.model == null, "Invalid build clears stale assembly")
	check(not preview.rotation_button.visible, "Invalid build hides unavailable rotation control")
	check(is_equal_approx(turntable.rotation.y, angle), "Invalid showcase suspends rotation")
	var invalid := ContentRegistry.new().starter()
	invalid.name = ""
	invalid.parts.weapon = "unknown"
	invalid.parts.chassis = "unknown"
	preview.show_loadout(invalid)
	check(preview._status_pages.size() > 1, "Invalid fixture contains multiple reason pages")
	preview._status_next.pressed.emit()
	var reviewed_reason := preview.status.text
	for refresh in 3: preview.show_loadout(invalid.duplicate(true))
	check(preview.status.text == reviewed_reason and preview._status_page == 1, "Repeated invalid refresh preserves reviewed reason page")
	preview.show_loadout(ContentRegistry.new().starter())
	check(preview.model != null and preview._status_pages.is_empty(), "Changed valid build replaces cached invalid status")
	preview.show_loadout(invalid)
	check(preview.model == null and preview._status_page == 0, "Changed invalid build clears valid geometry and starts its own review")
	preview.set_auto_rotate(false)
	check(is_zero_approx(turntable.rotation.y), "Disabling showcase restores normal model orientation")
	host.free()
	for frame in 2: await get_tree().process_frame
	if failures.is_empty(): print("GARAGE SHOWCASE PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
