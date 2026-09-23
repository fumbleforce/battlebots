extends SceneTree
## Copy into an empty project: no Battlebots classes/assets/autoloads required.
## Upstream: https://github.com/godotengine/godot/issues/122498
var cycles := 10
var replace_world := false
var with_probe := true

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--replace-world": replace_world = true
		if arg == "--no-probe": with_probe = false
		if arg.begins_with("--cycles="): cycles = int(arg.trim_prefix("--cycles="))
	run.call_deferred()

func frames() -> void:
	for index: int in 40: await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null or cycles < 3:
		push_error("Requires a native Forward+ renderer and at least three cycles")
		quit(1)
		return
	root.size = Vector2i(640, 360)
	for cycle: int in cycles:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(320, 180)
		viewport.own_world_3d = replace_world
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.add_child(Camera3D.new())
		if with_probe:
			var probe := ReflectionProbe.new()
			probe.size = Vector3(20, 20, 20)
			viewport.add_child(probe)
		await frames()
		var viewport_ref: WeakRef = weakref(viewport)
		viewport.queue_free()
		viewport = null
		await frames()
		if viewport_ref.get_ref() != null:
			push_error("Viewport was not freed")
			quit(1)
			return
		print("LIFECYCLE ", JSON.stringify({"phase":"freed", "cycle":cycle,
			"textures":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}))
	print("REFLECTION REPRO PASS")
	quit()
