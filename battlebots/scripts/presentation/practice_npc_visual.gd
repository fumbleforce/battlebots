class_name PracticeNpcVisual
extends Node3D
## Three Blender-authored industrial silhouettes, driven by accepted BotView only.
const MODELS := {
	"wedge":preload("res://assets/models/practice_npcs/wedge.glb"),
	"bruiser":preload("res://assets/models/practice_npcs/bruiser.glb"),
	"sentry":preload("res://assets/models/practice_npcs/sentry.glb")}
var variant := "wedge"
var nodes: Dictionary = {}
var _rest: Dictionary = {}
var _groups := {"weapon":[], "drive_left":[], "drive_right":[]}
var _previous_pose := Transform3D.IDENTITY
var _observed := false
var _spin := 0.0
var _travel := 0.0
var gun_effects: MinigunEffects
var gun_mount: Node3D

func assemble(style: String, size: Vector3) -> void:
	variant = style if MODELS.has(style) else "wedge"
	var model: Node3D = MODELS[variant].instantiate()
	add_child(model)
	scale = size / Vector3(1.6, 0.5, 2.0)
	for node: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		nodes[str(node.name)] = node
		_rest[node] = node.transform
		if str(node.name).begins_with("Detach_Weapon"): _groups.weapon.append(node)
		elif str(node.name).begins_with("Detach_Drive_Left"): _groups.drive_left.append(node)
		elif str(node.name).begins_with("Detach_Drive_Right"): _groups.drive_right.append(node)
	if variant == "sentry":
		gun_mount = Node3D.new()
		gun_mount.name = "GunMount"
		gun_mount.position = Vector3(.66, .22, -.42)
		add_child(gun_mount)
		for label: String in ["Detach_Weapon_Receiver", "Detach_Weapon_Barrels"]:
			nodes[label].reparent(gun_mount, true)
		var muzzle := Node3D.new()
		muzzle.position = Vector3(0, .05, -1.30)
		gun_mount.add_child(muzzle)
		gun_effects = MinigunEffects.new()
		add_child(gun_effects)
		gun_effects.configure(nodes.get("Detach_Weapon_Barrels"), muzzle, BotScale.from_size(size), gun_mount)

func component_meshes() -> Dictionary:
	return _groups

func show_state(view: BotView, delta: float) -> void:
	if view == null: return
	if gun_effects != null: gun_effects.show_state(view, delta, true)
	if not _observed:
		_previous_pose = view.pose
		_observed = true
	var movement := view.pose.origin - _previous_pose.origin
	if movement.length() < 3.0 and not view.eliminated:
		_travel += movement.dot(-view.pose.basis.z) / (0.255 * scale.y)
	_previous_pose = view.pose
	for label: String in nodes:
		if "_Wheel" in label:
			var node: MeshInstance3D = nodes[label]
			var rest: Transform3D = _rest[node]
			node.basis = Basis(Vector3.RIGHT, -_travel) * rest.basis
	if nodes.has("Detach_Weapon_Spinner"):
		_spin += view.weapon_charge_fraction * delta * 43.0 if not view.eliminated else 0.0
		var node: MeshInstance3D = nodes.Detach_Weapon_Spinner
		var rest: Transform3D = _rest[node]
		node.basis = Basis(Vector3.RIGHT, _spin) * rest.basis
	if nodes.has("Detach_Weapon_Lifter"):
		var node: MeshInstance3D = nodes.Detach_Weapon_Lifter
		var rest: Transform3D = _rest[node]
		node.basis = Basis(Vector3.RIGHT, -view.weapon_charge_fraction * 0.8) * rest.basis
