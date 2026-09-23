extends Node3D
## Mortar artillery view under the Foundry roof: the camera stays below the
## visual-only roof trusses yet still looks out across the mortar's range;
## the open Moon keeps the full height. Natively (without --headless) it also
## saves near/far captures under exports/mortar-camera-review.
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func review(arena: String) -> void:
	var session := MvpSession.new()
	session.name = "Session"
	session.pickups_enabled = false
	add_child(session)
	var source := SessionBotSource.new()
	source.name = "Source"
	source.session_path = NodePath("../Session")
	add_child(source)
	var draft := session.registry.atlas()
	draft.parts.utility = "turret_mortar"
	check(session.practice(draft, arena) == OK, "Mortar practice starts in " + arena)
	for frame: int in 600:
		await get_tree().process_frame
		if session.local_source() != null and session.match_view.get("phase") == "active": break
	var preview: Node3D = load("res://scenes/ui/baseline_preview.tscn").instantiate()
	preview.source_path = NodePath("../Source")
	preview.settings_path = ""
	add_child(preview)
	preview.set_physics_process(false)
	var rig: BotOrbitCamera = preview.rig
	var ceiling := ArenaBounds.ceiling(arena)
	# Look the way the tank faces at spawn: toward the arena centre.
	var facing := -source.read_view().pose.basis.z
	rig.yaw = atan2(-facing.x, -facing.z)
	for reach: float in [0.0, 1.0]:
		rig.pitch = lerpf(TankSightCamera.PITCH_MIN, TankSightCamera.PITCH_MAX, reach)
		for frame: int in 20:
			preview._update_tank_sight(source.read_view(), 1.0 / 60.0)
			await get_tree().process_frame
		var camera: Camera3D = preview.tank_sight.camera
		check(preview.tank_sight.artillery and camera.current, "%s: the mortar uses the artillery view" % arena)
		var at := camera.global_position
		check(at.y < ceiling - 1.0, "%s: the artillery camera stays below the roof (%.1f m, roof %.1f)" % [arena, at.y, ceiling])
		var forward := -camera.global_basis.z
		var hit := get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(at, at + forward * 300.0, BaselineConfig.WORLD_LAYER))
		var bot_at: Vector3 = session.local_source().read_view().pose.origin
		var ground := -1.0 if hit.is_empty() else Vector2(hit.position.x - bot_at.x, hit.position.z - bot_at.z).length()
		print("%s reach %.0f: camera y %.1f, looks %.0f m ahead" % [arena, reach, at.y, ground])
		if reach == 0.0:
			check(ground > 5.0 and ground < (20.0 if arena == "foundry" else 30.0), "%s: near aim lands just ahead of the tank" % arena)
		else:
			# Far aim reaches the mortar's long range or looks past the arena
			# walls (the stands have no collision), never at the roof.
			check(ground > 40.0 or ground < 0.0, "%s: far aim looks well out across the arena" % arena)
			check(forward.y < -0.1, "%s: far aim still looks down, not at the roof" % arena)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var output := ProjectSettings.globalize_path("res://exports/mortar-camera-review")
			DirAccess.make_dir_recursive_absolute(output)
			get_viewport().get_texture().get_image().save_png(output.path_join("%s-%s.png" % [arena, "far" if reach > 0.5 else "near"]))
	preview.queue_free()
	session.leave()
	session.queue_free()
	source.queue_free()
	for frame: int in 5: await get_tree().process_frame

func run() -> void:
	await review("foundry")
	await review("moon")
	print("MORTAR ARTILLERY CAMERA PASS" if failures == 0 else "MORTAR ARTILLERY CAMERA FAIL")
	get_tree().quit(0 if failures == 0 else 1)
