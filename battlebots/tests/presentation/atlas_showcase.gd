extends Node3D
## Actual imported asset and production-arena review. No gameplay acceptance claim.
## Run natively; optional ATLAS_CAPTURE_DIR redirects all PNGs and render metadata.
const MODEL_PATH := "res://assets/models/atlas_runtime/atlas_mx.glb"
const RESOLUTION := Vector2i(1800, 1350)
var session: MvpSession
var camera: Camera3D
var sequence := 0
var output := ""
var captures: Array[String] = []
var report: Dictionary = {}

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Atlas review requires the native Forward+ renderer, without --headless.")
		get_tree().quit(1)
		return
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().size = RESOLUTION
	get_viewport().msaa_3d = Viewport.MSAA_4X
	output = OS.get_environment("ATLAS_CAPTURE_DIR")
	if output.is_empty(): output = ProjectSettings.globalize_path("res://exports/atlas-review")
	var directory_error := DirAccess.make_dir_recursive_absolute(output)
	if directory_error != OK:
		push_error("Cannot create Atlas review directory: " + output)
		get_tree().quit(1)
		return
	# Review images are generated evidence, not textures to import into the game.
	var ignore_file := FileAccess.open(output.path_join(".gdignore"), FileAccess.WRITE)
	if ignore_file != null: ignore_file.store_string("")
	camera = Camera3D.new()
	camera.near = 0.02
	camera.far = 180.0
	add_child(camera)
	camera.current = true
	run.call_deferred()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(session) or session.local_source() == null: return
	var command := BotCommand.new()
	command.sequence = sequence
	command.brake = true
	sequence += 1
	session.submit_local(command)

func _softbox_sky() -> Sky:
	# Original linear HDR panorama: broad white softboxes give honest bevel and
	# roughness readback on the imported PBR materials, without touching materials.
	var panorama := Image.create(512, 256, false, Image.FORMAT_RGBAF)
	var cards: Array[Dictionary] = [
		{"direction": Vector3(-0.7, 0.85, -0.55).normalized(), "radius": 0.23, "energy": 1.2},
		{"direction": Vector3(0.8, 0.48, 0.25).normalized(), "radius": 0.13, "energy": 1.0},
		{"direction": Vector3(-0.2, 0.3, 0.9).normalized(), "radius": 0.10, "energy": 0.8},
	]
	for y: int in 256:
		var latitude := PI * float(y) / 255.0
		for x: int in 512:
			var longitude := TAU * float(x) / 511.0
			var direction := Vector3(sin(latitude) * sin(longitude), cos(latitude), -sin(latitude) * cos(longitude))
			var value := lerpf(0.04, 0.20, clampf(direction.y * 0.5 + 0.5, 0.0, 1.0))
			for card: Dictionary in cards:
				var distance: float = 1.0 - direction.dot(card.direction)
				value += (1.0 - smoothstep(card.radius * 0.75, card.radius, distance)) * float(card.energy)
			panorama.set_pixel(x, y, Color(value, value * 0.98, value * 0.95, 1.0))
	var material := PanoramaSkyMaterial.new()
	material.panorama = ImageTexture.create_from_image(panorama)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_512
	sky.sky_material = material
	return sky

func _studio() -> Node3D:
	var stage := Node3D.new()
	stage.name = "AtlasReviewStudio"
	add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.79, 0.80, 0.81)
	environment.sky = _softbox_sky()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.60
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_radius = 0.14
	environment.ssao_intensity = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -32, 0)
	key.light_color = Color(1.0, 0.96, 0.9)
	key.light_energy = 1.05
	key.shadow_enabled = true
	key.light_angular_distance = 6.0
	key.directional_shadow_max_distance = 22.0
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 142, 0)
	fill.light_color = Color(0.87, 0.93, 1.0)
	fill.light_energy = 0.22
	stage.add_child(fill)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200, 200)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.59, 0.61, 0.64)
	floor_material.roughness = 0.78
	floor_mesh.material = floor_material
	var floor_visual := MeshInstance3D.new()
	floor_visual.mesh = floor_mesh
	floor_visual.position.y = -0.004
	stage.add_child(floor_visual)
	return stage

