extends Node3D
## Woodland surroundings, presentation only: forested hills and granite crags
## around the stadium, a river with a timber bridge, a lake, gate roads and a
## far mountain sky. Nothing here collides or affects play; every placement is
## seeded so all clients see the same valley.

const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const FLOOR = preload("res://assets/materials/arena/woodland_forest_floor.gdshader")
const WATER = preload("res://assets/materials/arena/woodland_water.gdshader")
const ROCK = preload("res://assets/materials/arena/woodland_rock.gdshader")
const INNER := 118.0
const OUTER := 1500.0
const WATER_LEVEL := -5.0
const YARD := 165.0
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _crags := FastNoiseLite.new()
var flora: Node3D

func _init() -> void:
	_hills.seed = 4401
	_hills.frequency = 0.0022
	_hills.fractal_octaves = 5
	_detail.seed = 4402
	_detail.frequency = 0.012
	_detail.fractal_octaves = 4
	_crags.seed = 4403
	_crags.frequency = 0.008
	_crags.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_crags.fractal_octaves = 4

static func river_z(x: float) -> float:
	return 225.0 + sin(x * 0.0055 + 0.6) * 45.0 + sin(x * 0.017) * 12.0

static func lake_distance(p: Vector2) -> float:
	var q := (p - Vector2(560, -620)).rotated(-0.5)
	return Vector2(q.x / 460.0, q.y / 250.0).length()

static func road_distance(p: Vector2) -> float:
	# East/west gate roads and the south road to the river bridge.
	var d := absf(p.y + sin(p.x * 0.01) * 6.0) if absf(p.x) > INNER else INF
	if p.y > INNER:
		d = minf(d, absf(p.x - sin(p.y * 0.012) * 10.0))
	return d

func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var r := p.length()
	var rise := smoothstep(YARD - 5.0, 300.0, r)
	var h := -0.25 + rise * ((_hills.get_noise_2d(x, z) + 0.55) * 70.0 + _detail.get_noise_2d(x, z) * 9.0)
	# Granite crags break out of the nearer hills.
	# Broad granite knolls: smoothed ridged noise, never needle peaks.
	var crag := smoothstep(0.1, 0.8, _crags.get_noise_2d(x, z))
	h += crag * crag * 22.0 * smoothstep(YARD + 10.0, 260.0, r) * (1.0 - smoothstep(700.0, 1100.0, r))
	# Distant ground climbs toward the painted mountains.
	h += smoothstep(900.0, OUTER, r) * 140.0
	# Roads are graded flat.
	var road := road_distance(p)
	h = lerpf(minf(h, 0.3 + rise * 4.0), h, smoothstep(7.0, 22.0, road))
	# Water carves the river channel and the lake basin.
	var river := absf(z - river_z(x))
	h = minf(h, lerpf(WATER_LEVEL - 3.0, h, smoothstep(16.0, 55.0, river)))
	h = minf(h, lerpf(WATER_LEVEL - 8.0, h, smoothstep(0.85, 1.25, lake_distance(p))))
	return h

func build() -> void:
	_terrain()
	_water()
	_forest()
	_boulders()
	_bridge()

func _terrain() -> void:
	var radii := PackedFloat32Array()
	var r := INNER
	while r < OUTER:
		radii.append(r)
		r += maxf(2.0, r * 0.03)
	radii.append(OUTER)
	var segments := 384
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for ring: int in radii.size():
		for s: int in range(segments):
			var a := TAU * s / segments
			var at := Vector2(cos(a), sin(a)) * radii[ring]
			var y := height(at.x, at.y)
			vertices.append(Vector3(at.x, y, at.y))
			var e := maxf(1.0, radii[ring] * 0.01)
			normals.append(Vector3(height(at.x - e, at.y) - height(at.x + e, at.y), 2.0 * e, height(at.x, at.y - e) - height(at.x, at.y + e)).normalized())
	var indices := PackedInt32Array()
	for ring: int in range(radii.size() - 1):
		for s: int in range(segments):
			var a := ring * segments + s
			var b := ring * segments + (s + 1) % segments
			var c := a + segments
			var d := b + segments
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR
	mat.set_shader_parameter("water_level", WATER_LEVEL)
	mesh.surface_set_material(0, mat)
	var visual := MeshInstance3D.new()
	visual.name = "Valley"
	visual.mesh = mesh
	add_child(visual)

