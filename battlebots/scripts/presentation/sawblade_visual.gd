class_name SawbladeVisual
extends Node3D
## Art-only assembly. All damage and attack eligibility stay in CombatState.
const MODEL := preload("res://assets/models/sawblade_runtime/sawblade_runtime.glb")
const PAINT := preload("res://assets/models/sawblade_runtime/paint.gdshader")
static var hammer_samples: Dictionary = {}
static var tread_samples: Dictionary = {}
var nodes: Dictionary = {}
var kind := "saw"
var hammer_frame := 1.0
var _travel := [0.0, 0.0]
var _wheel_rest: Dictionary = {}
var _ramp_rest := Transform3D.IDENTITY
var _previous_pose := Transform3D.IDENTITY
var _have_pose := false
var _tracks := true

func assemble(draft: Dictionary, size: Vector3) -> void:
	if hammer_samples.is_empty():
		hammer_samples = JSON.parse_string(FileAccess.get_file_as_string("res://data/sawblade_hammer.json"))
		tread_samples = JSON.parse_string(FileAccess.get_file_as_string("res://data/sawblade_treads.json"))
	var model := MODEL.instantiate()
	add_child(model)
	for node: Node in model.find_children("*", "Node3D", true, false):
		var source: String = node.get_meta("extras", {}).get("source_name", "")
		if not source.is_empty(): nodes[source] = node
	# Fit the authored 1.68 x 2.60 body footprint to the canonical chassis.
	# Keep ground origin aligned with the bottom of the physics body.
	scale = Vector3(size.x / 1.68, size.z / 2.60, size.z / 2.60)
	position.y = -size.y * 0.5
	kind = draft.parts.weapon
	_tracks = draft.parts.drive == "traction"
	var config: Dictionary = draft.cosmetics.sawblade
	for weapon: String in ["saw", "hammer", "ramp"]:
		nodes["Module_weapon_" + weapon].visible = weapon == SawbladeConfig.WEAPONS[kind]
	nodes.Module_drive_tracks.visible = _tracks
	nodes.Module_drive_wheels.visible = not _tracks
	nodes.Module_armor_side_reference.visible = config.armor_side == 1
	nodes.Module_armor_side_heavy.visible = config.armor_side == 2
	for side: String in ["top", "front", "rear"]:
		nodes["Module_armor_" + side + "_guard"].visible = config["armor_" + side] == 1
	for index: int in 3:
		nodes["Module_exhaust_" + ["small", "medium", "large"][index]].visible = config.exhaust == index + 1
	var materials := {}
	for node: Node3D in nodes.values():
		if str(node.get_meta("extras", {}).get("source_name", "")).begins_with("Wheel_SPIN_X") or str(node.get_meta("extras", {}).get("source_name", "")).begins_with("Drive wheel"):
			_wheel_rest[node] = node.basis
		if not node is MeshInstance3D: continue
		for surface: int in node.mesh.get_surface_count():
			var original: StandardMaterial3D = node.mesh.surface_get_material(surface)
			if original == null: continue
			var label := original.resource_name
			if not materials.has(label):
				var channel := "paint_secondary"
				if label.begins_with("01") or label.begins_with("08"): channel = "paint_primary"
				elif label.begins_with("03"): channel = "paint_rubber"
				elif label.left(2) in ["04", "05", "06", "09"]: channel = "paint_metal"
				var rgba: Array = config[channel]
				var material := ShaderMaterial.new()
				material.shader = PAINT
				material.set_shader_parameter("surface_atlas", original.albedo_texture)
				# Root colors are linear Blender values; source_color converts sRGB input.
				material.set_shader_parameter("paint", Color(rgba[0], rgba[1], rgba[2], 1).linear_to_srgb())
				material.set_shader_parameter("metal", original.metallic)
				material.set_shader_parameter("rough", original.roughness)
				materials[label] = material
			node.set_surface_override_material(surface, materials[label])
	_ramp_rest = nodes.Module_weapon_ramp.transform
	set_hammer_frame(1)

func set_hammer_frame(frame: float) -> void:
	hammer_frame = clampf(frame, 1, 33)
	var index := mini(int(hammer_frame) - 1, 31)
	var weight := hammer_frame - float(index + 1)
	for key: String in hammer_samples:
		var a: Array = hammer_samples[key][index]
		var b: Array = hammer_samples[key][index + 1]
		var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), weight)
		var rotation := Quaternion(a[3], a[4], a[5], a[6]).normalized().slerp(Quaternion(b[3], b[4], b[5], b[6]).normalized(), weight)
		var stretch := Vector3(a[7], a[8], a[9]).lerp(Vector3(b[7], b[8], b[9]), weight)
		nodes[key].transform = Transform3D(Basis(rotation).scaled(stretch), origin)

func show_state(view: BotView, delta: float) -> void:
	var disabled := view.eliminated or view.weapon_state == "disabled"
	if kind == "hammer":
		var frame := 1.0
		if not disabled:
			if view.weapon_state == "windup": frame = lerpf(1, 9, view.weapon_charge_fraction)
			elif view.weapon_state == "strike": frame = 9
			elif view.weapon_cooldown > 0:
				frame = lerpf(9, 33, clampf(1.0 - view.weapon_cooldown / 1.4, 0, 1))
		set_hammer_frame(frame)
	elif kind == "saw" and not disabled and view.weapon_state == "active":
		nodes.Saw_SPIN_X.rotate_x(-delta * 36)
	elif kind == "lifter":
		var angle := 0.0 if disabled else view.weapon_charge_fraction * deg_to_rad(40)
		if not disabled and (view.weapon_state == "launch" or view.weapon_cooldown > 2.7): angle = deg_to_rad(75)
		nodes.Module_weapon_ramp.transform = _ramp_rest * Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO)
	if _have_pose and delta > 0:
		var displacement := view.pose.origin - _previous_pose.origin
		if displacement.length() < 1.0 and not view.eliminated:
			var forward := displacement.dot(-view.pose.basis.z.normalized()) / scale.z
			var turn := _previous_pose.basis.get_rotation_quaternion().angle_to(view.pose.basis.get_rotation_quaternion())
			var direction := signf(_previous_pose.basis.z.cross(view.pose.basis.z).y)
			advance_drive(forward + turn * direction * 0.66, forward - turn * direction * 0.66)
	_previous_pose = view.pose
	_have_pose = true

func advance_drive(left: float, right: float) -> void:
	_travel[0] += left
	_travel[1] += right
	for node: Node3D in _wheel_rest:
		var side := 0 if node.position.x < 0 else 1
		node.basis = _wheel_rest[node] * Basis(Vector3.RIGHT, -_travel[side] / 0.30)
	if not _tracks: return
	for key: String in tread_samples:
		var side := 0 if key.begins_with("Tread_L") else 1
		# Authored loop is 3.91 m long; position is relative to the model root.
		var phase := fposmod(_travel[side] / 3.91 * 120, 120)
		var index := int(phase)
		var a: Array = tread_samples[key][index]
		var b: Array = tread_samples[key][(index + 1) % 120]
		var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), phase - index)
		var node: Node3D = nodes[key]
		var root_node: Node3D = nodes.SawbladeTank_ROOT
		node.global_transform = root_node.global_transform * Transform3D(Basis(Vector3.RIGHT, lerp_angle(a[3], b[3], phase - index)), origin)

