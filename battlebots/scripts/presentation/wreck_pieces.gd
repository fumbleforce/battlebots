extends RefCounted
## Generic wreck break-up (#72). Any bot visual breaks the same way with no
## per-model authoring: its visible meshes are copied into physics pieces, and
## each piece discards everything outside its own region in the shader
## (destruction_cut.gdshaderinc). The killing blow (BotView.death) decides the
## regions: a saw halves the bot along its blade, a railgun bores a tunnel
## (and splits a badly overkilled bot), a blast shatters it into Voronoi shards.
## Plans are deterministic from the replicated death record and entity id, so
## every client breaks a bot the same way.
const TUNING := preload("res://scripts/core/destruction_tuning.gd")
const SURFACE := preload("res://scripts/presentation/destruction_surface.gdshader")
const PIECE := preload("res://scripts/presentation/wreck_piece.gd")
const ATLAS_PAINT := preload("res://scripts/presentation/atlas_paint.gdshader")
const SAWBLADE_PAINT := preload("res://assets/models/sawblade_runtime/paint.gdshader")
## Share of the bot's extent around its centre that a split plane may move to,
## so a glancing blow still cuts two real halves rather than a sliver.
const SPLIT_REACH := 0.35
## Voronoi seeds stay inside this share of the bounds, best of this many tries.
const SEED_SPREAD := 0.8
const SEED_TRIES := 8
## Material conversions are shared by every piece; the cache is bounded.
const MATERIAL_CACHE_MAX := 512

static var _materials: Dictionary = {}

## Visible meshes of a bot visual in the bot frame (frame = its world pose):
## [{source, mesh, transform, aabb}] with aabb also in the bot frame.
static func capture(visual_root: Node3D, frame: Transform3D, excluded: Array = []) -> Array[Dictionary]:
	var inverse := frame.affine_inverse()
	var result: Array[Dictionary] = []
	for mesh: MeshInstance3D in visual_root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or mesh in excluded:
			continue
		var local := inverse * mesh.global_transform
		result.append({"source":mesh, "mesh":mesh.mesh, "transform":local, "aabb":local * mesh.mesh.get_aabb()})
	return result

static func bounds_of(captured: Array[Dictionary]) -> AABB:
	if captured.is_empty():
		return AABB()
	var bounds: AABB = captured[0].aabb
	for entry: Dictionary in captured:
		bounds = bounds.merge(entry.aabb)
	return bounds

