extends Node3D
## Isolated cosmetic impact acceptance; no simulation or network producer involved.
const KINDS := ["vertical_spinner","horizontal_spinner","saw","hammer","lifter","ram"]
var failures: Array[String] = []
class ShakeProbe extends Node:
	var calls := 0
	var strength := 0.0
	func add_impact_shake(_origin: Vector3, value: float) -> void:
		calls += 1
		strength = value
func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func active_meshes(effect: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in effect.get_children():
		if child is MeshInstance3D and child.visible: result.append(child)
	return result
func run() -> void:
	var script: Script = load("res://scripts/presentation/combat_impact_visual.gd")
	var effect: Node3D = script.new()
	add_child(effect)
	effect.set_process(false)
	var probe := ShakeProbe.new()
	probe.add_to_group(&"bot_orbit_cameras")
	add_child(probe)
	for kind: String in KINDS:
		effect.clear_effects()
		probe.calls = 0
		effect.spawn_impact(Vector3(2,1,-3),Vector3.UP,kind,80.0)
		check(effect.burst_count() == 1,"Confirmed " + kind + " contact throws one spark shower")
		check(effect.shockwave_count() == (1 if kind == "hammer" else 0),"Only hammer contact emits a shockwave (" + kind + ")")
		check(probe.calls == (1 if kind == "hammer" else 0),"Only hammer contact shakes nearby cameras (" + kind + ")")
		check(effect.spark_count() > 0,"Confirmed " + kind + " contact produces sparks")
		check(effect.fragment_count() > 0,"Damaging " + kind + " contact produces cosmetic fragments")
		check(effect.spark_count() <= 64 and effect.fragment_count() <= 20,"Per-client budgets apply to " + kind)
		for mesh: MeshInstance3D in active_meshes(effect):
			check(mesh.global_position.distance_to(Vector3(2,1,-3)) < 0.25,"Impact starts at supplied world contact")
		effect._process(1.51)
		check(effect.spark_count() == 0 and effect.fragment_count() == 0,"Every " + kind + " effect expires within1.5 seconds")
		check(effect.burst_count() == 0 and effect.shockwave_count() == 0,"Every " + kind + " shower and ring expires within1.5 seconds")
		check(active_meshes(effect).is_empty(),"Expired effects are invisible")
	for index in 200:
		effect.spawn_impact(Vector3(index * 0.01,1,0),Vector3.UP,KINDS[index % KINDS.size()],200.0)
		check(effect.spark_count() <= 64 and effect.fragment_count() <= 20,"Burst never exceeds global effect budgets")
		check(effect.burst_count() <= 10 and effect.shockwave_count() <= 4,"Showers and rings stay within their pools")
	var pool_size := effect.get_child_count()
	for index in 200: effect.spawn_impact(Vector3.ZERO,Vector3.UP,"saw",200.0)
	check(effect.get_child_count() == pool_size,"Further bursts reuse bounded pool nodes")
	check(effect.get_child_count() <= 85,"Pool has at most64 sparks,20 fragments and one burst container")
	var bursts: Node = effect.get_node("Bursts")
	var burst_nodes := bursts.get_child_count()
	check(burst_nodes <= 10 * 2 + 4 * 2,"Burst container holds at most ten showers with flashes and four rings with dust")
	for index in 50: effect.spawn_impact(Vector3.ZERO,Vector3.UP,"hammer",200.0)
	check(bursts.get_child_count() == burst_nodes,"Further hammer blows reuse pooled rings and showers")
	effect.spawn_impact(Vector3.ZERO,Vector3.UP,"hammer",10.0)
	check(probe.strength > 0.0 and probe.strength <= 1.0,"Shake strength is bounded")
	check(effect.find_children("*","CollisionObject3D",true,false).is_empty(),"Cosmetic effects create no collision bodies")
	check(effect.find_children("*","CollisionShape3D",true,false).is_empty(),"Cosmetic effects create no collision shapes")
	effect.clear_effects()
	check(effect.spark_count() == 0 and effect.fragment_count() == 0 and active_meshes(effect).is_empty(),"Clear removes every live effect immediately")
	check(effect.burst_count() == 0 and effect.shockwave_count() == 0,"Clear retires every shower and ring immediately")
	effect.spawn_ground_slam(Vector3(1,0,2),Vector3.UP)
	check(effect.shockwave_count() == 1 and effect.burst_count() == 1,"Ground slam emits one ring and one shower")
	effect.clear_effects()
	for bad: Vector3 in [Vector3(NAN,0,0),Vector3(0,INF,0)]:
		effect.spawn_ground_slam(bad,Vector3.UP)
		effect.spawn_ground_slam(Vector3.ZERO,bad)
	effect.spawn_ground_slam(Vector3.ZERO,Vector3.UP,NAN)
	check(effect.shockwave_count() == 0,"Invalid ground slams rejected")
	# One ring per hammer swing, keyed by attacker.
	effect.spawn_impact(Vector3(0,1,0),Vector3.UP,"hammer",38.0,7)
	effect.spawn_impact(Vector3(2,1,0),Vector3.UP,"hammer",38.0,7)
	check(effect.shockwave_count() == 1 and effect.burst_count() == 2,"Multi-target swing makes one ring but sparks on each hit")
	effect.spawn_ground_slam(Vector3(1,0,1),Vector3.UP,0.8,7)
	effect._process(0.3)
	check(effect.shockwave_count() == 1 and effect.pending_slam_count() == 0,"Ground slam after a bot hit adds no second ring")
	effect.spawn_impact(Vector3(5,1,0),Vector3.UP,"hammer",38.0,8)
	check(effect.shockwave_count() == 2,"Another attacker gets its own ring")
	effect.clear_effects()
	effect.spawn_ground_slam(Vector3(1,0,1),Vector3.UP,0.8,9)
	effect.spawn_ground_slam(Vector3(1,0,1),Vector3.UP,0.8,9)
	check(effect.shockwave_count() == 0 and effect.pending_slam_count() == 1,"Ground slam waits once for a late bot event")
	effect.spawn_impact(Vector3(0,1,0),Vector3.UP,"hammer",38.0,9)
	effect._process(0.3)
	check(effect.shockwave_count() == 1 and effect.pending_slam_count() == 0,"A late bot hit replaces the pending ground ring")
	effect.clear_effects()
	effect.spawn_ground_slam(Vector3(1,0,1),Vector3.UP,0.8,10)
	effect._process(0.2)
	check(effect.shockwave_count() == 1,"An unclaimed ground slam rings after the grace period")
	effect._process(1.0)
	effect.spawn_ground_slam(Vector3(1,0,1),Vector3.UP,0.8,10)
	effect._process(0.2)
	check(effect.shockwave_count() == 1,"The next swing rings again once the window has passed")
	effect.clear_effects()
	await check_slam_detector()
	effect.spawn_impact(Vector3.ZERO,Vector3.UP,"lifter",0.0)
	check(effect.spark_count() > 0 and effect.fragment_count() == 0,"Zero-damage contact has sparks without damage fragments")
	effect.clear_effects()
	for damage: float in [-1.0,NAN,INF]:
		effect.spawn_impact(Vector3.ZERO,Vector3.UP,"saw",damage)
		check(effect.spark_count() == 0 and effect.fragment_count() == 0,"Invalid damage rejected")
	for origin: Vector3 in [Vector3(NAN,0,0),Vector3(0,INF,0)]:
		effect.spawn_impact(origin,Vector3.UP,"saw",30.0)
		check(effect.spark_count() == 0 and effect.fragment_count() == 0,"Nonfinite world origin rejected")
	for normal: Vector3 in [Vector3(NAN,0,0),Vector3(0,INF,0)]:
		effect.spawn_impact(Vector3.ZERO,normal,"saw",30.0)
		check(effect.spark_count() == 0 and effect.fragment_count() == 0,"Nonfinite surface normal rejected")
	effect.spawn_impact(Vector3.ZERO,Vector3.UP,"unknown",30.0)
	check(effect.spark_count() == 0 and effect.fragment_count() == 0,"Unknown impact kind rejected")
	effect.spawn_impact(Vector3.ZERO,Vector3.ZERO,"saw",30.0)
	check(effect.spark_count() > 0,"Degenerate normal uses a finite upward fallback")
	effect.clear_effects()
	var other: Node3D = script.new()
	add_child(other)
	other.set_process(false)
	other.spawn_impact(Vector3.ZERO,Vector3.UP,"hammer",40.0)
	check(effect.spark_count() == 0 and other.spark_count() > 0,"Instances own independent effect state")
	other.free()
	effect.transform = Transform3D(Basis.from_euler(Vector3(0.4,1.3,PI)).scaled(Vector3(2,0.6,1.2)),Vector3(9,4,-5))
	var contact := Vector3(-4,2,7)
	effect.spawn_impact(contact,Vector3.UP,"vertical_spinner",40.0)
	var before: Dictionary = {}
	for mesh: MeshInstance3D in active_meshes(effect):
		check(mesh.global_position.distance_to(contact) < 0.25,"Transformed parent preserves supplied world origin")
		before[mesh] = mesh.global_transform
	effect.position += Vector3(10,8,6)
	effect.rotate_z(0.6)
	for mesh: MeshInstance3D in active_meshes(effect):
		check(mesh.global_transform.is_equal_approx(before[mesh]),"Parent motion does not drag emitted effects")
	effect._process(0.05)
	for mesh: MeshInstance3D in active_meshes(effect):
		check(mesh.global_transform.is_finite(),"World trajectories remain finite")
	effect.clear_effects()
	effect.transform = Transform3D.IDENTITY
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless": await capture(effect)
	effect.free()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("COMBAT IMPACT VISUAL PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

func slab(at: Vector3, extent: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.position = at
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = extent
	body.add_child(shape)
	add_child(body)
	return body

func check_slam_detector() -> void:
	check(HammerSlamDetector.strike_edge("windup",0.0,"strike",1.4),"Strike state marks a hammer blow")
	check(not HammerSlamDetector.strike_edge("strike",1.4,"cooldown",1.38),"Cooldown after a seen strike is not a second blow")
	check(HammerSlamDetector.strike_edge("windup",0.0,"cooldown",1.38),"A skipped strike tick is recovered from the fresh cooldown")
	check(not HammerSlamDetector.strike_edge("cooldown",0.9,"cooldown",0.88),"Ordinary cooldown is not a blow")
	var size := Vector3(1.5,1.5,3.0)
	var detector := HammerSlamDetector.new()
	add_child(detector)
	detector.configure({},size,RID())
	var head: Dictionary = HammerSlamDetector.head_end({},size)
	check(head.center.z < -size.z * 0.5,"Generic hammer lands ahead of the hull")
	var floor := slab(Vector3(0,-0.5,0),Vector3(40,1,40),BaselineConfig.WORLD_LAYER)
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,0.75,0))
	await get_tree().physics_frame
	var landing: Dictionary = detector.find_landing(pose)
	check(not landing.is_empty() and absf(landing.position.y) < 0.01 and landing.normal.is_equal_approx(Vector3.UP),"Hammer head over the floor lands on it")
	var tip: Vector3 = pose * (head.center as Vector3)
	var victim := slab(Vector3(tip.x,0.3,tip.z),Vector3(1,0.6,1),BaselineConfig.BOT_LAYER)
	await get_tree().physics_frame
	check(detector.find_landing(pose).is_empty(),"A bot under the head suppresses the ground slam")
	victim.free()
	var registry := ContentRegistry.new()
	var sawblade := registry.duelist()
	sawblade.cosmetics = {"paint":"cyan", "sawblade":SawbladeConfig.defaults()}
	for build: Dictionary in [registry.duelist(), registry.scorpion(), sawblade]:
		var stats: Dictionary = registry.validate(build).stats
		detector.configure(registry.validate(build).loadout, stats.size, RID())
		var standing := Transform3D(Basis.IDENTITY, Vector3(0, stats.size.y * 0.5, 0))
		check(not detector.find_landing(standing).is_empty(), "Real %s hammer reaches the floor" % build.parts.chassis)
	floor.free()
	detector.free()

func capture(effect: Node3D) -> void:
	get_window().size = Vector2i(1280,720)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(3,2.8,4.4).normalized() * 6.0 + Vector3(0,0.5,0)
	camera.look_at(Vector3(0,0.5,0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("28323d")
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-30,0)
	light.light_energy = 1.5
	add_child(light)
	var target := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.6,0.5,2.0)
	target.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("495d72")
	target.material_override = material
	target.position.y = 0.35
	add_child(target)
	var label := Label.new()
	label.position = Vector2(24,24)
	label.add_theme_font_size_override("font_size",24)
	add_child(label)
	for kind: String in KINDS:
		effect.clear_effects()
		effect.spawn_impact(Vector3(0.6,0.55,0.9),Vector3(1,1,1).normalized(),kind,80.0)
		effect._process(0.08)
		label.text = "%s contact - camera 6m" % kind
		for frame in 3: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("combat-impact-%s-6m.png" % kind))
	light.free()
	camera.free()
	environment.free()
	target.free()
	label.free()


