extends SceneTree
var failures := 0
const CHOICE = preload("res://scripts/arena/arena_scenery.gd")
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var path := "user://test-arena-choice.cfg"
	check(CHOICE.save_choice("moon",path)==OK and CHOICE.load_choice(path)=="moon","Moon persists")
	check(CHOICE.save_choice("foundry",path)==OK and CHOICE.load_choice(path)=="foundry","Foundry persists")
	check(CHOICE.save_choice("invalid",path)==ERR_INVALID_PARAMETER,"Unknown choice rejected")
	DirAccess.remove_absolute(path)
	check(CHOICE.load_choice(path)=="foundry","Missing choice defaults Foundry")
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280,720)
	var game = load("res://scenes/dev/b_menu_game.tscn").instantiate()
	game.audio_settings_path = ""
	game.get_node("Preview").settings_path = ""
	root.add_child(game)
	await frames()
	var router := root.get_node("MenuRouter")
	game.screen.get_node("%Practice").pressed.emit()
	await frames()
	check(router.arena_intent == "practice", "Main Practice enters setup")
	router.open_host()
	await frames()
	check(router.arena_intent == "select", "LAN navigation clears Practice intent")
	router.goto("arena_select")
	await frames()
	check(game.screen.get_node("%Next").text == "USE ARENA", "Generic arena selection after LAN never starts Practice")
	router.goto("main")
	await frames()
	game.screen.get_node("%Practice").pressed.emit()
	await frames()
	var screen: Control = game.screen
	check(screen.get_node("%Next").text == "START PRACTICE", "Practice has the explicit start action")
	screen.get_node("%Tiles").get_child(1).button_pressed = true
	screen.get_node("%Tiles").get_child(1).pressed.emit()
	check(screen.get_node("%DetailName").text=="LUNAR OUTPOST","Moon selectable")
	check(screen.get_node("%DetailImage").texture!=null,"Moon preview available")
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		for factor: float in [1.0,1.5]:
			screen.apply_text_scale(factor)
			await frames()
			var body: ScrollContainer = screen.get_node("Layout/Body")
			check(not body.get_h_scroll_bar().visible and not body.get_v_scroll_bar().visible, "Practice setup needs no scrolling at %s %.1f" % [resolution, factor])
			for control: Node in screen.find_children("*","Control",true,false):
				if control.is_visible_in_tree() and (control is Label or control is Button):
					check(Rect2(Vector2.ZERO,Vector2(root.size)).grow(1).encloses(control.get_global_rect()),"Practice setup fits %s %.1f: %s" % [resolution, factor, screen.get_path_to(control)])
			for action: Button in [screen.get_node("%Back"), screen.get_node("%Next")]:
				check(action.is_visible_in_tree() and not action.disabled, "Practice action remains available: " + action.text)
			if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("user://practice-setup-%dx%d-%d.png" % [resolution.x,resolution.y,roundi(factor * 100)])
	game.queue_free()
	await frames()
	print("ARENA SELECTION PASS" if failures==0 else "ARENA SELECTION FAIL")
	quit(0 if failures==0 else 1)

func frames() -> void:
	for index: int in 10:
		await process_frame
