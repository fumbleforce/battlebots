extends Node3D
## Independent cosmetic lifecycle contract; no authority or contact simulation is needed.
const EFFECT_PATH := "res://scripts/presentation/bot_destruction_visual.gd"
var failures: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func view(destroyed := false, core := 1.0) -> BotView:
	var result := BotView.new()
	result.entity_id = 7
	result.pose = Transform3D(Basis.IDENTITY, Vector3(7, 2, -5))
	result.eliminated = destroyed
	result.core_fraction = core
	return result

func fixture() -> Dictionary:
	var visual := Node3D.new()
	visual.position = Vector3(7, 2, -5)
	visual.rotation = Vector3(0.3, 0.8, PI)
	visual.scale = Vector3(1.4, 0.8, 1.2)
	add_child(visual)
	var intact := MeshInstance3D.new()
	intact.mesh = BoxMesh.new()
	var original := StandardMaterial3D.new()
	original.albedo_color = Color(0.2, 0.7, 0.9)
	intact.material_overlay = original
	visual.add_child(intact)
	var hidden := MeshInstance3D.new()
	hidden.mesh = BoxMesh.new()
	visual.add_child(hidden)
	hidden.hide()
	var component := MeshInstance3D.new()
	component.mesh = BoxMesh.new()
	component.material_overlay = StandardMaterial3D.new()
	visual.add_child(component)
	var effect: Node3D = load(EFFECT_PATH).new()
	visual.add_child(effect)
	effect.set_process(false)
	effect.configure(visual, Vector3(1.7, 0.6, 2.6), [component])
	return {"visual":visual, "intact":intact, "hidden":hidden,
		"component":component, "original":original, "effect":effect}

func no_collision(root: Node) -> void:
	check(root.find_children("*", "CollisionObject3D", true, false).is_empty(), "Decoration adds no collision objects")
	check(root.find_children("*", "CollisionShape3D", true, false).is_empty(), "Decoration adds no collision shapes")

func run() -> void:
	var first := fixture()
	var effect: Node3D = first.effect
	var component_overlay: Material = first.component.material_overlay
	var dead := view(true, 0.0)
	effect.observe(dead)
	check(effect.burst_count == 0 and not effect.active, "First destroyed baseline is silent")
	check(first.intact.material_overlay != first.original, "Existing wreck receives scorch without replaying its destruction")
	check(first.component.material_overlay == component_overlay, "Scorch preserves component-owned damage overlay")
	check(not first.hidden.visible, "Existing hidden baseline geometry stays hidden")
	effect.observe(view())
	check(first.intact.material_overlay == first.original, "Healthy state restores caller material overlay")
	effect.observe(view(true, 0.5))
	check(effect.burst_count == 0 and not effect.active, "Elimination with surviving core does not invent physical destruction")
	effect.observe(view())
	var source_pose := dead.pose
	effect.observe(dead)
	check(effect.burst_count == 1 and effect.active, "Observed healthy-to-zero-core transition explodes once")
	check(dead.pose == source_pose and dead.core_fraction == 0.0 and dead.eliminated, "Presentation leaves its detached input unchanged")
	for repeated: int in 8: effect.observe(dead)
	check(effect.burst_count == 1, "Repeated terminal snapshots cannot replay explosion")
	check(is_instance_valid(effect.burst_root), "Destruction creates world-space burst root")
	if is_instance_valid(effect.burst_root):
		check(effect.burst_root.top_level, "Burst ignores inherited bot rotation and scale")
		var origin: Transform3D = effect.burst_root.global_transform
		first.visual.position += Vector3(4, -1, 3)
		first.visual.rotation = Vector3(-0.5, 1.2, 0.7)
		first.visual.scale = Vector3(0.5, 2.0, 1.8)
		check(effect.burst_root.global_transform.is_equal_approx(origin), "Moving a wreck does not drag existing explosion")
	no_collision(first.visual)
	effect._process(5.0)
	check(not effect.active, "Transient explosion expires within 4.5 seconds")
	effect.observe(dead)
	check(effect.burst_count == 1 and not effect.active, "Expired wreck cannot restart its explosion")
	effect.observe(view())
	effect.observe(dead)
	check(effect.burst_count == 2 and effect.active, "Healthy next round rearms destruction")
	effect.clear_effects()
	check(not effect.active, "Explicit clear ends transient effects immediately")
	effect.observe(dead)
	check(effect.burst_count == 2, "Clearing transients retains terminal observation")
	effect.reset_observation()
	check(not effect.active and first.intact.material_overlay == first.original, "Reset clears burst and restores original appearance")
	effect.observe(dead)
	check(effect.burst_count == 2 and not effect.active, "Fresh terminal baseline after reset remains silent")
	effect.observe(null)
	check(first.intact.material_overlay == first.original and not effect.active, "Missing observation clears stale presentation")
	first.visual.free()

	var fixtures: Array[Dictionary] = []
	for index: int in 5:
		var record := fixture()
		fixtures.append(record)
		record.effect.observe(view())
		record.effect.observe(dead)
		var active_count := 0
		for current: Dictionary in fixtures: active_count += int(current.effect.active)
		check(active_count <= 2, "Simultaneous destruction is bounded tree-wide")
	var last: Dictionary = fixtures.back()
	var independent: Dictionary = fixtures[fixtures.size() - 2]
	check(last.intact.material_overlay != independent.intact.material_overlay, "Bots own separate scorch materials")
	last.effect.observe(view())
	check(independent.intact.material_overlay != independent.original, "Repairing one bot preserves another wreck")
	for record: Dictionary in fixtures:
		no_collision(record.visual)
		record.visual.free()
	var final_fixture := fixture()
	final_fixture.effect.observe(view())
	final_fixture.effect.observe(dead)
	check(final_fixture.effect.active, "Freeing old bots releases the shared burst budget")
	var orphan: Node = final_fixture.effect.burst_root
	final_fixture.visual.free()
	check(not is_instance_valid(orphan), "Freeing the bot removes its world-space burst")
	check_combined_debris_budget()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("DESTRUCTION VISUAL PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

func check_combined_debris_budget() -> void:
	var impact := CombatImpactVisual.new()
	add_child(impact)
	impact.set_process(false)
	for hit: int in 10: impact.spawn_impact(Vector3.ZERO, Vector3.UP, "hammer", 40.0)
	check(impact.fragment_count() == 20, "Ordinary contacts can fill the existing twenty-fragment budget")
	var first := fixture()
	first.effect.observe(view())
	first.effect.observe(view(true, 0.0))
	check(impact.fragment_count() <= 12, "First destruction reserves eight panels within the client debris budget")
	var second := fixture()
	second.effect.observe(view())
	second.effect.observe(view(true, 0.0))
	check(impact.fragment_count() <= 4, "Two destructions leave at most four ordinary fragments")
	for hit: int in 10: impact.spawn_impact(Vector3.ZERO, Vector3.UP, "hammer", 40.0)
	check(impact.fragment_count() <= 4, "Continuing contacts cannot exceed the combined debris budget")
	first.effect._process(5.0)
	second.effect._process(5.0)
	for hit: int in 10: impact.spawn_impact(Vector3.ZERO, Vector3.UP, "hammer", 40.0)
	check(impact.fragment_count() == 20, "Expired explosions return fragment capacity to ordinary contacts")
	first.visual.free()
	second.visual.free()
	impact.free()
