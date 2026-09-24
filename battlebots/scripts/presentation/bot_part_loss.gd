extends Node3D
## Progressive part loss (#72): a bot being beaten sheds its parts as physics
## debris while it still fights. Works on any visual with no authoring: the
## model's component meshes (weapon, drive sides) and its smaller hull panels,
## grouped by the face they sit on, are split into spatial clusters. A cluster
## comes off whenever its zone's replicated HP fraction falls through a
## threshold (data/destruction.json parts), so every client, spectator and
## reconnecting peer loses the same number of parts. Accepted combat events
## only choose which cluster goes (the one nearest the hit) and how: saw and
## grinder hits sever parts with a glowing seam, anything else knocks them off.
## Snapshot-driven and cosmetic: nothing here touches authoritative state.
const TUNING := preload("res://scripts/core/destruction_tuning.gd")
const PIECES := preload("res://scripts/presentation/wreck_pieces.gd")
const PIECE := preload("res://scripts/presentation/wreck_piece.gd")
const GROUP := &"bot_part_loss"
const FACES := ["front", "rear", "left", "right", "top", "underside"]
const COMPONENTS := ["weapon", "drive_left", "drive_right"]
## Hull panels on each face are split into this many clusters.
const FACE_CLUSTERS := 4
## A detached cluster's collision hull uses every mesh corner up to this many
## meshes, then just the cluster's box.
const HULL_CORNER_MESHES := 12
## A parent with at most this many mesh children is treated as one assembly.
const ASSEMBLY_MESHES := 3

var entity_id := 0
## pool (zone name) -> Array of {meshes, centre, bounds, lost}
var pools: Dictionary = {}
var _geometry_scale := 1.0
var _bounds := AABB()
var _pose := Transform3D.IDENTITY
var _clock := 0.0
var _hits: Array[Dictionary] = []
var _observed := false
var _lost_by_zone: Dictionary = {}
var _core_lost := 0
var _pieces_root: Node3D

func _ready() -> void:
	add_to_group(GROUP)

## visual_root is the bot's presentation (its frame is the bot frame);
## components is the visual's component_meshes() grouping.
func configure(visual_root: Node3D, components: Dictionary, size: Vector3, entity: int) -> void:
	restore()
	pools.clear()
	entity_id = entity
	_geometry_scale = BotScale.from_size(size)
	_pose = visual_root.global_transform
	var tuning: RefCounted = TUNING.settings()
	var captured := PIECES.capture(visual_root, _pose)
	_bounds = PIECES.bounds_of(captured)
	var claimed := {}
	for zone: String in COMPONENTS:
		var meshes: Array[Dictionary] = []
		for mesh: Variant in components.get(zone, []):
			for entry: Dictionary in captured:
				if entry.source == mesh:
					meshes.append(entry)
					claimed[mesh] = true
		pools[zone] = _clusters(meshes, tuning.thresholds.component.size())
	var volume := maxf(_bounds.size.x * _bounds.size.y * _bounds.size.z, 0.0001)
	var faces := {}
	for face: String in FACES:
		faces[face] = [] as Array[Dictionary]
	for entry: Dictionary in captured:
		if claimed.has(entry.source) or not _detachable(entry):
			continue
		var box: AABB = entry.aabb
		if box.size.x * box.size.y * box.size.z > volume * float(tuning.parts.hull_share):
			continue
		faces[face_of(box.get_center(), _bounds)].append(entry)
	for face: String in FACES:
		pools[face] = _clusters(faces[face], FACE_CLUSTERS)

## Only surfaces the cut shader can stand in for: this keeps effect meshes
## (flames, beams, glows) on the bot.
func _detachable(entry: Dictionary) -> bool:
	var source: MeshInstance3D = entry.source
	for surface: int in entry.mesh.get_surface_count():
		if PIECES.material_for(source.get_active_material(surface)) == null:
			return false
	return entry.mesh.get_surface_count() > 0

