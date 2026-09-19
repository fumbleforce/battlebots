extends SceneTree

func _initialize() -> void:
	var scene := load("res://assets/models/flamebot/flamebot_07.glb") as PackedScene
	assert(scene != null, "GLB must import as a scene")
	var model := scene.instantiate()
	root.add_child(model)
	await process_frame
	for part in ["Chassis", "TurretYaw", "MinigunSpin", "WheelLeftFront", "WheelLeftRear", "WheelRightFront", "WheelRightRear"]:
		assert(model.find_child(part, true, false) != null, "Missing moving assembly: " + part)
	var bounds := AABB()
	var mesh_count := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
		mesh_count += 1
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface)
			assert(mat != null, "Every surface requires an imported material")
	assert(mesh_count == 7, "Expected seven independently movable meshes")
	assert(bounds.size.y > 1.8 and bounds.size.y < 2.2, "Godot must be Y up at meter scale")
	assert(bounds.position.z < -1.2, "Wedge must point toward Godot -Z")
	assert(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Art must not introduce physics")
	assert(model.find_children("*", "Camera3D", true, false).is_empty(), "Studio must not be exported")
	print("FLAMEBOT CHECK PASSED: 7 meshes, movable pivots, materials, Y-up/-Z-forward, no physics or studio. Bounds: ", bounds)
	model.queue_free()
	quit()
