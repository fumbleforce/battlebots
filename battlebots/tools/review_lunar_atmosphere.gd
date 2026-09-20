extends SceneTree
## Native art review. Does not change game cameras or saved settings.
## Capture each revision in a fresh process: changing render layers after light
## pairing triggers Godot 4.7 issue #121989 when the scene is removed.
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
	var effects := world.arena.get_node("FoundryVisuals/EnvironmentArt/LunarEffects")
	# Fix the vent/beacon phase for review; particle positions still evolve.
	effects.set_process(false)
	effects._process(2.0)
	var output := "res://exports/lunar-backdrop/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+".gdignore",FileAccess.WRITE).close()
	for shot: Array in [["arena",Vector3(7,3,14),Vector3(-2,5,-25)], ["outpost",Vector3(-8,5,-18),Vector3(0,6,-29)], ["reverse",Vector3(-12,4,-12),Vector3(3,3,18)]]:
		camera.position = shot[1]
		camera.look_at(shot[2])
		for frame: int in range(90):
			await process_frame
			# Explicit draws also finish if Windows occludes/minimizes the review.
			RenderingServer.force_draw(false)
		var image := root.get_texture().get_image()
		assert(image.get_size() == Vector2i(2560,1440))
		assert(image.save_png(output+"after-"+shot[0]+".png") == OK)
		print("LUNAR REVIEW CAPTURE ",shot[0])
	(world.arena.get_node("WorldEnvironment").environment as Environment).volumetric_fog_enabled = false
	for frame: int in range(5):
		await process_frame
		RenderingServer.force_draw(false)
	world.queue_free()
	for frame: int in range(10): await process_frame
	print("LUNAR ATMOSPHERE REVIEW COMPLETE")
	quit()
