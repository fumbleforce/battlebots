extends Node3D
## Physical geometry grows exactly once while workshop assembly remains canonical.
const CANONICAL := Vector3(1.6, 0.5, 2.0)
var failures: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func bounds(root: Node3D) -> AABB:
	var result := AABB()
	var initialized := false
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var box := mesh.get_aabb()
		for index: int in 8:
			var point := mesh.global_transform * box.get_endpoint(index)
			if not initialized:
				result = AABB(point, Vector3.ZERO)
				initialized = true
			else: result = result.expand(point)
	return result

func compare_geometry(small: Node3D, large: Node3D, label: String) -> void:
	var canonical := bounds(small)
	var physical := bounds(large)
	check((canonical.size * BotScale.FACTOR).distance_to(physical.size) < 0.003,
		label + ": visible mesh dimensions grow exactly threefold")
	check((canonical.position * BotScale.FACTOR).distance_to(physical.position) < 0.003,
		label + ": weapon/drive mounts stay aligned with the enlarged body")
	small.free()
	large.free()

func check_geometry(registry: ContentRegistry) -> void:
	for kind: String in ["vertical_spinner", "horizontal_spinner", "saw", "hammer", "lifter"]:
		var small := MvpWeaponVisual.new()
		var large := MvpWeaponVisual.new()
		add_child(small)
		add_child(large)
		small.assemble(kind, CANONICAL)
		large.assemble(kind, CANONICAL * BotScale.FACTOR)
		compare_geometry(small, large, "Primitive " + kind)
		var draft := SawbladeConfig.starter(registry)
		draft.parts.weapon = kind
		var authored_small := SawbladeVisual.new()
		var authored_large := SawbladeVisual.new()
		add_child(authored_small)
		add_child(authored_large)
		authored_small.assemble(draft, CANONICAL)
		authored_large.assemble(draft, CANONICAL * BotScale.FACTOR)
		compare_geometry(authored_small, authored_large, "Authored " + kind)
	var draft := SawbladeConfig.starter(registry)
	draft.parts.drive = "walker"
	var small := SawbladeVisual.new()
	var large := SawbladeVisual.new()
	add_child(small)
	add_child(large)
	small.assemble(draft, CANONICAL)
	large.assemble(draft, CANONICAL * BotScale.FACTOR)
	for visual: SawbladeVisual in [small, large]:
		visual.walker_legs.terrain = false
		visual.walker_legs.reset_feet()
	compare_geometry(small, large, "Authored walker including planted feet")

func check_effects() -> void:
	var effects: Array[BotDestructionVisual] = []
	for factor: float in [1.0, BotScale.FACTOR]:
		var effect := BotDestructionVisual.new()
		add_child(effect)
		effect.configure(effect, CANONICAL * factor)
		var view := BotView.new()
		view.entity_id = 19
		effect.observe(view)
		view.eliminated = true
		view.core_fraction = 0.0
		effect.observe(view)
		effect._process(0.3)
		effect.set_process(false)
		effects.append(effect)
	var small := effects[0]
	var large := effects[1]
	check(small.burst_root.get_child_count() == large.burst_root.get_child_count(), "Larger explosion preserves its node budget")
	var small_batches := small.burst_root.find_children("*", "MultiMeshInstance3D", true, false)
	var large_batches := large.burst_root.find_children("*", "MultiMeshInstance3D", true, false)
	for index: int in small_batches.size():
		var a: MultiMesh = small_batches[index].multimesh
		var b: MultiMesh = large_batches[index].multimesh
		check(a.instance_count == b.instance_count, "Larger explosion preserves its fragment and spark counts")
		# The dummy renderer returns identity transforms instead of GPU instance data.
		if DisplayServer.get_name() == "headless": continue
		var original := a.get_instance_transform(0)
		var enlarged := b.get_instance_transform(0)
		check((original.origin * BotScale.FACTOR).distance_to(enlarged.origin) < 0.001,
			"Explosion trajectories grow with the physical body")
		check((original.basis.get_scale() * BotScale.FACTOR).distance_to(enlarged.basis.get_scale()) < 0.001,
			"Explosion debris geometry grows with the physical body")
	compare_geometry(small, large, "Explosion cloud and shockwave")
	var damage := BotDamageVisual.new()
	add_child(damage)
	damage.bind_component("weapon", [], damage)
	var smoke: CPUParticles3D = damage.components.weapon.smoke
	var amount := smoke.amount
	var original_quad: Vector2 = smoke.mesh.size
	damage.set_geometry_scale(BotScale.FACTOR)
	damage.set_geometry_scale(BotScale.FACTOR)
	check(smoke.mesh.size.is_equal_approx(original_quad * BotScale.FACTOR), "Damage plume scaling is noncompounding")
	check(smoke.amount == amount, "Larger damage plume preserves its particle budget")
	damage.free()