## MvpBot.zone_at's face rule on the visual's bounds.
static func face_of(point: Vector3, bounds: AABB) -> String:
	var local := point - bounds.get_center()
	var half := (bounds.size * 0.5).max(Vector3.ONE * 0.0001)
	if local.y > half.y * 0.8: return "top"
	if local.y < -half.y * 0.8: return "underside"
	if absf(local.x) / half.x > absf(local.z) / half.z:
		return "left" if local.x < 0 else "right"
	return "front" if local.z < 0 else "rear"

## Groups meshes by assembly (their parent pivot) so a wheel leaves whole,
## then splits the assemblies along the pool's longest axis into count clusters.
func _clusters(entries: Array[Dictionary], count: int) -> Array[Dictionary]:
	var assemblies := {}
	for entry: Dictionary in entries:
		# A pivot holding a few surfaces (a wheel, a leg link) is one assembly;
		# loose meshes under a shared root each stand alone.
		var parent: Node = entry.source.get_parent()
		var key: Variant = parent if parent.get_children().filter(func(child: Node) -> bool:
			return child is MeshInstance3D).size() <= ASSEMBLY_MESHES else entry.source
		if not assemblies.has(key):
			assemblies[key] = [] as Array[Dictionary]
		assemblies[key].append(entry)
	var units: Array = assemblies.values()
	if units.is_empty():
		return []
	var span := AABB(_unit_box(units[0]).get_center(), Vector3.ZERO)
	for unit: Array in units:
		span = span.expand(_unit_box(unit).get_center())
	var axis := span.get_longest_axis()
	units.sort_custom(func(a: Array, b: Array) -> bool:
		return _unit_box(a).get_center().dot(axis) < _unit_box(b).get_center().dot(axis))
	var clusters: Array[Dictionary] = []
	var groups := mini(maxi(count, 1), units.size())
	for index: int in groups:
		var meshes: Array[Dictionary] = []
		for unit: int in range(units.size() * index / groups, units.size() * (index + 1) / groups):
			meshes.append_array(units[unit])
		var box: AABB = meshes[0].aabb
		for entry: Dictionary in meshes:
			box = box.merge(entry.aabb)
		clusters.append({"meshes":meshes, "centre":box.get_center(), "bounds":box, "lost":false})
	return clusters

static func _unit_box(unit: Array) -> AABB:
	var box: AABB = unit[0].aabb
	for entry: Dictionary in unit:
		box = box.merge(entry.aabb)
	return box

## An accepted combat event (CombatImpactFeedback broadcasts every kind).
func note_hit(event: Dictionary) -> void:
	if event.get("target") != entity_id or not event.get("position") is Vector3 or not event.position.is_finite():
		return
	var frame := _pose.affine_inverse()
	var axis: Variant = event.get("axis", event.get("normal", Vector3.UP))
	_hits.append({"zone":str(event.get("zone", "")), "kind":str(event.get("kind", "")),
		"point":frame * event.position, "axis":(frame.basis * axis) if axis is Vector3 and axis.is_finite() else Vector3.UP,
		"time":_clock})
	if _hits.size() > 16:
		_hits.pop_front()

func _process(delta: float) -> void:
	if is_finite(delta):
		_clock += delta

func observe(view: BotView) -> void:
	if view == null or not view.pose.is_finite():
		return
	_pose = view.pose
	if view.eliminated:
		# The wreck breaks as a whole (BotDestructionVisual); lose nothing more.
		_observed = true
		return
	var tuning: RefCounted = TUNING.settings()
	var moving := _observed
	var targets := {}
	for zone: String in COMPONENTS:
		targets[zone] = _crossed(float(view.zones.get(zone, BotDamageVisual.MAXIMUM[zone])) / BotDamageVisual.MAXIMUM[zone],
			tuning.thresholds.component, pools[zone].size())
	for face: String in FACES:
		var fitted := float(view.plate_max.get(face, 0.0))
		targets[face] = _crossed(float(view.zones.get(face, fitted)) / fitted, tuning.thresholds.armour, pools[face].size()) if fitted > 0.0 else 0
	var core_target := _crossed(view.core_fraction, tuning.thresholds.core, 0)
	# Repair (new round, practice respawn) brings every part back.
	var repaired := core_target < _core_lost
	for zone: String in targets:
		repaired = repaired or targets[zone] < int(_lost_by_zone.get(zone, 0))
	if repaired:
		restore()
		moving = false
	for zone: String in targets:
		while int(_lost_by_zone.get(zone, 0)) < targets[zone]:
			_lost_by_zone[zone] = int(_lost_by_zone.get(zone, 0)) + 1
			_lose(zone, moving, tuning)
	while _core_lost < core_target:
		_core_lost += 1
		_lose("", moving, tuning)
	_observed = true

