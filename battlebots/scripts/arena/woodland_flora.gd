extends Node3D
## Woodland vegetation and ground dressing. Presentation only: the few trunks
## inside the arena get their collision from woodland_ground.gd; nothing built
## here collides, and every placement is seeded so all clients match.

const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const BARK = preload("res://assets/materials/arena/woodland_bark.gdshader")
const ROCK = preload("res://assets/materials/arena/woodland_rock.gdshader")
const CONIFER = preload("res://assets/materials/arena/woodland_conifer.gdshader")
const HALF := GROUND.HALF
var bark := ShaderMaterial.new()
var stone := ShaderMaterial.new()
var side_cards := ShaderMaterial.new()
var branch_cards := ShaderMaterial.new()

func _init() -> void:
	bark.shader = BARK
	for map: String in ["diff", "nor", "arm"]:
		bark.set_shader_parameter("bark_" + map, load("res://assets/textures/woodland/pine_bark_%s_1k.jpg" % map))
	stone.shader = ROCK
	side_cards.shader = CONIFER
	side_cards.set_shader_parameter("atlas", load("res://assets/textures/woodland/conifer_sides.png"))
	branch_cards.shader = CONIFER
	branch_cards.set_shader_parameter("atlas", load("res://assets/textures/woodland/conifer_branches.png"))
	branch_cards.set_shader_parameter("normal_tex", load("res://assets/textures/woodland/conifer_branches_nor.png"))
	branch_cards.set_shader_parameter("use_normal", true)
	branch_cards.set_shader_parameter("use_occlusion", true)

var _heights := PackedFloat32Array()
var _pines: Dictionary = {}

func build_interior(heights: PackedFloat32Array) -> void:
	_heights = heights
	var rng := RandomNumberGenerator.new()
	for item: Dictionary in GROUND.obstacles():
		if item.kind != "tree":
			continue
		rng.seed = item.seed
		var variant: int = item.seed % 6
		if not _pines.has(variant):
			_pines[variant] = pine(9000 + variant, 19.0 + variant * 1.4, 2)
		var tree := MeshInstance3D.new()
		tree.name = String(item.name).replace("Trunk", "Pine")
		tree.mesh = _pines[variant]
		tree.position = item.at - Vector3(0, 0.3, 0)
		tree.rotation.y = rng.randf() * TAU
		tree.scale = Vector3.ONE * rng.randf_range(0.9, 1.12)
		add_child(tree)
	_interior_grass()

