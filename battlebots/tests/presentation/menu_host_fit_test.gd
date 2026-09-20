extends SceneTree
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func frames() -> void:
	for index in range(8):
		await process_frame
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.hud_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	for extent in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(2560,1080), Vector2i(1280,1024)]:
		root.size = extent
		await frames()
		var bounds := root.get_visible_rect()
		check(game.menu_host.get_global_rect().is_equal_approx(bounds), "Actual game menu host fills viewport at %s" % extent)
		check(game.screen.get_node("Bg").get_global_rect().is_equal_approx(bounds), "Actual main background fills both axes at %s" % extent)
		for factor in [1.0, 1.5]:
			game.screen.apply_text_scale(factor)
			await frames()
			for button in game.screen.find_children("*", "Button", true, false):
				if button.is_visible_in_tree():
					check(bounds.grow(1).encloses(button.get_global_rect()), "Actual game action fits: %s at %s/%s" % [button.name, extent, factor])
	game.queue_free()
	await frames()
	if failures == 0:
		print("MENU HOST FIT PASS")
	quit(0 if failures == 0 else 1)
