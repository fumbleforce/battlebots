extends Node3D
## Woodland vegetation and ground dressing. Presentation only: the few trunks
## inside the arena get their collision from woodland_ground.gd; nothing built
## here collides, and every placement is seeded so all clients match.

const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const BARK = preload("res://assets/materials/arena/woodland_bark.gdshader")
const NEEDLES = preload("res://assets/materials/arena/woodland_needles.gdshader")
const GRASS = preload("res://assets/materials/arena/woodland_grass.gdshader")
const ROCK = preload("res://assets/materials/arena/woodland_rock.gdshader")
const HALF := GROUND.HALF
var bark := ShaderMaterial.new()
var needles := ShaderMaterial.new()
var grass := ShaderMaterial.new()
var stone := ShaderMaterial.new()

func _init() -> void:
	bark.shader = BARK
	needles.shader = NEEDLES
	grass.shader = GRASS
	stone.shader = ROCK

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

func _interior_grass() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var patches := FastNoiseLite.new()
	patches.seed = 77
	patches.frequency = 0.05
	var poses: Array[Transform3D] = []
	var attempts := 0
	while poses.size() < 26000 and attempts < 160000:
		attempts += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		var edge := GROUND.octagon_distance(p)
		if edge < 0.4:
			continue
		var y := height(p.x, p.y)
		var near := 1.0 - smoothstep(1.0, 9.0, edge)
		near = maxf(near, smoothstep(0.4, 1.3, y))
		# Mesa and terrace tops are undriven enough to stay grassy.
		near = maxf(near, smoothstep(2.0, 3.0, y) * 0.8)
		for outcrop: Dictionary in GROUND.OUTCROPS:
			var size: float = outcrop.size
			for sign: float in [1.0, -1.0]:
				var at: Vector2 = outcrop.at
				near = maxf(near, 1.0 - smoothstep(size * 3.5, size * 7.0, p.distance_to(at * sign)))
		near *= smoothstep(20.0, 34.0, p.length()) * 0.8 + 0.2
		if rng.randf() > near * (0.5 + patches.get_noise_2dv(p) * 0.7):
			continue
		var at := Vector3(p.x, y - 0.03, p.y)
		if GROUND.blocks(at, 0.2):
			continue
		var s := rng.randf_range(0.9, 1.8)
		poses.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)), at))
	_multimesh("GrassTufts", _tuft_mesh(), grass, poses, false)

func _interior_stones() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123
	var poses: Array[Transform3D] = []
	var attempts := 0
	while poses.size() < 6000 and attempts < 80000:
		attempts += 1
		var p := Vector2(rng.randf_range(-HALF, HALF), rng.randf_range(-HALF, HALF))
		if GROUND.octagon_distance(p) < 0.6:
			continue
		var near := 0.12
		for outcrop: Dictionary in GROUND.OUTCROPS:
			var size: float = outcrop.size
			for sign: float in [1.0, -1.0]:
				var at: Vector2 = outcrop.at
				near = maxf(near, 1.0 - smoothstep(size * 3.0, size * 8.0, p.distance_to(at * sign)))
		if rng.randf() > near:
			continue
		var s := rng.randf_range(0.06, 0.22) * (1.0 + near * 1.6)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
		poses.append(Transform3D(basis.scaled_local(Vector3(s * rng.randf_range(0.9, 1.6), s * 0.55, s)), Vector3(p.x, height(p.x, p.y) + s * 0.1, p.y)))
	var pebble := SphereMesh.new()
	pebble.radius = 0.5
	pebble.height = 1.0
	pebble.radial_segments = 7
	pebble.rings = 4
	var grit := StandardMaterial3D.new()
	grit.albedo_color = Color(0.3, 0.285, 0.26)
	grit.roughness = 0.9
	_multimesh("Stones", pebble, grit, poses, false)

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

func _tuft_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for card: int in range(3):
		var angle := card * PI / 3.0
		var side := Vector3(cos(angle), 0, sin(angle)) * 0.34
		var lean := Vector3(-side.z, 0, side.x) * 0.12
		var corners := [-side, side, side + Vector3(0, 0.5, 0) + lean, -side + Vector3(0, 0.5, 0) + lean]
		var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for index: int in [0, 2, 1, 0, 3, 2]:
			tool.set_normal(Vector3.UP)
			tool.set_uv(uvs[index])
			tool.add_vertex(corners[index])
	return tool.commit()

## A seeded pine: detail 2 is a hero tree, 1 mid-distance, 0 a far silhouette.
## Surface 0 is bark, surface 1 needle cards. The trunk base is the origin.
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
	trunk.set_material(bark)
	trunk.commit(mesh)
	# Needle sprays in whorls; the crown narrows to a leader at the top.
	var foliage := SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var crown_base := height * rng.randf_range(0.2, 0.32)
	var reach := height * rng.randf_range(0.19, 0.24)
	var spacing: float = [1.6, 1.0, 0.62][detail]
	var levels := maxi(4, int((height - crown_base) / spacing))
	var per_level: int = [6, 9, 12][detail]
	var segments: int = [2, 3, 4][detail]
	var crown_centre := Vector3(0, (crown_base + height) * 0.5, 0)
	for level: int in range(levels):
		var t := float(level) / (levels - 1)
		var y := lerpf(crown_base, height - 0.4, t) + rng.randf_range(-0.15, 0.15)
		var radius := reach * pow(1.0 - t, 0.9) + 0.45
		var count := maxi(3, int(round(per_level * (1.0 - t * 0.45))))
		for b: int in range(count):
			var az := TAU * b / count + level * 2.39996 + rng.randf_range(-0.3, 0.3)
			var dir := Vector3(sin(az), 0, cos(az))
			var length := radius * rng.randf_range(0.8, 1.12)
			var droop := length * rng.randf_range(0.28, 0.5) * (1.0 - t * 0.6)
			var lift := length * 0.22
			var base: Vector3 = axis.call(y)
			var strips := 3 if detail > 1 else (2 if detail > 0 else 1)
			for strip: int in range(strips):
				var side := dir.cross(Vector3.UP)
				var across := side if strip == 0 else ((Vector3.UP * 0.9 + side * 0.3).normalized() if strip == 1 else (side + Vector3.UP * 0.6).normalized())
				var previous: Array = []
				for k: int in range(segments + 1):
					var u := float(k) / segments
					var centre := base + dir * length * u + Vector3.UP * (lift * u - droop * u * u)
					var width := length * (0.72 if strip == 0 else 0.48) * (0.35 + 0.65 * sin(PI * minf(1.0, u * 0.95 + 0.12)))
					var normal := ((centre - crown_centre) * Vector3(1, 0.6, 1) + Vector3.UP * radius * 0.6).normalized()
					var left := [centre - across * width * 0.5, normal, Vector2(0, u)]
					var right := [centre + across * width * 0.5, normal, Vector2(1, u)]
					if k > 0:
						_tri(foliage, previous[0], previous[1], right)
						_tri(foliage, previous[0], right, left)
					previous = [left, right]
	# Leader tip.
	var tip: Vector3 = axis.call(height)
	for b: int in range(3):
		var az := TAU * b / 3.0
		var across := Vector3(cos(az), 0, sin(az)) * 0.45
		var n := Vector3(-across.z, 0.5, across.x).normalized()
		_tri(foliage, [tip - across - Vector3(0, 1.4, 0), n, Vector2(0, 0)], [tip + across - Vector3(0, 1.4, 0), n, Vector2(1, 0)], [tip + Vector3(0, 0.5, 0), n, Vector2(0.5, 1)])
	foliage.set_material(needles)
	foliage.commit(mesh)
	return mesh

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
