extends SceneTree
## Manual playable review: selects Bracken for this process only, then opens the
## normal game with --practice. Never writes the user's saved builds/settings.
## godot --path battlebots --script res://tests/presentation/bracken_playtest.gd -- --practice

func _initialize() -> void:
	launch.call_deferred()

func launch() -> void:
	var profile := root.get_node("PlayerProfile")
	for index: int in profile.loadouts.size():
		if AtlasGeometry.bracken_enabled(profile.loadouts[index]):
			profile.active_bot = index
			change_scene_to_file("res://scenes/dev/b_menu_game.tscn")
			if "--bracken-capture" in OS.get_cmdline_user_args():
				capture.call_deferred()
			return
	push_error("Bracken factory preset is missing")
	quit(1)

func capture() -> void:
	for frame: int in 1800:
		await process_frame
		if current_scene == null: continue
		var session := current_scene.get_node_or_null("Session") as MvpSession
		if session == null or session.local_source() == null: continue
		if session.match_view.get("phase") != "active": continue
		if current_scene._practice_loading: continue
		print("BRACKEN PLAYTEST READY: ", session.local_source().loadout.name)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://exports/bracken-preview/native-practice.png")
		return
