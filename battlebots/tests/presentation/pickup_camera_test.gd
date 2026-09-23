extends SceneTree
## A part pickup rebuilds the local bot node; the real menu game must keep the
## player's camera orbit instead of recentring as it does for a new match.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

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
	var session: MvpSession = game.session
	check(session.practice(ContentRegistry.new().starter(), "foundry") == OK, "Practice starts")
	game.resume_gameplay()
	await frames(10)
	var rig: BotOrbitCamera = game.preview.rig
	var before: MvpBot = session.local_source()
	rig.auto_recenter = false
	rig.yaw = 2.1
	rig.pitch = deg_to_rad(40.0)
	await frames(2)
	var swap := before.loadout.duplicate(true)
	swap.parts.chassis = "atlas_mx"
	swap.parts.drive = "traction"
	session.world.apply_loadout(session.local_entity, swap)
	await frames(10)
	check(session.local_source() != before and session.local_source().loadout.parts.chassis == "atlas_mx",
		"Pickup swap replaces the local bot node")
	check(is_equal_approx(rig.yaw, 2.1) and is_equal_approx(rig.pitch, deg_to_rad(40.0)),
		"Camera keeps its orbit through a part pickup (yaw %.2f pitch %.1f°)" % [rig.yaw, rad_to_deg(rig.pitch)])
	check(rig.camera.global_position.distance_to(session.local_source().camera_anchor().global_position) < 60.0,
		"Camera follows the rebuilt bot")
	game.return_to_main()
	await frames(5)
	check(session.practice(ContentRegistry.new().starter(), "foundry") == OK, "Practice restarts")
	game.resume_gameplay()
	await frames(10)
	check(is_equal_approx(rig.pitch, deg_to_rad(24.0)), "A new session still recentres the camera")
	game.queue_free()
	await frames(2)
	print("PICKUP CAMERA PASS" if failures == 0 else "PICKUP CAMERA FAIL")
	quit(0 if failures == 0 else 1)
