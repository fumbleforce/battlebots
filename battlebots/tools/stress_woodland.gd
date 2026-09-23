extends SceneTree
## Woodland stress benchmark: the practice session with the Warden plus a
## free-for-all of armed bots using every turret, melee weapon, nitro and
## jumps, filmed from a chase-height camera near the fight. Reports frame,
## GPU, CPU and physics time, and live effect counts. Native renderer only.
## godot --path battlebots --script res://tools/stress_woodland.gd -- [--size=2560x1440] [--bots=12] [--seconds=45]
const TURRETS := ["turret_cannon_quad", "turret_plasma_quad", "turret_flamer", "turret_tesla", "turret_railgun",
	"turret_harpoon", "turret_mortar", "turret_cannon_dual", "turret_plasma_dual", "turret_cannon"]
const MELEE := ["hammer", "vertical_spinner", "horizontal_spinner", "saw", "lifter", "battering_ram", "spear_fork", "grinder_drum"]

var session: MvpSession
var fighter_ids: Array[int] = []
var fighters: Array[MvpBot]:
	get:
		var out: Array[MvpBot] = []
		for id: int in fighter_ids:
			if session.world.bots.has(id) and is_instance_valid(session.world.bots[id]):
				out.append(session.world.bots[id])
		return out
var _clock := 0.0

func _initialize() -> void:
	call_deferred("_run")

