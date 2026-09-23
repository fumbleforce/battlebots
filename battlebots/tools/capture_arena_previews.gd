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
	for id: String in ["foundry", "moon"]:
		var arena := load("res://scenes/arenas/%s_arena.tscn" % ("baseline" if id == "foundry" else "moon")).instantiate() as Node3D
		root.add_child(arena)
		var camera := Camera3D.new()
		arena.add_child(camera)
		camera.current = true
		camera.fov = 75
		camera.far = 600
		camera.position = Vector3(30, 17, 34) if id == "foundry" else Vector3(16, 10, 18)
		camera.look_at(Vector3(-8, 1, -10) if id == "foundry" else Vector3(-2, 2, -6))
		# Let shader compilation, atmosphere and reflection captures settle.
		for frame: int in range(120):
			await process_frame
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := "res://ui/menus/art/arena_foundry.jpg" if id == "foundry" else "res://ui/menus/art/arena_moon.png"
		var error := image.save_jpg(path, 0.95) if id == "foundry" else image.save_png(path)
		if error != OK:
			push_error("Cannot save native arena preview: " + path)
			quit(1)
			return
		print("ARENA CAPTURE: ", path)
		arena.queue_free()
		await process_frame
	print("ARENA PREVIEWS CAPTURED")
	quit()
