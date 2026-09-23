extends SceneTree
## Native-only differential diagnosis for #18; launched by check-scorpion-lifecycle.mjs.
var mode := "world"
var cycles := 10
var failures := 0
var registry := ContentRegistry.new()

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--cycles="): cycles = int(arg.trim_prefix("--cycles="))
	run.call_deferred()

func frames(count := 40) -> void:
	for index: int in count: await process_frame

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func memory(phase: String, cycle := -1) -> void:
	print("LIFECYCLE ", JSON.stringify({"mode":mode, "phase":phase, "cycle":cycle,
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"textures":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}))

func run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		push_error("This diagnostic requires a native Forward+ renderer; headless cannot reproduce #18")
		quit(1)
		return
	if mode not in ["model", "visual", "bot", "arena", "world", "world_no_reflections"] or cycles < 3:
		push_error("Invalid mode or fewer than three cycles")
		quit(1)
		return
	root.size = Vector2i(960, 600)
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(12, 10, -16)
	camera.look_at(Vector3(0, 2, 0))
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 20, 0)
	stage.add_child(light)
	await frames()
	memory("initial")
	for cycle: int in cycles:
		var subject: Node3D
		match mode:
			"model": subject = load("res://assets/models/scorpion_runtime/scorpion.glb").instantiate()
			"visual": subject = ScorpionVisual.new()
			"bot": subject = MvpBot.create(1, 0, registry.scorpion(), registry)
			_: subject = AuthorityWorld.new()
		stage.add_child(subject)
		if mode == "world_no_reflections":
			var probes := subject.find_children("*", "ReflectionProbe", true, false)
			check(not probes.is_empty(), "Control must remove an actual arena probe")
			for reflection: ReflectionProbe in probes: reflection.free()
		if mode == "visual": subject.assemble(registry.scorpion(), registry.validate(registry.scorpion()).stats.size)
		if mode == "bot": subject.body.freeze = true
		if mode.begins_with("world"):
			var world := subject as AuthorityWorld
			var bot := world.spawn(1, 0, 0, registry.scorpion())
			bot.body.freeze = true
			await frames()
			var original: WeakRef = weakref(bot)
			var draft := registry.scorpion()
			draft.cosmetics.paint = "cyan"
			var replacement := world.apply_loadout(1, draft)
			check(replacement != null and replacement != bot, "Live loadout swap must rebuild the bot")
			bot = null
			await frames()
			check(original.get_ref() == null, "Replaced bot must be freed")
		await frames()
		memory("built", cycle)
		var subject_ref: WeakRef = weakref(subject)
		subject.queue_free()
		subject = null
		await frames()
		check(subject_ref.get_ref() == null, "Freed subject remains alive")
		memory("freed", cycle)
	stage.queue_free()
	await frames()
	memory("shutdown")
	print("SCORPION LIFECYCLE PASS" if failures == 0 else "SCORPION LIFECYCLE FAIL")
	quit(failures)
