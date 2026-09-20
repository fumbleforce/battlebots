extends Node3D
## Independent presentation acceptance: detached integrity snapshots only.
var failures: Array[String] = []
const DAMAGE_SCRIPT := "res://scripts/presentation/bot_damage_visual.gd"

func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func make_mesh() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	add_child(mesh)
	return mesh
func make_view(left: Variant = 100.0, right: Variant = 100.0, weapon: Variant = 140.0) -> BotView:
	var view := BotView.new()
	view.zones = {"drive_left":left, "drive_right":right, "weapon":weapon}
	return view
func run() -> void:
	var script: Script = load(DAMAGE_SCRIPT)
	var damage: Node3D = script.new()
	add_child(damage)
	var left := make_mesh()
	var right := make_mesh()
	var weapon := make_mesh()
	var original := StandardMaterial3D.new()
	original.albedo_color = Color(0.2,0.8,0.4,0.5)
	left.material_overlay = original
	damage.bind_component("drive_left", [left], left)
	damage.bind_component("drive_right", [right], right)
	damage.bind_component("weapon", [weapon], weapon)
	check(damage.stage_for("unrecognised") == -1,"Unknown component lookup stays unknown")
	var healthy := make_view()
	damage.show_state(healthy)
	check(damage.stage_for("drive_left") == 0 and damage.stage_for("weapon") == 0,"Full integrity is intact")
	check(left.material_overlay == original and right.material_overlay == null,"Intact component preserves caller overlays")
	var snapshot := make_view(50.0,50.001,70.0)
	var detached := snapshot.zones.duplicate(true)
	damage.show_state(snapshot)
	check(damage.stage_for("drive_left") == 1 and damage.stage_for("weapon") == 1,"Half integrity starts damage feedback")
	check(damage.stage_for("drive_right") == 0,"Integrity above threshold stays intact")
	check(snapshot.zones == detached,"Presentation does not mutate the detached snapshot")
	check(left.material_overlay != null and left.material_overlay != original,"Damaged component shows its own overlay")
	var first_overlay: Material = left.material_overlay
	damage.show_state(snapshot)
	check(left.material_overlay == first_overlay,"Repeated state reuses the component overlay")
	snapshot.zones.drive_left = 100.0
	check(damage.stage_for("drive_left") == 1,"Editing a previous snapshot cannot mutate visual state without presentation update")
	damage.show_state(make_view(0.0,100.0,0.0))
	check(damage.stage_for("drive_left") == 2 and damage.stage_for("weapon") == 2,"Zero integrity disables exactly affected components")
	check(damage.stage_for("drive_right") == 0 and right.material_overlay == null,"Healthy opposite drive remains unchanged")
	var other: Node3D = script.new()
	add_child(other)
	var other_left := make_mesh()
	other.bind_component("drive_left", [other_left], other_left)
	other.show_state(make_view())
	check(other.stage_for("drive_left") == 0 and other_left.material_overlay == null,"Other vehicle stays healthy")
	other.show_state(make_view(0.0))
	check(other_left.material_overlay != left.material_overlay,"Each vehicle owns its overlay resource")
	var eliminated := make_view()
	eliminated.eliminated = true
	damage.show_state(eliminated)
	check(damage.stage_for("drive_left") == 2 and damage.stage_for("drive_right") == 2 and damage.stage_for("weapon") == 2,"Elimination marks every bound component disabled")
	damage.show_state(healthy)
	check(left.material_overlay == original and right.material_overlay == null and weapon.material_overlay == null,"Round reset restores original component appearance")
	for malformed: Variant in ["0", true, NAN, INF, -1.0, 101.0, null]:
		damage.show_state(make_view(malformed))
		check(damage.stage_for("drive_left") == -1,"Malformed integrity stays unknown: " + str(malformed))
		check(left.material_overlay == original,"Malformed integrity does not imply damage")
	damage.show_state(null)
	check(damage.stage_for("drive_left") == -1 and left.material_overlay == original,"Absent view restores original appearance")
	var missing := BotView.new()
	damage.show_state(missing)
	check(damage.stage_for("weapon") == -1 and weapon.material_overlay == null,"Missing zones clear stale damage without inventing health")
	damage.show_state(make_view(0.0))
	var replacement := make_mesh()
	damage.bind_component("drive_left", [replacement], replacement)
	check(left.material_overlay == original,"Rebinding restores previous component overlay")
	damage.show_state(make_view(0.0))
	check(replacement.material_overlay != null,"Replacement component receives current damage")
	damage.free()
	check(replacement.material_overlay == null,"Removing presentation restores surviving component overlay")
	check(left.material_overlay == original,"Cleanup preserves original shared material")
	for component: Node in other.find_children("*", "CollisionObject3D", true, false):
		check(false,"Damage presentation has no collision objects: " + component.name)
	for particle: Node in other.find_children("*", "CPUParticles3D", true, false):
		check(particle.amount <= 6,"Smoke particle count is bounded per component")
	other.free()
	for mesh in [left, right, weapon, other_left, replacement]: mesh.queue_free()
	await get_tree().process_frame
	check_emitter_transforms()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless": await capture_variants()
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("COMPONENT DAMAGE PASS")
	get_tree().quit(0 if failures.is_empty() else 1)



