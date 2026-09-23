extends SceneTree
## Native moving-camera/belt evidence for #66; ATLAS_PANEL_CAPTURE selects output.
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280, 960)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.msaa_3d = Viewport.MSAA_4X
	var stage := Node3D.new()
	root.add_child(stage)
	var visual := AtlasVisual.new()
	stage.add_child(visual)
	var registry := ContentRegistry.new()
	var draft := registry.atlas()
	visual.assemble(draft, registry.validate(draft).stats.size)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16,0.18,0.20)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.75
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 1.5
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.near = 0.1
	camera.far = 100
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.1
	stage.add_child(camera)
	camera.current = true
	var output := OS.get_environment("ATLAS_PANEL_CAPTURE")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://exports/atlas-hood-review")
	DirAccess.make_dir_recursive_absolute(output)
	for frame: int in 24:
		var target := Vector3(0.94,0.4,0.985)*3.0
		camera.position = target + Vector3(-0.6 + frame*0.007,1.2,2.0)*3.0
		camera.look_at(target)
		visual.advance_drive(0.001,0.001)
		for wait_frame: int in 2: await process_frame
		await RenderingServer.frame_post_draw
		var error := get_root().get_texture().get_image().save_png(output.path_join("rear-%02d.png" % frame))
		if error != OK:
			push_error("Could not save hood review frame")
			quit(1)
			return
	print("ATLAS PANEL CAPTURE PASS")
	quit()