func _water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(OUTER * 2.0, OUTER * 2.0)
	var mat := ShaderMaterial.new()
	mat.shader = WATER
	plane.material = mat
	var water := MeshInstance3D.new()
	water.name = "RiverAndLake"
	water.mesh = plane
	water.position.y = WATER_LEVEL
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var near_meshes: Array[Mesh] = []
	var far_meshes: Array[Mesh] = []
	for v: int in range(4):
		near_meshes.append(flora.pine(9100 + v, 20.0 + v * 2.0, 1))
		var far: ArrayMesh = flora.pine(9200 + v, 20.0 + v * 2.0, 0)
		var far_needles := (far.surface_get_material(1) as ShaderMaterial).duplicate() as ShaderMaterial
		far_needles.set_shader_parameter("solidify_far", true)
		far.surface_set_material(1, far_needles)
		far_meshes.append(far)
	# Sixteen sectors per band so frustum culling drops what is behind the camera.
	# Near stands use mid-detail pines and cast shadows; far ones are silhouettes.
	var bands := [[YARD + 5.0, 480.0, 3200, near_meshes, 0.0], [480.0, 1250.0, 7000, far_meshes, 1.0]]
	for band: Array in bands:
		var sectors: Array = []
		for s: int in range(16):
			var variants: Array = []
			for v: int in range(4):
				variants.append([])
			sectors.append(variants)
		var placed := 0
		var attempts := 0
		while placed < int(band[2]) and attempts < int(band[2]) * 6:
			attempts += 1
			var r := sqrt(rng.randf_range(float(band[0]) * float(band[0]), float(band[1]) * float(band[1])))
			var a := rng.randf() * TAU
			var p := Vector2(cos(a), sin(a)) * r
			var y := height(p.x, p.y)
			if y < WATER_LEVEL + 1.0 or road_distance(p) < 12.0 or absf(p.y - river_z(p.x)) < 30.0:
				continue
			var e := 3.0
			var slope := Vector2(height(p.x + e, p.y) - height(p.x - e, p.y), height(p.x, p.y + e) - height(p.x, p.y - e)).length() / (2.0 * e)
			if slope > 0.9:
				continue
			# Clearings and meadows thin the forest into stands.
			if _detail.get_noise_2d(p.x * 0.4, p.y * 0.4) < -0.25 and rng.randf() < 0.8:
				continue
			var s := rng.randf_range(0.75, 1.35)
			var pose := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), Vector3(p.x, y - 0.4, p.y))
			var sector := int(fposmod(a, TAU) / TAU * 16.0) % 16
			sectors[sector][rng.randi() % 4].append(pose)
			placed += 1
		for s: int in range(16):
			for v: int in range(4):
				var poses: Array = sectors[s][v]
				if poses.is_empty():
					continue
				var multi := MultiMesh.new()
				multi.transform_format = MultiMesh.TRANSFORM_3D
				multi.mesh = band[3][v]
				multi.instance_count = poses.size()
				for i: int in range(poses.size()):
					multi.set_instance_transform(i, poses[i])
				var visual := MultiMeshInstance3D.new()
				visual.name = "Forest%d_%d_%d" % [int(band[0]), s, v]
				visual.multimesh = multi
				# Valley pines never shade the bowl; skipping them keeps shadow passes cheap.
				visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(visual)

func _boulders() -> void:
	# Granite blocks on the crags and river banks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7070
	var mat := ShaderMaterial.new()
	mat.shader = ROCK
	var placed := 0
	var attempts := 0
	while placed < 70 and attempts < 4000:
		attempts += 1
		var r := rng.randf_range(YARD + 10.0, 650.0)
		var a := rng.randf() * TAU
		var p := Vector2(cos(a), sin(a)) * r
		var bank := absf(p.y - river_z(p.x))
		var crag := _crags.get_noise_2d(p.x, p.y)
		if not (crag > 0.35 or (bank > 14.0 and bank < 40.0)) or road_distance(p) < 12.0:
			continue
		var size := rng.randf_range(4.0, 14.0)
		var radii := Vector3(size, size * rng.randf_range(0.6, 1.1), size * rng.randf_range(0.7, 1.0))
		var seed := 900 + placed
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sphere: Dictionary = get_parent().call("_icosphere", 3)
		var verts := PackedVector3Array()
		for direction: Vector3 in sphere.vertices:
			verts.append(GROUND.boulder_vertex(direction, radii, rng.randf() * TAU, seed))
		for index: int in sphere.indices:
			tool.add_vertex(verts[index])
		tool.index()
		tool.generate_normals()
		var rock := MeshInstance3D.new()
		rock.name = "ValleyRock%d" % placed
		rock.mesh = tool.commit()
		rock.material_override = mat
		rock.position = Vector3(p.x, height(p.x, p.y) - size * 0.15, p.y)
		add_child(rock)
		placed += 1

func _bridge() -> void:
	# Timber trestle carrying the south road over the river.
	var x := 0.0
	var z := river_z(x)
	var parent := get_parent()
	var frame := Transform3D(Basis.IDENTITY, Vector3(x, 0, z))
	parent.set("_side", frame)
	var deck_y := 1.2
	var span := 90.0
	var z0 := -span * 0.5
	var n := 0
	while z0 + n * 0.8 < span * 0.5:
		parent.call("_box", "deck", Vector3(0, deck_y, z0 + n * 0.8), Vector3(10.0, 0.25, 0.75), Vector3.ZERO, Color(0.9, 0.9, 0.9))
		n += 1
	for side: float in [-5.2, 5.2]:
		parent.call("_box", "timber", Vector3(side, deck_y - 0.5, 0), Vector3(0.6, 0.9, span), Vector3.ZERO, Color.WHITE)
		parent.call("_box", "rail", Vector3(side, deck_y + 1.1, 0), Vector3(0.2, 0.2, span), Vector3.ZERO, Color.WHITE)
		for k: int in range(16):
			var pz := z0 + k * span / 15.0
			parent.call("_box", "rail", Vector3(side, deck_y + 0.55, pz), Vector3(0.2, 1.1, 0.2), Vector3.ZERO, Color.WHITE)
	for k: int in range(7):
		var pz := z0 + 6.0 + k * (span - 12.0) / 6.0
		for side: float in [-4.0, 4.0]:
			parent.call("_log", "log", Vector3(side, WATER_LEVEL - 4.0, pz), Vector3(side, deck_y - 0.4, pz), 0.4, Color.WHITE)
		parent.call("_beam", "rail", Vector3(-4.0, WATER_LEVEL, pz), Vector3(4.0, deck_y - 0.6, pz), Vector2(0.3, 0.25), Color.WHITE, "box", Vector3.BACK)
	parent.set("_side", Transform3D.IDENTITY)
