extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func run() -> void:
	var game: Node3D = load("res://scenes/dev/b_lobby_game.tscn").instantiate()
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await ticks(2)
	check(game.lobby.visible and game.session.connection_state == "offline", "Game opens at play menu")
	game.lobby.practice_requested.emit()
	await ticks(15)
	check(game.session.local_source() != null and game.preview.controls_enabled and not game.lobby.visible,
		"Practice enters actual arena with a controllable bot")
	var player: BotSource = game.session.local_source()
	# Practice also spawns flank pilots and nimble roamers (#45, #61): the opponent
	# straight ahead of the player's start is the calibration target.
	var enemy: Node3D = game.session.practice_target()
	check(enemy != null and game.session.world.bots.get(game.session.local_entity) != enemy, "Practice places an opponent ahead of the player")
	var before: Vector3 = player.read_view().pose.origin
	var enemy_core: float = enemy.combat.core
	Input.action_press("primary")
	await ticks(120)
	check(player.read_view().weapon_charge_fraction > 0.5, "Player input spins up actual weapon")
	Input.action_press("drive_forward")
	await ticks(120)
	Input.action_release("drive_forward")
	Input.action_release("primary")
	check(player.read_view().pose.origin.distance_to(before) > 1.0, "WASD input moves authoritative bot")
	check(enemy.combat.core < enemy_core, "Driving spinning weapon into opponent inflicts authoritative damage")
	game.show_lobby()
	check(not game.gameplay_input_allowed() and game.lobby.visible, "Escape menu suspends gameplay")
	Input.action_press("drive_forward")
	await ticks(40)
	check(not game.preview.controls_enabled, "Holding drive cannot dismiss the menu")
	Input.action_release("drive_forward")
	game.open_settings()
	game.preview.settings_panel.cancel()
	await ticks(2)
	check(game.lobby.visible and not game.preview.controls_enabled, "Settings return honors frontend navigation")
	game.resume_gameplay()
	await ticks(2)
	check(game.preview.controls_enabled and not game.lobby.visible, "Resume returns to arena")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://b-lobby-gameplay.png")
		print("CAPTURE: ", ProjectSettings.globalize_path("user://b-lobby-gameplay.png"))
	game.session.leave()
	game.queue_free()
	await process_frame
	print("LOBBY GAME PASS" if failures == 0 else "LOBBY GAME FAIL")
	quit(0 if failures == 0 else 1)
