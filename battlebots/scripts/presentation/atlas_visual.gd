class_name AtlasVisual
extends Node3D
## Authored Atlas shell, socket-mounted existing weapons, observed track travel.
## No collision, authoritative damage, input or simulated weapon state lives here.
const MODEL := "res://assets/models/atlas_runtime/atlas_mx.glb"
const LIFTER := "res://assets/models/atlas_runtime/atlas_lifter.glb"
const PAINT := preload("res://scripts/presentation/atlas_paint.gdshader")
var model: Node3D
var nodes: Dictionary = {}
var primary: MvpWeaponVisual
var auxiliary: MvpWeaponVisual
var _wheels: Array[Dictionary] = []
var _links: Array[Dictionary] = []
var _connectors: Array[Dictionary] = []
var _travel := [0.0, 0.0]
var _previous_pose := Transform3D.IDENTITY
var _have_pose := false
var _size := Vector3.ZERO

func assemble(draft: Dictionary, size: Vector3) -> void:
	_size = size
	scale = Vector3.ONE * BotScale.from_size(size)
	model = load(MODEL).instantiate()
	add_child(model)
	for node: Node in model.find_children("*", "Node3D", true, false):
		nodes[str(node.name)] = node
		var label := str(node.name)
		if not node is MeshInstance3D and (label.begins_with("Wheel_L_") or label.begins_with("Wheel_R_")):
			_wheels.append({"node":node, "basis":node.basis, "side":0 if label.begins_with("Wheel_L_") else 1,
				"radius":0.388 if "Front" in label or "Rear" in label else (0.105 if "Return" in label else 0.120)})
		elif not node is MeshInstance3D and (label.begins_with("Tread_L_") or label.begins_with("Tread_R_")):
			_links.append(_track_part(node, 0 if label.begins_with("Tread_L_") else 1))
		elif not node is MeshInstance3D and (label.begins_with("TrackConnector_L_") or label.begins_with("TrackConnector_R_")):
			_connectors.append(_track_part(node, 0 if label.begins_with("TrackConnector_L_") else 1))
	_apply_modules(draft.cosmetics.get("sawblade", AtlasGeometry.paint_defaults()))
	primary = _weapon(draft.parts.weapon)
	if draft.parts.weapon == "lifter" and ResourceLoader.exists(LIFTER):
		for child: Node in primary.mechanism.get_children(): child.free()
		var attachment: Node3D = load(LIFTER).instantiate()
		attachment.name = "AtlasLifterAttachment"
		primary.mechanism.add_child(attachment)
	if draft.parts.weapon == "minigun":
		primary.position = AtlasGeometry.GUN_OFFSET
	else:
		_assemble_tool_adapter()
	if draft.parts.utility == "minigun_pod":
		auxiliary = _weapon("minigun")
		auxiliary.position = AtlasGeometry.GUN_OFFSET
	_apply_paint(draft.cosmetics.get("sawblade", AtlasGeometry.paint_defaults()))

func _track_part(node: Node3D, side: int) -> Dictionary:
	var rest := _relative_transform(node)
	var distance := AtlasGeometry.track_distance(rest.origin)
	var frame := AtlasGeometry.track_transform(distance, rest.origin.x)
	return {"node":node, "side":side, "distance":distance, "x":rest.origin.x,
		"basis":frame.basis.inverse() * rest.basis}

func _weapon(kind: String) -> MvpWeaponVisual:
	var visual := MvpWeaponVisual.new()
	visual.name = "PrimaryModule" if primary == null else "AuxiliaryModule"
	add_child(visual)
	visual.scale = Vector3.ONE / scale
	visual.assemble(kind, _size)
	return visual

func _assemble_tool_adapter() -> void:
	# The quick-release coupler is at z=-1.08; existing weapon sweeps are centered
	# on the canonical front edge z=-1.30. Two rails physically join those frames.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("394754")
	material.metallic = 0.8
	material.roughness = 0.32
	for side: int in [-1, 1]:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.11, 0.12, 0.40)
		mesh.material = material
		var rail := MeshInstance3D.new()
		rail.name = "ToolCouplerRail"
		rail.mesh = mesh
		rail.position = Vector3(side * 0.25, -0.02, -1.14)
		add_child(rail)

func _apply_modules(config: Dictionary) -> void:
	var selection := {"ArmorSideReference":config.armor_side == 1,
		"ArmorSideHeavy":config.armor_side == 2, "ArmorTop":config.armor_top == 1,
		"ArmorFront":config.armor_front == 1, "ArmorRear":config.armor_rear == 1,
		"ExhaustSmall":config.exhaust == 1, "ExhaustMedium":config.exhaust == 2,
		"ExhaustLarge":config.exhaust == 3}
	for label: String in selection:
		if nodes.has(label): nodes[label].visible = selection[label]

