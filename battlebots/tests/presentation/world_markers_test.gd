extends SceneTree
## Public detached views only; stand-ins deliberately avoid bot assets and controls.
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func bot(id: int, team: int, origin: Vector3) -> BotView:
	var view := BotView.new()
	view.entity_id = id
	view.team = team
	view.pose.origin = origin
	return view

func box(parent: Node3D, origin: Vector3, extent: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = extent
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = origin
	return mesh

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var badges := BotWorldMarkers.new()
	world.add_child(badges)
	var local := bot(29, 7, Vector3(-2, 0.4, 0))
	var rival := bot(3, 4, Vector3(2, 0.4, 0))
	var views: Array[BotView] = [rival, local]
	badges.render(views, 29, false, true)
	check(badges.markers.size() == 2 and badges.markers[29].text.is_empty() and badges.markers[3].text == "◇ RIVAL", "Only rival receives a floating identity, selected by published local ID rather than ordering")
	check(not badges.markers[29].get_node("Leader").visible and badges.markers[29].get_node("HealthBar").is_visible_in_tree(), "Local floating tag and stem are suppressed while its health bar remains visible")
	var original := badges.markers[3]
	var leader := original.get_node("Leader") as MeshInstance3D
	var stem := leader.mesh as CylinderMesh
	var leader_material := leader.material_override
	check(is_equal_approx(leader.global_position.y - stem.height * 0.5, rival.pose.origin.y + BotWorldMarkers.ANCHOR_HEIGHT), "Leader ends above the chassis")
	rival.pose.origin.z = -2
	badges.render(views, 29, false, true)
	check(badges.markers[3] == original and original.global_position == rival.pose.origin + Vector3.UP * BotWorldMarkers.HEIGHT, "Presentation pose updates existing marker")
	check(leader.mesh == stem and leader.material_override == leader_material, "Pose updates reuse leader resources")
	badges.position = Vector3(9, 2, 4)
	badges.rotation_degrees = Vector3(20,30,10)
	badges.scale = Vector3(2,2,2)
	badges.render(views, 29, false, true)
	check(original.global_position.is_equal_approx(rival.pose.origin + Vector3.UP * BotWorldMarkers.HEIGHT), "Global presentation pose is independent of marker parent transform")
	check(original.global_basis.is_equal_approx(Basis.IDENTITY), "Leader stays world-up with unscaled dimensions beneath a transformed parent")
	badges.transform = Transform3D.IDENTITY
	badges.render(views, 3, false, true)
	check(original.text.is_empty() and not leader.visible and original.get_node("HealthBar").is_visible_in_tree(), "Changing local identity suppresses the new local tag and stem without hiding health")
	check(badges.markers[29].text == "◇ RIVAL" and badges.markers[29].get_node("Leader").visible, "Previous local identity regains rival text and stem")
	badges.render(views, 29, false, true)
	check(original.text == "◇ RIVAL" and leader.visible and badges.markers[29].text.is_empty(), "Returning local identity restores the original classification")
	local.eliminated = true
	badges.render(views, 29, false, true)
	check(badges.markers[29].text.is_empty() and badges.markers[29].get_node("HealthBar").visible, "Local elimination does not recreate a tag or invent missing health")
	local.eliminated = false
	rival.eliminated = true
	badges.render(views, 29, true, false)
	check(original.text == "◇ TARGET / OUT", "Practice and elimination are explicit text")
	for colors: String in BotWorldMarkers.PALETTES:
		badges.apply_accessibility(1.5, colors, true)
		check(original.font_size == 48 and original.outline_modulate == Color.WHITE, "150 percent and high contrast apply")
		check(not original.no_depth_test and original.fixed_size and not original.shaded and original.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "Badges stay readable but depth tested")
		check(not badges.markers[29].get_node("Leader").visible and badges.markers[29].get_node("HealthBar").visible, "Accessibility preserves local tag suppression and health feedback")
	badges.render([rival], 29, false, true)
	check(badges.markers.is_empty(), "Missing local baseline suppresses all classification")
	local.team = -1
	badges.render(views, 29, false, true)
	check(badges.markers.is_empty(), "Unknown local team suppresses classification")
	local.team = 7
	rival.pose.origin.x = NAN
	badges.render(views, 29, false, true)
	check(badges.markers.size() == 1 and badges.markers.has(29), "Invalid presentation pose is removed")
	rival.pose.origin = Vector3(2, 0.4, 0)
	rival.eliminated = false
	badges.render(views, 29, false, false)
	check(badges.markers.is_empty(), "Deferred modes stay unlabelled")
	badges.render([local], 29, false, true)
	check(badges.markers.size() == 1, "Removed opponent leaves no stale badge")
	badges.render([local,rival,bot(10,8,Vector3.ZERO)], 29, false, true)
	check(badges.markers.size() == 1, "Ambiguous multi-opponent data does not invent a duel rival")
	rival.pose.basis = Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
	badges.render(views, 29, false, true)
	check(badges.markers.size() == 1, "Degenerate pose is ignored")
	rival.pose.basis = Basis.IDENTITY
	badges.apply_accessibility(NAN,"unknown",false)
	check(badges.text_scale == 1.0 and badges.palette == "standard", "Invalid accessibility values return to defaults")
	badges.render(views, 29, false, true)
	box(world, Vector3(0,-0.1,0), Vector3(16,0.2,16), Color("283441"))
	box(world, local.pose.origin, Vector3(1.5,0.8,1.8), Color("ae7428"))
	box(world, rival.pose.origin, Vector3(1.5,0.8,1.8), Color("377bab"))
	var wall := box(world, Vector3(2,1.8,2), Vector3(3,3.6,0.3), Color("627581"))
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-45,-25,0)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,5,11)
	camera.look_at(Vector3(0,1,0))
	camera.current = true
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3840,2160)]:
			root.size = size
			for contrast: bool in [false,true]:
				badges.apply_accessibility(1.5,"deuteranopia",contrast)
				for occluded: bool in [false,true]:
					wall.visible = occluded
					for frame: int in 5:
						await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("user://a-world-markers-%d-%s-%s.png" % [size.x,contrast,occluded])
	world.free()
	await process_frame
	print("WORLD MARKERS PASS" if failures == 0 else "WORLD MARKERS FAIL")
	quit(0 if failures == 0 else 1)
