extends SceneTree
var output := "res://exports/settings-review"
func _initialize() -> void: run.call_deferred()
func capture(caption: String) -> void:
	for i: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(caption+".png"))
func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920,1080)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.video_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	game.open_settings()
	await capture("hub")
	for category: String in ["video","audio","accessibility","camera","controls"]:
		game._open_settings_category(category)
		if category == "video":
			for tab: String in ["Display","Quality","Effects"]:
				game.video_settings.select_tab(tab)
				await capture(tab.to_lower())
		else: await capture(category)
		if category in ["camera","controls"]: game.preview.settings_panel.cancel()
		else: game._cancel_general_settings()
	game.queue_free()
	for i: int in 4: await process_frame
	print("SETTINGS CAPTURE PASS")
	quit()
