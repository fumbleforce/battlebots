class_name ScorpionVisual
extends Node3D
## Authored modular Scorpion. Authority uses the same articulated weapon geometry.
var model: Node3D
var nodes: Dictionary = {}
var walker_legs: ScorpionLegs
var gun_effects: MinigunEffects
var diesel_exhaust: ScorpionDieselExhaust
var fallback_weapon: MvpWeaponVisual
var kind := "hammer"
var hammer_fraction := 0.0
## Trebuchet windup (#17), presentation only: the first COCK_SHARE of the
## windup draws the tail up and back by COCK (radians per joint: base, upper,
## fore, head); the rest whips the joints through in sequence, each starting
## WHIP_STAGGER later, so the head lands on the authoritative strike pose at
## the strike tick. The authority sweep and strike pose are unchanged.
const COCK := Vector4(0.45, 0.30, -0.45, -0.70)
const COCK_SHARE := 0.6
const WHIP_STAGGER := 0.08
## The head overshoots the strike angle by this share as it lands.
const HEAD_OVERSHOOT := 0.12
var _size := Vector3.ZERO

static func enabled(draft: Dictionary) -> bool:
	return draft.get("parts", {}).get("chassis") == "scorpion_hex"

func assemble(draft: Dictionary, size: Vector3) -> void:
	_size = size
	scale = Vector3.ONE * BotScale.from_size(size)
	model = load("res://assets/models/scorpion_runtime/scorpion.glb").instantiate()
	add_child(model)
	for node: Node in model.find_children("*", "Node3D", true, false): nodes[str(node.name)] = node
	kind = draft.parts.weapon
	var tail: Node3D = nodes.TailBase
	tail.visible = kind == "hammer"
	var has_gun: bool = kind == "minigun" or draft.parts.utility == "minigun_pod"
	nodes.GunMount.visible = has_gun
	if kind not in ["hammer", "minigun"]:
		fallback_weapon = MvpWeaponVisual.new()
		add_child(fallback_weapon)
		fallback_weapon.scale = Vector3.ONE / scale
		fallback_weapon.position = ScorpionGeometry.fallback_socket(size) / scale
		fallback_weapon.assemble(kind, size)
		_assemble_fallback_mount()
	walker_legs = ScorpionLegs.new()
	add_child(walker_legs)
	walker_legs.scale = Vector3.ONE / scale
	walker_legs.assemble(size, null, {})
	diesel_exhaust = ScorpionDieselExhaust.new()
	add_child(diesel_exhaust)
	diesel_exhaust.configure(nodes, BotScale.from_size(size))
	_apply_paint(draft)
	if has_gun:
		var muzzle := Node3D.new()
		add_child(muzzle)
		muzzle.position = Vector3(0.66, 0.27, -1.72)
		gun_effects = MinigunEffects.new()
		add_child(gun_effects)
		gun_effects.configure(nodes.GunRotor, muzzle, BotScale.from_size(size), nodes.GunMount)

func _assemble_fallback_mount() -> void:
	# These source-metre adapter arms join the underside of the hexagonal hull
	# to the lowered tool socket. The main tail and gun keep their own mounts.
	var dark := _mount_material("BlackenedSteel")
	var paint := _mount_material("OrangeCeramic")
	for side: int in [-1, 1]:
		var upper := Vector3(side * 0.24, 0.34, -0.67)
		var lower := Vector3(side * 0.24, 0, -0.94)
		var arm := BoxMesh.new()
		arm.size = Vector3(0.12, upper.distance_to(lower), 0.13)
		var visual := _mount_piece(arm, (upper + lower) * 0.5, dark)
		visual.basis = Basis(Quaternion(Vector3.UP, (upper - lower).normalized()))
		var cap := CylinderMesh.new()
		cap.top_radius = 0.085
		cap.bottom_radius = 0.085
		cap.height = 0.08
		cap.radial_segments = 16
		visual = _mount_piece(cap, lower, paint)
		visual.rotation.z = PI * 0.5
	var bridge := BoxMesh.new()
	bridge.size = Vector3(0.52, 0.12, 0.32)
	_mount_piece(bridge, Vector3(0, 0, -0.94), dark)

func _mount_material(label: String) -> Material:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(index)
			if material != null and label in material.resource_name: return material
	return null

