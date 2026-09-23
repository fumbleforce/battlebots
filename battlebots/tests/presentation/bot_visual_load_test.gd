extends Node3D
## Native rendering measurement, not a combat/physics or cross-hardware acceptance test.
const WARM_FRAMES := 120
const SAMPLE_FRAMES := 240
var bots: Array[MvpBot] = []
var impacts: CombatImpactVisual
var failures: Array[String] = []
func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Bot visual load measurement requires a native renderer")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1920,1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var arena: Node3D = load("res://scenes/arenas/baseline_arena.tscn").instantiate()
	add_child(arena)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0,8,14)
	camera.look_at(Vector3(0,0.5,0))
	camera.current = true
	impacts = CombatImpactVisual.new()
	add_child(impacts)
	var registry := ContentRegistry.new()
	var rows: Array[Dictionary] = []
	for count: int in [2,10]:
		for index: int in count:
			var draft := SawbladeConfig.starter(registry)
			draft.parts.drive = ["traction","agile","standard_wheels","walker"][index % 4]
			draft.parts.weapon = ["saw","hammer","lifter","vertical_spinner","horizontal_spinner"][index % 5]
			var bot := MvpBot.create(index + 1,index % 2,draft,registry)
			check(bot != null,"Benchmark build validates")
			if bot == null: continue
			bot.simulated = false
			add_child(bot)
			bot.set_physics_process(false)
			bot.body.set_physics_process(false)
			var origin := Vector3((index % 5 - 2) * 2.8,0.7,(index / 5) * 3.2 - 1.6)
			if count == 2: origin = Vector3((index * 2 - 1) * 2,0.7,0)
			bot.body.global_position = origin
			bot.presentation.global_position = origin
			bots.append(bot)
		for damaged: bool in [false,true]:
			for bot: MvpBot in bots:
				for zone: String in ["drive_left","drive_right","weapon"]:
					bot.combat.zones[zone] = 0.0 if damaged else (140.0 if zone == "weapon" else 100.0)
			impacts.clear_effects()
			rows.append(await measure(count,damaged))
			if "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(
					"bot-visual-load-%d-%s.png" % [count,"damaged" if damaged else "intact"]))
		for bot: MvpBot in bots: bot.free()
		bots.clear()
	var report := {"engine":Engine.get_version_info().string,"adapter":RenderingServer.get_video_adapter_name(),
		"resolution":[1920,1080],"vsync":false,"warm_frames":WARM_FRAMES,"sample_frames":SAMPLE_FRAMES,
		"scope":"Foundry render only; frozen physics, no networking or HUD; wall frame time includes OS/other-process contention",
		"samples":rows,"failures":failures}
	var path := OS.get_environment("TEMP").path_join("battlebots-visual-load.json")
	var output := FileAccess.open(path,FileAccess.WRITE)
	if output == null:
		failures.append("Could not write measurement report")
	else:
		output.store_string(JSON.stringify(report,"\t"))
		output.close()
	print("VISUAL LOAD REPORT ",path)
	for row: Dictionary in rows: print(JSON.stringify(row))
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("BOT VISUAL LOAD PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

func measure(count: int, damaged: bool) -> Dictionary:
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	var max_sparks := 0
	var max_fragments := 0
	var calls := 0.0
	var primitives := 0.0
	for frame: int in WARM_FRAMES + SAMPLE_FRAMES:
		if damaged and frame % 10 == 0:
			for index: int in 8:
				impacts.spawn_impact(bots[index % bots.size()].presentation.global_position + Vector3.UP,
					Vector3.UP,"hammer",40.0)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if frame >= WARM_FRAMES:
			samples.append(float(now - previous) / 1000.0)
			calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		previous = now
		max_sparks = maxi(max_sparks,impacts.spark_count())
		max_fragments = maxi(max_fragments,impacts.fragment_count())
	check(max_sparks <= 64 and max_fragments <= 20,"Combined client effects stay capped")
	var smoke := 0
	for bot: MvpBot in bots:
		for particle: CPUParticles3D in bot.damage_visual.find_children("*","CPUParticles3D",true,false):
			if particle.emitting: smoke += particle.amount
	check(smoke == count * 18 if damaged else smoke == 0,"Smoke matches disabled components")
	var total := 0.0
	for sample: float in samples: total += sample
	samples.sort()
	return {"bots":count,"damaged_and_impacts":damaged,"mean_frame_ms":total / SAMPLE_FRAMES,
		"median_frame_ms":samples[SAMPLE_FRAMES / 2],"p95_frame_ms":samples[ceili(SAMPLE_FRAMES * 0.95) - 1],
		"mean_draw_calls":calls / SAMPLE_FRAMES,"mean_primitives":primitives / SAMPLE_FRAMES,
		"peak_sparks":max_sparks,"peak_fragments":max_fragments,"smoke_capacity":smoke}
