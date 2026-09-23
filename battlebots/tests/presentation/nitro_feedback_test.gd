extends Node3D
## Nitro plume outlets/state and the local camera's speed feel. Presentation only.
var failures := 0

class NitroSource extends BotSource:
	var nitro := false
	var eliminated := false
	func read_view() -> BotView:
		var view := BotView.new()
		view.pose = global_transform
		view.nitro_active = nitro
		view.eliminated = eliminated
		return view

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)

func boost(visual: NitroFlameVisual, on: bool, seconds: float, eliminated := false) -> void:
	var view := BotView.new()
	view.nitro_active = on
	view.eliminated = eliminated
	for step: int in int(seconds * 60.0): visual.show_state(view, 1.0 / 60.0)

func visible_flames(visual: NitroFlameVisual) -> int:
	var count := 0
	for outlet: Dictionary in visual.outlets:
		if (outlet.flame as MeshInstance3D).visible: count += 1
	return count

func run() -> void:
	await get_tree().process_frame
	# Hull without authored pipes vents from its rear (+Z) face.
	var hull := Node3D.new()
	add_child(hull)
	var fallback := NitroFlameVisual.new()
	hull.add_child(fallback)
	fallback.configure(hull, Vector3(2.4, 1.5, 3.0), 3.0)
	check(fallback.outlets.size() == 2, "Unauthored hull gets two rear outlets")
	for outlet: Dictionary in fallback.outlets:
		check(outlet.offset.z >= 1.5 and outlet.offset.z < 1.6 and outlet.direction.z > 0.9, "Fallback vents rearward from the hull back")
	check(fallback.intensity == 0.0 and visible_flames(fallback) == 0, "Plume starts idle")
	boost(fallback, true, 0.4)
	check(fallback.intensity > 0.95, "Nitro ignites the plume quickly")
	check(visible_flames(fallback) == 2, "Every outlet shows a flame while boosting")
	for outlet: Dictionary in fallback.outlets:
		var flame: MeshInstance3D = outlet.flame
		check((outlet.embers as GPUParticles3D).emitting, "Embers stream while boosting")
		var nozzle: Vector3 = hull.global_transform * (outlet.offset as Vector3)
		check(flame.global_position.z > nozzle.z, "Flame extends behind the nozzle")
		check(flame.global_transform.is_finite(), "Flame transform is finite")
	boost(fallback, false, 1.0)
	check(fallback.intensity == 0.0 and visible_flames(fallback) == 0, "Releasing nitro extinguishes the plume")
	for outlet: Dictionary in fallback.outlets:
		check(not (outlet.embers as GPUParticles3D).emitting, "Embers stop after release")
	boost(fallback, true, 0.5, true)
	check(fallback.intensity == 0.0, "Eliminated bots never show nitro")
	hull.position = Vector3(5, 0, -2)
	hull.rotation.y = PI * 0.5
	boost(fallback, true, 0.3)
	var outlet0: Dictionary = fallback.outlets[0]
	var world_nozzle: Vector3 = hull.global_transform * (outlet0.offset as Vector3)
	check((outlet0.embers as GPUParticles3D).global_position.distance_to(world_nozzle) < 0.001, "Jets follow the moving chassis")
	check(fallback.find_children("*", "CollisionObject3D", true, false).is_empty(), "Plume creates no collision")
	hull.free()

	# Scorpion: the imported pipe lips are the emission origins.
	var scorpion := Node3D.new()
	add_child(scorpion)
	for label: String in ["ExhaustLeft", "ExhaustRight"]:
		var lip := Node3D.new()
		lip.name = label
		scorpion.add_child(lip)
	check(NitroFlameVisual.find_outlets(scorpion, Vector3.ONE).size() == 2, "Scorpion uses both authored stack lips")
	scorpion.free()

	# Atlas: two upright stacks at the rear of the selected exhaust module.
	var atlas: Node3D = load("res://assets/models/atlas_runtime/atlas_mx.glb").instantiate()
	add_child(atlas)
	for label: String in ["ExhaustMedium", "ExhaustLarge"]: atlas.find_child(label, true, false).hide()
	var atlas_outlets := NitroFlameVisual.find_outlets(atlas, Vector3.ONE)
	check(atlas_outlets.size() == 2, "Atlas small exhaust has two stack outlets (got %d)" % atlas_outlets.size())
	for outlet: Dictionary in atlas_outlets:
		var at: Vector3 = (outlet.anchor as Node3D).global_transform * (outlet.offset as Vector3)
		check(absf(absf(at.x) - 0.49) < 0.03 and absf(at.y - 0.71) < 0.03 and absf(at.z - 0.72) < 0.03,
			"Atlas outlet sits on a stack rim: %s" % at)
		check(outlet.direction == Vector3.UP and outlet.radius > 0.02, "Atlas stacks fire upward from a real rim")
	atlas.free()

	# Sawblade: rear-facing hollow pipes of the selected module.
	var sawblade: Node3D = load("res://assets/models/sawblade_runtime/sawblade_runtime.glb").instantiate()
	add_child(sawblade)
	for node: Node in sawblade.find_children("*", "Node3D", true, false):
		var source: String = node.get_meta("extras", {}).get("source_name", "")
		if source in ["Module_exhaust_medium", "Module_exhaust_large"]: node.hide()
	var saw_outlets := NitroFlameVisual.find_outlets(sawblade, Vector3.ONE)
	check(saw_outlets.size() == 1, "Sawblade small exhaust has one pipe (got %d)" % saw_outlets.size())
	for outlet: Dictionary in saw_outlets:
		var at: Vector3 = (outlet.anchor as Node3D).global_transform * (outlet.offset as Vector3)
		check(at.distance_to(Vector3(0, 0.68, 1.75)) < 0.03, "Sawblade outlet sits on the pipe mouth: %s" % at)
	sawblade.free()

	# Local camera: FOV kick, boom stretch and easing back out.
	var source := NitroSource.new()
	add_child(source)
	source.position = Vector3(0, 0.6, 0)
	var rig: BotOrbitCamera = load("res://scenes/ui/orbit_camera.tscn").instantiate()
	add_child(rig)
	rig.set_physics_process(false)
	rig.bind_source(source)
	await get_tree().physics_frame
	for step: int in 30: rig.update_camera(1.0 / 60.0)
	var calm_fov := rig.camera.fov
	var calm_distance := rig.actual_distance
	check(is_equal_approx(calm_fov, rig.base_fov), "Camera keeps its base FOV without nitro")
	check(rig.camera.position.is_equal_approx(Vector3(0, 0, rig.actual_distance)), "No shake without nitro or impacts")
	source.nitro = true
	for step: int in 90: rig.update_camera(1.0 / 60.0)
	check(rig.camera.fov > calm_fov + rig.nitro_fov_boost * 0.9, "Nitro widens the FOV (%.1f)" % rig.camera.fov)
	check(rig.actual_distance > calm_distance, "Nitro stretches the camera boom")
	check(absf(rig.camera.position.z - rig.actual_distance) < 0.001 and rig.camera.position.length() > rig.actual_distance, "Nitro adds a small rumble around the boom")
	source.nitro = false
	for step: int in 150: rig.update_camera(1.0 / 60.0)
	check(is_equal_approx(rig.camera.fov, rig.base_fov), "FOV eases back after nitro")
	source.nitro = true
	source.eliminated = true
	for step: int in 60: rig.update_camera(1.0 / 60.0)
	check(is_equal_approx(rig.camera.fov, rig.base_fov), "Eliminated bots get no nitro camera")
	source.eliminated = false
	rig.speed_effects = false
	for step: int in 60: rig.update_camera(1.0 / 60.0)
	check(is_equal_approx(rig.camera.fov, rig.base_fov), "Disabling speed effects suppresses the FOV kick")
	rig.speed_effects = true
	source.nitro = false
	for step: int in 150: rig.update_camera(1.0 / 60.0)
	# Hammer shake attenuates with distance and decays.
	check(rig.is_in_group(&"bot_orbit_cameras"), "Rig listens for impact shake")
	rig.add_impact_shake(rig.global_position + Vector3(200, 0, 0), 1.0)
	check(rig.shake_trauma == 0.0, "Distant blows do not shake the camera")
	rig.add_impact_shake(rig.global_position + Vector3(1, 0, 0), 1.0)
	check(rig.shake_trauma > 0.3, "A nearby hammer blow shakes the camera")
	rig.update_camera(1.0 / 60.0)
	check(not rig.camera.position.is_equal_approx(Vector3(0, 0, rig.actual_distance)), "Shake displaces the camera")
	for bad: float in [NAN, INF, -1.0]:
		var before := rig.shake_trauma
		rig.add_impact_shake(Vector3.ZERO, bad)
		check(rig.shake_trauma == before, "Invalid shake strength ignored")
	for step: int in 90: rig.update_camera(1.0 / 60.0)
	check(rig.shake_trauma == 0.0 and rig.camera.position.is_equal_approx(Vector3(0, 0, rig.actual_distance)), "Shake settles")
	rig.free()
	source.free()
	if failures == 0: print("NITRO FEEDBACK PASS")
	get_tree().quit(0 if failures == 0 else 1)
