class_name MvpWeaponVisual
extends Node3D
## Primitive cosmetic placeholder. Never adds collision or awards hits.
## Lifter/flipper arm: its lip rests on the ground in front of the hull (found
## with a presentation-only ray, so it follows uneven terrain), trembles harder
## as the charge builds, snaps violently past vertical on release, holds, then
## drops back onto the ground.
const LIFTER_LAUNCH_ANGLE := deg_to_rad(100.0)
## Deepest the arm may hang when no ground is found below its lip (airborne).
const LIFTER_MAX_DROP_ANGLE := deg_to_rad(40.0)
## Lip clearance above the ground so the arm does not z-fight the floor (m).
const LIFTER_GROUND_CLEARANCE := 0.03
## Loaded-spring tremble at full charge.
const LIFTER_TREMBLE_AMPLITUDE := deg_to_rad(1.5)
const LIFTER_TREMBLE_RATE := 70.0
## Cooldown starts at 3 s on launch; the arm stays extended for its first 0.3 s.
const LIFTER_EXTENDED_UNTIL_COOLDOWN := 2.7
const LIFTER_SNAP_RATE := 90.0
const LIFTER_GROUND_FOLLOW_RATE := 25.0
const LIFTER_DROP_RATE := 8.0
var kind := ""
## Forward reach of the lifter arm from its hinge, in the mechanism frame.
var _lifter_reach := -1.0
var _lifter_time := 0.0
var mechanism: Node3D
var gun_effects: MinigunEffects
var metal := StandardMaterial3D.new()
var accent := StandardMaterial3D.new()

func assemble(weapon: String, size: Vector3) -> void:
	# Author in the original meter frame, including fixed blade/arm dimensions.
	# Multiply existing scale so Sawblade's art-scale compensation is preserved.
	var geometry_scale := BotScale.from_size(size)
	size /= geometry_scale
	scale *= geometry_scale
	kind = weapon
	metal.albedo_color = Color(0.28, 0.32, 0.37)
	metal.metallic = 0.75
	metal.roughness = 0.4
	accent.albedo_color = Color(1.0, 0.73, 0.15)
	accent.metallic = 0.5
	mechanism = Node3D.new()
	mechanism.name = "Mechanism"
	add_child(mechanism)
	if kind == "minigun":
		var donor: Node3D = load("res://assets/models/scorpion_runtime/scorpion.glb").instantiate()
		var mount: Node3D = donor.find_child("GunMount", true, false)
		mount.owner = null
		for child: Node in mount.find_children("*", "", true, false): child.owner = null
		mount.reparent(mechanism, false)
		var rotor: Node3D = mount.find_child("GunRotor", true, false)
		donor.free()
		var muzzle := Node3D.new()
		add_child(muzzle)
		muzzle.position = ScorpionGeometry.GUN_MUZZLE
		gun_effects = MinigunEffects.new()
		add_child(gun_effects)
		gun_effects.configure(rotor, muzzle, geometry_scale, mount)
	elif kind == "vertical_spinner":
		mechanism.position = Vector3(0, 0.14, -size.z * 0.5 - 0.1)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.36
		disc.bottom_radius = 0.36
		disc.height = 0.18
		disc.radial_segments = 20
		var rotor := _mesh(mechanism, disc, Vector3.ZERO, metal)
		rotor.rotation.z = PI / 2
		_box(mechanism, Vector3(0.23, 0.84, 0.12), Vector3.ZERO, accent)
		_box(mechanism, Vector3(0.23, 0.12, 0.84), Vector3.ZERO, accent)
		for side: int in [-1, 1]:
			_box(self, Vector3(0.12, 0.22, 0.5), Vector3(side * 0.3, 0.04, -size.z * 0.5), metal)
	elif kind == "horizontal_spinner":
		mechanism.position = Vector3(0, 0, -size.z * 0.5 - 0.2)
		var disc := CylinderMesh.new()
		disc.top_radius = size.x * 0.65
		disc.bottom_radius = disc.top_radius
		disc.height = 0.18
		disc.radial_segments = 32
		_mesh(mechanism, disc, Vector3.ZERO, metal)
		_box(mechanism, Vector3(disc.top_radius * 2, 0.24, 0.12), Vector3.ZERO, accent)
		_box(mechanism, Vector3(0.12, 0.24, disc.top_radius * 2), Vector3.ZERO, accent)
		_box(self, Vector3(0.24, 0.2, 0.55), Vector3(0, 0, -size.z * 0.5 + 0.05), metal)
	elif kind == "saw":
		mechanism.position = Vector3(0, 0.1, -size.z * 0.5 - 0.4)
		var disc := CylinderMesh.new()
		disc.top_radius = 0.28
		disc.bottom_radius = 0.28
		disc.height = 0.16
		disc.radial_segments = 24
		var blade := _mesh(mechanism, disc, Vector3.ZERO, metal)
		blade.rotation.z = PI / 2.0
		for tooth: int in range(12):
			var angle := TAU * tooth / 12.0
			var tooth_mesh := BoxMesh.new()
			tooth_mesh.size = Vector3(0.16, 0.08, 0.08)
			var tip := _mesh(mechanism, tooth_mesh, Vector3(0, cos(angle), sin(angle)) * 0.28, accent)
			tip.rotation.x = angle
		for side: int in [-1, 1]:
			_box(self, Vector3(0.1, 0.14, 0.6), Vector3(side * 0.16, 0.1, -size.z * 0.5 - 0.15), metal)
	elif kind == "hammer":
		mechanism.position = Vector3(0, size.y * 0.5, -size.z * 0.5 + 0.15)
		mechanism.rotation.x = PI / 6.0
		_box(mechanism, Vector3(0.1, 0.1, 1.2), Vector3(0, 0, -0.6), metal)
		_box(mechanism, Vector3(0.34, 0.24, 0.24), Vector3(0, 0, -1.2), accent)
		_box(self, Vector3(0.4, 0.18, 0.22), mechanism.position, metal)
	elif kind == "lifter":
		mechanism.position = Vector3(0, -0.12, -size.z * 0.5 + 0.2)
		for side: int in [-1, 1]:
			_box(mechanism, Vector3(0.16, 0.12, 1.0), Vector3(side * size.x * 0.3, 0, -0.45), accent)
		_box(mechanism, Vector3(size.x * 0.7, 0.12, 0.14), Vector3(0, 0, -0.88), metal)
		_box(mechanism, Vector3(size.x * 0.7, 0.16, 0.18), Vector3.ZERO, metal)

