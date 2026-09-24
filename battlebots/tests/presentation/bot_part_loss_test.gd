extends Node3D
## #72 progressive part loss: clusters from any visual, thresholds from the
## replicated zones, hit-chosen clusters, severing, repair and reconnects.
const PART_LOSS := preload("res://scripts/presentation/bot_part_loss.gd")
const TUNING := preload("res://scripts/core/destruction_tuning.gd")
const POSE := Transform3D(Basis(Vector3.UP, 0.4), Vector3(3, 1, -2))
var failures: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func box(parent: Node3D, label: String, size: Vector3, at: Vector3, unshaded := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	var material := StandardMaterial3D.new()
	if unshaded: material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, material)
	mesh.position = at
	parent.add_child(mesh)
	return mesh

## A 4 x 1.2 x 6 m hull with three left wheels on their own pivots, a front
## weapon, four small front panels, one rear panel and a glowing effect mesh.
func fixture() -> Dictionary:
	var presentation := Node3D.new()
	add_child(presentation)
	presentation.global_transform = POSE
	var hull := box(presentation, "Hull", Vector3(4, 1.2, 6), Vector3.ZERO)
	var wheels: Array = []
	for z: float in [-2.2, 0.0, 2.2]:
		var pivot := Node3D.new()
		pivot.name = "Wheel%d" % wheels.size()
		pivot.position = Vector3(-2.3, -0.3, z)
		presentation.add_child(pivot)
		wheels.append(box(pivot, "WheelSurface", Vector3(0.5, 0.9, 0.9), Vector3.ZERO))
	var weapon := box(presentation, "Saw", Vector3(0.3, 0.8, 0.8), Vector3(0, 0, -3.4))
	var panels: Array = []
	for x: float in [-1.2, -0.4, 0.4, 1.2]:
		panels.append(box(presentation, "FrontPanel", Vector3(0.8, 0.5, 0.1), Vector3(x, 0, -3.05)))
	var rear := box(presentation, "RearPanel", Vector3(1.0, 0.5, 0.1), Vector3(0, 0, 3.05))
	var glow := box(presentation, "Glow", Vector3(0.2, 0.2, 0.2), Vector3(0, 0, 3.2), true)
	var loss: Node3D = PART_LOSS.new()
	add_child(loss)
	loss.configure(presentation, {"weapon":[weapon], "drive_left":wheels, "drive_right":[]}, Vector3(1.6, 0.5, 2.0) * 3.0, 21)
	return {"presentation":presentation, "hull":hull, "wheels":wheels, "weapon":weapon, "panels":panels,
		"rear":rear, "glow":glow, "loss":loss}

func view(zones: Dictionary = {}, core := 1.0, plates: Dictionary = {}) -> BotView:
	var result := BotView.new()
	result.entity_id = 21
	result.pose = POSE
	result.core_fraction = core
	result.zones = {"drive_left":100.0, "drive_right":100.0, "weapon":140.0}
	result.zones.merge(zones, true)
	for face: String in plates:
		result.plate_max[face] = plates[face]
		if not result.zones.has(face): result.zones[face] = plates[face]
	return result

func hit(zone: String, local: Vector3, kind := "hammer") -> Dictionary:
	return {"target":21, "zone":zone, "kind":kind, "position":POSE * local, "normal":Vector3.UP, "axis":POSE.basis * Vector3.RIGHT}

func pools() -> void:
	var setup := fixture()
	var loss: Node3D = setup.loss
	check(loss.pools.drive_left.size() == 3, "Each wheel pivot is its own drive cluster: %d" % loss.pools.drive_left.size())
	check(loss.pools.weapon.size() == 1, "The weapon is one cluster")
	var front: Array = loss.pools.front
	var in_front := 0
	for cluster: Dictionary in front:
		in_front += cluster.meshes.size()
	check(in_front == 4, "Small front panels pool on the front face: %d" % in_front)
	for pool: Array in loss.pools.values():
		for cluster: Dictionary in pool:
			for entry: Dictionary in cluster.meshes:
				check(entry.source != setup.hull, "The main hull never comes off")
				check(entry.source != setup.glow, "Effect meshes stay on the bot")
	setup.presentation.queue_free()
	loss.queue_free()

