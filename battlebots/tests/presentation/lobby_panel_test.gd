extends SceneTree
var _failures: Array[String] = []
var _requests: Array = []
func _initialize() -> void:
	call_deferred("_run")
func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var panel: LobbyPanel = load("res://scenes/ui/lobby_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	panel.host_requested.connect(func(port: int, count: int) -> void: _requests.append([port, count]))
	panel.ready_requested.connect(func(value: bool) -> void: _requests.append(value))
	panel.loadout_requested.connect(func(draft: Dictionary) -> void: _requests.append(draft))
	panel.render("offline", {}, -1)
	panel.focus_default()
	_check(panel.host_button.has_focus(), "Offline focuses Host")
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	root.push_input(key)
	await process_frame
	key.pressed = false
	root.push_input(key)
	await process_frame
	_check(_requests.size() == 1 and _requests[0] == [24567, 4], "Keyboard Host emits port and 2v2 default")
	var registry := ContentRegistry.new()
	var view := {"capacity":4, "mode":"2v2", "phase":"lobby", "slots":[{"entity_id":1, "team":0, "connected":true, "ready":false, "loadout":registry.starter()}, {"entity_id":2, "team":1, "connected":false, "ready":true, "loadout":registry.starter(true)}]}
	var original := view.duplicate(true)
	panel.render("hosting", view, 1)
	_check(panel.roster_labels[0].text.contains("YOU") and panel.roster_labels[1].text.contains("OPEN"), "Local and open slots shown")
	_check(panel.roster_labels[2].text.contains("Disconnected"), "Disconnected roster retained")
	panel.ready_button.pressed.emit()
	_check(_requests.back() == true and panel.ready_button.text == "Ready", "Ready request is not optimistic")
	panel.loadout_choice.item_selected.emit(1)
	_check(_requests.back() == registry.starter(true) and panel.loadout_choice.selected == 0, "Loadout restores authoritative selection")
	panel.focus_default()
	panel.render("hosting", view, 1)
	_check(panel.ready_button.has_focus(), "Rerender preserves focus")
	panel.render("hosting", view, 1, {"pending":true})
	_check(panel.ready_button.disabled and panel.team_choice.disabled and panel.loadout_choice.disabled, "Pending locks edits")
	view.phase = "active"
	panel.render("hosting", view, 1, {"can_resume":true})
	_check(panel.ready_button.disabled and panel.resume_button.visible, "Active phase locks edits and allows explicit resume")
	view.phase = "lobby"
	_check(view == original, "Panel never mutates view")
	panel.render("hosting", {"capacity":4,"slots":[{}]}, 1)
	_check(panel.ready_button.disabled and panel.team_choice.disabled, "Malformed view disables edits")
	panel.render("connecting", {}, -1)
	panel.focus_default()
	_check(panel.leave_button.has_focus() and panel.leave_button.text == "Cancel connection", "Connecting offers focused cancel")
	panel.render("hosting", original, 1, {"endpoint":"Office host · UDP 24567", "notice":"Waiting for all players to ready", "build":"mvp-ab-2"})
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await process_frame
		root.get_texture().get_image().save_png("user://b-lobby-panel.png")
		print(ProjectSettings.globalize_path("user://b-lobby-panel.png"))
	if _failures.is_empty():
		print("LOBBY PANEL PASS")
	else:
		for failure: String in _failures:
			push_error(failure)
	quit(0 if _failures.is_empty() else 1)
