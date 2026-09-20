extends SceneTree
## Main-menu intent follows a short path without mandatory garage or map choices.
var failures := 0
var game: Node3D
var router: Node
var profile: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index: int in range(count):
		await process_frame

func press(unique_name: String) -> bool:
	var button := game.screen.get_node_or_null("%" + unique_name) as Button
	if button == null:
		check(false, "Menu exposes " + unique_name)
		return false
	check(button.is_visible_in_tree() and not button.disabled, unique_name + " is an available action")
	button.pressed.emit()
	await frames()
	return true

func run() -> void:
	root.size = Vector2i(1280, 720)
	router = root.get_node("MenuRouter")
	profile = root.get_node("PlayerProfile")
	var original_bot: int = profile.active_bot
	profile.active_bot = 1
	game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	var viewport_bounds := Rect2(Vector2.ZERO, Vector2(root.size))
	for action: Control in game.screen.get_node("%Play").get_parent().get_children():
		if action.is_visible_in_tree():
			check(viewport_bounds.encloses(action.get_global_rect()), "Main action fits the 1280×720 viewport: " + str(action.name))
	await join_flow()
	await host_flow()
	await garage_flow()
	await practice_flow()
	profile.active_bot = original_bot
	game.session.leave()
	game.queue_free()
	await frames()
	print("MENU FLOW PASS" if failures == 0 else "MENU FLOW FAIL")
	quit(0 if failures == 0 else 1)

func join_flow() -> void:
	var join_button := game.screen.get_node_or_null("%JoinGame") as Button
	check(join_button != null and not join_button.disabled, "Main exposes an available Join Game action")
	if join_button == null:
		return
	var click := InputEventMouseButton.new()
	click.position = join_button.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	await frames()
	check(router.current == "lobby" and router.lobby_intent == "join", "Main Join opens the join screen directly")
	if router.current != "lobby":
		return
	var lobby: Control = game.screen
	check(game.session.connection_state == "offline", "Opening Join does not silently create a game")
	check(lobby.join_button.is_visible_in_tree() and not lobby.host_button.is_visible_in_tree(), "Join screen offers joining without host setup")
	check(lobby.address.is_visible_in_tree() and lobby.address.editable, "Join immediately accepts the host address")
	check(not lobby.get_node("Layout/Body/Row/Match/Rules").is_visible_in_tree(), "Offline Join does not require or imply a map selection")
	check(not lobby.get_node("Layout/Body/Row/Blue").is_visible_in_tree() and not lobby.get_node("Layout/Body/Row/Red").is_visible_in_tree(), "Offline Join does not invent host teams")
	check(lobby.get_node("%Back").text == "BACK", "Offline Join says Back instead of Leave")
	lobby.address.text = " "
	lobby.join_button.pressed.emit()
	check(game.session.connection_state == "offline", "Blank host address keeps the player in offline Join")
	await press("Back")
	check(router.current == "main" and game.session.connection_state == "offline", "Join Back returns directly to main")

func host_flow() -> void:
	if not await press("Play"):
		return
	check(router.current == "mode_select" and router.lobby_intent == "host", "Main Host opens host mode selection")
	if router.current != "mode_select":
		return
	var duel: Button
	for card: Button in game.screen.get_node("%Cards").get_children():
		check(card.data.get("id") in ["duel", "team", "5v5", "ffa"], "Host selector contains only available multiplayer modes")
		if card.data.get("id") == "duel":
			duel = card
	check(duel != null and not duel.disabled, "Duel is an available host mode")
	if duel == null:
		return
	duel.pressed.emit()
	await press("Next")
	check(router.current == "lobby" and router.match_setup.mode == "duel", "Host mode continues directly to lobby, skipping garage and arena")
	if router.current != "lobby":
		return
	var lobby: Control = game.screen
	check(lobby.host_button.is_visible_in_tree() and not lobby.join_button.is_visible_in_tree(), "Host setup offers hosting without the join form")
	lobby.port.value = 33000 + OS.get_process_id() % 9000
	lobby.host_button.pressed.emit()
	await frames()
	check(game.session.connection_state == "hosting" and game.session.player_capacity == 2, "Selected duel hosts a real two-player lobby")
	var slot: Dictionary = lobby._local_slot()
	check(slot.get("loadout", {}).get("parts", {}).get("weapon") == "lifter", "Host uses the selected bot without a mandatory garage visit")
	check(not lobby.build_button.is_visible_in_tree(), "Matching selected build does not offer a redundant Apply action")
	var peer: MultiplayerPeer = game.session.multiplayer.multiplayer_peer
	game.session.set_ready(true)
	lobby.featured_vehicle.previous_button.pressed.emit()
	check(lobby.build_button.is_visible_in_tree(), "Changing selected build offers an explicit Apply action")
	lobby.build_button.pressed.emit()
	await frames()
	check(lobby._local_slot().get("loadout", {}).get("parts", {}).get("weapon") == "vertical_spinner" and not lobby._local_slot().get("ready", true), "Inline build change applies authoritative loadout and clears readiness")
	check(game.session.multiplayer.multiplayer_peer == peer and router.current == "lobby", "Inline build change preserves the same session and lobby")
	lobby.featured_vehicle.next_button.pressed.emit()
	lobby.build_button.pressed.emit()
	await frames()
	await press("Back")
	check(router.current == "main" and game.session.connection_state == "offline", "Leaving host lobby closes session and returns to main without stale setup history")

func garage_flow() -> void:
	if not await press("Garage"):
		return
	check(router.current == "garage", "Garage stays a separate main-menu action")
	check(game.screen.get_node("%Next").text == "DONE", "Standalone garage offers Done")
	await press("Next")
	check(router.current == "main" and game.session.connection_state == "offline", "Garage Done returns to main without starting host setup")

func practice_flow() -> void:
	if not await press("Practice"):
		return
	await frames(8)
	check(game.session.connection_state == "practice" and not game.menu_host.visible, "Main Practice immediately starts the arena without setup screens")
	var bot = game.session.local_source()
	check(bot != null, "Direct Practice creates a physical player bot")
	if bot != null:
		check(bot.combat.stats.weapon == "lifter", "Direct Practice uses the selected Controller build")
	game.return_to_main()
	await frames()
	check(router.current == "main" and game.menu_host.visible and not game.preview.controls_enabled, "Practice return restores the main menu and releases controls")