func _apply_paint(config: Dictionary) -> void:
	var shared := {}
	var defaults := AtlasGeometry.paint_defaults()
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			if original == null: continue
			var label := original.resource_name.to_lower().replace("_", "")
			var channel := ""
			if "paintprimary" in label: channel = "paint_primary"
			elif "paintsecondary" in label: channel = "paint_secondary"
			elif "metal" in label: channel = "paint_metal"
			elif "rubber" in label: channel = "paint_rubber"
			if channel.is_empty(): continue
			if config[channel] == defaults[channel]: continue
			if not shared.has(original):
				var rgba: Array = config[channel]
				var tint := Color(rgba[0], rgba[1], rgba[2], 1).linear_to_srgb()
				if original.albedo_texture != null and channel in ["paint_primary", "paint_secondary"]:
					var material := ShaderMaterial.new()
					material.shader = PAINT
					material.set_shader_parameter("surface_albedo", original.albedo_texture)
					material.set_shader_parameter("surface_orm", original.metallic_texture)
					material.set_shader_parameter("surface_normal", original.normal_texture)
					material.set_shader_parameter("normal_strength", original.normal_scale)
					material.set_shader_parameter("paint", tint)
					var source: Array = defaults[channel]
					material.set_shader_parameter("authored_paint", Color(source[0], source[1], source[2], 1).linear_to_srgb())
					shared[original] = material
				else:
					var material := original.duplicate() as StandardMaterial3D
					if label == "atlaspaintprimaryedge":
						# The clean painted chamfer keeps its authored contrast in every color.
						tint = Color(minf(rgba[0] * 1.15 + 0.025, 1.0),
							minf(rgba[1] * 1.15 + 0.025, 1.0), minf(rgba[2] * 1.15 + 0.025, 1.0)).linear_to_srgb()
					material.albedo_color = tint
					shared[original] = material
			mesh.set_surface_override_material(index, shared[original])

func _relative_transform(node: Node3D) -> Transform3D:
	if node == self: return Transform3D.IDENTITY
	var result := node.transform
	var parent := node.get_parent() as Node3D
	while parent != self:
		result = parent.transform * result
		parent = parent.get_parent() as Node3D
	return result

func advance_drive(left: float, right: float) -> void:
	_travel[0] += left
	_travel[1] += right
	for wheel: Dictionary in _wheels:
		wheel.node.basis = wheel.basis * Basis(Vector3.RIGHT, -_travel[wheel.side] / wheel.radius)
	_advance_track_parts(_links)
	_advance_track_parts(_connectors)

func _advance_track_parts(parts: Array[Dictionary]) -> void:
	for link: Dictionary in parts:
		var frame := AtlasGeometry.track_transform(link.distance - _travel[link.side], link.x)
		frame.basis *= link.basis
		var parent: Node3D = link.node.get_parent()
		link.node.transform = _relative_transform(parent).affine_inverse() * frame

func show_state(view: BotView, delta: float) -> void:
	primary.show_state(view, delta)
	if auxiliary != null:
		auxiliary.gun_effects.show_state(view, delta, false)
	if _have_pose and delta > 0.0:
		var displacement := view.pose.origin - _previous_pose.origin
		if displacement.length() < 2.0 and not view.eliminated:
			var forward := displacement.dot(-view.pose.basis.z.normalized()) / scale.z
			var turn := _previous_pose.basis.get_rotation_quaternion().angle_to(view.pose.basis.get_rotation_quaternion())
			var direction := signf(_previous_pose.basis.z.cross(view.pose.basis.z).y)
			advance_drive(forward - turn * direction * 0.94, forward + turn * direction * 0.94)
	_previous_pose = view.pose
	_have_pose = true

func component_meshes() -> Dictionary:
	var groups := {"weapon":[], "drive_left":[], "drive_right":[]}
	_collect(primary, groups.weapon)
	if auxiliary != null: _collect(auxiliary, groups.weapon)
	if nodes.has("DriveLeft"): _collect(nodes.DriveLeft, groups.drive_left)
	if nodes.has("DriveRight"): _collect(nodes.DriveRight, groups.drive_right)
	return groups

func _collect(root: Node3D, result: Array) -> void:
	if not root.visible: return
	if root is MeshInstance3D: result.append(root)
	for child: Node in root.get_children():
		if child is Node3D: _collect(child, result)

func reset_observation() -> void:
	_have_pose = false
	if primary.gun_effects != null: primary.gun_effects.clear_effects()
	if auxiliary != null: auxiliary.gun_effects.clear_effects()