## Bilinear sample of the shared physical height grid.
func height(x: float, z: float) -> float:
	var gx := clampf((x + HALF) / GROUND.STEP, 0.0, GROUND.GRID - 1.001)
	var gz := clampf((z + HALF) / GROUND.STEP, 0.0, GROUND.GRID - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	var g := GROUND.GRID
	return lerpf(lerpf(_heights[iz * g + ix], _heights[iz * g + ix + 1], fx),
		lerpf(_heights[(iz + 1) * g + ix], _heights[(iz + 1) * g + ix + 1], fx), fz)

const MASKS = preload("res://assets/textures/woodland/ground_masks.png")
const SCAN_PROP = preload("res://assets/materials/arena/woodland_scan_prop.gdshader")
const CHUNK := 24.0
const LUMP_RES := 481 # 0.5 m texels over the 240 m octagon.
static var _lumps := PackedFloat32Array()

## Visual-only ground lumps (<= ~0.3 m), shared by the terrain shader and
## scatter placement so props sit on the rendered surface.
static func lump_data() -> PackedFloat32Array:
	if _lumps.is_empty():
		var n := FastNoiseLite.new()
		n.seed = 6161
		n.frequency = 0.17
		n.fractal_octaves = 3
		var fine := FastNoiseLite.new()
		fine.seed = 6162
		fine.frequency = 0.85
		_lumps.resize(LUMP_RES * LUMP_RES)
		for z: int in range(LUMP_RES):
			for x: int in range(LUMP_RES):
				var wx := x * 0.5 - HALF
				var wz := z * 0.5 - HALF
				_lumps[z * LUMP_RES + x] = n.get_noise_2d(wx, wz) * 0.22 + fine.get_noise_2d(wx, wz) * 0.04
	return _lumps

static func lump_texture() -> ImageTexture:
	return ImageTexture.create_from_image(Image.create_from_data(LUMP_RES, LUMP_RES, false, Image.FORMAT_RF, lump_data().to_byte_array()))

static func lump_at(x: float, z: float) -> float:
	var data := lump_data()
	var gx := clampf((x + HALF) * 2.0, 0.0, LUMP_RES - 1.001)
	var gz := clampf((z + HALF) * 2.0, 0.0, LUMP_RES - 1.001)
	var ix := int(gx)
	var iz := int(gz)
	var fx := gx - ix
	var fz := gz - iz
	return lerpf(lerpf(data[iz * LUMP_RES + ix], data[iz * LUMP_RES + ix + 1], fx),
		lerpf(data[(iz + 1) * LUMP_RES + ix], data[(iz + 1) * LUMP_RES + ix + 1], fx), fz)
const RUT_DEPTH := 0.16 # Matches woodland_terrain.gdshader.
var _masks: Image

func _mask(x: float, z: float) -> Color:
	var px := clampi(int((x + HALF) / (HALF * 2.0) * _masks.get_width()), 0, _masks.get_width() - 1)
	var pz := clampi(int((z + HALF) / (HALF * 2.0) * _masks.get_height()), 0, _masks.get_height() - 1)
	return _masks.get_pixel(px, pz)

## Visual ground height including the shader's rut groove, so nothing floats.
func ground_y(x: float, z: float) -> float:
	var r := _mask(x, z).r
	var profile := -smoothstep(0.15, 1.0, r) + smoothstep(0.0, 0.15, r) * (1.0 - smoothstep(0.15, 0.45, r)) * 0.35
	# Mirrors the terrain shader's visual lumps so scatter sits on the surface.
	var lumps := lump_at(x, z) * (1.0 - smoothstep(0.05, 0.5, r))
	return height(x, z) + lumps + profile * RUT_DEPTH

## Mesh variants of a Blender-built scatter set (art_source/woodland/build_scatter.py).
## Rebuild an imported scan material on woodland_scan_prop.gdshader.
func _scan_material(source: BaseMaterial3D, saturation: float, tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SCAN_PROP
	var foliage := source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.set_shader_parameter("foliage", foliage)
	mat.set_shader_parameter("albedo_tex", source.albedo_texture)
	mat.set_shader_parameter("has_normal", source.normal_texture != null)
	mat.set_shader_parameter("normal_tex", source.normal_texture)
	mat.set_shader_parameter("has_arm", source.roughness_texture != null)
	mat.set_shader_parameter("arm_tex", source.roughness_texture)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("tint", tint)
	return mat

func _variants(set_name: String, max_tris: int = 1 << 30, tint: Color = Color.WHITE, saturation: float = 1.0) -> Array[Mesh]:
	var scene: Node = load("res://assets/models/woodland/%s.gltf" % set_name).instantiate()
	var out: Array[Mesh] = []
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh.duplicate() as Mesh
		var tris := 0
		for surface: int in range(mesh.get_surface_count()):
			tris += mesh.surface_get_array_index_len(surface) / 3
		if tris <= max_tris:
			for surface: int in range(mesh.get_surface_count()):
				mesh.surface_set_material(surface, _scan_material(mesh.surface_get_material(surface) as BaseMaterial3D, saturation, tint))
			out.append(mesh)
	scene.free()
	return out

## Instances bucketed into 24 m chunks so culling and visibility ranges work.
func _scatter(label: String, meshes: Array[Mesh], poses: Array, range_end: float, shadows: bool) -> void:
	var buckets: Dictionary = {}
	for entry: Array in poses:
		var pose: Transform3D = entry[1]
		var key := Vector3i(int(floor(pose.origin.x / CHUNK)), int(floor(pose.origin.z / CHUNK)), int(entry[0]))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(pose)
	for key: Vector3i in buckets:
		var centre := Vector3((key.x + 0.5) * CHUNK, 0.0, (key.y + 0.5) * CHUNK)
		var list: Array = buckets[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = meshes[key.z]
		multi.instance_count = list.size()
		for i: int in range(list.size()):
			var pose: Transform3D = list[i]
			multi.set_instance_transform(i, Transform3D(pose.basis, pose.origin - centre))
		var visual := MultiMeshInstance3D.new()
		visual.name = "%s_%d_%d_%d" % [label, key.x, key.y, key.z]
		visual.multimesh = multi
		visual.position = centre
		# Full density out to range_end, then a thinned copy to 3x that, so the
		# ground never reads as bare beyond a short radius.
		visual.visibility_range_end = range_end
		visual.visibility_range_end_margin = CHUNK
		visual.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		var sparse := MultiMesh.new()
		sparse.transform_format = MultiMesh.TRANSFORM_3D
		sparse.mesh = multi.mesh
		sparse.instance_count = (list.size() + 2) / 3
		for i: int in range(sparse.instance_count):
			sparse.set_instance_transform(i, multi.get_instance_transform(i * 3))
		var far := MultiMeshInstance3D.new()
		far.name = visual.name + "_far"
		far.multimesh = sparse
		far.position = centre
		far.visibility_range_begin = range_end
		far.visibility_range_begin_margin = CHUNK
		far.visibility_range_end = range_end * 3.0
		far.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(far)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)

func _clear_of_play(p: Vector2, margin: float) -> bool:
	if GROUND.octagon_distance(p) < 0.6:
		return false
	return not GROUND.blocks(Vector3(p.x, 0.0, p.y), margin)

## Grass patches: two crossed 1.2 x 0.6 m cards per mesh, textured from the
## Blender-rendered scan atlas (art_source/woodland/build_grass_atlas.py).
func _grass_cards() -> Array[Mesh]:
	var mat := ShaderMaterial.new()
	mat.shader = SCAN_PROP
	mat.set_shader_parameter("foliage", true)
	mat.set_shader_parameter("albedo_tex", load("res://assets/textures/woodland/grass_patches.png"))
	mat.set_shader_parameter("has_normal", false)
	mat.set_shader_parameter("has_arm", false)
	mat.set_shader_parameter("cutoff", 0.5)
	mat.set_shader_parameter("tint", Color(1.08, 1.1, 1.0))
	var out: Array[Mesh] = []
	for cell: int in range(8):
		var u0 := float(cell % 2) * 0.5
		var v0 := float(cell / 2) * 0.25
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for card: int in range(3):
			var yaw := card * PI / 3.0 + cell * 0.4
			var across := Vector3(cos(yaw), 0, sin(yaw)) * 0.6
			var corners := [-across, across, across + Vector3(0, 0.6, 0), -across + Vector3(0, 0.6, 0)]
			var uvs := [Vector2(u0, v0 + 0.25), Vector2(u0 + 0.5, v0 + 0.25), Vector2(u0 + 0.5, v0), Vector2(u0, v0)]
			for index: int in [0, 2, 1, 0, 3, 2]:
				tool.set_normal(Vector3.UP)
				tool.set_uv(uvs[index])
				tool.add_vertex(corners[index])
		tool.set_material(mat)
		out.append(tool.commit())
	return out

func _interior_grass() -> void:
	_masks = MASKS.get_image()
	if _masks.is_compressed():
		_masks.decompress()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var grass := _grass_cards()
	var ferns := _variants("scatter_fern")
	var rocks := _variants("scatter_rocks")
	# The granite pebble scan is pinkish; pull it toward the arena's grey stone.
	var pebbles := _variants("scatter_pebbles", 1 << 30, Color(0.62, 0.61, 0.6), 0.2)
	var small_rocks := _variants("scatter_rocks")
	var grass_poses: Array = []
	var fern_poses: Array = []
	var pebble_poses: Array = []
	var rock_poses: Array = []
	# One jittered candidate per 0.45 m cell, accepted by the baked masks.
	var cell := 0.42
	var n := int(HALF * 2.0 / cell)
	for iz: int in range(n):
		for ix: int in range(n):
			var p := Vector2(-HALF + (ix + rng.randf()) * cell, -HALF + (iz + rng.randf()) * cell)
			var roll := rng.randf()
			var m := _mask(p.x, p.y)
			var slope := absf(height(p.x + 0.5, p.y) - height(p.x - 0.5, p.y)) + absf(height(p.x, p.y + 0.5) - height(p.x, p.y - 0.5))
			if slope > 0.9:
				continue
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			if roll < minf(1.0, m.g * 1.3):
				if not _clear_of_play(p, 0.3):
					continue
				# Scanned clumps are ~0.3 m; tank-scale meadow grass stands 0.4-0.7 m.
				var s := rng.randf_range(0.85, 1.5) * (0.7 + m.g * 0.5)
				grass_poses.append([rng.randi() % grass.size(), Transform3D(yaw.scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, ground_y(p.x, p.y) - 0.02, p.y))])
				continue
			# Pebbles gather on the churned lips of ruts and around features.
			var lip := smoothstep(0.0, 0.2, m.r) * (1.0 - smoothstep(0.2, 0.5, m.r))
			var near := 0.0
			for outcrop: Dictionary in GROUND.OUTCROPS:
				var size: float = outcrop.size
				var centre: Vector2 = outcrop.at
				for sign: float in [1.0, -1.0]:
					near = maxf(near, 1.0 - smoothstep(size * 2.0, size * 7.0, p.distance_to(centre * sign)))
			var open_tuft := rng.randf()
			if open_tuft < 0.07 * (1.0 - smoothstep(0.02, 0.3, m.r)) and _clear_of_play(p, 0.3):
				# Sparse tufts survive across the driven ground too.
				var t := rng.randf_range(0.45, 0.8)
				grass_poses.append([rng.randi() % grass.size(), Transform3D(yaw.scaled(Vector3(t, t * rng.randf_range(0.7, 1.1), t)), Vector3(p.x, ground_y(p.x, p.y) - 0.02, p.y))])
			if rng.randf() < 0.55 and _clear_of_play(p, 0.05):
				# Dense fine debris: small scanned stones everywhere.
				var tilt2 := Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, rng.randf_range(-0.4, 0.4)))
				var d := rng.randf_range(0.25, 0.7)
				pebble_poses.append([rng.randi() % pebbles.size(), Transform3D(tilt2.scaled(Vector3(d, d * 0.7, d)), Vector3(p.x, ground_y(p.x, p.y) - 0.02 * d, p.y))])
			if roll < 0.03 + lip * 0.25 + near * 0.25:
				if not _clear_of_play(p, 0.1):
					continue
				var tilt := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
				if rng.randf() < 0.25:
					# Fist-to-knee sized mossy stones among the pebbles.
					var r := rng.randf_range(0.08, 0.22) * (1.0 + near)
					rock_poses.append([rng.randi() % small_rocks.size(), Transform3D(tilt.scaled(Vector3.ONE * r), Vector3(p.x, ground_y(p.x, p.y) - 0.12 * r, p.y))])
				else:
					var s := rng.randf_range(0.8, 2.6) * (1.0 + near * 1.5)
					pebble_poses.append([rng.randi() % pebbles.size(), Transform3D(tilt.scaled(Vector3.ONE * s), Vector3(p.x, ground_y(p.x, p.y) - 0.03 * s, p.y))])
	# Ferns and mossy rocks: fewer, placed around walls, groves and outcrops.
	var attempts := 0
	var big_rocks := 0
	while (fern_poses.size() < 900 or big_rocks < 260) and attempts < 60000:
		attempts += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		var m := _mask(p.x, p.y)
		if m.g < 0.4 or not _clear_of_play(p, 0.8):
			continue
		var yaw := Basis(Vector3.UP, rng.randf() * TAU)
		if rng.randf() < 0.75 and fern_poses.size() < 900:
			var s := rng.randf_range(1.4, 2.4)
			fern_poses.append([rng.randi() % ferns.size(), Transform3D(yaw.scaled(Vector3.ONE * s), Vector3(p.x, ground_y(p.x, p.y) - 0.03, p.y))])
		elif big_rocks < 260:
			big_rocks += 1
			var s := rng.randf_range(0.35, 0.9)
			rock_poses.append([rng.randi() % rocks.size(), Transform3D(yaw.scaled(Vector3.ONE * s), Vector3(p.x, ground_y(p.x, p.y) - 0.1 * s, p.y))])
	_scatter("Grass", grass, grass_poses, 90.0, false)
	_scatter("Ferns", ferns, fern_poses, 120.0, true)
	_scatter("Pebbles", pebbles, pebble_poses, 80.0, false)
	_scatter("MossRocks", rocks, rock_poses, 160.0, true)
	print_verbose("Woodland scatter: grass %d, ferns %d, pebbles %d, rocks %d" % [grass_poses.size(), fern_poses.size(), pebble_poses.size(), rock_poses.size()])