func check_preview(registry: ContentRegistry) -> void:
	var host := Control.new()
	host.size = Vector2(640, 440)
	add_child(host)
	var preview := GarageBotPreview.new()
	host.add_child(preview)
	for drive: String in ["traction", "walker"]:
		var draft := SawbladeConfig.starter(registry)
		draft.parts.drive = drive
		draft.parts.armor = "light"
		preview.show_loadout(draft)
		var reference := SawbladeVisual.new()
		add_child(reference)
		var size: Vector3 = registry.validate(draft).stats.size / BotScale.FACTOR
		reference.assemble(draft, size)
		reference.position += preview.model.position
		if reference.walker_legs != null:
			reference.walker_legs.terrain = false
			reference.walker_legs.reset_feet()
		var expected := bounds(reference)
		var actual := bounds(preview.model)
		check(actual.size.distance_to(expected.size) < 0.003, "Garage keeps canonical " + drive + " dimensions")
		check(actual.position.distance_to(expected.position) < 0.003, "Garage keeps canonical " + drive + " placement")
		check(is_equal_approx(preview.distance, 5.4), "Garage retains its original inspection camera")
		reference.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		host.size = Vector2(1280, 720)
		for frame: int in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("heavy-garage.png")) == OK,
			"Native canonical garage capture saved")
	host.free()

func check_runtime(registry: ContentRegistry) -> void:
	var arena: Node3D = load("res://scenes/arenas/baseline_arena.tscn").instantiate()
	add_child(arena)
	var bot := MvpBot.create(1, 0, SawbladeConfig.starter(registry), registry)
	add_child(bot)
	bot.set_process(false)
	bot.body.freeze = true
	bot.body.reset_pose = null
	bot.body.global_position = Vector3(0, bot.combat.stats.size.y * 0.5 + 0.03, 0)
	bot._process(0.0)
	var rig: BotOrbitCamera = load("res://scenes/ui/orbit_camera.tscn").instantiate()
	add_child(rig)
	rig.set_physics_process(false)
	rig.bind_source(bot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	rig.update_camera(0.016)
	check(is_equal_approx(rig.desired_distance, 12.0), "Larger robot has the authored closer 12m follow distance")
	check(is_equal_approx(rig.actual_distance, rig.desired_distance - 0.03), "Open arena gives enlarged bot full camera boom")
	check(is_equal_approx(bot.camera_anchor().position.y, 0.6 * BotScale.FACTOR), "Runtime camera anchor grows with chassis")
	rig.zoom(100)
	check(is_equal_approx(rig.desired_distance, 18.0), "Physical zoom maximum")
	rig.zoom(-100)
	check(is_equal_approx(rig.desired_distance, 8.0), "Physical zoom minimum")
	rig.zoom(4)
	var preserved := rig.desired_distance
	rig.bind_source(bot)
	check(is_equal_approx(rig.desired_distance, preserved), "Rebinding the same scale preserves relative player zoom")
	rig.update_camera(0.016)
	if DisplayServer.get_name() != "headless":
		var extent := bounds(bot.presentation)
		var viewport_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
		for index: int in 8:
			var point := extent.get_endpoint(index)
			check(not rig.camera.is_position_behind(point) and viewport_rect.has_point(rig.camera.unproject_position(point)),
				"The complete enlarged authored bot fits the normal gameplay camera")
		if "--capture" in OS.get_cmdline_user_args():
			for frame: int in 4: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("heavy-gameplay.png")) == OK,
				"Native enlarged robot and original arena capture saved")
	rig.free()
	bot.free()
	arena.free()

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	var registry := ContentRegistry.new()
	check_geometry(registry)
	check_effects()
	await check_preview(registry)
	await check_runtime(registry)
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("HEAVY VISUAL SCALE PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
