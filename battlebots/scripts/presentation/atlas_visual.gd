class_name AtlasVisual
extends Node3D
## Authored Atlas shell, socket-mounted existing weapons, observed track travel.
## No collision, authoritative damage, input or simulated weapon state lives here.
const MODEL := "res://assets/models/atlas_runtime/atlas_mx.glb"
const LIFTER := "res://assets/models/atlas_runtime/atlas_lifter.glb"
const TURRET := "res://assets/models/atlas_runtime/atlas_turret.glb"
## Alternative running gear on the approved sponsons (tools/build-atlas-drives.py).
const DRIVES := "res://assets/models/atlas_runtime/atlas_drives.glb"
## atlas_drives.glb group per running gear; the others are freed on assembly.
const GEAR_GROUPS := {"wheels":"WheelsLarge", "legs":"Legs"}
## Deck modules the fitted turret occupies or sweeps through (clearance audit).
const TURRET_HIDDEN := ["ArmorTop", "ExhaustSmall", "ExhaustMedium", "ExhaustLarge"]
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
## "tracks", "wheels" or "legs" (AtlasGeometry.DRIVE_GEAR).
var drive_gear := "tracks"
var drives: Node3D
var legs: AtlasLegs
var turret: Node3D
var turret_kind := ""
var turret_model := ""
## TurretShotEffects (cannon/plasma) or TurretSpecialEffects (flamer, tesla,
## railgun); both expose configure/show_state/clear_effects/muzzles/shot_count.
var turret_effects: Node3D
## Smoothed yaw/pitch actually drawn this frame (also drives the reticle).
var turret_display := Vector2.ZERO
var _turret_yaw: Node3D
var _turret_pitch: Node3D
var _turret_rest := {}
var _turret_shown := false
var _sample := Vector2.ZERO
var _sample_rate := Vector2.ZERO
var _sample_tick := -1
var _since_sample := 0.0

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
	drive_gear = AtlasGeometry.drive_gear(draft)
	if drive_gear in GEAR_GROUPS and ResourceLoader.exists(DRIVES):
		_assemble_drives(size)
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
	turret_kind = AtlasGeometry.turret_kind(draft)
	turret_model = AtlasGeometry.turret_model(draft)
	if not turret_kind.is_empty() and ResourceLoader.exists(TURRET):
		_assemble_turret()
	_apply_paint(draft.cosmetics.get("sawblade", AtlasGeometry.paint_defaults()))

## The approved tracks, sprockets and rollers give way to the chosen gear. Its
## GLB carries the same sponsons (hood, corner sockets, skirts, axle bosses)
## with only the track-specific roller mounts removed.
func _assemble_drives(size: Vector3) -> void:
	for label: String in ["DriveLeft", "DriveRight"]:
		if nodes.has(label): nodes[label].visible = false
	_wheels.clear()
	_links.clear()
	_connectors.clear()
	drives = load(DRIVES).instantiate()
	drives.name = "AtlasDriveGear"
	add_child(drives)
	for gear: String in GEAR_GROUPS:
		if gear != drive_gear: drives.find_child(GEAR_GROUPS[gear], true, false).free()
	var found := {}
	for node: Node in drives.find_children("*", "Node3D", true, false):
		found[str(node.name)] = node
	if drive_gear == "wheels":
		var radius := AtlasDriveRig.settings().wheel_radius
		for label: String in found:
			var node: Node3D = found[label]
			if not node is MeshInstance3D and (label.begins_with("Wheel_L_") or label.begins_with("Wheel_R_")):
				_wheels.append({"node":node, "basis":node.basis, "side":0 if label.begins_with("Wheel_L_") else 1, "radius":radius})
	else:
		legs = AtlasLegs.new()
		legs.name = "AtlasLegs"
		add_child(legs)
		legs.scale = Vector3.ONE / scale
		legs.attach(size, found)

func _assemble_turret() -> void:
	turret = load(TURRET).instantiate()
	turret.name = "AtlasTurretModule"
	add_child(turret)
	var found := {}
	for node: Node in turret.find_children("*", "Node3D", true, false):
		found[str(node.name)] = node
	_turret_yaw = found.get("TurretYaw")
	_turret_pitch = found.get("TurretPitch")
	# Node names: Attachment<Family><Suffix>, CannonRecoil<Suffix>_i, Muzzle<Family><Suffix>_i.
	var family := turret_kind.capitalize()
	var suffix := turret_model.get_slice("_", 1).capitalize() if "_" in turret_model else ""
	var chosen := "Attachment" + family + suffix
	for label: String in found:
		if label.begins_with("Attachment") and not label.ends_with("Surface"):
			found[label].visible = label == chosen
		elif label == "SponsonsQuad":
			# Turret-integrated armored sponsons house the quad side guns.
			found[label].visible = turret_model.ends_with("_quad")
	for node: Node3D in [_turret_yaw, _turret_pitch]:
		if node != null: _turret_rest[node] = node.transform
	for label: String in TURRET_HIDDEN:
		if nodes.has(label): nodes[label].visible = false
	var muzzles: Array[Node3D] = []
	var recoils: Array[Node3D] = []
	var barrels: int = AtlasGeometry.TURRET_BARRELS.get(turret_model, [[0, 0]]).size()
	for index: int in barrels:
		var tag := "" if suffix.is_empty() else "%s_%d" % [suffix, index]
		muzzles.append(found.get("Muzzle" + family + tag))
		recoils.append(found.get("CannonRecoil" + tag) if turret_kind == "cannon" else null)
	turret_effects = TurretSpecialEffects.new() if turret_kind in ["flamer", "tesla", "railgun"] else TurretShotEffects.new()
	turret_effects.name = "TurretShotEffects"
	add_child(turret_effects)
	turret_effects.configure(turret_kind, muzzles, recoils, _size.y / BotScale.AUTHORING_HEIGHT)

