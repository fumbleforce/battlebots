extends SceneTree
## Menu composition only; damaged state is explicit fixture setup, not natural combat.
var failures := 0
const ARENA_CHOICE = preload("res://scripts/arena/arena_scenery.gd")

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func run() -> void:
	root.size = Vector2i(1280, 720)
	var original_audio := AudioPreferences.load_file(AudioPreferences.DEFAULT_PATH)
	var arena_file_existed := FileAccess.file_exists(ARENA_CHOICE.PATH)
	var arena_file_bytes := FileAccess.get_file_as_bytes(ARENA_CHOICE.PATH) if arena_file_existed else PackedByteArray()
	var original_arena: String = ARENA_CHOICE.load_choice()
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	current_scene = game
	await frames()
	check(not game._restart_practice.visible and not game.practice_hud.visible, "Main menu has no practice-only controls")
	game.restart_practice()
	check(game.session.connection_state == "offline", "Restart cannot create a practice session from main")
	var router := root.get_node("MenuRouter")
	game.screen.get_node("%Practice").pressed.emit()
	await frames()
	check(router.current == "arena_select" and game.session.connection_state == "offline", "Practice opens arena setup before starting a session")
	check(game.screen.get_node("%Title").text == "PRACTICE" and game.screen.get_node("%Next").text == "START PRACTICE", "Practice setup has a clear title and start action")
	var preview_choice := 0 if original_arena == "moon" else 1
	game.screen.get_node("%Tiles").get_child(preview_choice).pressed.emit()
	game.screen.get_node("%Back").pressed.emit()
	await frames()
	check(router.current == "main" and game.session.connection_state == "offline", "Back from Practice setup returns to main without starting")
	check(ARENA_CHOICE.load_choice() == original_arena, "Backing out does not save the previewed arena")
	game.screen.get_node("%Practice").pressed.emit()
	await frames()
	check(router.match_setup.arena == ARENA_CHOICE.IDS.find(original_arena), "Practice setup restores the last saved arena")
	game.screen.get_node("%Tiles").get_child(0).pressed.emit()
	game.screen.get_node("%Next").pressed.emit()
	await frames()
	check(game.session.connection_state == "practice" and game.session.arena_id == "foundry", "Start Practice enters the selected arena through the actual session")
	check(ARENA_CHOICE.load_choice() == "foundry", "Confirmed practice arena remains available to LAN hosting and workshop test drive")
	var bot: MvpBot = game.session.local_source()
	var target: MvpBot = game.session.practice_target()
	var world: AuthorityWorld = game.session.world
	check(not game.practice_hud.visible and game._restart_practice.visible, "Practice keeps the duplicate target panel hidden and exposes pause restart")
	var target_marker: Label3D = game.world_markers.markers.get(target.read_view().entity_id)
	check(target_marker != null and target_marker.is_visible_in_tree() and target_marker.get_node("HealthBar").is_visible_in_tree(), "Practice target retains visible in-world identity and health feedback")
	check(game.world_markers.markers.size() == 4, "Player and all three practice NPCs retain visible health markers")
	check(game.practice_hud.target_label.text.contains("100"), "Retained practice readout receives fresh target health")
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(game.practice_hud.get_global_rect()), "Target HUD fits 720p: %s within %s" % [game.practice_hud.get_global_rect(), root.size])
	game.preview.release_controls()
	await frames()
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(game._restart_practice.get_global_rect()), "Restart fits actual pause menu")
	check(game.preview.resume_button.get_node(game.preview.resume_button.focus_next) == game._restart_practice, "Keyboard navigation includes Restart after Resume")
	target.combat.core = target.combat.stats.core * 0.5
	target.combat.zones.weapon = 0
	await frames()
	check(game.practice_hud.target_label.text.contains("50") and game.practice_hud.components_label.text.contains("Weapon"), "Retained practice readout consumes authoritative damage and disabled weapon")
	target.combat.eliminate("test knockout")
	await frames()
	check(game.practice_hud.target_label.text.to_lower().contains("defeated") and target_marker != null and target_marker.text.contains("OUT"), "Target knockout reaches retained readout and in-world marker")
	game._restart_practice.pressed.emit()
	await frames()
	check(game.session.world == world and game.session.local_source() == bot and game.session.practice_target() == target, "Restart retains world and bot identities")
	check(game.preview.controls_enabled and not game.preview.pause_menu.visible, "Restart returns directly to driving")
	check(not target.combat.eliminated and game.practice_hud.target_label.text.contains("100"), "Restart repairs target and refreshes feedback")
	bot.combat.eliminate("test player knockout")
	await frames()
	check(game.preview.pause_menu.visible and not game.gameplay_input_allowed() and game.preview.resume_button.disabled, "Player knockout opens pause and disables meaningless resume")
	check(root.gui_get_focus_owner() == game._restart_practice, "Knockout focuses the restart action")
	game.resume_gameplay()
	check(not game.preview.controls_enabled, "Resume cannot capture driving for a knocked-out practice bot")
	game.preview.open_settings()
	game.preview.settings_panel.cancel()
	await frames()
	check(game.preview.pause_menu.visible and not game.preview.controls_enabled, "Closing settings cannot resume a knocked-out practice bot")
	game._restart_practice.pressed.emit()
	await frames()
	check(not bot.combat.eliminated and game.preview.controls_enabled and not game.preview.resume_button.disabled, "Restart revives player and makes resume available")
	game.preview.open_settings()
	await frames()
	check(not game.practice_hud.visible, "Settings hides practice readout")
	game.audio_settings_button.pressed.emit()
	await frames()
	check(not game.practice_hud.visible, "Audio modal hides practice readout")
	game.audio_settings.cancel()
	game.preview.settings_panel.cancel()
	game.return_to_main()
	await frames()
	check(not game.practice_hud.visible and not game._restart_practice.visible, "Leaving removes practice-only UI")
	check(game.session.host(39000 + OS.get_process_id() % 10000, true, 2) == OK, "Fixture starts LAN host")
	await frames()
	game.restart_practice()
	check(game.session.connection_state == "hosting" and not game._restart_practice.visible, "LAN has no restart action and ignores root restart")
	game.return_to_main()
	game.queue_free()
	await frames()
	if arena_file_existed:
		var arena_file := FileAccess.open(ARENA_CHOICE.PATH, FileAccess.WRITE)
		arena_file.store_buffer(arena_file_bytes)
		arena_file.close()
	else:
		DirAccess.remove_absolute(ARENA_CHOICE.PATH)
	original_audio.apply()
	print("PRACTICE MENU PASS" if failures == 0 else "PRACTICE MENU FAIL")
	quit(0 if failures == 0 else 1)
