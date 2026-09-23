extends SceneTree
## Native production-scene captures. Run with a graphical Godot renderer:
## godot --path battlebots --script res://tools/capture_arena_previews.gd
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Arena previews require the native renderer")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	var arenas: Array[String] = ["foundry"]
	if not "--foundry-only" in OS.get_cmdline_user_args(): arenas.append_array(["moon", "woodland"])
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			arenas.assign([arg.substr(7)])
	for id: String in arenas:
		var arena := load("res://scenes/arenas/%s_arena.tscn" % ("baseline" if id == "foundry" else id)).instantiate() as Node3D
		root.add_child(arena)
		var camera := Camera3D.new()
		arena.add_child(camera)
		camera.current = true
		camera.fov = {"foundry":70, "moon":75, "woodland":62}[id]
		camera.far = 2000
		camera.position = {"foundry":Vector3(16, 12, 24), "moon":Vector3(16, 10, 18), "woodland":Vector3(30, 46, 150)}[id]
		camera.look_at({"foundry":Vector3(-4, 2, -17), "moon":Vector3(-2, 2, -6), "woodland":Vector3(0, 0, -10)}[id])
		# Let shader compilation, atmosphere and reflection captures settle.
		for frame: int in range(120):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path: String = {"foundry":"res://ui/menus/art/arena_foundry.jpg", "moon":"res://ui/menus/art/arena_moon.png",
			"woodland":"res://ui/menus/art/arena_woodland.jpg"}[id]
		var error := image.save_jpg(path, 0.92) if path.ends_with(".jpg") else image.save_png(path)
		if error != OK:
			push_error("Cannot save native arena preview: " + path)
			quit(1)
			return
		print("ARENA CAPTURE: ", path)
		arena.queue_free()
		await process_frame
	print("ARENA PREVIEWS CAPTURED")
	quit()
