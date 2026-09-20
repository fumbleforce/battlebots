extends SceneTree
var world: AuthorityWorld
var sequence := 0
var failures := 0
var run_physics := true
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool,message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func _physics_process(delta: float) -> bool:
	if is_instance_valid(world) and run_physics:
		sequence+=1
		for bot: MvpBot in world.bots.values():
			var command := BotCommand.new()
			command.sequence=sequence
			command.throttle=.65
			command.steering=.55 if bot.entity_id==1 else -.55
			bot.submit_command(command)
		world.step(delta,true,1)
	return false
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Rendered benchmark needs Forward+")
		quit(1)
		return
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.size=Vector2i(2560,1440)
	root.msaa_3d=Viewport.MSAA_2X
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	world=AuthorityWorld.new()
	world.arena_id="moon"
	root.add_child(world)
	var first := SawbladeConfig.starter(world.registry)
	var second := SawbladeConfig.starter(world.registry)
	second.parts.weapon = "hammer"
	world.spawn(1,0,0,first)
	world.spawn(2,1,0,second)
	var camera:=Camera3D.new()
	world.add_child(camera)
	camera.current=true
	camera.far=150
	camera.fov=68
	var art:=world.arena.get_node("FoundryVisuals/EnvironmentArt")
	var effects:=art.get_node("LunarEffects")
	check(effects.volumes.size()==3,"Three localized volumes")
	check(effects.tracks.size()==192,"Bounded track pool")
	check((world.arena.get_node("WorldEnvironment").environment as Environment).volumetric_fog_density==0,"Global fog stays clear")
	var timings:Array[float]=[]
	var output:="res://exports/lunar-review/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var peak_memory:=0.0
	var gpu_peak_mib:=0
	for shot:Array in [["showcase",Vector3(-8,5,-18),Vector3(0,6,-29)], ["arena",Vector3(7,3,14),Vector3(-2,5,-25)], ["reverse",Vector3(-12,4,-12),Vector3(3,3,18)]]:
		camera.position=shot[1]
		camera.look_at(shot[2])
		for frame:int in range(180):
			await process_frame
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+shot[0]+".png")
		var memory_output:Array=[]
		var memory_status:=OS.execute("nvidia-smi",["--query-gpu=memory.used","--format=csv,noheader,nounits"],memory_output,true)
		check(memory_status==0 and not memory_output.is_empty(),"GPU memory measurement available")
		if memory_status==0 and not memory_output.is_empty():gpu_peak_mib=maxi(gpu_peak_mib,str(memory_output[0]).strip_edges().to_int())
		var previous:=Time.get_ticks_usec()
		for frame:int in range(360):
			camera.position.x+=sin(frame*.02)*.002
			await process_frame
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec()
			timings.append((now-previous)/1000.0)
			previous=now
			peak_memory=maxf(peak_memory,Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	# Validate current replicated movement state independently of the physics tick.
	run_physics=false
	var bot: MvpBot=world.bots[1]
	bot.body.freeze=true
	bot.simulated=false
	bot.remote_state=bot.combat.snapshot()
	bot.remote_state.merge({"velocity":Vector3(0,0,5),"grounded":true,"eliminated":false},true)
	for i:int in range(3):await process_frame
	check(effects.fine_dust[1].emitting,"Grounded remote movement emits fine dust")
	bot.remote_state.grounded=false
	for i:int in range(3):await process_frame
	check(not effects.fine_dust[1].emitting,"Airborne remote movement stops fine dust")
	bot.remote_state.grounded=true
	bot.remote_state.eliminated=true
	for i:int in range(3):await process_frame
	check(not effects.fine_dust[1].emitting,"Eliminated bot stops fine dust")
	bot.remote_state.eliminated=false
	bot.remote_state.velocity=Vector3.ZERO
	for i:int in range(3):await process_frame
	check(not effects.fine_dust[1].emitting,"Stationary bot stops fine dust")
	var ramp: GradientTexture1D=effects.fine_dust[1].process_material.color_ramp
	check(ramp.gradient.sample(0).a==0 and ramp.gradient.sample(1).a==0,"Puffs fade in and out")
	world.clear_bots()
	for i:int in range(3):await process_frame
	check(effects.fine_dust.is_empty() and effects.last_track.is_empty(),"Removed bots release emitters and history")
	# Direct stamping exercises capacity and expiry without movement timing.
	for i:int in range(194):effects.stamp(Vector3(i%10,0,i%8),.2)
	check(effects.tracks.size()==192,"Stamping reuses pool")
	effects._process(36)
	check(effects.tracks.all(func(t:MeshInstance3D)->bool:return not t.visible),"Tracks fade out")
	timings.sort()
	var report:={"resolution":"2560x1440","bots":2,"samples":timings.size(),"p50_ms":timings[timings.size()/2],"p95_ms":timings[int(timings.size()*.95)],"p99_ms":timings[int(timings.size()*.99)],"engine_peak_video_mib":peak_memory/1048576.0}
	report["system_gpu_peak_mib"]=gpu_peak_mib
	report["adapter"]=RenderingServer.get_video_adapter_name()
	report["engine"]=Engine.get_version_info().string
	report["scope"]="Two moving authored SawbladeConfig bots (saw/hammer), three views, native Forward+, 2xMSAA; no HUD/network traffic or sustained combat effects. System VRAM sampled per view."
	check(report.p95_ms<=16.7,"1440p frame-time target")
	check(gpu_peak_mib>0 and gpu_peak_mib<8192,"Total GPU memory stays below 8 GiB")
	FileAccess.open(output+"benchmark.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LUNAR BENCHMARK ",JSON.stringify(report))
	(world.arena.get_node("WorldEnvironment").environment as Environment).volumetric_fog_enabled=false
	for i:int in range(5):
		await process_frame
		await RenderingServer.frame_post_draw
	world.queue_free()
	for i:int in range(10):await process_frame
	print("LUNAR CINEMATIC PASS" if failures==0 else "LUNAR CINEMATIC FAIL")
	quit(0 if failures==0 else 1)
