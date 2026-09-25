class_name SawbladeVisual
extends Node3D
## Art-only assembly. All damage and attack eligibility stay in CombatState.
const MODEL := preload("res://assets/models/sawblade_runtime/sawblade_runtime.glb")
const PAINT := preload("res://assets/models/sawblade_runtime/paint.gdshader")
## Authored tread loop length in model metres; sawblade_treads.json samples it evenly.
const TREAD_LOOP_LENGTH := 3.91
static var hammer_samples: Dictionary = {}
static var tread_samples: Dictionary = {}
var nodes: Dictionary = {}
var kind := "saw"
var hammer_frame := 1.0
var _travel := [0.0, 0.0]
var _wheel_rest: Dictionary = {}
var _ramp_rest := Transform3D.IDENTITY
var _ramp_pivot: Node3D
var _previous_pose := Transform3D.IDENTITY
var _have_pose := false
var _tracks := true
var walker_legs: WalkerLegs
var fallback_weapon: MvpWeaponVisual

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
	scale = SawbladeGeometry.scale_for(size)
	position.y = -size.y * 0.5
	kind = draft.parts.weapon
	_tracks = draft.parts.drive == "traction"
	var config: Dictionary = draft.cosmetics.sawblade
	for weapon: String in ["saw", "hammer", "ramp"]:
		nodes["Module_weapon_" + weapon].visible = weapon == SawbladeConfig.WEAPONS.get(kind, "")
	if not SawbladeConfig.WEAPONS.has(kind):
		fallback_weapon = MvpWeaponVisual.new()
		add_child(fallback_weapon)
		# Canonical weapon geometry uses body meters, outside the authored art scale.
		fallback_weapon.scale = Vector3.ONE / scale
		fallback_weapon.position.y = size.y * 0.5 / scale.y
		fallback_weapon.assemble(kind, size)
	nodes.Module_drive_tracks.visible = _tracks
	nodes.Module_drive_wheels.visible = draft.parts.drive in ["standard_wheels", "agile"]
	nodes.Module_armor_side_reference.visible = config.armor_side == 1
	nodes.Module_armor_side_heavy.visible = config.armor_side == 2
	for side: String in ["top", "front", "rear"]:
		nodes["Module_armor_" + side + "_guard"].visible = config["armor_" + side] == 1
	for index: int in 3:
		nodes["Module_exhaust_" + ["small", "medium", "large"][index]].visible = config.exhaust == index + 1
	var materials := {}
	# Armour modules take the armour paint; their trim keeps the factory secondary.
	var armor_meshes := {}
	for key: String in nodes:
		if key.begins_with("Module_armor_"):
			for mesh: Node in nodes[key].find_children("*", "MeshInstance3D", true, false):
				armor_meshes[mesh] = true
	for node: Node3D in nodes.values():
		if str(node.get_meta("extras", {}).get("source_name", "")).begins_with("Wheel_SPIN_X") or str(node.get_meta("extras", {}).get("source_name", "")).begins_with("Drive wheel"):
			_wheel_rest[node] = node.basis
		if not node is MeshInstance3D: continue
		for surface: int in node.mesh.get_surface_count():
			var original: StandardMaterial3D = node.mesh.surface_get_material(surface)
			if original == null: continue
			var label := original.resource_name
			var armor := armor_meshes.has(node)
			var key := ("armor|" if armor else "") + label
			if not materials.has(key):
				var channel := "paint_secondary"
				if label.begins_with("01") or label.begins_with("08"): channel = "paint_primary"
				elif label.begins_with("03"): channel = "paint_rubber"
				elif label.left(2) in ["04", "05", "06", "09"]: channel = "paint_metal"
				var rgba: Array = config[channel]
				if armor and channel == "paint_primary": rgba = SawbladeConfig.armor_color(config)
				elif armor and channel == "paint_secondary": rgba = SawbladeConfig.defaults().paint_secondary
				var material := ShaderMaterial.new()
				material.shader = PAINT
				material.set_shader_parameter("surface_atlas", original.albedo_texture)
				# Root colors are linear Blender values; source_color converts sRGB input.
				material.set_shader_parameter("paint", Color(rgba[0], rgba[1], rgba[2], 1).linear_to_srgb())
				material.set_shader_parameter("metal", original.metallic)
				material.set_shader_parameter("rough", original.roughness)
				materials[key] = material
			node.set_surface_override_material(surface, materials[key])
	_ramp_pivot = Node3D.new()
	nodes.SawbladeTank_ROOT.add_child(_ramp_pivot)
	_ramp_pivot.position = Vector3(0, 0.36, -0.30)
	nodes.Module_weapon_ramp.reparent(_ramp_pivot, true)
	_ramp_rest = _ramp_pivot.transform
	if draft.parts.drive == "walker":
		walker_legs = WalkerLegs.new()
		add_child(walker_legs)
		walker_legs.scale = Vector3.ONE / scale
		walker_legs.position.y = size.y * 0.5 / scale.y
		var primary: Material
		for label: String in materials:
			if label.begins_with("01"): primary = materials[label]
		walker_legs.assemble(size, primary, config)
	set_hammer_frame(1)