func losses() -> void:
	var setup := fixture()
	var loss: Node3D = setup.loss
	loss.observe(view())
	check(loss.lost_count() == 0, "A healthy bot keeps every part")
	# The latest hit on the left drive lands on the rear wheel: that one goes first.
	loss.note_hit(hit("drive_left", Vector3(-2.3, -0.3, 2.2)))
	loss.observe(view({"drive_left":55.0}))
	check(not setup.wheels[2].visible and setup.wheels[0].visible and setup.wheels[1].visible, "The wheel nearest the hit comes off first")
	var parts: Array[Node] = loss.lost_parts()
	check(parts.size() == 1 and parts[0].linear_velocity.length() > 0.5, "A lost part flies off as physics debris")
	check(parts.size() == 1 and parts[0].collision_layer == 0 and parts[0].collision_mask == BaselineConfig.WORLD_LAYER, "Lost parts only touch the world")
	loss.observe(view({"drive_left":0.0}))
	check(setup.wheels.all(func(wheel: MeshInstance3D) -> bool: return not wheel.visible), "A destroyed drive side loses every wheel")
	check(loss.lost_parts().size() == 3, "Each wheel is its own piece of debris")
	# Saw hits sever with a glowing seam.
	loss.note_hit(hit("weapon", Vector3(0, 0, -3.4), "saw"))
	loss.observe(view({"drive_left":0.0, "weapon":0.0}))
	check(not setup.weapon.visible, "A destroyed weapon comes off")
	var severed: Node = loss.lost_parts().back()
	var mesh: MeshInstance3D = severed.get_children().filter(func(child: Node) -> bool: return child is MeshInstance3D).front()
	check(mesh.get_surface_override_material(0) is ShaderMaterial and mesh.get_instance_shader_parameter("cut_state").x > 0.0,
		"A sawn-off part glows where it was cut")
	# Core damage strips hull panels from the face last hit.
	loss.note_hit(hit("front", Vector3(1.2, 0, -3.05)))
	loss.observe(view({"drive_left":0.0, "weapon":0.0}, 0.45))
	var gone: int = setup.panels.filter(func(panel: MeshInstance3D) -> bool: return not panel.visible).size()
	check(gone >= 2 and setup.rear.visible, "Core damage strips panels from the struck face: %d" % gone)
	check(not setup.panels[3].visible, "The panel nearest the hit goes")
	# A new round repairs everything.
	loss.observe(view())
	await get_tree().process_frame
	check(loss.lost_count() == 0 and setup.wheels[2].visible and setup.weapon.visible and setup.panels[3].visible, "Repair brings every part back")
	check(loss.lost_parts().is_empty(), "Repair clears the debris")
	setup.presentation.queue_free()
	loss.queue_free()

func armour() -> void:
	var setup := fixture()
	var loss: Node3D = setup.loss
	var plates := {"front":80.0}
	loss.observe(view({}, 1.0, plates))
	loss.observe(view({"front":30.0}, 1.0, plates))
	var gone: int = setup.panels.filter(func(panel: MeshInstance3D) -> bool: return not panel.visible).size()
	check(gone == 1, "Armour worn past half loses one front cluster: %d" % gone)
	loss.observe(view({"front":0.0}, 1.0, plates))
	check(setup.panels.all(func(panel: MeshInstance3D) -> bool: return not panel.visible), "Destroyed armour strips the whole face")
	setup.presentation.queue_free()
	loss.queue_free()

func reconnect() -> void:
	var setup := fixture()
	var loss: Node3D = setup.loss
	# The first baseline already shows a wrecked drive: hide the parts, no debris rain.
	loss.observe(view({"drive_left":20.0}))
	check(loss.lost_count() == 2 and loss.lost_parts().is_empty(), "A late joiner sees lost parts without replayed debris")
	loss.reset_observation()
	check(loss.lost_count() == 0 and setup.wheels.all(func(wheel: MeshInstance3D) -> bool: return wheel.visible), "Reset restores the bot")
	setup.presentation.queue_free()
	loss.queue_free()

func run() -> void:
	pools()
	await losses()
	armour()
	reconnect()
	await get_tree().process_frame
	for failure: String in failures:
		push_error(failure)
	print("BOT PART LOSS PASS" if failures.is_empty() else "BOT PART LOSS FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
