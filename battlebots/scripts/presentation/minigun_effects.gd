class_name MinigunEffects
extends Node3D
## Accepted shot snapshots only; muzzle/tracer/casing presentation never awards hits.
const TRACERS := 8
const CASINGS := 16
var rotor: Node3D
var muzzle: Node3D
var flash: MeshInstance3D
var light: OmniLight3D
var shot_count := 0
var gun_mount: Node3D
var _mount_rest := Transform3D.IDENTITY
var _seen := -1
var _tick := -1
var _scale := 1.0
var _flash_age := 1.0
var _tracers: Array[Dictionary] = []
var _casings: Array[Dictionary] = []

func configure(barrels: Node3D, socket: Node3D, geometry_scale: float, mount: Node3D = null) -> void:
	rotor = barrels
	muzzle = socket
	_scale = geometry_scale
	gun_mount = mount
	if gun_mount != null: _mount_rest = gun_mount.transform
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.75, 0.25)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.45, 0.055)
	hot.emission_energy_multiplier = 7.0
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("bf9342")
	brass.metallic = 0.85
	brass.roughness = 0.26
	for index: int in TRACERS:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.009 * _scale
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 1.0
		mesh.radial_segments = 6
		var node := _mesh(mesh, hot)
		_tracers.append({"node":node, "age":1.0})
	for index: int in CASINGS:
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.012 * _scale
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.052 * _scale
		mesh.radial_segments = 8
		var node := _mesh(mesh, brass)
		_casings.append({"node":node, "age":2.0, "velocity":Vector3.ZERO, "spin":Vector3.ZERO})
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.08 * _scale
	cone.height = 0.4 * _scale
	cone.radial_segments = 7
	flash = _mesh(cone, hot)
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.52, 0.14)
	light.omni_range = 2.8 * _scale
	light.light_energy = 0.0
	add_child(light)
	light.top_level = true

func _mesh(shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.hide()
	return node

func show_state(view: BotView, delta: float, primary := false) -> void:
	if gun_mount != null:
		var rotation := Basis(Vector3.RIGHT, view.gun_pitch)
		var pivot := ScorpionGeometry.GUN_PIVOT
		gun_mount.transform = Transform3D(rotation, pivot - rotation * pivot) * _mount_rest
	var spool := view.weapon_charge_fraction if primary else view.secondary_charge
	if is_instance_valid(rotor) and not view.eliminated:
		rotor.rotate_z(-delta * spool * 65.0)
	if _seen < 0 or view.server_tick < _tick or view.shot_sequence < _seen:
		_seen = view.shot_sequence
		clear_effects()
	elif view.shot_sequence > _seen:
		_seen = view.shot_sequence
		if not view.eliminated and view.server_tick - view.last_shot_tick <= 12:
			_fire(view.last_shot_from, view.last_shot_to, view.pose)
	_tick = view.server_tick
	if view.eliminated: clear_effects()
	_flash_age += delta
	flash.visible = _flash_age < 0.045
	light.light_energy = maxf(0.0, 1.0 - _flash_age / 0.045) * 3.5
	for tracer: Dictionary in _tracers:
		tracer.age += delta
		tracer.node.visible = tracer.age < 0.065
	for casing: Dictionary in _casings:
		casing.age += delta
		casing.node.visible = casing.age < 0.75
		if casing.node.visible:
			casing.velocity.y -= 9.8 * delta
			casing.node.global_position += Vector3(casing.velocity) * delta
			casing.node.rotation += Vector3(casing.spin) * delta

func _fire(from: Vector3, to: Vector3, pose: Transform3D) -> void:
	var direction := to - from
	if direction.length_squared() < 0.0001: return
	var distance := direction.length()
	direction /= distance
	var right := direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	var frame := Basis(right, direction, right.cross(direction))
	var tracer: Dictionary = _tracers[shot_count % TRACERS]
	tracer.age = 0.0
	tracer.node.global_transform = Transform3D(frame.scaled_local(Vector3(1, distance, 1)), (from + to) * 0.5)
	flash.global_transform = Transform3D(frame, from + direction * 0.12 * _scale)
	light.global_position = from
	_flash_age = 0.0
	var casing: Dictionary = _casings[shot_count % CASINGS]
	casing.age = 0.0
	casing.node.global_transform = Transform3D(pose.basis, from + pose.basis.z * 0.45 * _scale)
	casing.velocity = (pose.basis.x * 1.3 + Vector3.UP * 0.8) * _scale
	casing.spin = Vector3(9, 15, 4)
	shot_count += 1

func clear_effects() -> void:
	_flash_age = 1.0
	for tracer: Dictionary in _tracers: tracer.age = 1.0
	for casing: Dictionary in _casings: casing.age = 2.0
	if is_instance_valid(flash): flash.hide()
	if is_instance_valid(light): light.light_energy = 0.0