## Thresholds crossed by a fraction; reaching zero takes the whole pool.
static func _crossed(fraction: float, thresholds: Array[float], everything: int) -> int:
	if not is_finite(fraction):
		return 0
	if fraction <= 0.0 and everything > 0:
		return maxi(everything, thresholds.size())
	var count := 0
	for threshold: float in thresholds:
		if fraction <= threshold and threshold > 0.0:
			count += 1
	return count

## Detaches one cluster of a pool. An empty pool name is core damage: the
## face of the latest hit loses a panel cluster.
func _lose(pool: String, moving: bool, tuning: RefCounted) -> void:
	var hit := _recent_hit(pool, tuning)
	var candidates: Array[String] = [pool]
	if pool.is_empty():
		candidates.clear()
		if not hit.is_empty():
			candidates.append(face_of(hit.point, _bounds))
		candidates.append_array(FACES)
	for name: String in candidates:
		var cluster := _pick(pools.get(name, []), hit)
		if cluster.is_empty():
			continue
		cluster.lost = true
		if moving:
			_launch(cluster, hit, tuning)
		for entry: Dictionary in cluster.meshes:
			if is_instance_valid(entry.source): entry.source.hide()
		return

func _recent_hit(pool: String, tuning: RefCounted) -> Dictionary:
	for index: int in range(_hits.size() - 1, -1, -1):
		var hit: Dictionary = _hits[index]
		if _clock - float(hit.time) > float(tuning.parts.hit_memory):
			break
		if pool.is_empty() or hit.zone == pool or face_of(hit.point, _bounds) == pool:
			return hit
	return {}