## Pure break-up plan in the bot frame. scale is the bot's geometry scale
## (BotScale), applied to every distance and speed in the style.
## {style, regions:[{planes:Array[Plane], tears:Array[float], points, centroid,
## velocity, spin}], tunnel:[start, end, radius, tear] or []}.
static func plan(death: Dictionary, bounds: AABB, identity: int, scale: float, tuning: RefCounted = null) -> Dictionary:
	if tuning == null:
		tuning = TUNING.settings()
	var kind: String = death.get("kind", "")
	var style: Dictionary = tuning.style_for(kind)
	var centre := bounds.get_center()
	var point: Vector3 = death.get("point", centre)
	point = point.clamp(bounds.position, bounds.end)
	var axis: Vector3 = death.get("axis", Vector3.UP)
	axis = axis.normalized() if axis.length_squared() > 0.000001 else Vector3.UP
	var force := clampf(float(death.get("force", 1.0)), 0.0, 20.0)
	var random := RandomNumberGenerator.new()
	random.seed = hash([identity, kind, Vector3i(point * 100.0), Vector3i(axis * 1000.0)])
	var pieces := int(style.pieces)
	var tunnel: Array = []
	if style.tunnel > 0.0:
		var reach := bounds.size.length()
		tunnel = [point - axis * reach, point + axis * reach, style.tunnel * scale, style.tear * scale * 0.5]
		if style.has("split_force") and force >= style.split_force:
			pieces = maxi(pieces, 2)
	var tear: float = style.tear * scale
	var regions: Array[Dictionary] = []
	if pieces == 1:
		regions.append({"planes":[] as Array[Plane], "tears":[] as Array[float]})
	elif pieces == 2:
		# The saw and grinder cut across their axis; a railgun splits along its bore.
		var normal := axis
		if not tunnel.is_empty():
			normal = axis.cross(Vector3.UP)
			if normal.length_squared() < 0.01:
				normal = axis.cross(Vector3.RIGHT)
			normal = normal.normalized()
		var half := bounds.size * 0.5
		var extent := absf(normal.x) * half.x + absf(normal.y) * half.y + absf(normal.z) * half.z
		var offset := clampf(normal.dot(point.lerp(centre, style.centre_pull)) - normal.dot(centre), -extent * SPLIT_REACH, extent * SPLIT_REACH)
		var plane := Plane(normal, normal.dot(centre) + offset)
		regions.append({"planes":[plane] as Array[Plane], "tears":[tear] as Array[float]})
		regions.append({"planes":[-plane] as Array[Plane], "tears":[-tear] as Array[float]})
	else:
		var seeds: Array[Vector3] = [point.lerp(centre, style.centre_pull)]
		var inner := AABB(centre - bounds.size * SEED_SPREAD * 0.5, bounds.size * SEED_SPREAD)
		while seeds.size() < pieces:
			var best := centre
			var best_gap := -1.0
			for attempt: int in SEED_TRIES:
				var candidate := inner.position + Vector3(random.randf(), random.randf(), random.randf()) * inner.size
				var gap := INF
				for other: Vector3 in seeds:
					gap = minf(gap, _scaled_distance(candidate, other, bounds.size))
				if gap > best_gap:
					best_gap = gap
					best = candidate
			seeds.append(best)
		for i: int in seeds.size():
			var planes: Array[Plane] = []
			var tears: Array[float] = []
			for j: int in seeds.size():
				if i == j:
					continue
				var normal := (seeds[j] - seeds[i]).normalized()
				planes.append(Plane(normal, normal.dot((seeds[i] + seeds[j]) * 0.5)))
				# Each shared seam carries opposite tears on its two sides so they still meet.
				tears.append(tear if i < j else -tear)
			regions.append({"planes":planes, "tears":tears})
	var grid := int(tuning.value("debris", "hull_grid"))
	var origin := point
	if tuning.style_name(kind) == "explosive":
		origin = point - axis * bounds.size.length() * 0.25
	var speed: float = style.speed * scale * (0.8 + 0.2 * minf(force, 3.0))
	var kept: Array[Dictionary] = []
	for region: Dictionary in regions:
		var points := _grid_points(bounds, grid, region.planes)
		if points.size() < 4:
			continue
		var centroid := Vector3.ZERO
		for sample: Vector3 in points:
			centroid += sample
		centroid /= points.size()
		region.points = points
		region.centroid = centroid
		var away := centroid - origin
		if regions.size() == 2 and region.planes.size() == 1:
			away = region.planes[0].normal * -1.0
		if regions.size() == 1 or away.length_squared() < 0.000001:
			away = axis
		var velocity: Vector3 = away.normalized() * speed + Vector3.UP * speed * style.lift
		if not tunnel.is_empty():
			velocity += axis * speed * 0.6
		region.velocity = velocity
		region.spin = Vector3(random.randf_range(-1, 1), random.randf_range(-1, 1), random.randf_range(-1, 1)).normalized() * style.spin
		kept.append(region)
	return {"style":style, "style_name":tuning.style_name(kind), "regions":kept, "tunnel":tunnel}

static func _scaled_distance(a: Vector3, b: Vector3, size: Vector3) -> float:
	var span := size.max(Vector3.ONE * 0.001)
	return ((a - b) / span).length()

## Regular grid through the bounds kept by the planes: the piece's collision
## hull, centroid and share of the bot's volume.
static func _grid_points(bounds: AABB, grid: int, planes: Array[Plane]) -> PackedVector3Array:
	var points := PackedVector3Array()
	var steps := maxi(grid, 2)
	for x: int in steps:
		for y: int in steps:
			for z: int in steps:
				var sample := bounds.position + bounds.size * Vector3(x, y, z) / float(steps - 1)
				var inside := true
				for plane: Plane in planes:
					if plane.distance_to(sample) > 0.0:
						inside = false
						break
				if inside:
					points.append(sample)
	return points

