extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var scene := Node3D.new()
	scene.name = "BakedServiceBay"
	root.add_child(scene)
	var source := load("res://assets/models/lunar/service_bay.glb").instantiate() as Node3D
	scene.add_child(source)
	var bay := Node3D.new()
	bay.name = "service_bay"
	scene.remove_child(source)
	scene.add_child(bay)
	bay.owner = scene
	for original: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		var mesh := MeshInstance3D.new()
		mesh.name = original.name
		mesh.transform = original.transform
		mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var copy := original.mesh.duplicate() as ArrayMesh
		var error := copy.lightmap_unwrap(mesh.transform,.12)
		if error!=OK: push_error("Unwrap failed "+str(error))
		mesh.mesh = copy
		bay.add_child(mesh)
		mesh.owner = scene
	source.free()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28,-38,0)
	sun.light_energy = 1.25
	sun.light_color = Color("ffebd5")
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	scene.add_child(sun)
	sun.owner = scene
	var gi := LightmapGI.new()
	gi.name = "IndirectLight"
	gi.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	gi.environment_custom_color = Color(.15,.2,.28)
	gi.environment_custom_energy = .15
	gi.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	gi.bounces = 3
	gi.max_texture_size = 2048
	scene.add_child(gi)
	gi.owner = scene
	gi.light_data = LightmapGIData.new()
	ResourceSaver.save(gi.light_data,"res://assets/models/lunar/bay_indirect.lmbake")
	gi.light_data.take_over_path("res://assets/models/lunar/bay_indirect.lmbake")
	var packed := PackedScene.new()
	packed.pack(scene)
	ResourceSaver.save(packed,"res://assets/models/lunar/baked_service_bay.tscn")
	print("BAKE SCENE READY")
	quit()