func _mount_piece(mesh: PrimitiveMesh, at: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = "ToolSocketAdapter"
	mesh.material = material
	visual.mesh = mesh
	visual.position = at
	fallback_weapon.add_child(visual)
	return visual

func _apply_paint(draft: Dictionary) -> void:
	var paint_id: String = draft.cosmetics.get("paint", "orange")
	if paint_id == "orange": return
	var tint: Color = GarageBotPreview.PAINTS.get(paint_id, Color.WHITE)
	var shared := {}
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for index: int in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			if original == null or not "orange" in original.resource_name.to_lower(): continue
			if not shared.has(original):
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_color = tint
				shared[original] = material
			mesh.set_surface_override_material(index, shared[original])

func component_meshes() -> Dictionary:
	var groups := walker_legs.component_meshes()
	if nodes.TailBase.visible: _collect(nodes.TailBase, groups.weapon)
	if nodes.GunMount.visible: _collect(nodes.GunMount, groups.weapon)
	if fallback_weapon != null: _collect(fallback_weapon, groups.weapon)
	return groups

func _collect(root: Node3D, meshes: Array) -> void:
	if not root.visible: return
	if root is MeshInstance3D: meshes.append(root)
	for child: Node in root.get_children():
		if child is Node3D: _collect(child, meshes)

func set_hammer_fraction(fraction: float) -> void:
	hammer_fraction = clampf(fraction, 0.0, 1.0)
	_pose_hammer(ScorpionGeometry.hammer_angles(hammer_fraction), hammer_fraction)

## Joint angles (base, upper, fore, head) and telescopic extension fraction.
func _pose_hammer(angles: Vector4, extension: float) -> void:
	for index: int in 4:
		nodes[["TailBase", "TailUpper", "TailFore", "HammerHead"][index]].rotation.x = angles[index]
	if nodes.has("TailExtension"):
		nodes.TailExtension.position = ScorpionGeometry.HEAD_PIVOT - ScorpionGeometry.TAIL_FORE \
			+ ScorpionGeometry.hammer_extension_offset(extension)

## Windup pose at charge 0..1: cock back, then a staggered whip to the strike.
func _windup_pose(charge: float) -> void:
	if charge < COCK_SHARE:
		hammer_fraction = 0.0
		_pose_hammer(COCK * smoothstep(0.0, 1.0, charge / COCK_SHARE), 0.0)
		return
	var whip := (charge - COCK_SHARE) / (1.0 - COCK_SHARE)
	var strike := ScorpionGeometry.hammer_angles(1.0)
	var angles := Vector4.ZERO
	for joint: int in 4:
		var t := clampf((whip - joint * WHIP_STAGGER) / (1.0 - 3.0 * WHIP_STAGGER), 0.0, 1.0)
		# Accelerating swing; the head snaps past the strike angle as it lands.
		var target: float = strike[joint] * (1.0 + HEAD_OVERSHOOT * sin(t * PI) if joint == 3 else 1.0)
		angles[joint] = lerpf(COCK[joint], target, t * t)
	hammer_fraction = whip
	_pose_hammer(angles, whip)

func show_state(view: BotView, delta: float) -> void:
	if kind == "hammer":
		var fraction := 0.0
		if view.weapon_state == "windup" and not view.eliminated:
			_windup_pose(view.weapon_charge_fraction)
			fraction = -1.0
		elif view.weapon_state == "strike": fraction = 1.0
		elif view.weapon_cooldown > 0.0: fraction = 1.0 - smoothstep(0.10, 1.0, 1.0 - view.weapon_cooldown / 1.4)
		if view.eliminated or view.weapon_state == "disabled": fraction = hammer_fraction
		if fraction >= 0.0: set_hammer_fraction(fraction)
	if fallback_weapon != null: fallback_weapon.show_state(view, delta)
	if gun_effects != null: gun_effects.show_state(view, delta, kind == "minigun")
	diesel_exhaust.show_state(view, global_transform, delta, walker_legs.terrain)
	walker_legs.observe_state(view)
	walker_legs.set_process(not view.eliminated)

func reset_observation() -> void:
	walker_legs.reset_feet()
	diesel_exhaust.reset_observation()
	if gun_effects != null: gun_effects.clear_effects()