func _model_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	var triangle_count := 0
	var visible_mesh_count := 0
	var materials: Dictionary = {}
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		visible_mesh_count += 1
		var world_bounds: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(world_bounds) if started else world_bounds
		started = true
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangle_count += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var material := mesh.get_active_material(surface)
			if material != null: materials[material.get_instance_id()] = material.resource_name
	report["asset"] = {"path": MODEL_PATH, "visible_mesh_instances": visible_mesh_count, "triangles": triangle_count,
		"materials": materials.values(), "bounds_min": str(bounds.position), "bounds_size": str(bounds.size)}
	return bounds

func _frame(bounds: AABB, offset: Vector3, up := Vector3.UP) -> void:
	var center := bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	camera.position = center + offset * extent
	camera.look_at(center, up)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var projected := AABB()
	var first := true
	for corner: int in 8:
		var point: Vector3 = camera.global_transform.affine_inverse() * bounds.get_endpoint(corner)
		if first:
			projected = AABB(point, Vector3.ZERO)
			first = false
		else: projected = projected.expand(point)
	var aspect := float(RESOLUTION.x) / float(RESOLUTION.y)
	camera.size = maxf(projected.size.y, projected.size.x / aspect) * 1.22

func _capture(label: String) -> bool:
	for frame: int in 45: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var filename := output.path_join(label + ".png")
	var error := get_viewport().get_texture().get_image().save_png(filename)
	if error != OK:
		push_error("Cannot save Atlas native capture: " + filename)
		return false
	captures.append(filename)
	print("ATLAS NATIVE CAPTURE ", filename)
	return true

func _measure_foundry() -> void:
	# Bounded, uncapped frame intervals for this static review viewpoint only.
	# It includes the ordinary practice world, not just an isolated chassis.
	var old_cap := Engine.max_fps
	var old_vsync := DisplayServer.window_get_vsync_mode()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for frame: int in 40: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var intervals: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame: int in 120:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		intervals.append(float(now - previous) / 1000.0)
		previous = now
	intervals.sort()
	var viewport := get_viewport()
	report["foundry_frame_sample"] = {"samples": intervals.size(), "warmup_frames": 40,
		"p50_frame_ms": intervals[60], "p95_frame_ms": intervals[114], "max_frame_ms": intervals.back(),
		"frame_cap": 0, "vsync": "disabled", "resolution": str(RESOLUTION),
		"visible_objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME),
		"visible_draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"visible_primitives": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"shadow_draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"engine_video_memory_mib": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"scope": "Static native Foundry review camera, ordinary Atlas practice plus three NPC bots, 4x MSAA. Frame intervals include engine/render/presentation work. Player brakes with no commanded attacks; NPC behavior remains active. No HUD, networking, or long soak; not a release performance certification."}
	Engine.max_fps = old_cap
	DisplayServer.window_set_vsync_mode(old_vsync)
	print("ATLAS FOUNDRY SAMPLE ", JSON.stringify(report.foundry_frame_sample))

func _capture_garage() -> bool:
	# The live menu/profile supplies the actual built-in preset. Selection changes
	# only in this process; no save/reload method writes the player's saved builds.
	var profile := get_node("/root/PlayerProfile")
	var router := get_node("/root/MenuRouter")
	var previous_selection: int = profile.active_bot
	var previous_router_selection: int = router.match_setup.bot
	var selected := -1
	for index: int in mini(profile.PRESET_COUNT, profile.loadouts.size()):
		if profile.loadouts[index].parts.chassis == "atlas_mx":
			selected = index
			break
	if selected < 0:
		push_error("Atlas built-in garage preset is missing.")
		return false
	profile.active_bot = selected
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var garage := load("res://ui/menus/screens/garage.tscn").instantiate() as Control
	add_child(garage)
	for frame: int in 8: await get_tree().process_frame
	var preview := garage.get("build_preview") as GarageBotPreview
	var clipped_meshes: Array[String] = []
	var viewport_extent := Vector2(preview.viewport.size)
	for mesh: MeshInstance3D in preview.model.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree(): continue
		var bounds := mesh.get_aabb()
		for corner: int in 8:
			var world_point: Vector3 = mesh.global_transform * bounds.get_endpoint(corner)
			var screen_point := preview.camera.unproject_position(world_point)
			if preview.camera.is_position_behind(world_point) or screen_point.x < 0.0 or screen_point.y < 0.0 or screen_point.x > viewport_extent.x or screen_point.y > viewport_extent.y:
				clipped_meshes.append(str(mesh.name))
				break
	var okay := await _capture("atlas-native-garage")
	report["garage"] = {"resolution": "1920x1080", "preset_index": selected,
		"preview_size": str(preview.viewport.size), "clipped_mesh_bounds": clipped_meshes,
		"scope": "Actual garage scene, default Atlas preset and default camera. In-memory selection only; saved loadouts untouched."}
	garage.queue_free()
	for frame: int in 3: await get_tree().process_frame
	profile.active_bot = previous_selection
	router.match_setup.bot = previous_router_selection
	return okay

