extends SceneTree
## All implemented modes use the same main menu, lobby and persistent game owner.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index: int in range(count):
		await process_frame

func run() -> void:
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	var router: Node = root.get_node("MenuRouter")
	var port := 31000 + OS.get_process_id() % 10000
	for mode: String in ["5v5", "ffa"]:
		game.screen.get_node("%Play").pressed.emit()
		await frames()
		check(router.current == "mode_select", "Host opens unified mode selection")
		var selected: Button
		for card: Button in game.screen.get_node("%Cards").get_children():
			if card.data.get("id") == mode:
				selected = card
		check(selected != null and not selected.disabled, mode + " is selectable in normal host flow")
		if selected == null:
			break
		selected.pressed.emit()
		var capacity: OptionButton = game.screen.capacity_choice
		if mode == "ffa":
			check(capacity.is_visible_in_tree() and capacity.get_selected_id() == 8, "FFA defaults to eight players before selection")
			var index := capacity.get_item_index(5)
			check(index >= 0, "FFA offers a five-player maximum")
			capacity.select(index)
			capacity.item_selected.emit(index)
			check(router.match_setup.capacity == 5, "Actual FFA dropdown publishes the selected maximum")
		else:
			check(not capacity.is_visible_in_tree(), "Team modes do not expose an irrelevant FFA capacity choice")
		game.screen.get_node("%Next").pressed.emit()
		await frames()
		check(router.current == "lobby" and current_scene == game, mode + " continues directly to the persistent lobby")
		if router.current != "lobby":
			break
		var lobby: Control = game.screen
		lobby.port.value = port
		lobby.host_button.pressed.emit()
		await frames()
		check(game.session.connection_state == "hosting", mode + " hosts a real session from the unified lobby")
		check(game.session.lobby_view.get("mode") == mode, mode + " lobby publishes its authoritative mode")
		if mode == "5v5":
			check(game.session.player_capacity == 10, "5v5 selects ten-player capacity")
		else:
			check(game.session.match_mode == "ffa" and game.session.player_capacity == 5, "FFA hosts the five-player maximum selected in the dropdown")
		check(game.session.lobby_view.get("capacity") == game.session.player_capacity, "Lobby capacity agrees with authority")
		var loading: Control = load("res://ui/menus/screens/loading.tscn").instantiate()
		root.add_child(loading)
		await frames(2)
		var roster: Label = loading._roster
		var slots: Array = game.session.lobby_view.get("slots", [])
		check(roster.visible and roster.text.split("\n").size() == slots.size() + 1, "Expanded loading roster displays only actual participants")
		for slot: Dictionary in slots:
			check(roster.text.contains("PLAYER %d" % int(slot.entity_id)), "Loading roster includes each authoritative participant")
		check(not loading.get_node("BlueTeam").visible and not loading.get_node("RedTeam").visible, "Expanded modes hide the legacy four-player loading cards")
		if mode == "ffa":
			check(roster.text.begins_with("FREE FOR ALL") and not roster.text.contains("BLUE") and not roster.text.contains("RED"), "FFA loading roster uses neutral player labels")
		loading.queue_free()
		await frames(2)
		lobby.get_node("%Back").pressed.emit()
		await frames()
		check(game.session.connection_state == "offline" and router.current == "main" and current_scene == game, mode + " Leave returns to main and frees the port without swapping apps")
	game.session.leave()
	game.queue_free()
	await frames()
	print("ADVANCED MENU PASS" if failures == 0 else "ADVANCED MENU FAIL")
	quit(0 if failures == 0 else 1)
