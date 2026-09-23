extends SceneTree
## Native production materials and authored bots, including the real player camera.
var arena: Node3D
var camera: Camera3D
var orbit: BotOrbitCamera
var bots: Array[MvpBot] = []
var output := "res://exports/foundry-material-review"

func _initialize() -> void:
	run.call_deferred()

func settle() -> void:
	for frame: int in 90:
		if orbit and orbit.camera.current: orbit.update_camera(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw

func save_view(label: String) -> void:
	await settle()
	var path := output.path_join(label + ".png")
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Cannot save material review: " + path)
		quit(1)
		return
	print("MATERIAL CAPTURE: ", ProjectSettings.globalize_path(path))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Foundry material review requires native rendering")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	arena = load("res://scenes/arenas/baseline_arena.tscn").instantiate()
	root.add_child(arena)
	var registry := ContentRegistry.new()
	for index: int in 2:
		var build := registry.atlas() if index == 0 else SawbladeConfig.starter(registry)
		if index == 1: build.cosmetics.sawblade.paint_primary = [0.025, 0.55, 0.72, 1.0]
		var bot := MvpBot.create(index + 1, index, build, registry)
		arena.add_child(bot)
		bot.body.freeze = true
		bot.body.position = Vector3(-6 + index * 12, bot.ground_clearance(), -3 - index * 6)
		bot.body.rotation.y = 0.35 if index == 0 else -0.65
		bot.previous_pose = bot.body.global_transform
		bots.append(bot)
	camera = Camera3D.new()
	arena.add_child(camera)
	camera.current = true
	camera.fov = 70
	camera.far = 180
	for view: Array in [
		["overview", Vector3(16, 12, 24), Vector3(-4, 2, -17)],
		["floor", Vector3(-3, 3, 9), Vector3(-3, 0, -1)],
		["wall", Vector3(-22, 6, -32), Vector3(-7, 8, -51)]]:
		camera.position = view[1]
		camera.look_at(view[2])
		await save_view(view[0])
	orbit = load("res://scenes/ui/orbit_camera.tscn").instantiate()
	arena.add_child(orbit)
	orbit.bind_source(bots[0])
	orbit.camera.current = true
	await save_view("player-camera")
	# Measure a bounded native render sample; no multiplayer/performance claim.
	if "--benchmark" in OS.get_cmdline_user_args():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		await settle()
		var times: Array[float] = []
		var gpu_times: Array[float] = []
		var cpu_times: Array[float] = []
		var previous := Time.get_ticks_usec()
		for frame: int in 240:
			await process_frame
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			times.append((now - previous) / 1000.0)
			gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu_times.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			previous = now
		times.sort()
		gpu_times.sort()
		cpu_times.sort()
		print("FOUNDRY FRAME SAMPLE: median=%.3fms p95=%.3fms draws=%d video=%.1fMiB adapter=%s" % [
			times[120], times[228], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, RenderingServer.get_video_adapter_name()])
		print("FOUNDRY RENDER SAMPLE: GPU median=%.3fms p95=%.3fms CPU median=%.3fms p95=%.3fms" % [
			gpu_times[120], gpu_times[228], cpu_times[120], cpu_times[228]])
	arena.queue_free()
	await process_frame
	print("FOUNDRY MATERIAL CAPTURE PASS")
	quit()