func run() -> void:
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_error("Atlas GLB must be built and imported before the showcase runs.")
		get_tree().quit(1)
		return
	var stage := _studio()
	get_viewport().use_taa = true
	var model := scene.instantiate() as Node3D
	stage.add_child(model)
	# The GLB ships all optional modules for assembly. A bare base must not show
	# mutually exclusive armor/exhaust upgrades merely because they are exported.
	for label: String in ["ArmorSideReference", "ArmorSideHeavy", "ArmorTop", "ArmorFront", "ArmorRear",
		"ExhaustSmall", "ExhaustMedium", "ExhaustLarge"]:
		var optional := model.find_child(label, true, false) as Node3D
		if optional != null: optional.hide()
	var bounds := _model_bounds(model)
	model.position.y = -bounds.position.y
	bounds.position.y = 0.0
	var okay := true
	for shot: Array in [["atlas-native-hero", Vector3(1.45, 1.05, -1.9), Vector3.UP],
		["atlas-native-rear", Vector3(-1.45, 0.95, 1.9), Vector3.UP],
		["atlas-native-side", Vector3(2.5, 0.22, 0), Vector3.UP],
		["atlas-native-top", Vector3(0, 3, 0), Vector3.FORWARD]]:
		_frame(bounds, shot[1], shot[2])
		okay = await _capture(shot[0]) and okay
	# Low front-quarter crop keeps the front docking cap, its fender seat and
	# the adjacent side casting in one actual rendered view for mechanical review.
	var detail_bounds := AABB(Vector3(0.60, 0.20, -1.27), Vector3(0.67, 1.02, 1.73))
	_frame(detail_bounds, Vector3(2.3, 0.7, -2.8))
	okay = await _capture("atlas-native-mount-detail") and okay
	# Orthographic side close-up exposes all three lower rollers and their gap to
	# the slotted casting. Studio grounding is already derived from mesh bounds.
	var side_detail_bounds := AABB(Vector3(0.72, 0.03, -0.63), Vector3(0.55, 0.88, 1.26))
	_frame(side_detail_bounds, Vector3.RIGHT * 2.5)
	okay = await _capture("atlas-native-side-detail") and okay
	stage.queue_free()
	for frame: int in 4: await get_tree().process_frame
	get_viewport().use_taa = false
	if "--studio-only" not in OS.get_cmdline_user_args():
		session = MvpSession.new()
		add_child(session)
		var draft: Dictionary = session.registry.atlas()
		var practice_error := session.practice(draft, "foundry")
		if practice_error != OK:
			push_error("Atlas production practice failed: " + error_string(practice_error))
			get_tree().quit(1)
			return
		for frame: int in 150: await get_tree().process_frame
		var bot := session.local_source() as MvpBot
		if bot == null:
			push_error("Atlas production practice did not provide a local bot.")
			get_tree().quit(1)
			return
		var center: Vector3 = bot.body.global_position
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 43.0
		camera.position = center + Vector3(12.5, 10.0, -16.5)
		camera.look_at(center + Vector3(0, 0.4, -0.7))
		await _measure_foundry()
		okay = await _capture("atlas-native-foundry") and okay
		session.leave()
		session.queue_free()
		for frame: int in 5: await get_tree().process_frame
		okay = await _capture_garage() and okay
	report.merge({"engine": Engine.get_version_info().string,
		"adapter": RenderingServer.get_video_adapter_name(), "resolution": str(RESOLUTION),
		"captures": captures, "scope": "Actual imported GLB studio views and optionally unmodified production Foundry practice. Visual review only; user approval pending."})
	var report_file := FileAccess.open(output.path_join("atlas-native-review.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("Cannot write Atlas review metadata.")
		okay = false
	else: report_file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ATLAS NATIVE REVIEW COMPLETE" if okay else "ATLAS NATIVE REVIEW FAILED")
	get_tree().quit(0 if okay else 1)
