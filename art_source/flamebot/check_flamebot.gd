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
	var high_resolution_armor_found := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
		mesh_count += 1
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface)
			assert(mat != null, "Every surface requires an imported material")
			if mat.resource_name.begins_with("Oxide red") or mat.resource_name.begins_with("Ochre safety"):
				assert(mat is StandardMaterial3D, "Paint must use Godot PBR material")
				assert(mat.normal_enabled and mat.normal_texture != null, "Grit normal maps must survive GLB import")
				assert(mat.roughness_texture != null, "Matte roughness map must survive GLB import")
				assert(mat.albedo_texture != null and mat.albedo_texture.get_width() >= 2048, "Paint color detail must survive at 2K or greater")
				assert(mat.normal_texture.get_width() == 2048, "Paint relief must retain 2K resolution")
				if mat.resource_name.contains("worn armor edges"):
					assert(mat.albedo_texture.get_width() == 4096, "Main armor must retain 4K color detail")
					high_resolution_armor_found = true
	assert(high_resolution_armor_found, "Main armor material must survive export and import")
	assert(mesh_count == 7, "Expected seven independently movable meshes")
	assert(bounds.size.y > 1.8 and bounds.size.y < 2.2, "Godot must be Y up at meter scale")
	assert(bounds.position.z < -1.2, "Wedge must point toward Godot -Z")
	var front := model.find_child("WheelRightFront", true, false) as Node3D
	var rear := model.find_child("WheelRightRear", true, false) as Node3D
	assert(front.position.z < rear.position.z, "Front wheels must precede rear wheels along -Z")
	assert(absf(front.position.x - 0.93) < 0.001, "Widened wheel stance must survive export")
	assert(absf(front.position.y - 0.42) < 0.001, "Wheel pivot height must match revised tire radius")
	assert(model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Art must not introduce physics")
	assert(model.find_children("*", "Camera3D", true, false).is_empty(), "Studio must not be exported")
	print("FLAMEBOT CHECK PASSED: 7 meshes, movable pivots, materials, Y-up/-Z-forward, no physics or studio. Bounds: ", bounds)
	model.queue_free()
	quit()