## Only equipped mechanisms; armor skirts, body panels and exhaust stay separate.
func component_meshes() -> Dictionary:
	var result := {"weapon": [], "drive_left": [], "drive_right": []}
	var weapon_root: Node3D = fallback_weapon
	if weapon_root == null and SawbladeConfig.WEAPONS.has(kind):
		weapon_root = nodes.get("Module_weapon_" + SawbladeConfig.WEAPONS[kind])
	if weapon_root != null:
		_collect_component_meshes(weapon_root, result.weapon)
	if walker_legs != null:
		var walking := walker_legs.component_meshes()
		result.drive_left = walking.drive_left
		result.drive_right = walking.drive_right
	else:
		var drive_root: Node3D = nodes.get("Module_drive_tracks" if _tracks else "Module_drive_wheels")
		var meshes: Array = []
		if drive_root != null: _collect_component_meshes(drive_root, meshes)
		for mesh: MeshInstance3D in meshes:
			# Mesh origins can sit at a common socket; use the actual bounds center.
			var center := mesh.get_aabb().get_center()
			var ancestor: Node3D = mesh
			while ancestor != self:
				center = ancestor.transform * center
				ancestor = ancestor.get_parent() as Node3D
			result["drive_left" if center.x < 0 else "drive_right"].append(mesh)
	return result

func _collect_component_meshes(root: Node3D, result: Array) -> void:
	if not root.visible: return
	if root is MeshInstance3D: result.append(root)
	for child: Node in root.get_children():
		if child is Node3D: _collect_component_meshes(child, result)

func set_hammer_frame(frame: float) -> void:
	hammer_frame = clampf(frame, 1, 33)
	var sample := (hammer_frame - 1.0) * 4.0
	var index := mini(int(sample), 127)
	var weight := sample - float(index)
	for key: String in hammer_samples:
		var a: Array = hammer_samples[key][index]
		var b: Array = hammer_samples[key][index + 1]
		var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), weight)
		var rotation := Quaternion(a[3], a[4], a[5], a[6]).normalized().slerp(Quaternion(b[3], b[4], b[5], b[6]).normalized(), weight)
		var stretch := Vector3(a[7], a[8], a[9]).lerp(Vector3(b[7], b[8], b[9]), weight)
		nodes[key].transform = Transform3D(Basis(rotation).scaled(stretch), origin)

func show_state(view: BotView, delta: float) -> void:
	if fallback_weapon != null:
		fallback_weapon.show_state(view, delta)
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
		_ramp_pivot.transform = _ramp_rest * Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO)
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
		# Samples are relative to the model root. fposmod can round up to exactly
		# count for tiny negative travel, so wrap the index and derive the blend.
		var samples: Array = tread_samples[key]
		var count := samples.size()
		var phase := fposmod(_travel[side] / TREAD_LOOP_LENGTH * count, count)
		var index := int(phase) % count
		var blend := phase - floorf(phase)
		var a: Array = samples[index]
		var b: Array = samples[(index + 1) % count]
		var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), blend)
		var node: Node3D = nodes[key]
		var root_node: Node3D = nodes.SawbladeTank_ROOT
		node.global_transform = root_node.global_transform * Transform3D(Basis(Vector3.RIGHT, lerp_angle(a[3], b[3], blend)), origin)
