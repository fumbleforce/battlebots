extends SceneTree
## Real arena/materials at one fixed view plus bounded moving-camera GPU samples.
var runtime: GraphicsRuntime
var camera: Camera3D
var arena: Node3D
var output := "res://exports/graphics-review"
func _initialize() -> void: run.call_deferred()
func settle(frames := 60) -> void:
	for i: int in frames:
		await process_frame
		await RenderingServer.frame_post_draw
func capture(caption: String) -> void:
	await settle()
	root.get_texture().get_image().save_png(output.path_join(caption+".png"))
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Native rendering required")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	runtime = GraphicsRuntime.new()
	root.add_child(runtime)
	arena = load("res://scenes/arenas/baseline_arena.tscn").instantiate()
	root.add_child(arena)
	var registry := ContentRegistry.new()
	var bot := MvpBot.create(1,0,registry.atlas(),registry)
	arena.add_child(bot)
	bot.body.freeze = true
	bot.body.position = Vector3(0,bot.ground_clearance(),0)
	camera = Camera3D.new()
	arena.add_child(camera)
	camera.current = true
	camera.fov = 70
	camera.position = Vector3(7,5,12)
	camera.look_at(Vector3(0,1,-8))
	await settle(8)
	var previous := GraphicsOptions.DEFAULTS.duplicate(true)
	previous.aa = "msaa4"
	previous.indirect = 0
	previous.reflections = 0
	runtime.apply(previous)
	await capture("msaa4-before")
	var report := {}
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for index: int in [0,2,3]:
		runtime.apply(GraphicsOptions.preset(index))
		camera.position = Vector3(7,5,12)
		camera.look_at(Vector3(0,1,-8))
		await capture(GraphicsOptions.PRESETS[index].to_lower())
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		var wall: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame: int in 180:
			camera.position.x = 7.0+sin(frame/90.0)*1.5
			camera.look_at(Vector3(0,1,-8))
			await settle(1)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			var now := Time.get_ticks_usec()
			wall.append((now-last)/1000.0)
			last = now
		gpu.sort(); cpu.sort(); wall.sort()
		report[GraphicsOptions.PRESETS[index]] = {"gpu_median_ms":gpu[90],"gpu_p95_ms":gpu[171],"cpu_p95_ms":cpu[171],"wall_p95_ms":wall[171]}
		root.get_texture().get_image().save_png(output.path_join(GraphicsOptions.PRESETS[index].to_lower()+"-motion.png"))
		report[GraphicsOptions.PRESETS[index]]["video_mib"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0
	report["scope"] = "1600x900, Vulkan Forward+, actual Foundry and Atlas, static bot and moving camera. Bounded fixture, not whole-game or low-end certification."
	report["adapter"] = RenderingServer.get_video_adapter_name()
	var file := FileAccess.open(output.path_join("performance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	arena.queue_free()
	runtime.queue_free()
	await process_frame
	print("GRAPHICS CAPTURE PASS")
	quit()
