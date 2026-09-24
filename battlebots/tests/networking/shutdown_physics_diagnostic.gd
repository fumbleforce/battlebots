extends SceneTree
## Diagnosis only (#10): step physics (BATTLEBOTS_DIAG_PHYSICS = "frames" for an
## empty world, "body" for a floor plus one falling rigid body), then quit.

func _initialize() -> void:
	if OS.get_environment("BATTLEBOTS_DIAG_PHYSICS") == "body":
		var floor := StaticBody3D.new()
		var floor_shape := CollisionShape3D.new()
		floor_shape.shape = BoxShape3D.new()
		floor_shape.shape.size = Vector3(40, 1, 40)
		floor.add_child(floor_shape)
		root.add_child(floor)
		var body := RigidBody3D.new()
		var body_shape := CollisionShape3D.new()
		body_shape.shape = BoxShape3D.new()
		body.add_child(body_shape)
		body.position = Vector3(0, 3, 0)
		root.add_child(body)
	for index: int in range(60):
		await physics_frame
	print("SHUTDOWN LOAD DONE physics")
	quit()
