extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func frames(count := 4) -> void:
	for i: int in count: await process_frame
func run() -> void:
	var runtime := GraphicsRuntime.new()
	root.add_child(runtime)
	if DisplayServer.get_name() == "headless":
		var before := Engine.max_fps
		runtime.apply(GraphicsOptions.preset(3))
		check(Engine.max_fps == before and runtime.get_child_count() == 0,"Headless server creates no render owner state")
	else:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = Vector2i(1280,720)
		var authored := Environment.new()
		authored.glow_enabled = true
		authored.volumetric_fog_enabled = true
		authored.adjustment_brightness = 0.9
		var world := WorldEnvironment.new()
		world.environment = authored
		root.add_child(world)
		var light := OmniLight3D.new()
		light.shadow_enabled = true
		root.add_child(light)
		var fill := OmniLight3D.new()
		fill.shadow_enabled = false
		root.add_child(fill)
		var particles := GPUParticles3D.new()
		particles.amount = 100
		particles.emitting = false
		particles.amount_ratio = .3
		root.add_child(particles)
		await frames()
		check(world.environment != authored,"Render settings duplicate authored environment")
		for mode: String in GraphicsOptions.CHOICES.aa.values():
			var draft := GraphicsOptions.DEFAULTS.duplicate(true)
			draft.aa = mode
			runtime.apply(draft)
			check(root.use_taa == (mode in ["taa","taa_msaa"]),"Temporal AA applies: "+mode)
			check(root.msaa_3d == {"msaa2":1,"msaa4":2,"msaa8":3,"taa_msaa":1}.get(mode,0),"MSAA applies: "+mode)
			check(root.screen_space_aa == {"fxaa":1,"smaa":2}.get(mode,0),"Post AA applies: "+mode)
		var draft := GraphicsOptions.preset(0)
		draft.upscaler = "fsr2"
		draft.render_scale = 150
		draft.shadows = 0
		draft.brightness = 110
		draft.fps_limit = 120
		runtime.apply(draft)
		check(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and root.scaling_3d_scale == 1.0 and not root.use_taa and root.msaa_3d == 0,"FSR2 overrides AA and caps scale")
		check(not world.environment.ssao_enabled and not world.environment.ssil_enabled and not world.environment.ssr_enabled,"Low quality disables expensive screen-space effects")
		check(not light.shadow_enabled and not fill.shadow_enabled,"Shadows Off respects authored fill lights")
		check(particles.amount == 35 and is_equal_approx(particles.amount_ratio,.3),"Particle quality scales allocation without overriding dynamic engine-load density")
		check(Engine.max_fps == 120,"Frame limiter applies")
		check(is_equal_approx(world.environment.adjustment_brightness,.99),"Brightness composes with authored grading")
		runtime.apply(draft)
		check(is_equal_approx(world.environment.adjustment_brightness,.99),"Repeated apply does not compound grading")
		draft = GraphicsOptions.preset(2)
		runtime.apply(draft)
		check(light.shadow_enabled and not fill.shadow_enabled,"Restoring shadows restores only authored casters")
		check(particles.amount == 100,"Particle quality restores original budget")
		check(world.environment.ssao_enabled and world.environment.ssil_enabled and world.environment.ssr_enabled,"High enables refined lighting")
		var later := WorldEnvironment.new()
		later.environment = authored
		var holder := SubViewport.new()
		root.add_child(holder)
		holder.add_child(later)
		await frames()
		check(holder.use_taa and holder.msaa_3d == 1,"New viewports inherit graphics choices")
		check(later.environment.ssao_enabled and later.environment != authored,"New environments inherit without altering shared authoring")
		check(is_equal_approx(authored.adjustment_brightness,.9),"Source resource stays intact")
		holder.queue_free()
		world.queue_free()
		light.queue_free()
		fill.queue_free()
		particles.queue_free()
		await frames()
		check(runtime._environments.is_empty() and runtime._particles.is_empty() and runtime._lights.is_empty(),"Removed scenes release captured resources without waiting for another Apply")
		runtime.apply(GraphicsOptions.DEFAULTS)
	runtime.queue_free()
	await frames()
	print("GRAPHICS RUNTIME PASS" if failures == 0 else "GRAPHICS RUNTIME FAIL")
	quit(0 if failures == 0 else 1)