func capture_variants() -> void:
	get_window().size = Vector2i(1280,720)
	var world := Node3D.new()
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-35,0)
	light.light_energy = 1.8
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.055,0.07,0.09)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.7,0.8,1)
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	var floor_mesh := MeshInstance3D.new()
	var floor_shape := PlaneMesh.new()
	floor_shape.size = Vector2(20,20)
	floor_mesh.mesh = floor_shape
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.16,0.18,0.21)
	floor_mesh.material_override = floor_material
	world.add_child(floor_mesh)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(-3.4,2.8,-4.2).normalized() * 6.0 + Vector3(0,0.5,0)
	camera.look_at(Vector3(0,0.5,0))
	camera.current = true
	var heading := Label.new()
	heading.position = Vector2(28,24)
	heading.add_theme_font_size_override("font_size",24)
	add_child(heading)
	var registry := ContentRegistry.new()
	for variant: Array in [["traction","saw"],["agile","hammer"],["walker","lifter"]]:
		var draft := registry.starter()
		draft.cosmetics.sawblade = SawbladeConfig.defaults()
		draft.parts.drive = variant[0]
		draft.parts.weapon = variant[1]
		var validation := registry.validate(draft)
		check(validation.valid,"Capture fixture build validates")
		var model := SawbladeVisual.new()
		world.add_child(model)
		model.assemble(draft, validation.stats.size)
		model.position.y = 0.18
		var damage := BotDamageVisual.new()
		world.add_child(damage)
		var groups := model.component_meshes()
		for zone: String in groups:
			check(not groups[zone].is_empty(),"Equipped " + zone + " has damage geometry for " + str(variant))
			var anchor := Node3D.new()
			world.add_child(anchor)
			var body_size: Vector3 = validation.stats.size
			anchor.position = Vector3(-body_size.x * 0.5 if zone == "drive_left" else body_size.x * 0.5,body_size.y + 0.18,0) if zone != "weapon" else Vector3(0,body_size.y + 0.18,-body_size.z * 0.5)
			damage.bind_component(zone, groups[zone], anchor)
		for stage: int in [0,1,2]:
			var view := make_view(100.0 if stage == 0 else (50.0 if stage == 1 else 0.0),100.0,140.0 if stage == 0 else (70.0 if stage == 1 else 0.0))
			damage.show_state(view)
			heading.text = "%s / %s — %s — camera 6m" % [variant[0],variant[1],["intact","damaged","disabled"][stage]]
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("component-%s-%s-%d.png" % [variant[0],variant[1],stage]))
		damage.free()
		model.free()
	world.queue_free()
	heading.queue_free()
	await get_tree().process_frame






func check_emitter_transforms() -> void:
	var rolled_parent := Node3D.new()
	rolled_parent.position = Vector3(7,4,-9)
	rolled_parent.rotation = Vector3(0.4,1.1,PI)
	rolled_parent.scale = Vector3(1.4,0.7,1.8)
	add_child(rolled_parent)
	var anchor := Node3D.new()
	anchor.position = Vector3(-0.6,0.3,-0.2)
	rolled_parent.add_child(anchor)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	rolled_parent.add_child(mesh)
	var damage := BotDamageVisual.new()
	rolled_parent.add_child(damage)
	damage.set_process(false)
	damage.bind_component("drive_left", [mesh], anchor)
	var smoke: CPUParticles3D = damage.components.drive_left.smoke
	check(smoke.global_position.is_equal_approx(anchor.global_position),"Emitter starts at anchor before first process")
	check(smoke.global_basis.is_equal_approx(Basis.IDENTITY),"Emitter ignores parent roll and scale")
	check(smoke.direction.is_equal_approx(Vector3.UP) and not smoke.local_coords,"Smoke rises in world coordinates")
	anchor.position += Vector3(0.2,0.1,-0.3)
	damage.show_state(make_view(0.0))
	check(smoke.global_position.is_equal_approx(anchor.global_position),"Disabling updates emitter position before first process")
	check(smoke.visible and smoke.emitting,"Valid disabled component emits smoke")
	rolled_parent.rotation = Vector3(-0.8,0.2,-PI * 0.5)
	rolled_parent.scale = Vector3(0.8,2.0,1.2)
	damage._process(0.0)
	check(smoke.global_position.is_equal_approx(anchor.global_position),"Emitter follows a moved rolled anchor")
	check(smoke.global_basis.is_equal_approx(Basis.IDENTITY),"Emitter stays world-up after parent rotation and scale change")
	anchor.free()
	damage._process(0.0)
	check(not smoke.visible and not smoke.emitting,"Freed anchor hides and stops its plume")
	damage.show_state(make_view())
	damage.show_state(make_view(0.0))
	check(not smoke.visible and not smoke.emitting,"New disabled state cannot resurrect a freed-anchor plume")
	damage.bind_component("weapon", [mesh], null)
	damage.show_state(make_view(0.0,100.0,0.0))
	var missing_smoke: CPUParticles3D = damage.components.weapon.smoke
	check(not missing_smoke.visible and not missing_smoke.emitting,"Missing anchor never emits at world origin")
	rolled_parent.free()