func _multimesh(label: String, mesh: Mesh, material: Material, poses: Array[Transform3D], shadows: bool) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = poses.size()
	for i: int in range(poses.size()):
		multi.set_instance_transform(i, poses[i])
	var visual := MultiMeshInstance3D.new()
	visual.name = label
	visual.multimesh = multi
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return visual

## A seeded conifer: detail 2 is a hero tree, 1 mid-distance, 0 a far silhouette.
## Surface 0 is bark, surface 1 crossed side cards, surface 2 (detail > 0) whorl
## discs; both foliage surfaces use Blender renders of a CC0 fir scan. The trunk
## base is the origin.
func pine(seed: int, height: float, detail: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var phase := Vector2(rng.randf() * TAU, rng.randf() * TAU)
	var lean := Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25))
	var axis := func(y: float) -> Vector3:
		var t := y / height
		return Vector3(sin(y * 0.31 + phase.x) * 0.1 + lean.x * t * t, y, cos(y * 0.23 + phase.y) * 0.1 + lean.y * t * t)
	var mesh := ArrayMesh.new()
	# Bark: a tapering, gently bending trunk with a root flare.
	var sides: int = [6, 9, 12][detail]
	var rings: int = [3, 8, 14][detail]
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_points: Array = []
	for r: int in range(rings + 1):
		var y := height * 0.97 * pow(float(r) / rings, 1.15) - 0.25
		var t := clampf(y / height, 0.0, 1.0)
		var radius := lerpf(height * 0.03, 0.06, pow(t, 0.8)) + height * 0.014 * exp(-maxf(y, 0.0) * 1.6)
		var centre: Vector3 = axis.call(y)
		var ring: Array = []
		for s: int in range(sides + 1):
			var a := TAU * s / sides
			ring.append([centre + Vector3(sin(a), 0, cos(a)) * radius, Vector3(sin(a), 0.1, cos(a)).normalized(), Vector2(float(s) / sides, y)])
		ring_points.append(ring)
	for r: int in range(rings):
		for s: int in range(sides):
			var quad := [ring_points[r][s], ring_points[r][s + 1], ring_points[r + 1][s + 1], ring_points[r + 1][s]]
			_tri(trunk, quad[0], quad[1], quad[2])
			_tri(trunk, quad[0], quad[2], quad[3])
	trunk.generate_tangents()
	trunk.set_material(bark)
	trunk.commit(mesh)
	# Crossed side cards: the whole foliage for far trees, a dense core for near ones.
	var width := height * 0.56 * (1.0 if detail == 0 else 0.62)
	var crown_centre := height * 0.55
	var cross := SurfaceTool.new()
	cross.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cards: int = [2, 2, 3][detail]
	for k: int in range(cards):
		var cell := (seed + k * 2) % 6
		var u0 := float(cell % 3) / 3.0
		var v0 := float(cell / 3) / 2.0
		var yaw := PI * k / cards + rng.randf_range(-0.2, 0.2)
		var across := Vector3(cos(yaw), 0, sin(yaw))
		var grid: Array = []
		for r: int in range(5):
			var row: Array = []
			for c: int in range(5):
				var fx := float(c) / 4.0
				var fy := float(r) / 4.0
				var at := across * (fx - 0.5) * width + Vector3(0, fy * height * 1.03 - 0.3, 0)
				var normal := (Vector3(at.x, (at.y - crown_centre) * 0.35, at.z) + Vector3.UP * height * 0.12).normalized()
				row.append([at, normal, Vector2(u0 + fx / 3.0, v0 + (1.0 - fy) / 2.0)])
			grid.append(row)
		for r: int in range(4):
			for c: int in range(4):
				_tri(cross, grid[r][c], grid[r][c + 1], grid[r + 1][c + 1])
				_tri(cross, grid[r][c], grid[r + 1][c + 1], grid[r + 1][c])
	cross.set_material(side_cards)
	cross.commit(mesh)
	if detail == 0:
		return mesh
	# Near trees: whorls of drooping branch cards rendered from the scan
	# (art_source/woodland/build_branch_atlas.py), like production conifers.
	var branches := SurfaceTool.new()
	branches.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown_base := height * rng.randf_range(0.14, 0.22)
	var reach := height * rng.randf_range(0.2, 0.25)
	var spacing: float = [1.3, 1.3, 0.85][detail]
	var levels := maxi(5, int((height - crown_base) / spacing))
	var per_level: int = [5, 6, 8][detail]
	var index := 0
	for level: int in range(levels):
		var t := float(level) / (levels - 1)
		var y := lerpf(crown_base, height - 0.6, t) + rng.randf_range(-0.2, 0.2)
		var length := reach * pow(1.0 - t, 0.85) + 0.7
		var count := maxi(3, int(round(per_level * (1.0 - t * 0.4))))
		for n: int in range(count):
			index += 1
			var az := TAU * n / count + level * 2.39996 + rng.randf_range(-0.25, 0.25)
			var out := Vector3(cos(az), 0, sin(az))
			var pitch := lerpf(0.5, -0.15, t) + rng.randf_range(-0.12, 0.12) # + is downward.
			var dir := (out * cos(pitch) - Vector3.UP * sin(pitch)).normalized()
			var side := out.cross(Vector3.UP).normalized().rotated(dir, rng.randf_range(-0.4, 0.4))
			var up := side.cross(dir).normalized()
			if up.y < 0.0:
				up = -up
			var w := length * 0.48
			var droop := length * lerpf(0.28, 0.08, t) * rng.randf_range(0.7, 1.3)
			var cell := (seed + index) % 8
			var u0 := float(cell % 2) * 0.5
			var v0 := float(cell / 2) * 0.25
			var base: Vector3 = axis.call(y)
			var grid: Array = []
			for k: int in range(5):
				var u := float(k) / 4.0
				var centre := base + dir * length * u - Vector3.UP * droop * u * u
				var row: Array = []
				for j: int in range(3):
					var v := float(j) / 2.0
					var at := centre + side * (v - 0.5) * w * (0.55 + 0.45 * u) + up * (0.5 - absf(v - 0.5)) * w * 0.08
					# Rounded crown shading: blend card up with the outward direction.
					var normal := (up * 0.7 + out * 0.6 + Vector3.UP * 0.2).normalized()
					var occlusion := lerpf(0.45, 1.0, u) * lerpf(0.75, 1.0, t)
					row.append([at, normal, Vector2(u0 + u * 0.5, v0 + v * 0.25), Color(occlusion, occlusion, occlusion)])
				grid.append(row)
			for k: int in range(4):
				for j: int in range(2):
					_tri_c(branches, grid[k][j], grid[k + 1][j], grid[k + 1][j + 1])
					_tri_c(branches, grid[k][j], grid[k + 1][j + 1], grid[k][j + 1])
	branches.generate_tangents()
	branches.set_material(branch_cards)
	branches.commit(mesh)
	return mesh

func _tri_c(tool: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for v: Array in [a, b, c]:
		tool.set_color(v[3])
		tool.set_normal(v[1])
		tool.set_uv(v[2])
		tool.add_vertex(v[0])

func _tri(tool: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	# Keep Godot's clockwise front faces pointing along the authored normals.
	var pa: Vector3 = a[0]
	var pb: Vector3 = b[0]
	var pc: Vector3 = c[0]
	var na: Vector3 = a[1]
	var nb: Vector3 = b[1]
	var nc: Vector3 = c[1]
	var order := [a, b, c] if (pb - pa).cross(pc - pa).dot(na + nb + nc) < 0.0 else [a, c, b]
	for v: Array in order:
		tool.set_normal(v[1])
		tool.set_uv(v[2])
		tool.add_vertex(v[0])