## The remaining cluster nearest the hit, else the first remaining one (the
## same on every client).
static func _pick(clusters: Array, hit: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for cluster: Dictionary in clusters:
		if cluster.lost:
			continue
		if hit.is_empty():
			return cluster
		var distance: float = cluster.bounds.get_center().distance_to(hit.point)
		if distance < best_distance:
			best = cluster
			best_distance = distance
	return best

func _launch(cluster: Dictionary, hit: Dictionary, tuning: RefCounted) -> void:
	if not is_inside_tree():
		return
	var body: RigidBody3D = PIECE.new()
	body.name = "LostPart"
	var box: AABB = cluster.bounds
	var points := PackedVector3Array()
	var sources: Array = cluster.meshes if cluster.meshes.size() <= HULL_CORNER_MESHES else [{"aabb":box}]
	for entry: Dictionary in sources:
		for corner: int in 8:
			points.append(entry.aabb.get_endpoint(corner))
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	shape.shape = hull
	body.add_child(shape)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = box.get_center()
	body.mass = maxf(tuning.value("debris", "density") * box.size.x * box.size.y * box.size.z * 0.3, 1.0)
	body.linear_damp = tuning.value("debris", "linear_damp")
	body.angular_damp = tuning.value("debris", "angular_damp")
	var physics := PhysicsMaterial.new()
	physics.friction = tuning.value("debris", "friction")
	physics.bounce = tuning.value("debris", "bounce")
	body.physics_material_override = physics
	var outward := box.get_center() - _bounds.get_center()
	outward.y = 0.0
	outward = outward.normalized() if outward.length_squared() > 0.0001 else Vector3.BACK
	var sever: bool = not hit.is_empty() and hit.kind in tuning.sever_kinds
	var direction := outward
	if not hit.is_empty() and not sever:
		# Knocked off along the blow, still away from the hull.
		direction = (outward + (box.get_center() - hit.point).normalized()).normalized()
	var speed: float = tuning.parts.speed * _geometry_scale
	var random := RandomNumberGenerator.new()
	random.seed = hash([entity_id, Vector3i(box.get_center() * 100.0)])
	var local_velocity := direction * speed * random.randf_range(0.8, 1.2) + Vector3.UP * speed * float(tuning.parts.lift)
	var spin := Vector3(random.randf_range(-1, 1), random.randf_range(-1, 1), random.randf_range(-1, 1)).normalized() * float(tuning.parts.spin)
	var cut_meshes: Array[MeshInstance3D] = []
	var state := Vector4.ZERO
	# A severed part glows along the side that faced the hull, where it was cut.
	var seam := {"planes":[Plane(-outward, -outward.dot(box.get_center()) + _inner_depth(box, outward))] as Array[Plane], "tears":[0.0] as Array[float]}
	for entry: Dictionary in cluster.meshes:
		var copy := MeshInstance3D.new()
		copy.mesh = entry.mesh
		copy.transform = entry.transform
		copy.cast_shadow = entry.source.cast_shadow
		var cut := sever
		for surface: int in entry.mesh.get_surface_count():
			cut = cut and PIECES.material_for(entry.source.get_active_material(surface)) != null
		for surface: int in entry.mesh.get_surface_count():
			var original: Material = entry.source.get_active_material(surface)
			copy.set_surface_override_material(surface, PIECES.material_for(original) if cut else original)
		if cut:
			var scale: Vector3 = entry.transform.basis.get_scale()
			var unit := maxf((absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0, 0.0001)
			state = Vector4(float(tuning.parts.sever_heat), tuning.value("cut", "glow_band") * 2.0 / unit, tuning.value("cut", "tear_frequency") * unit, 0.0)
			PIECES._apply_cut(copy, entry.transform, seam, [], state)
			cut_meshes.append(copy)
		body.add_child(copy)
	body.set_cut_meshes(cut_meshes, state, tuning.value("cut", "heat_seconds"))
	if _pieces_root == null:
		_pieces_root = Node3D.new()
		_pieces_root.name = "LostParts"
		add_child(_pieces_root)
		_pieces_root.top_level = true
	_pieces_root.add_child(body)
	body.global_transform = _pose
	body.linear_velocity = _pose.basis * local_velocity
	body.angular_velocity = _pose.basis * spin
	PIECE.enforce_budget(get_tree(), int(tuning.value("debris", "max_pieces")), tuning.value("debris", "sink_seconds"))

## Half the cluster's depth along -outward: the seam plane sits just past
## its innermost corner so nothing is discarded, only lit.
static func _inner_depth(box: AABB, outward: Vector3) -> float:
	var reach := 0.0
	for corner: int in 8:
		reach = maxf(reach, (-outward).dot(box.get_endpoint(corner) - box.get_center()))
	return reach + 0.001

## Puts every lost part back and clears the debris (new round, respawn).
func restore() -> void:
	for pool: Array in pools.values():
		for cluster: Dictionary in pool:
			if cluster.lost:
				for entry: Dictionary in cluster.meshes:
					if is_instance_valid(entry.source): entry.source.show()
			cluster.lost = false
	_lost_by_zone.clear()
	_core_lost = 0
	_hits.clear()
	if _pieces_root != null and is_instance_valid(_pieces_root):
		for piece: Node in _pieces_root.get_children():
			piece.queue_free()

func reset_observation() -> void:
	restore()
	_observed = false

func lost_parts() -> Array[Node]:
	var result: Array[Node] = []
	if _pieces_root != null and is_instance_valid(_pieces_root):
		for piece: Node in _pieces_root.get_children():
			if not piece.is_queued_for_deletion(): result.append(piece)
	return result

func lost_count() -> int:
	var count := 0
	for pool: Array in pools.values():
		for cluster: Dictionary in pool:
			if cluster.lost: count += 1
	return count

func _exit_tree() -> void:
	restore()
