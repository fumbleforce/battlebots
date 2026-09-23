extends SceneTree
## Native authored bots/terrain; deterministic accepted remote motion, not driving physics acceptance.
const SURFACE = preload("res://scripts/arena/moon_surface.gd")
var world: AuthorityWorld
var camera: Camera3D
var runtime: GraphicsRuntime
var t := 0.0
var output := "res://exports/lunar-driving-review"
func _initialize() -> void: run.call_deferred()
func step() -> void:
	t += 1.0/60.0
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		var angle := t*.52+PI*(id-1)
		var radius := 10.0 if id==1 else 12.0
		var pos := Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var velocity := Vector3(-sin(angle),0,cos(angle))*radius*.52
		pos.y = SURFACE.height_at(pos.x,pos.z)+bot.ground_clearance()+.06
		var pose := Transform3D(Basis.looking_at(velocity,Vector3.UP),pos)
		bot.presentation.global_transform = pose
		bot.body.global_transform = pose
		bot.remote_state.velocity = velocity
		bot.remote_state.angular = Vector3(0,-.52,0)
		bot.remote_state.grounded = true
		bot.server_tick += 1
	var first: MvpBot = world.bots[1]
	var target := first.presentation.global_position
	camera.position = target+first.presentation.global_basis*Vector3(7,5.2,11)
	camera.look_at(target+Vector3.UP*.7)
	await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	runtime = GraphicsRuntime.new()
	root.add_child(runtime)
	world = AuthorityWorld.new()
	world.arena_id = "moon"
	root.add_child(world)
	for id: int in [1,2]:
		var bot := world.spawn(id,id-1,0,world.registry.atlas() if id==1 else world.registry.scorpion())
		bot.simulated = false
		bot.body.freeze = true
		bot.body.reset_pose = null
		bot.remote_state = bot.combat.snapshot()
		bot.remote_state.merge({"velocity":Vector3.ZERO,"angular":Vector3.ZERO,"grounded":true,"eliminated":false},true)
	camera = Camera3D.new()
	camera.fov = 70
	camera.far = 150
	world.add_child(camera)
	camera.current = true
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var report := {"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"scope":"1600x900 Forward+, two authored Atlas/Scorpion bots on Moon with identical scripted accepted remote circular motion and moving review camera per mode; rendering fixture, not physics/network or low-end certification."}
	var effects := world.arena.get_node("FoundryVisuals/EnvironmentArt/LunarEffects")
	for mode: String in ["high-fog","high-particles-only","low"]:
		t = 0.0
		effects.elapsed = 0.0
		effects.clear_trails()
		var values := GraphicsOptions.preset(0) if mode=="low" else GraphicsOptions.DEFAULTS.duplicate(true)
		values.fog = mode=="high-fog"
		values.fps_limit = 60
		runtime.apply(values)
		for i: int in 120: await step()
		var gpu: Array[float] = []
		var cpu: Array[float] = []
		for frame: int in 180:
			await step()
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			if frame in [30,120]: root.get_texture().get_image().save_png(output.path_join(mode+"-%d.png"%frame))
		gpu.sort(); cpu.sort()
		report[mode] = {"gpu_median_ms":gpu[90],"gpu_p95_ms":gpu[171],"cpu_p95_ms":cpu[171],"volume_pool":effects.clouds.size(),"particle_emitters":effects.side_dust.size()*4,"video_mib":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0}
	FileAccess.open(output.path_join("performance.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print(JSON.stringify(report))
	world.arena.get_node("WorldEnvironment").environment.volumetric_fog_enabled=false
	for i: int in 5: await process_frame
	world.queue_free()
	runtime.queue_free()
	for i: int in 10: await process_frame
	print("LUNAR DRIVING REVIEW PASS")
	quit()
