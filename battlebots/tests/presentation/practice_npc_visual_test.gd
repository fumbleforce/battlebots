extends Node3D
## Authored mesh/destruction contract plus optional native screenshot evidence.
var failures: Array[String] = []
var actors: Array[Dictionary] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path := "res://exports/evidence/"
	DirAccess.make_dir_recursive_absolute(path)
	get_viewport().get_texture().get_image().save_png(path+label+".png")

func run() -> void:
	var arena := preload("res://scenes/arenas/baseline_arena.tscn").instantiate()
	add_child(arena)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(10,9,17)
	camera.look_at(Vector3(0,0.8,-1))
	camera.fov = 48
	camera.current = true
	for index: int in 3:
		var visual := PracticeNpcVisual.new()
		add_child(visual)
		visual.assemble(PracticeBotDirector.VARIANTS[index], Vector3(4.8,1.5,6))
		visual.position = Vector3((index-1)*8.0,0.9,0)
		visual.rotation.y = PI
		var groups := visual.component_meshes()
		check(not groups.weapon.is_empty() and not groups.drive_left.is_empty() and not groups.drive_right.is_empty(),
			"Every authored NPC has weapon and independent drive damage groups")
		check(visual.find_children("Detach_*", "MeshInstance3D", true, false).size() >= 8,
			"Every NPC exposes at least eight detailed detachable assemblies")
		var effect := BotDestructionVisual.new()
		add_child(effect)
		effect.configure(visual, Vector3(4.8,1.5,6))
		var view := BotView.new()
		view.entity_id = index+1
		view.pose = visual.global_transform
		if index == 2:
			view.gun_pitch = -0.3
			visual.show_state(view, 0.0)
			var expected := visual.to_global(ScorpionGeometry.gun_muzzle(Vector3(1.6,.5,2), view.gun_pitch))
			check(visual.gun_effects.muzzle.global_position.distance_to(expected) < 0.001,
				"Sentry's authored muzzle follows the exact authoritative servo pivot and pitch")
			view.gun_pitch = 0.0
			visual.show_state(view, 0.0)
		effect.observe(view)
		actors.append({"visual":visual,"effect":effect,"view":view})
	for frame: int in 30: await get_tree().process_frame
	await capture("practice-npc-lineup")
	var actor: Dictionary = actors[1]
	var effect: BotDestructionVisual = actor.effect
	var pose: Transform3D = actor.visual.global_transform
	actor.view.core_fraction = 0.0
	actor.view.eliminated = true
	effect.observe(actor.view)
	effect.set_process(false)
	check(effect._chunk_paths.size() == BotDestructionVisual.PANELS and effect._panels.multimesh.visible_instance_count == 0,
		"Real imported chunks replace eight generic panels within the existing budget")
	check(effect._detached_sources.size() == 8, "Only eight source assemblies detach")
	for index: int in effect._detached_sources.size():
		var source := effect._detached_sources[index]
		var chunk := effect._chunks[index]
		check(not source.visible and chunk.visible and source.mesh == chunk.mesh,
			"Each flying chunk retains its exact authored mesh and hides the attached counterpart")
		check(chunk.global_transform.is_equal_approx(source.global_transform),
			"Authored chunks start at exact world position/orientation/scale")
	check(effect.burst_root.find_children("*","CollisionObject3D",true,false).is_empty(), "Detailed cosmetic debris cannot alter physics")
	effect._process(0.17)
	await capture("practice-npc-destruction")
	actor.visual.position += Vector3(3,0,0)
	check(effect.burst_root.global_position == pose.origin, "Detached explosion remains anchored in world space")
	effect._process(5.0)
	check(not effect.active, "Authored debris expires within the bounded burst lifetime")
	actor.view.core_fraction = 1.0
	actor.view.eliminated = false
	effect.observe(actor.view)
	for node: MeshInstance3D in actor.visual.find_children("Detach_*","MeshInstance3D",true,false):
		check(node.visible, "Repair restores every detached mesh")
	for record: Dictionary in actors:
		record.effect.free()
		record.visual.free()
	arena.free()
	camera.free()
	for failure: String in failures: push_error(failure)
	print("PRACTICE NPC VISUAL PASS" if failures.is_empty() else "PRACTICE NPC VISUAL FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
