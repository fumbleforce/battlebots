extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	var world := AuthorityWorld.new()
	world.arena_id = "moon"
	root.add_child(world)
	var bot := world.spawn(1,0,0,world.registry.starter())
	check(is_equal_approx(bot.body.gravity_scale,1.62/9.8),"Moon gravity scale missing")
	check(absf(bot.body.model_config().gravity.y+1.62)<0.001,"Prediction gravity differs")
	check(world.arena.has_node("LunarSurface"),"Lunar collision absent")
	check(world.arena.get_node("SpawnPoints").get_child_count()==18,"Spawns missing")
	await physics_frame
	await physics_frame
	var space := world.get_world_3d().direct_space_state
	# Sample authored grid vertices: between them both surfaces interpolate.
	for p: Vector3 in [Vector3(12.5,0,8.125),Vector3(-13.75,0,11.875),Vector3(0,0,0)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p+Vector3.DOWN,1))
		check(not hit.is_empty(),"Terrain missing")
		if not hit.is_empty():
			check(absf(hit.position.y-preload("res://scripts/arena/moon_surface.gd").height_at(p.x,p.z))<0.012,"Terrain height disagrees with mesh")
	var surface = preload("res://scripts/arena/moon_surface.gd")
	for p: Vector2 in [Vector2(12.2,8.4),Vector2(-14,12),Vector2(16.1,-9.2)]:
		var cell: Vector2 = ((p+Vector2.ONE*25)/surface.STEP).floor()*surface.STEP-Vector2.ONE*25
		var uv: Vector2 = (p-cell)/surface.STEP
		var a: float = surface.height_at(cell.x,cell.y)
		var b: float = surface.height_at(cell.x+surface.STEP,cell.y)
		var c: float = surface.height_at(cell.x,cell.y+surface.STEP)
		var d: float = surface.height_at(cell.x+surface.STEP,cell.y+surface.STEP)
		var mesh_y: float = a+(b-a)*uv.x+(c-a)*uv.y if uv.x+uv.y<=1 else d+(c-d)*(1-uv.x)+(b-d)*(1-uv.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x,2,p.y),Vector3(p.x,-1,p.y),1))
		check(not hit.is_empty() and absf(hit.position.y-mesh_y)<0.002,"Interior triangle collision matches rendered surface")
	await check_flight(bot)
	await check_traversal(world,bot)
	if DisplayServer.get_name()=="headless":
		check(world.arena.get_node("FoundryVisuals").get_child_count()==0,"Headless constructed scenery")
	else:
		check(world.arena.find_child("Earth",true,false)!=null,"Earth missing")
		await check_dust(world,bot)
		if "--capture" in OS.get_cmdline_user_args():
			await capture(world,bot)
	world.queue_free()
	await process_frame
	print("MOON ARENA PASS" if failures==0 else "MOON ARENA FAIL")
	quit(0 if failures==0 else 1)

func check_flight(bot: MvpBot) -> void:
	bot.body.reset_pose = Transform3D(Basis.IDENTITY,Vector3(0,10,0))
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame
	var body := bot.body
	var state := {"pose":body.global_transform,"velocity":body.linear_velocity,"angular":body.angular_velocity,"grounded":false}
	var commands: Array = []
	for i: int in range(15):
		var command := BotCommand.new()
		command.sequence = i
		body.accept_command(command)
		commands.append(WireCodec.command_to_array(command))
		await physics_frame
		await process_frame
	var predicted := DriveModel.replay(state,commands,body.model_config())
	check(predicted.pose.origin.distance_to(body.global_position)<0.05,"Moon prediction follows physical flight")
	check(predicted.velocity.distance_to(body.linear_velocity)<0.05,"Moon replay velocity follows Jolt")
	check(absf(body.linear_velocity.y-state.velocity.y+1.62*0.25)<0.06,"Physical gravity is 1.62 m/s²")

func check_dust(world: AuthorityWorld, bot: MvpBot) -> void:
	var art := world.arena.get_node("FoundryVisuals/EnvironmentArt")
	bot.body.freeze = true
	bot.simulated = false
	bot.remote_state = bot.combat.snapshot()
	bot.remote_state.merge({"velocity":Vector3(0,0,5),"grounded":true,"eliminated":false},true)
	await process_frame
	await process_frame
	check(art._dust[1].emitting,"Remote grounded movement emits dust")
	bot.remote_state.grounded = false
	await process_frame
	await process_frame
	check(not art._dust[1].emitting,"Airborne bots stop emitting dust")
	bot.remote_state.grounded = true
	bot.remote_state.velocity = Vector3.ZERO
	await process_frame
	await process_frame
	check(not art._dust[1].emitting,"Stopped bots stop emitting dust")
	bot.simulated = true

func check_traversal(world: AuthorityWorld, bot: MvpBot) -> void:
	bot.body.reset_pose = Transform3D(Basis.IDENTITY,Vector3(12,0.9,14))
	for i: int in range(240):
		var command := BotCommand.new()
		command.sequence = 1000+i
		command.throttle = 1.0 if i>75 else 0.0
		bot.submit_command(command)
		world.step(1.0/60.0,true,1)
		await physics_frame
		await process_frame
		check(bot.body.global_position.is_finite() and bot.body.global_position.y > -0.1,"Bot remains above uneven lunar collision")
	check(bot.body.global_position.z<8,"Bot traverses rolling terrain")
func capture(world: AuthorityWorld, bot: MvpBot) -> void:
	root.size = Vector2i(1600,900)
	root.msaa_3d = Viewport.MSAA_2X
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 150
	camera.fov = 68
	bot.body.freeze = true
	bot.body.position = Vector3(-3,0.5,4)
	bot.body.reset_pose = null
	bot.previous_pose = bot.body.global_transform
	var output := "res://exports/moon-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+"/.gdignore",FileAccess.WRITE).close()
	for shot: Array in [["overview",Vector3(16,12,17),Vector3(0,4,-12)],
		["floor",Vector3(6,2.8,14),Vector3(-2,7,-35)],
		["outpost",Vector3(-10,4,-12),Vector3(0,8,-32)]]:
		camera.position = shot[1]
		camera.look_at(shot[2])
		for i: int in range(40):
			await process_frame
			await RenderingServer.frame_post_draw
		var path: String = output+"/moon-"+shot[0]+".png"
		check(root.get_texture().get_image().save_png(path)==OK,"Capture failed")
		print("CAPTURE ",ProjectSettings.globalize_path(path))
	bot.body.freeze = false
	bot.body.reset_pose = Transform3D(Basis.IDENTITY,Vector3(0,0.6,10))
	for i: int in range(180):
		var command := BotCommand.new()
		command.sequence = 2000+i
		command.throttle = 1.0 if i>90 else 0.0
		bot.submit_command(command)
		world.step(1.0/60.0,true,1)
		await physics_frame
		await process_frame
		camera.position = bot.body.global_position+Vector3(3,1.8,4.5)
		camera.look_at(bot.body.global_position+Vector3(0,0,-0.5))
	check(world.arena.get_node("FoundryVisuals/EnvironmentArt")._dust[1].emitting,"Physical driving emits lunar dust")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output+"/moon-dust.png")==OK,"Dust capture failed")
