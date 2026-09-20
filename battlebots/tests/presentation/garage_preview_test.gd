extends Node
## Independent garage renderer acceptance; no profile mutation or network/physics fixture.
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _ready() -> void:
	call_deferred("run")

func meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		if child is MeshInstance3D: result.append(child)
		result.append_array(meshes(child))
	return result

func colors(node: Node) -> Array[String]:
	var result: Array[String] = []
	for mesh: MeshInstance3D in meshes(node):
		var material := mesh.get_active_material(0)
		if material is StandardMaterial3D:
			result.append(material.albedo_color.to_html())
	result.sort()
	return result

func check_cosmetic_only(node: Node) -> void:
	check(not node is CollisionObject3D, "Preview must not contain physics bodies or areas: " + str(node.get_path()))
	for child: Node in node.get_children(): check_cosmetic_only(child)

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	var registry := ContentRegistry.new()
	var preview := GarageBotPreview.new()
	var main_host := Control.new()
	main_host.position = Vector2(80, 80)
	main_host.size = Vector2(720, 540)
	add_child(main_host)
	preview.show_loadout(registry.starter())
	main_host.add_child(preview)
	check(preview.model != null, "Draft supplied before ready renders on the first frame")
	await get_tree().process_frame
	var original := registry.starter()
	var detached := original.duplicate(true)
	preview.show_loadout(original)
	check(original == detached, "Rendering preserves the caller's full draft")
	check(preview.model != null and preview.weapon_visual != null, "Starter assembles model and weapon")
	check(preview.viewport.own_world_3d, "Preview owns an isolated 3D world")
	check(preview.viewport.find_world_3d() != get_viewport().find_world_3d(), "Preview does not share the game's world")
	check(preview.camera.current, "Preview has a current camera")
	for chassis: String in ["compact", "balanced", "wide"]:
		for weapon: String in ["vertical_spinner", "horizontal_spinner", "lifter", "hammer", "saw"]:
			var draft := registry.duelist()
			draft.parts.chassis = chassis
			draft.parts.weapon = weapon
			var previous: Node3D = preview.model
			preview.show_loadout(draft)
			await get_tree().process_frame
			check(not is_instance_valid(previous), "Replacing a draft frees the previous model")
			check(preview.model != null, "Assembles legal " + chassis + "/" + weapon)
			if preview.model == null: continue
			check(preview.weapon_visual.kind == weapon, "Preview matches selected weapon " + weapon)
			check(preview.weapon_visual.mechanism.get_child_count() > 0, "Weapon has visible geometry " + weapon)
			var expected: Array = registry.parts[chassis].size
			var expected_size := Vector3(expected[0], expected[1], expected[2])
			var found := false
			for mesh: MeshInstance3D in meshes(preview.model):
				if mesh.mesh is BoxMesh and mesh.mesh.size.is_equal_approx(expected_size): found = true
			check(found, "Chassis uses catalogue dimensions for " + chassis)
			check_cosmetic_only(preview.model)
	var prior_colors: Array[String] = []
	for paint: String in ["cyan", "orange", "white", "red"]:
		var draft := registry.starter()
		draft.cosmetics.paint = paint
		preview.show_loadout(draft)
		var current := colors(preview.model)
		check(not current.is_empty() and current != prior_colors, "Paint visibly changes materials: " + paint)
		prior_colors = current
	preview.reset_view()
	var base_yaw: float = preview.yaw
	var base_pitch: float = preview.pitch
	var base_distance: float = preview.distance
	preview.rotate_view(Vector2(120, 60))
	check(not is_equal_approx(base_yaw, preview.yaw), "Orbit changes viewing yaw")
	preview.rotate_view(Vector2(0, 100000))
	check(preview.pitch >= -0.1501 and preview.pitch <= 1.1001, "Positive orbit pitch is bounded")
	preview.rotate_view(Vector2(0, -100000))
	check(preview.pitch >= -0.1501 and preview.pitch <= 1.1001, "Negative orbit pitch is bounded")
	preview.zoom_view(100000)
	check(preview.distance >= 3.0 and preview.distance <= 9.0, "Positive zoom stays in range")
	preview.zoom_view(-100000)
	check(preview.distance >= 3.0 and preview.distance <= 9.0, "Negative zoom stays in range")
	preview.reset_view()
	check(is_equal_approx(preview.yaw, base_yaw) and is_equal_approx(preview.pitch, base_pitch) and is_equal_approx(preview.distance, base_distance), "Reset restores the initial view")
	check(original == detached, "Camera interactions do not edit the draft")
	var broken := registry.starter()
	broken.parts.weapon = "unrecognized-weapon"
	preview.show_loadout(broken)
	check(preview.model == null and not preview.status.text.is_empty(), "Malformed draft clears stale geometry and explains failure")
	var overweight := registry.starter(true)
	overweight.parts.weapon = "horizontal_spinner"
	overweight.parts.armor = "heavy"
	overweight.parts.utility = "battery_pack"
	preview.show_loadout(overweight)
	check(preview.model == null and not preview.status.text.is_empty(), "Overweight draft is explicitly invalid, without stale geometry")
	preview.show_loadout({})
	check(preview.model == null, "Missing draft remains empty safely")
	preview.show_loadout(original)
	check(preview.model != null, "Valid draft recovers after invalid preview")
	var other := GarageBotPreview.new()
	var other_host := Control.new()
	other_host.position = Vector2(830, 100)
	other_host.size = Vector2(360, 420)
	add_child(other_host)
	other_host.add_child(other)
	other.show_loadout(registry.duelist())
	check(other.viewport.find_world_3d() != preview.viewport.find_world_3d(), "Two previews have separate worlds")
	var second_yaw: float = other.yaw
	preview.rotate_view(Vector2(40, 0))
	check(is_equal_approx(other.yaw, second_yaw), "Orbit is local to its preview")
	check_cosmetic_only(preview)
	for _frame in 4: await get_tree().process_frame
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("battlebots-garage-preview.png"))
	other.free()
	preview.free()
	for _frame in 2: await get_tree().process_frame
	if failures.is_empty(): print("GARAGE PREVIEW PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)


