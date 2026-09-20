extends SceneTree
## Native before/after art review. Does not change game cameras or saved settings.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(2560,1440)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	root.size = Vector2i(2560,1440)
	root.msaa_3d = Viewport.MSAA_2X
	var world := AuthorityWorld.new()
	world.arena_id = "moon"
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	camera.far = 150
	camera.fov = 68
	var env: Environment = world.arena.get_node("WorldEnvironment").environment
	var sun: DirectionalLight3D = world.arena.get_node("Sun")
	var art := world.arena.get_node("FoundryVisuals/EnvironmentArt")
	var effects := art.get_node("LunarEffects")
	# Hold the same vent/beacon phase in both views so illumination is comparable.
	effects.set_process(false)
	effects._process(2.0)
	var production_environment := env.duplicate() as Environment
	var production_sun := [sun.rotation_degrees, sun.light_color, sun.light_energy, sun.light_volumetric_fog_energy]
	var output := "res://exports/lunar-atmosphere/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+".gdignore",FileAccess.WRITE).close()
	for variant: String in ["before", "after"]:
		if variant == "before":
			env.ambient_light_color = Color("adbace")
			env.ambient_light_energy = .15
			sun.rotation_degrees = Vector3(-28,-38,0)
			sun.light_color = Color("ffebd5")
			sun.light_energy = 1.25
			sun.light_volumetric_fog_energy = .15
		else:
			world.arena.get_node("WorldEnvironment").environment = production_environment
			sun.rotation_degrees = production_sun[0]
			sun.light_color = production_sun[1]
			sun.light_energy = production_sun[2]
			sun.light_volumetric_fog_energy = production_sun[3]
		for child: Node in art.get_children():
			if child is SpotLight3D:
				child.light_color = Color("d3e8ff") if variant == "before" else Color("ffe1b6")
		for shot: Array in [["arena",Vector3(7,3,14),Vector3(-2,5,-25)], ["outpost",Vector3(-8,5,-18),Vector3(0,6,-29)], ["reverse",Vector3(-12,4,-12),Vector3(3,3,18)]]:
			camera.position = shot[1]
			camera.look_at(shot[2])
			for frame: int in range(90):
				await process_frame
				await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			assert(image.get_size() == Vector2i(2560,1440))
			assert(image.save_png(output+variant+"-"+shot[0]+".png") == OK)
	production_environment.volumetric_fog_enabled = false
	for frame: int in range(5):
		await process_frame
		await RenderingServer.frame_post_draw
	world.queue_free()
	for frame: int in range(10): await process_frame
	print("LUNAR ATMOSPHERE REVIEW COMPLETE")
	quit()
