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
	var host := Control.new()
	root.add_child(host)
	host.size = Vector2(1920,1080)
	host.scale = Vector2.ONE*(2.0/3.0)
	var screen: Control = load("res://ui/menus/screens/arena_select.tscn").instantiate()
	host.add_child(screen)
	screen.get_node("%Tiles").get_child(1).button_pressed = true
	screen.get_node("%Tiles").get_child(1).pressed.emit()
	check(screen.get_node("%DetailName").text=="LUNAR OUTPOST","Moon selectable")
	check(screen.get_node("%DetailImage").texture!=null,"Moon preview available")
	for factor: float in [1.0,1.5]:
		screen.apply_text_scale(factor)
		for i: int in range(10):
			await process_frame
		for control: Node in screen.find_children("*","Control",true,false):
			if control.is_visible_in_tree() and (control is Label or control is Button):
				check(Rect2(Vector2.ZERO,Vector2(root.size)).grow(1).encloses(control.get_global_rect()),"Arena selector fits: "+str(screen.get_path_to(control)))
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://exports/moon-review/selector-%.1f.png" % factor)
	host.queue_free()
	await process_frame
	print("ARENA SELECTION PASS" if failures==0 else "ARENA SELECTION FAIL")
	quit(0 if failures==0 else 1)
