extends SceneTree
## Starting Practice from the menus (#70): the loading card is drawn before the
## arena builds, still covers the first gameplay frames, then lifts. A refused
## start lifts it too, and a second request while loading is ignored.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(count := 1) -> void:
	for index in count:
		await physics_frame
		await process_frame

func run() -> void:
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	var card: PracticeLoadingOverlay = game.practice_loading
	check(card != null and not card.visible, "The loading card waits hidden in the menus")
	var arena := preload("res://scripts/arena/arena_scenery.gd").load_choice()
	game.load_practice()
	check(card.visible and game.session.connection_state == "offline",
		"The card is up before anything builds")
	check(card.arena_label.text == MenuData.ARENAS[PracticeLoadingOverlay.ARENA_IDS.find(arena)].name and card.art.texture != null,
		"The card names and shows the arena being loaded")
	game.load_practice()
	await process_frame
	await process_frame
	check(game.session.connection_state == "practice" and card.visible,
		"The arena builds behind the card, which still covers the first frames")
	check(game.session.world.bots.size() > 0 and game.session.local_source() != null,
		"A second request while loading starts nothing extra")
	for index in 60:
		await process_frame
		if not card.visible: break
	check(not card.visible and not game.menu_host.visible, "The card lifts onto the running practice")
	game.return_to_main()
	await frames(3)
	# A refused start (no valid build) must not leave the card up.
	var profile: Node = root.get_node("PlayerProfile")
	var saved: int = profile.active_bot
	profile.active_bot = -1
	game.load_practice()
	for index in 60:
		await process_frame
		if not card.visible: break
	check(game.session.connection_state == "offline" and not card.visible, "A refused start lifts the card again")
	profile.active_bot = saved
	game.queue_free()
	await frames(2)
	for failure: String in failures: push_error(failure)
	print("PRACTICE LOADING PASS" if failures.is_empty() else "PRACTICE LOADING FAIL")
	quit(0 if failures.is_empty() else 1)
