class_name CombatImpactVisual
extends Node3D
## Disposable confirmed-contact decoration. No collision, gameplay state or event inference.
const MAX_SPARKS := 64
const MAX_FRAGMENTS := 20
const KINDS := ["vertical_spinner", "horizontal_spinner", "saw", "hammer", "lifter", "ram"]
const GOLDEN_ANGLE := 2.39996323
var _sparks: Array[Dictionary] = []
var _fragments: Array[Dictionary] = []
var _serial := 0
var _spark_mesh: BoxMesh
var _fragment_mesh: BoxMesh

func _ready() -> void:
	add_to_group(&"combat_impact_visuals")

func spawn_impact(position: Vector3, normal: Vector3, kind: String, damage: float) -> void:
	if not position.is_finite() or not normal.is_finite() or not is_finite(damage) or damage < 0 or kind not in KINDS:
		return
	# Scale before normalization so finite, unusually large normals cannot overflow.
	var extent := maxf(absf(normal.x), maxf(absf(normal.y), absf(normal.z)))
	var outward := (normal / extent).normalized() if extent > 0.000001 else Vector3.UP
	var tangent := outward.cross(Vector3.UP if absf(outward.y) < 0.9 else Vector3.RIGHT).normalized()
	var bitangent := outward.cross(tangent)
	var spark_total := 6 + int(ceil(minf(damage, 50.0) * 0.2))
	var fragment_total := clampi(int(ceil(minf(damage, 40.0) / 8.0)), 1, 5) if damage > 0 else 0
	for index: int in spark_total:
		_emit(_sparks, MAX_SPARKS, false, position, outward, tangent, bitangent, index, spark_total)
	for index: int in fragment_total:
		_emit(_fragments, MAX_FRAGMENTS, true, position, outward, tangent, bitangent, index, fragment_total)
	trim_fragments()

func trim_fragments() -> void:
	# Destruction panels share the existing twenty-piece client debris budget.
	var budget := MAX_FRAGMENTS
	for effect: Node in get_tree().get_nodes_in_group(&"bot_destruction_visuals"):
		if effect.active and effect.effect_age < 2.1: budget -= 8
	for particle: Dictionary in _fragments:
		if not particle.active: continue
		if budget > 0:
			budget -= 1
		else:
			particle.active = false
			particle.mesh.hide()

func spark_count() -> int:
	return _active_count(_sparks)

func fragment_count() -> int:
	return _active_count(_fragments)

func _active_count(pool: Array[Dictionary]) -> int:
	var count := 0
	for particle: Dictionary in pool:
		if particle.active: count += 1
	return count

func clear_effects() -> void:
	for pool: Array[Dictionary] in [_sparks, _fragments]:
		for particle: Dictionary in pool:
			particle.active = false
			particle.mesh.hide()

func _acquire(pool: Array[Dictionary], capacity: int, fragment: bool) -> Dictionary:
	for particle: Dictionary in pool:
		if not particle.active: return particle
	if pool.size() < capacity:
		var node := MeshInstance3D.new()
		node.name = ("Fragment" if fragment else "Spark") + str(pool.size())
		node.mesh = _shared_mesh(fragment)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.top_level = true
		var particle := {"mesh": node, "active": false, "age": 0.0, "lifetime": 0.0,
			"origin": Vector3.ZERO, "velocity": Vector3.ZERO, "spin": Vector3.ZERO,
			"basis": Basis.IDENTITY, "serial": 0, "fragment": fragment}
		pool.append(particle)
		return particle
	var oldest: Dictionary = pool[0]
	for particle: Dictionary in pool:
		if particle.serial < oldest.serial: oldest = particle
	return oldest

func _emit(pool: Array[Dictionary], capacity: int, fragment: bool, origin: Vector3,
		outward: Vector3, tangent: Vector3, bitangent: Vector3, index: int, total: int) -> void:
	var particle := _acquire(pool, capacity, fragment)
	var phase := float(index) * GOLDEN_ANGLE
	var spread := 0.25 + 0.6 * float(index + 1) / float(total)
	var direction := (outward + (tangent * cos(phase) + bitangent * sin(phase)) * spread).normalized()
	_serial += 1
	particle.serial = _serial
	particle.active = true
	particle.age = 0.0
	particle.lifetime = (0.95 + float(index % 3) * 0.2) if fragment else (0.28 + float(index % 4) * 0.06)
	particle.origin = origin
	particle.velocity = direction * ((0.9 + float(index % 3) * 0.3) if fragment else (2.2 + float(index % 4) * 0.35))
	particle.spin = Vector3(3.0 + index, 2.0, 1.5) if fragment else Vector3.ZERO
	particle.basis = Basis.looking_at(direction, tangent)
	particle.mesh.global_transform = Transform3D(particle.basis, origin)
	particle.mesh.show()

func _process(delta: float) -> void:
	if not is_finite(delta) or delta <= 0: return
	for pool: Array[Dictionary] in [_sparks, _fragments]:
		for particle: Dictionary in pool:
			if not particle.active: continue
			particle.age += delta
			if particle.age >= particle.lifetime:
				particle.active = false
				particle.mesh.hide()
				continue
			var age: float = particle.age
			var gravity := Vector3.DOWN * (3.5 if particle.fragment else 1.8)
			var at: Vector3 = particle.origin + particle.velocity * age + gravity * (0.5 * age * age)
			var rotation: Basis = particle.basis * Basis.from_euler(particle.spin * age)
			# Shrink only near expiry; opaque tiny meshes avoid blended screen flashes.
			var shrink := minf(1.0, (particle.lifetime - age) / 0.15)
			particle.mesh.global_transform = Transform3D(rotation.scaled(Vector3.ONE * shrink), at)

func _shared_mesh(fragment: bool) -> BoxMesh:
	if fragment and _fragment_mesh != null: return _fragment_mesh
	if not fragment and _spark_mesh != null: return _spark_mesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.065, 0.035, 0.08) if fragment else Vector3(0.035, 0.035, 0.18)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.38, 0.4, 0.43) if fragment else Color(1.0, 0.85, 0.4)
	material.metallic = 0.65 if fragment else 0.0
	material.roughness = 0.7
	if not fragment:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	if fragment: _fragment_mesh = mesh
	else: _spark_mesh = mesh
	return mesh