func _build(registry: ContentRegistry, index: int) -> Dictionary:
	var draft := registry.starter()
	draft.name = "Stress %d" % index
	if index % 3 == 2:
		draft.parts = {"chassis":"scorpion_hex", "drive":"walker", "weapon":MELEE[index % MELEE.size()] if index % 2 == 0 else "minigun",
			"utility":"recovery_assist", "nitro":"nitro_boost", "suspension":"charged_jump"}
	else:
		draft.parts = {"chassis":"atlas_mx", "drive":"traction", "weapon":MELEE[index % MELEE.size()],
			"utility":TURRETS[index % TURRETS.size()], "nitro":"nitro_boost", "suspension":"charged_jump"}
	draft.cosmetics = {"paint":["cyan", "orange", "white", "red"][index % 4], "sawblade":SawbladeConfig.defaults()}
	return draft

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(2560, 1440)
	var count := 12
	var seconds := 45.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.substr(7).split("x")
			root.size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("--bots="):
			count = int(arg.substr(7))
		elif arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
	root.mesh_lod_threshold = 2.0
	var vp := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	session = MvpSession.new()
	root.add_child(session)
	session.practice({}, "woodland")
	var registry := ContentRegistry.new()
	registry.enforce_budget = false
	var next := 100
	for index: int in count:
		var draft := _build(registry, index)
		var bot := MvpBot.create(next + index, 20 + index, draft, registry)
		if bot == null:
			print("SKIP invalid build ", draft.parts)
			continue
		session.world.add_child(bot)
		bot.arena_half_extent = ArenaBounds.half_extent("woodland")
		session.world.bots[bot.entity_id] = bot
		var angle := TAU * index / count
		var at := Vector3(cos(angle), 0, sin(angle)) * 55.0
		at.y = preload("res://scripts/arena/woodland_ground.gd").height_at(at.x, at.z) + bot.ground_clearance() + 0.3
		var pose := Transform3D(Basis(Vector3.UP, -angle - PI * 0.5), at)
		bot.spawn_pose = pose
		bot.body.reset_pose = pose
		bot.body.global_transform = pose
		bot.previous_pose = pose
		fighter_ids.append(bot.entity_id)
	var cam := Camera3D.new()
	session.world.add_child(cam)
	cam.current = true
	cam.fov = 70
	cam.far = 12000
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var physics_ms: Array[float] = []
	var peak := {}
	var previous := Time.get_ticks_usec()
	var elapsed := 0.0
	var known := {}
	while elapsed < seconds:
		await process_frame
		var processed := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if now - previous > 250000:
			print("STALL split: process ", (processed - previous) / 1000, " ms, draw ", (now - processed) / 1000, " ms")
		var ms := (now - previous) / 1000.0
		previous = now
		elapsed += ms / 1000.0
		_drive(ms / 1000.0)
		# Chase camera behind the first living fighter, looking at the melee.
		var focus: MvpBot = null
		for bot: MvpBot in fighters:
			if not bot.combat.eliminated:
				focus = bot
				break
		if focus != null:
			var back := focus.body.global_basis.z.slide(Vector3.UP).normalized()
			cam.position = cam.position.lerp(focus.body.global_position + back * 16.0 + Vector3.UP * 7.0, 0.1)
			cam.look_at(focus.body.global_position + Vector3.UP * 2.0 - back * 10.0)
		# Name what appeared in a stalled frame: first-use shader or pipeline
		# compiles show up as newly created effect nodes.
		var fresh := _new_nodes(known)
		if ms > 250.0:
			print("STALL new nodes: ", fresh.slice(0, 16))
		if ms > 250.0 and elapsed <= 3.0:
			print("STALL ", snappedf(ms, 1), " ms at ", snappedf(elapsed, 0.1), " s (warm-up)")
		if elapsed > 3.0:
			frames.append(ms)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			if ms > 250.0:
				print("STALL ", snappedf(ms, 1), " ms at ", snappedf(elapsed, 0.1), " s")
		if elapsed > 3.0 and frames.size() % 30 == 0:
			for key: String in ["GPUParticles3D", "Light3D", "FogVolume", "Decal"]:
				peak[key] = maxi(int(peak.get(key, 0)), root.find_children("*", key, true, false).size())
			peak["prims"] = maxf(float(peak.get("prims", 0.0)), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			peak["draws"] = maxf(float(peak.get("draws", 0.0)), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var shots := 0
	var eliminated := 0
	for bot: MvpBot in fighters:
		shots += bot.combat.shot_sequence
		eliminated += int(bot.combat.eliminated)
	for list: Array[float] in [frames, gpu, cpu, physics_ms]:
		list.sort()
	var pct := func(list: Array[float], q: float) -> float: return snappedf(list[mini(list.size() - 1, int(list.size() * q))], 0.1)
	print("STRESS %dx%d bots=%d(+giant+3 practice) seconds=%d frames=%d" % [root.size.x, root.size.y, fighters.size(), seconds, frames.size()])
	print("STRESS frame median=", pct.call(frames, 0.5), " p95=", pct.call(frames, 0.95), " p99=", pct.call(frames, 0.99), " max=", snappedf(frames[-1], 0.1))
	print("STRESS gpu median=", pct.call(gpu, 0.5), " p95=", pct.call(gpu, 0.95), " | cpu render median=", pct.call(cpu, 0.5),
		" | physics median=", pct.call(physics_ms, 0.5), " p95=", pct.call(physics_ms, 0.95))
	print("STRESS peaks ", peak, " turret shots=", shots, " eliminated=", eliminated)
	# Paired attribution while the fight continues (minimum GPU ms, on/off/on).
	var env: Environment = (session.world.arena.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun: DirectionalLight3D = session.world.arena.get_node("Sun")
	var tests := {
		"volumetric fog": [func(): env.volumetric_fog_enabled = false, func(): env.volumetric_fog_enabled = true],
		"combat particles": [func(): _set_all("GPUParticles3D", false), func(): _set_all("GPUParticles3D", true)],
		"dynamic lights": [func(): _set_lights(false), func(): _set_lights(true)],
		"sun shadows": [func(): sun.shadow_enabled = false, func(): sun.shadow_enabled = true],
		"ssil": [func(): env.ssil_enabled = false, func(): env.ssil_enabled = true],
		"particle shadows": [func(): _shadows(root.find_children("*", "GPUParticles3D", true, false), false),
			func(): _shadows(root.find_children("*", "GPUParticles3D", true, false), true)],
		"bot shadows": [func(): _shadows(_bot_geometry(), false), func(): _shadows(_bot_geometry(), true)],
		"4 -> 2 splits": [func(): sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
			func(): sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS],
	}
	for label: String in tests:
		var a := await _gpu_min(vp, 20)
		tests[label][0].call()
		var b := await _gpu_min(vp, 20)
		tests[label][1].call()
		var c := await _gpu_min(vp, 20)
		print("STRESS saves ", snappedf((a + c) * 0.5 - b, 0.01), " ms  ", label)
	quit()

func _new_nodes(known: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var id := node.get_instance_id()
		if not known.has(id):
			known[id] = true
			var script: Script = node.get_script()
			out.append("%s(%s)" % [node.name, script.resource_path.get_file() if script else node.get_class()])
	return out

func _gpu_min(vp: RID, frames: int) -> float:
	var best := INF
	for i in frames:
		await process_frame
		await RenderingServer.frame_post_draw
		_drive(1.0 / 60.0)
		if i > 4: best = minf(best, RenderingServer.viewport_get_measured_render_time_gpu(vp))
	return best

var _saved_shadows := {}
func _shadows(nodes: Array, on: bool) -> void:
	for node: Node in nodes:
		var geometry := node as GeometryInstance3D
		if geometry == null:
			continue
		if not on:
			_saved_shadows[geometry.get_instance_id()] = geometry.cast_shadow
			geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif _saved_shadows.has(geometry.get_instance_id()):
			geometry.cast_shadow = _saved_shadows[geometry.get_instance_id()]

func _bot_geometry() -> Array:
	var out := []
	for bot: MvpBot in session.world.bots.values():
		if is_instance_valid(bot):
			out.append_array(bot.find_children("*", "GeometryInstance3D", true, false))
	return out

func _set_all(type: String, on: bool) -> void:
	for node: Node in root.find_children("*", type, true, false):
		(node as Node3D).visible = on

func _set_lights(on: bool) -> void:
	for node: Node in root.find_children("*", "Light3D", true, false):
		if not node is DirectionalLight3D and node.get_parent() is Node3D and not String(node.get_path()).contains("EnvironmentArt"):
			(node as Light3D).visible = on

## Every fighter hunts the nearest other bot: full throttle with nitro, turret
## tracking, melee held when close, charged jumps now and then.
func _drive(delta: float) -> void:
	_clock += delta
	for bot: MvpBot in fighters:
		if bot.combat.eliminated:
			continue
		var target: MvpBot = null
		var best := INF
		for other: MvpBot in session.world.bots.values():
			if not is_instance_valid(other) or other == bot or other.combat.eliminated:
				continue
			var d := bot.body.global_position.distance_to(other.body.global_position)
			if d < best:
				best = d
				target = other
		var command := BotCommand.new()
		command.sequence = bot.last_sequence + 1
		if target != null:
			var to := target.body.global_position - bot.body.global_position
			var local := bot.body.global_basis.inverse() * to
			var angle := atan2(local.x, -local.z)
			command.throttle = 1.0 if absf(angle) < 1.2 else 0.4
			var forward := (-bot.body.global_basis.z).slide(Vector3.UP).normalized()
			command.steering = clampf(angle * 1.5, -1.0, 1.0) * DriveModel.steering_direction(bot.body.linear_velocity.dot(forward), command.throttle)
			command.nitro_held = best > 20.0 and fmod(_clock + bot.entity_id, 6.0) < 2.0
			command.primary_held = best < 14.0
			command.primary_pressed = command.primary_held and fmod(_clock * 60.0 + bot.entity_id, 30.0) < 1.0
			command.aim_valid = true
			command.aim_yaw = atan2(-to.x, -to.z)
			command.aim_pitch = atan2(to.y, Vector2(to.x, to.z).length())
			command.auxiliary_held = best < 150.0
			command.jump_held = fmod(_clock + bot.entity_id * 0.7, 9.0) < 0.6
		command.recovery_pressed = bot.body.global_basis.y.y < -0.2 and bot.combat.recovery_cooldown <= 0.0
		bot.submit_command(command)