## "outside", "inside" or "cut": where a mesh's bot-frame AABB lies against a
## region (plus the tunnel, which only ever removes material).
static func classify(aabb: AABB, region: Dictionary, tunnel: Array) -> String:
	var corners: Array[Vector3] = []
	for index: int in 8:
		corners.append(aabb.get_endpoint(index))
	var straddles := false
	for i: int in region.planes.size():
		var plane: Plane = region.planes[i]
		var slack := absf(region.tears[i])
		var low := INF
		var high := -INF
		for corner: Vector3 in corners:
			var distance := plane.distance_to(corner)
			low = minf(low, distance)
			high = maxf(high, distance)
		if low > slack:
			return "outside"
		if high > -slack:
			straddles = true
	if not tunnel.is_empty():
		var radius: float = tunnel[2] + absf(tunnel[3]) + aabb.size.length() * 0.5
		if _segment_distance(aabb.get_center(), tunnel[0], tunnel[1]) < radius:
			straddles = true
	return "cut" if straddles else "inside"

static func _segment_distance(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return point.distance_to(a + ab * t)

## Builds the pieces as physics bodies at frame (not yet in the tree).
## soot is the wreck overlay for meshes a piece keeps whole.
static func build(captured: Array[Dictionary], frame: Transform3D, layout: Dictionary, soot: Material, tuning: RefCounted = null) -> Array[RigidBody3D]:
	if tuning == null:
		tuning = TUNING.settings()
	var bodies: Array[RigidBody3D] = []
	var style: Dictionary = layout.style
	var total := float(maxi(int(tuning.value("debris", "hull_grid")), 2)) ** 3
	var bounds := bounds_of(captured)
	var volume := maxf(bounds.size.x * bounds.size.y * bounds.size.z, 0.001)
	var band: float = tuning.value("cut", "glow_band")
	var frequency: float = tuning.value("cut", "tear_frequency")
	var soot_level: float = tuning.value("cut", "soot")
	var heat: float = style.heat
	for region: Dictionary in layout.regions:
		var body: RigidBody3D = PIECE.new()
		body.name = "WreckPiece"
		body.transform = frame
		var shape := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = region.points
		shape.shape = hull
		body.add_child(shape)
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = region.centroid
		body.mass = maxf(tuning.value("debris", "density") * volume * region.points.size() / total, 1.0)
		body.linear_damp = tuning.value("debris", "linear_damp")
		body.angular_damp = tuning.value("debris", "angular_damp")
		var physics := PhysicsMaterial.new()
		physics.friction = tuning.value("debris", "friction")
		physics.bounce = tuning.value("debris", "bounce")
		body.physics_material_override = physics
		body.linear_velocity = frame.basis * region.velocity
		body.angular_velocity = frame.basis * region.spin
		var cut_meshes: Array[MeshInstance3D] = []
		var state := Vector4.ZERO
		for entry: Dictionary in captured:
			var placement := classify(entry.aabb, region, layout.tunnel)
			if placement == "outside":
				continue
			var copy := MeshInstance3D.new()
			copy.mesh = entry.mesh
			copy.transform = entry.transform
			copy.cast_shadow = entry.source.cast_shadow
			var surfaces: Array[Material] = []
			var convertible := placement == "cut"
			for surface: int in entry.mesh.get_surface_count():
				var original: Material = entry.source.get_active_material(surface)
				var converted := material_for(original) if convertible else null
				if convertible and converted == null:
					convertible = false
				surfaces.append(converted if convertible else original)
			if placement == "cut" and not convertible:
				# A surface the cut shader cannot stand in for goes whole to the
				# piece holding its centre, never to two pieces at once.
				if not _holds(region, entry.aabb.get_center()):
					copy.free()
					continue
				surfaces.clear()
				for surface: int in entry.mesh.get_surface_count():
					surfaces.append(entry.source.get_active_material(surface))
			for surface: int in surfaces.size():
				copy.set_surface_override_material(surface, surfaces[surface])
			if convertible:
				var scale: Vector3 = entry.transform.basis.get_scale()
				var unit := maxf((absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0, 0.0001)
				state = Vector4(heat, band / unit, frequency * unit, soot_level)
				_apply_cut(copy, entry.transform, region, layout.tunnel, state)
				cut_meshes.append(copy)
			else:
				copy.material_overlay = soot
			body.add_child(copy)
		body.set_cut_meshes(cut_meshes, state, tuning.value("cut", "heat_seconds"))
		bodies.append(body)
	return bodies

static func _holds(region: Dictionary, point: Vector3) -> bool:
	for plane: Plane in region.planes:
		if plane.distance_to(point) > 0.0:
			return false
	return true

## Region planes and tunnel moved into the mesh's own object space.
static func _apply_cut(copy: MeshInstance3D, local: Transform3D, region: Dictionary, tunnel: Array, state: Vector4) -> void:
	var tears := Vector4.ZERO
	for index: int in 4:
		var value := Vector4.ZERO
		if index < region.planes.size():
			var plane: Plane = region.planes[index]
			var normal := local.basis.transposed() * plane.normal
			var length := maxf(normal.length(), 0.000001)
			value = Vector4(normal.x / length, normal.y / length, normal.z / length, (plane.d - plane.normal.dot(local.origin)) / length)
			tears[index] = region.tears[index] / length
		copy.set_instance_shader_parameter("cut_plane_%d" % index, value)
	copy.set_instance_shader_parameter("cut_tear", tears)
	if tunnel.is_empty():
		copy.set_instance_shader_parameter("cut_tunnel_a", Vector4.ZERO)
		copy.set_instance_shader_parameter("cut_tunnel_b", Vector4.ZERO)
	else:
		var inverse := local.affine_inverse()
		var scale := local.basis.get_scale()
		var unit := maxf((absf(scale.x) + absf(scale.y) + absf(scale.z)) / 3.0, 0.0001)
		var start: Vector3 = inverse * tunnel[0]
		var finish: Vector3 = inverse * tunnel[1]
		copy.set_instance_shader_parameter("cut_tunnel_a", Vector4(start.x, start.y, start.z, tunnel[2] / unit))
		copy.set_instance_shader_parameter("cut_tunnel_b", Vector4(finish.x, finish.y, finish.z, tunnel[3] / unit))
	copy.set_instance_shader_parameter("cut_state", state)

## Cut-capable stand-in for a surface material, or null when the cut shader
## cannot reproduce it (the mesh then goes whole to one piece).
static func material_for(original: Material) -> ShaderMaterial:
	if original == null:
		return null
	var key := original.get_instance_id()
	if _materials.has(key) and _materials[key][0].get_ref() == original:
		return _materials[key][1]
	var converted: ShaderMaterial
	if original is StandardMaterial3D:
		converted = _from_standard(original)
	elif original is ShaderMaterial and original.shader == ATLAS_PAINT:
		converted = ShaderMaterial.new()
		converted.shader = SURFACE
		for uniform: Dictionary in ATLAS_PAINT.get_shader_uniform_list():
			converted.set_shader_parameter(uniform.name, original.get_shader_parameter(uniform.name))
	elif original is ShaderMaterial and original.shader == SAWBLADE_PAINT:
		converted = ShaderMaterial.new()
		converted.shader = SURFACE
		converted.set_shader_parameter("source_mode", 1)
		for name: String in ["surface_atlas", "paint", "metal", "rough"]:
			converted.set_shader_parameter(name, original.get_shader_parameter(name))
	if converted == null:
		return null
	if _materials.size() >= MATERIAL_CACHE_MAX:
		_materials.clear()
	# Hold the original weakly so a freed material never aliases a reused id.
	_materials[key] = [weakref(original), converted]
	return converted

static func _from_standard(original: StandardMaterial3D) -> ShaderMaterial:
	if original.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("surface_albedo", original.albedo_texture)
	material.set_shader_parameter("surface_orm", original.metallic_texture if original.metallic_texture != null else original.roughness_texture)
	material.set_shader_parameter("surface_ao", original.ao_texture)
	material.set_shader_parameter("surface_normal", original.normal_texture)
	material.set_shader_parameter("surface_emission", original.emission_texture)
	material.set_shader_parameter("vertex_color_enabled", original.vertex_color_use_as_albedo)
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
	return material
