extends SceneTree
const SURFACE = preload("res://scripts/arena/moon_surface.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count := 3) -> void:
	for i: int in count: await process_frame
func run() -> void:
	if DisplayServer.get_name() == "headless":
		var world := AuthorityWorld.new()
		world.arena_id = "moon"
		root.add_child(world)
		check(world.arena.find_child("LunarEffects",true,false)==null,"Headless world must not build GPU dust")
		world.queue_free()
		await frames()
		print("LUNAR DRIVING HEADLESS PASS" if failures==0 else "LUNAR DRIVING FAIL")
		quit(failures)
		return
	var runtime := GraphicsRuntime.new()
	root.add_child(runtime)
	var world := AuthorityWorld.new()
	world.arena_id = "moon"
	root.add_child(world)
	var bot := world.spawn(1,0,0,world.registry.atlas())
	bot.simulated = false
	bot.body.freeze = true
	bot.body.reset_pose = null
	bot.set_process(false)
	bot.remote_state = bot.combat.snapshot()
	bot.remote_state.merge({"velocity":Vector3(0,0,-6),"angular":Vector3.ZERO,"grounded":true,"eliminated":false},true)
	bot.presentation.position = Vector3(12,bot.ground_clearance(),9)
	var effects := world.arena.get_node("FoundryVisuals/EnvironmentArt/LunarEffects")
	effects.set_process(false)
	effects._process(.016)
	await frames()
	var size := bot.collision_bounds().size
	var pair: Array = effects.side_dust[1]
	check(pair.size()==2 and pair[0].global_position.distance_to(pair[1].global_position)>size.x*.9,"Dust originates on both sides of the current enlarged footprint")
	for emitter: GPUParticles3D in pair:
		var p := emitter.global_position
		check(absf(p.y-SURFACE.height_at(p.x,p.z)-.07)<.001,"Dust outlet follows local terrain, not hull height")
		check(emitter.emitting and not emitter.local_coords,"Grounded remote movement emits world-space dust")
	for i: int in 25: effects._process(1.0/60.0)
	check(effects.clouds.size()>=2,"Driving deposits local volumetric dust")
	var first: Dictionary = effects.clouds[0]
	var original: Vector3 = first.origin
	bot.presentation.position.z -= 1.0
	effects._process(.016)
	check(first.origin==original,"Deposited cloud stays at its world origin as bot drives away")
	for property: String in ["grounded","eliminated","stopped"]:
		bot.remote_state.grounded = property!="grounded"
		bot.remote_state.eliminated = property=="eliminated"
		bot.remote_state.velocity = Vector3.ZERO if property=="stopped" else Vector3(0,0,-6)
		effects._process(.016)
		check(not pair[0].emitting and not effects.ballistic_dust[1][0].emitting,"No new particles while "+property)
	bot.remote_state.eliminated = false
	bot.remote_state.grounded = true
	bot.remote_state.velocity = Vector3.ZERO
	bot.remote_state.angular = Vector3(0,1.4,0)
	effects._process(.016)
	check(pair[0].emitting,"Pivoting in place scuffs the ground")
	bot.remote_state.angular = Vector3.ZERO
	bot.remote_state.velocity = Vector3(0,0,6)
	effects._process(.016)
	check(pair[0].global_position.z<bot.presentation.global_position.z,"Reverse drive shifts emission to the trailing front contact")
	bot.presentation.position = Vector3(-12,bot.ground_clearance(),-12)
	effects._process(.016)
	check(not pair[0].emitting and effects.clouds.all(func(c:Dictionary)->bool:return not c.volume.visible),"Teleport clears the prior trail without a bridge")
	for i: int in 100: effects._spawn_cloud(1,Vector3(i%5,0,i%7),size,1.0)
	check(effects.clouds.size()==effects.CLOUD_LIMIT,"Sustained emission has a fixed volume budget")
	effects._update_clouds(3.0)
	check(effects.clouds.all(func(c:Dictionary)->bool:return not c.volume.visible),"Clouds expire completely")
	runtime.apply(GraphicsOptions.preset(0))
	check(pair[0].amount==63,"New emitters consume the Low particle budget")
	check(not world.arena.get_node("WorldEnvironment").environment.volumetric_fog_enabled,"Fog-off quality disables all local volume rendering")
	runtime.apply(GraphicsOptions.DEFAULTS)
	check(pair[0].amount==180,"High restores authored particle allocation")
	world.reset_round()
	effects._process(.016)
	check(effects.clouds.is_empty() and effects.tracks.all(func(t:MeshInstance3D)->bool:return not t.visible),"Round reset clears lingering fog and tracks")
	# Replacing a bot under the same network id must discard its old footprint.
	var old := world.bots[1] as MvpBot
	world.bots.erase(1)
	old.queue_free()
	var replacement := world.spawn(1,0,0,world.registry.starter())
	replacement.simulated = false
	replacement.body.freeze = true
	replacement.remote_state = replacement.combat.snapshot()
	effects._process(.016)
	check(effects.observations[1].bot.get_ref()==replacement and effects.observations[1].size==replacement.collision_bounds().size,"Same-id bot replacement refreshes contact geometry")
	for id: int in range(2,12):
		var extra := world.spawn(id,0,0,world.registry.starter())
		extra.simulated = false
		extra.body.freeze = true
		extra.remote_state = extra.combat.snapshot()
	effects._process(.016)
	check(effects.observations.size()==10 and effects.ballistic_dust.size()==10,"Emitter allocation stays bounded even with excess sources")
	world.clear_bots()
	effects._process(.016)
	await frames()
	check(effects.observations.is_empty() and effects.fine_dust.is_empty() and effects.ballistic_dust.is_empty() and effects.last_track.is_empty(),"Removed bots release emitters and history")
	world.arena.get_node("WorldEnvironment").environment.volumetric_fog_enabled=false
	await frames()
	world.queue_free()
	runtime.queue_free()
	await frames()
	print("LUNAR DRIVING DUST PASS" if failures==0 else "LUNAR DRIVING DUST FAIL")
	quit(0 if failures==0 else 1)
