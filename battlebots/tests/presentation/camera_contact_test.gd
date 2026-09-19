extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
func body(parent: Node3D, at: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var result := StaticBody3D.new()
	result.position = at
	result.collision_layer = layer
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	result.add_child(collision)
	parent.add_child(result)
	return result
func sync() -> void:
	await physics_frame
	await physics_frame
func run() -> void:
	var sandbox: Node3D = load("res://scenes/dev/b_presentation.tscn").instantiate()
	sandbox.get_node("Preview").settings_path = ""
	root.add_child(sandbox)
	await sync()
	var source: BotSource = sandbox.get_node("Bot")
	source.set_physics_process(false)
	source.position = Vector3(0, 0.3, 0)
	var preview: Node3D = sandbox.get_node("Preview")
	preview.set_physics_process(false)
	var rig: BotOrbitCamera = preview.rig
	rig.set_physics_process(false)
	var anchor := source.camera_anchor().global_position
	# Deterministic stationary Jolt collider reproduces a lifted opponent across
	# the real camera anchor; no simulated collision/query results are injected.
	var opponent := body(sandbox, anchor, Vector3(2.8, 1.0, 2.8), BaselineConfig.BOT_LAYER)
	await sync()
	rig.update_camera(1.0)
	check(rig.global_position.y > anchor.y + 0.5, "Camera pivot rises clear of overlapping opponent")
	check(rig.actual_distance > 4.0, "Contact camera retains readable third-person distance")
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = rig.camera_radius
	probe.shape = sphere
	probe.collision_mask = BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER
	probe.transform = Transform3D(Basis.IDENTITY, rig.camera.global_position)
	check(sandbox.get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty(), "Camera ends outside all bot/world collision")
	var ceiling := body(sandbox, anchor + Vector3.UP * 0.65, Vector3(8, 0.2, 8), BaselineConfig.WORLD_LAYER)
	await sync()
	rig.update_camera(1.0)
	check(is_equal_approx(rig.global_position.y, anchor.y) and is_zero_approx(rig.actual_distance), "Ceiling prevents escape through world geometry")
	ceiling.queue_free()
	opponent.queue_free()
	await sync()
	rig.update_camera(1.0)
	check(is_equal_approx(rig.global_position.y, anchor.y) and rig.actual_distance > 4.0, "Clear contact restores normal follow anchor")
	sandbox.queue_free()
	await process_frame
	print("CAMERA CONTACT PASS" if failures == 0 else "CAMERA CONTACT FAIL")
	quit(0 if failures == 0 else 1)