## Presentation only. Authoritative angles arrive per physics tick (60 Hz
## locally, 20 Hz snapshots remotely). Estimate their rate from each new
## sample, predict between samples and ease toward the prediction, so the
## turret moves smoothly at any frame rate without lagging the servo.
func _show_turret(view: BotView, delta: float) -> void:
	var target := Vector2(view.turret_yaw, view.gun_pitch)
	var jump := absf(wrapf(target.x - _sample.x, -PI, PI)) > 1.2
	if not _turret_shown or jump:
		turret_display = target
		_sample = target
		_sample_rate = Vector2.ZERO
		_sample_tick = view.server_tick
		_since_sample = 0.0
	elif view.server_tick != _sample_tick:
		var elapsed := maxf(_since_sample, 1.0 / 240.0)
		_sample_rate = Vector2(
			clampf(wrapf(target.x - _sample.x, -PI, PI) / elapsed, -TurretTuning.settings().yaw_rate, TurretTuning.settings().yaw_rate),
			clampf((target.y - _sample.y) / elapsed, -TurretTuning.settings().pitch_rate, TurretTuning.settings().pitch_rate))
		_sample = target
		_sample_tick = view.server_tick
		_since_sample = 0.0
	_turret_shown = true
	_since_sample += maxf(delta, 0.0)
	var ahead := minf(_since_sample, 0.1)
	var predicted := Vector2(wrapf(_sample.x + _sample_rate.x * ahead, -PI, PI), _sample.y + _sample_rate.y * ahead)
	var ease := 1.0 - exp(-maxf(delta, 0.0) * 30.0)
	turret_display.x = wrapf(turret_display.x + wrapf(predicted.x - turret_display.x, -PI, PI) * ease, -PI, PI)
	turret_display.y = lerpf(turret_display.y, predicted.y, ease)
	if _turret_yaw != null:
		_turret_yaw.transform = _turret_rest[_turret_yaw] * Transform3D(Basis(Vector3.UP, turret_display.x))
	if _turret_pitch != null:
		_turret_pitch.transform = _turret_rest[_turret_pitch] * Transform3D(Basis(Vector3.RIGHT, turret_display.y))
	turret_effects.show_state(view, delta)

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
				if original.albedo_texture != null:
					var coverage: Texture2D
					if channel in ["paint_primary", "paint_secondary"]:
						var coverage_path := original.albedo_texture.resource_path.get_basename().trim_suffix("_base") + "_coverage.png"
						if not ResourceLoader.exists(coverage_path):
							push_error("Atlas repaint requires its baked enamel coverage mask: " + coverage_path)
							continue
						coverage = load(coverage_path)
					var source: Array = defaults[channel]
					shared[original] = _repaint_material(original, coverage, tint,
						Color(source[0], source[1], source[2], 1).linear_to_srgb())
				else:
					var material := original.duplicate() as StandardMaterial3D
					material.albedo_color = tint
					shared[original] = material
			mesh.set_surface_override_material(index, shared[original])

func _repaint_material(original: StandardMaterial3D, coverage: Texture2D, tint: Color, authored: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT
	material.set_shader_parameter("surface_albedo", original.albedo_texture)
	material.set_shader_parameter("surface_orm", original.metallic_texture)
	material.set_shader_parameter("surface_coverage", coverage)
	material.set_shader_parameter("coverage_enabled", coverage != null)
	material.set_shader_parameter("surface_ao", original.ao_texture)
	material.set_shader_parameter("surface_normal", original.normal_texture)
	material.set_shader_parameter("surface_emission", original.emission_texture)
	material.set_shader_parameter("albedo_tint", original.albedo_color)
	material.set_shader_parameter("roughness_factor", original.roughness)
	material.set_shader_parameter("metallic_factor", original.metallic)
	material.set_shader_parameter("ao_enabled", original.ao_enabled)
	material.set_shader_parameter("ao_light_affect", original.ao_light_affect)
	material.set_shader_parameter("normal_strength", original.normal_scale if original.normal_enabled else 0.0)
	material.set_shader_parameter("emission_enabled", original.emission_enabled)
	material.set_shader_parameter("emission_texture_enabled", original.emission_texture != null)
	material.set_shader_parameter("emission_color", original.emission)
	material.set_shader_parameter("emission_energy", original.emission_energy_multiplier)
	material.set_shader_parameter("emission_add", original.emission_operator == BaseMaterial3D.EMISSION_OP_ADD)
	material.set_shader_parameter("paint", tint)
	material.set_shader_parameter("authored_paint", authored)
	return material

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
	if turret != null:
		_show_turret(view, delta)
	if legs != null:
		legs.observe_state(view)
		legs.set_process(not view.eliminated)
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
	if _turret_yaw != null: _collect(_turret_yaw, groups.weapon)
	if nodes.has("DriveLeft"): _collect(nodes.DriveLeft, groups.drive_left)
	if nodes.has("DriveRight"): _collect(nodes.DriveRight, groups.drive_right)
	if drives != null:
		for mesh: MeshInstance3D in drives.find_children("*", "MeshInstance3D", true, false):
			var label := str(mesh.name)
			(groups.drive_left if "Left" in label or "_L_" in label else groups.drive_right).append(mesh)
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
	if turret_effects != null: turret_effects.clear_effects()
	_turret_shown = false
	if legs != null: legs.reset_feet()