## Arm angle (negative = down) that rests the lip on the ground below it. The
## reach is measured from the arm's actual meshes, so swapped attachments such
## as Atlas's forged lifter rest correctly too.
func _lifter_ground_angle() -> float:
	if _lifter_reach < 0.0:
		_lifter_reach = 0.0
		var to_mechanism := mechanism.global_transform.affine_inverse()
		for node: Node in mechanism.find_children("*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			var bounds := to_mechanism * part.global_transform * part.get_aabb()
			_lifter_reach = maxf(_lifter_reach, -bounds.position.z)
	if _lifter_reach <= 0.0 or not is_inside_tree():
		return 0.0
	var frame := (mechanism.get_parent() as Node3D).global_transform
	var up := frame.basis.y.normalized()
	var forward := -frame.basis.z.normalized()
	var reach := _lifter_reach * mechanism.global_basis.get_scale().z
	var pivot := mechanism.global_position
	var lip := pivot + forward * reach
	var query := PhysicsRayQueryParameters3D.create(lip + up * reach, lip - up * reach * 2.0, BaselineConfig.WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -LIFTER_MAX_DROP_ANGLE
	var drop := (pivot - Vector3(hit.position)).dot(up) - LIFTER_GROUND_CLEARANCE
	return -asin(clampf(drop / reach, 0.0, sin(LIFTER_MAX_DROP_ANGLE)))

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_mesh(parent, mesh, at, material)

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = at
	parent.add_child(visual)
	return visual

func show_state(view: BotView, delta: float) -> void:
	if gun_effects != null: gun_effects.show_state(view, delta, true)
	var disabled := view.eliminated or view.weapon_state == "disabled"
	accent.albedo_color = Color(0.2, 0.22, 0.24) if disabled else Color(1.0, 0.73, 0.15)
	if kind == "vertical_spinner":
		if not disabled:
			mechanism.rotation.x = wrapf(mechanism.rotation.x + view.weapon_charge_fraction * delta * 24, -PI, PI)
	elif kind == "horizontal_spinner":
		if not disabled:
			mechanism.rotation.y = wrapf(mechanism.rotation.y + view.weapon_charge_fraction * delta * 24, -PI, PI)
	elif kind == "saw":
		if not disabled and view.weapon_state == "active":
			mechanism.rotation.x = wrapf(mechanism.rotation.x + delta * 36, -PI, PI)
	elif kind == "hammer":
		var angle := PI / 6.0
		if view.weapon_state == "windup":
			angle = lerpf(PI / 6.0, PI / 2.0, view.weapon_charge_fraction)
		elif view.weapon_state == "strike":
			angle = -PI / 6.0
		elif view.weapon_cooldown > 0:
			angle = lerpf(-PI / 6.0, PI / 6.0, clampf(1.0 - view.weapon_cooldown / 1.4, 0, 1))
		mechanism.rotation.x = 0.0 if disabled else angle
	elif kind == "lifter":
		_lifter_time += delta
		var angle := _lifter_ground_angle()
		var rate := LIFTER_GROUND_FOLLOW_RATE
		if view.weapon_state == "launch" or view.weapon_cooldown > LIFTER_EXTENDED_UNTIL_COOLDOWN:
			angle = LIFTER_LAUNCH_ANGLE
			rate = LIFTER_SNAP_RATE
		elif mechanism.rotation.x > angle + LIFTER_TREMBLE_AMPLITUDE:
			rate = LIFTER_DROP_RATE
		else:
			angle += sin(_lifter_time * LIFTER_TREMBLE_RATE) * LIFTER_TREMBLE_AMPLITUDE * view.weapon_charge_fraction
		if disabled:
			angle = _lifter_ground_angle()
		mechanism.rotation.x = lerpf(mechanism.rotation.x, angle, 1 - exp(-delta * rate))
