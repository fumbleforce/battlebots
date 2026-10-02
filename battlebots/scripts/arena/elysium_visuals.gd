extends Node3D
## Elysium presentation (#115). Never creates bodies, changes spawns or reads
## match state: it renders the shared layout in elysium_ground.gd. The island
## tops follow the collision height grid exactly; their edges follow the same
## signed distance field (marching squares), so what looks like ground is
## ground and what looks like sky is a fall. Below hang tapering limestone
## roots, cloud banks hug the cliffs and fill the chasm, waterfalls pour into
## the endless cloud sea, and distant islands, colossal pillars and towering
## cumulus fill the golden horizon.

const GROUND = preload("res://scripts/arena/elysium_ground.gd")
const GROUND_SHADER = preload("res://assets/materials/arena/elysium_ground.gdshader")
const ROCK_SHADER = preload("res://assets/materials/arena/elysium_rock.gdshader")
const MARBLE_SHADER = preload("res://assets/materials/arena/elysium_marble.gdshader")
const SKY_SHADER = preload("res://assets/materials/arena/elysium_sky.gdshader")
const SEA_SHADER = preload("res://assets/materials/arena/elysium_cloud_sea.gdshader")
const CLOUD_SHADER = preload("res://assets/materials/arena/elysium_cloud.gdshader")
const WATER_SHADER = preload("res://assets/materials/arena/elysium_water.gdshader")
const RAY_SHADER = preload("res://assets/materials/arena/elysium_ray.gdshader")
const SCAN_PROP = preload("res://assets/materials/arena/woodland_scan_prop.gdshader")
const TEXTURES := "res://assets/textures/woodland/%s_%s_%s.jpg"
## Sun elevation and bearing (degrees): low and golden, ahead of team 1 as it
## looks toward the Sanctum, so cloud linings and marble edges glow.
const SUN_PITCH := -24.0
const SUN_YAW := 158.0
## The cliff under every island edge before the roots taper away (m).
const LIP := 2.6
const MAX_ROOT := 120.0
## The ring promenade through the starts and the radial paths (m): as wide
## as the bridges they continue.
const PROMENADE := Vector2(96.0, 5.5)
const RADIAL_PATH := 10.0
const FLUTES := 20
const LATHE_SEGMENTS := 40
@export var arena_path: NodePath = NodePath("..")
var _rng := RandomNumberGenerator.new()
var _marble: ShaderMaterial
var _gold: ShaderMaterial
var _rock: ShaderMaterial
var _sun_dir := Vector3.UP
var _motes: GPUParticles3D
## Mesh cache: name -> Mesh (column shafts, capitals and the like).
var _meshes: Dictionary = {}

func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless":
		return
	_build.call_deferred()

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var view := float(GROUND.settings().art.view_distance)
	if camera.far < view:
		camera.far = view
	if _motes:
		_motes.global_position = camera.global_position

func _build() -> void:
	_rng.seed = 115_2026
	var arena := get_node(arena_path)
	for wall: Node in arena.get_node("Walls").get_children():
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			mesh.hide()
	(arena.get_node("Markings") as Node3D).hide()
	_materials()
	_lighting(arena)
	_islands()
	_architecture()
	_gardens()
	_waterfalls()
	_cloud_sea()
	_cloud_banks()
	_distant()
	_rays()
	_golden_motes()
	set_process(true)

# --- Materials ---------------------------------------------------------------

static func scan(id: String, map: String, size := "1k") -> Texture2D:
	return load(TEXTURES % [id, map, size])

func _materials() -> void:
	_marble = ShaderMaterial.new()
	_marble.shader = MARBLE_SHADER
	_marble.set_shader_parameter("stone_tex", scan("concrete_wall_008", "diff"))
	_marble.set_shader_parameter("stone_nor", scan("concrete_wall_008", "nor"))
	_gold = ShaderMaterial.new()
	_gold.shader = MARBLE_SHADER
	_gold.set_shader_parameter("gilded", true)
	_rock = ShaderMaterial.new()
	_rock.shader = ROCK_SHADER
	_rock.set_shader_parameter("rock_tex", scan("rock_face", "diff", "2k"))
	_rock.set_shader_parameter("rock_nor", scan("rock_face", "nor", "2k"))

func _cloud_material(opacity := 0.96, softness := 1.0, proximity := 6.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	mat.set_shader_parameter("sun_dir", _sun_dir)
	mat.set_shader_parameter("opacity", opacity)
	mat.set_shader_parameter("softness", softness)
	mat.set_shader_parameter("proximity", proximity)
	return mat

# --- Lighting ----------------------------------------------------------------

func _lighting(arena: Node) -> void:
	var cfg: Dictionary = GROUND.settings().art
	var sun := arena.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(SUN_PITCH, SUN_YAW, 0)
	sun.light_color = Color(1.0, 0.86, 0.66)
	sun.light_energy = float(cfg.sun_energy)
	sun.light_angular_distance = 1.0
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 360.0
	sun.light_volumetric_fog_energy = 1.6
	_sun_dir = sun.global_transform.basis.z.normalized() if sun.is_inside_tree() else Basis.from_euler(Vector3(deg_to_rad(SUN_PITCH), deg_to_rad(SUN_YAW), 0)).z
	var env_node: WorldEnvironment = arena.get_node("WorldEnvironment")
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_color = Color(0.9, 0.86, 0.95)
	env.ambient_light_energy = float(cfg.ambient_energy)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.92
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.15
	# Golden aerial perspective: distant things sink into the glowing haze.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(1.0, 0.9, 0.78)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.35
	env.fog_density = 0.00028
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.0
	# Soft god rays through the colonnades and over the edges.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0009
	env.volumetric_fog_albedo = Color(1.0, 0.93, 0.84)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env_node.environment = env

# --- Mesh helpers ------------------------------------------------------------

## Appends a triangle facing along want (Godot's front faces are clockwise).
static func _tri(indices: PackedInt32Array, verts: PackedVector3Array, a: int, b: int, c: int, want: Vector3) -> void:
	if (verts[b] - verts[a]).cross(verts[c] - verts[a]).dot(want) > 0.0:
		indices.append_array([a, c, b])
	else:
		indices.append_array([a, b, c])

static func _smooth_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i: int in range(0, indices.size(), 3):
		var a := indices[i]
		var b := indices[i + 1]
		var c := indices[i + 2]
		# Clockwise front faces: the face normal is the reversed cross product.
		var n := (verts[c] - verts[a]).cross(verts[b] - verts[a])
		normals[a] += n
		normals[b] += n
		normals[c] += n
	for i: int in normals.size():
		normals[i] = normals[i].normalized() if normals[i].length_squared() > 1e-12 else Vector3.UP
	return normals

static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array, material: Material, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(mesh, mesh.get_surface_count() - 1)
	tool.generate_tangents()
	var surface := mesh.get_surface_count() - 1
	var rebuilt := tool.commit_to_arrays()
	mesh.surface_remove(surface)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rebuilt)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh

func _instance(mesh: Mesh, xform := Transform3D.IDENTITY, parent: Node = self, shadows := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.transform = xform
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

# --- Islands -----------------------------------------------------------------

## A floating island set from samples of its signed distance field (negative
## inside) and top heights on a grid: a top surface, a cliff band and hanging
## limestone roots, built by marching squares so edges follow the field.
## paint(x, z, inside) -> Color for the top; roots(x, z, inside) -> depth (m)
## of the underside below the top.
func _island(origin: Vector2, step: float, nx: int, nz: int, sdf: PackedFloat32Array, heights: PackedFloat32Array,
		paint: Callable, roots: Callable, name_hint: String, parent: Node = self, ground_material: Material = null) -> void:
	if ground_material == null:
		ground_material = _ground_material()
	var top_v := PackedVector3Array()
	var top_c := PackedColorArray()
	var top_i := PackedInt32Array()
	var bot_v := PackedVector3Array()
	var bot_c := PackedColorArray()
	var bot_i := PackedInt32Array()
	var keys := {}
	var cliff_v := PackedVector3Array()
	var cliff_c := PackedColorArray()
	var cliff_uv := PackedVector2Array()
	var cliff_i := PackedInt32Array()
	var corner := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
	for j: int in nz - 1:
		for i: int in nx - 1:
			var s: Array[float] = []
			var inside_count := 0
			for k: int in 4:
				var g: Vector2i = Vector2i(i, j) + corner[k]
				s.append(sdf[g.y * nx + g.x])
				if s[k] <= 0.0:
					inside_count += 1
			if inside_count == 0:
				continue
			# Polygon of the inside part of the cell, in walking order.
			var poly: Array[int] = []
			var edge_points: Array[int] = []
			for k: int in 4:
				var g: Vector2i = Vector2i(i, j) + corner[k]
				if s[k] <= 0.0:
					poly.append(_vertex(keys, g.y * nx + g.x, top_v, top_c, bot_v, bot_c, origin, step, g, g, 0.0, nx, sdf, heights, paint, roots))
				var k2 := (k + 1) % 4
				if (s[k] <= 0.0) != (s[k2] <= 0.0):
					var g2: Vector2i = Vector2i(i, j) + corner[k2]
					var t := s[k] / (s[k] - s[k2])
					var low := Vector2i(mini(g.x, g2.x), mini(g.y, g2.y))
					var key := nx * nz + (low.y * nx + low.x) * 2 + (1 if g.x == g2.x else 0)
					var index := _vertex(keys, key, top_v, top_c, bot_v, bot_c, origin, step, g, g2, t, nx, sdf, heights, paint, roots)
					poly.append(index)
					edge_points.append(index)
			var outside := Vector2.ZERO
			for k: int in 4:
				if s[k] > 0.0:
					outside += Vector2(Vector2i(i, j) + corner[k]) / float(4 - inside_count)
			outside = origin + outside * step
			for k: int in range(1, poly.size() - 1):
				_tri(top_i, top_v, poly[0], poly[k], poly[k + 1], Vector3.UP)
				_tri(bot_i, bot_v, poly[0], poly[k], poly[k + 1], Vector3.DOWN)
			# The cliff band along each contour segment.
			for k: int in range(0, edge_points.size() - 1, 2):
				_cliff(cliff_v, cliff_c, cliff_uv, cliff_i, top_v[edge_points[k]], top_v[edge_points[k + 1]], bot_v[edge_points[k]], bot_v[edge_points[k + 1]], outside)
	var top_uv := PackedVector2Array()
	for v: Vector3 in top_v:
		top_uv.append(Vector2(v.x, v.z))
	var bot_uv := PackedVector2Array()
	for v: Vector3 in bot_v:
		bot_uv.append(Vector2(v.x, v.z) * 0.1)
	var top := _commit(top_v, _smooth_normals(top_v, top_i), top_c, top_uv, top_i, ground_material)
	_instance(top, Transform3D.IDENTITY, parent).name = name_hint + "Top"
	var rock := _commit(bot_v, _smooth_normals(bot_v, bot_i), bot_c, bot_uv, bot_i, _rock)
	_commit(cliff_v, _smooth_normals(cliff_v, cliff_i), cliff_c, cliff_uv, cliff_i, _rock, rock)
	_instance(rock, Transform3D.IDENTITY, parent).name = name_hint + "Roots"

var _ground_mat: ShaderMaterial
func _ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = GROUND_SHADER
		_ground_mat.set_shader_parameter("grass_tex", scan("sparse_grass", "diff"))
		_ground_mat.set_shader_parameter("grass_nor", scan("sparse_grass", "nor"))
		_ground_mat.set_shader_parameter("stone_tex", scan("concrete_wall_008", "diff"))
		_ground_mat.set_shader_parameter("stone_nor", scan("concrete_wall_008", "nor"))
		_ground_mat.set_shader_parameter("promenade", PROMENADE)
		_ground_mat.set_shader_parameter("radial_path", RADIAL_PATH)
		var kerbs := PackedVector3Array()
		for well: Dictionary in GROUND.wells():
			kerbs.append(Vector3(well.at.x, well.at.y, float(well.radius)))
		_ground_mat.set_shader_parameter("kerbs", kerbs)
	return _ground_mat

## Shared top and underside vertex at a grid corner (t = 0) or on the contour
## between two corners (inside corner a, outside b).
func _vertex(keys: Dictionary, key: int, top_v: PackedVector3Array, top_c: PackedColorArray, bot_v: PackedVector3Array, bot_c: PackedColorArray,
		origin: Vector2, step: float, a: Vector2i, b: Vector2i, t: float, nx: int, sdf: PackedFloat32Array, heights: PackedFloat32Array,
		paint: Callable, roots: Callable) -> int:
	if keys.has(key):
		return keys[key]
	var p := origin + (Vector2(a) + (Vector2(b) - Vector2(a)) * t) * step
	# Heights only exist on the land side: take the inside corner's.
	var ia := a.y * nx + a.x
	var ib := b.y * nx + b.x
	var inside_h := heights[ia] if sdf[ia] <= 0.0 else heights[ib]
	var h := inside_h if t > 0.0 else heights[ia]
	if t > 0.0 and sdf[ia] <= 0.0 and sdf[ib] <= 0.0:
		h = lerpf(heights[ia], heights[ib], t)
	var depth_in := maxf(0.0, -lerpf(sdf[ia], sdf[ib], t))
	var index := top_v.size()
	top_v.append(Vector3(p.x, h, p.y))
	top_c.append(paint.call(p.x, p.y, depth_in))
	var root: float = roots.call(p.x, p.y, depth_in)
	bot_v.append(Vector3(p.x, h - root, p.y))
	bot_c.append(Color(clampf(root / MAX_ROOT, 0.0, 1.0), clampf(1.0 - depth_in / 2.5, 0.0, 1.0), 0.0))
	keys[key] = index
	return index

## A cliff band between two contour points: the grassy lip bulges out a little
## over the stone, which steps back in uneven ledges to the roots.
func _cliff(verts: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array,
		top_a: Vector3, top_b: Vector3, bot_a: Vector3, bot_b: Vector3, outside: Vector2) -> void:
	var along := top_b - top_a
	var out := Vector3(along.z, 0, -along.x).normalized()
	var mid := (top_a + top_b) * 0.5
	# Outward points toward the cell's outside corners.
	if out.dot(Vector3(outside.x - mid.x, 0, outside.y - mid.z)) < 0.0:
		out = -out
	var rows := [0.0, 0.35, 1.0]
	var base := verts.size()
	for point: Array in [[top_a, bot_a], [top_b, bot_b]]:
		var top: Vector3 = point[0]
		var bottom: Vector3 = point[1]
		for r: float in rows:
			var y := lerpf(top.y, bottom.y, r)
			var bulge := 0.0
			if r > 0.0 and r < 1.0:
				bulge = 0.25 + 0.35 * _hash01(Vector2(top.x, top.z))
			verts.append(Vector3(top.x, y, top.z) + out * bulge)
			colors.append(Color(r * (top.y - bottom.y) / MAX_ROOT, 1.0 - r, 0.0))
			uvs.append(Vector2(top.x + top.z, y) * 0.1)
	var n := rows.size()
	for r: int in n - 1:
		var a := base + r
		var b := base + r + 1
		var c := base + n + r
		var d := base + n + r + 1
		_tri(indices, verts, a, c, b, out)
		_tri(indices, verts, b, c, d, out)

static func _hash01(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)

## The arena's islands, on the collision grid itself.
func _islands() -> void:
	var cfg: RefCounted = GROUND.settings()
	var n: int = GROUND.grid_size()
	var half: float = cfg.half
	var heights: PackedFloat32Array = GROUND.grid_heights()
	var sdf: PackedFloat32Array = GROUND.grid_sdf()
	var root := Node3D.new()
	root.name = "Islands"
	add_child(root)
	_island(Vector2(-half, -half), GROUND.STEP, n, n, sdf, heights, _arena_paint, _arena_roots, "Elysium", root)

## Vertex paint for the arena's tops: the Sanctum and the bridges are paved
## (the Halo's paths are drawn by the shader).
func _arena_paint(x: float, z: float, inside: float) -> Color:
	var p := Vector2(x, z)
	var pave := 0.0
	var polar := 0.0
	if GROUND.sanctum_sdf(p) <= 0.0:
		pave = 1.0
		polar = 1.0
	elif GROUND.halo_sdf(p) > 0.0 and GROUND.bridge_sdf(p) <= 0.0:
		pave = 1.0
	return Color(pave, 1.0 - clampf(inside / 3.0, 0.0, 1.0), polar)

## True on any paving (no grass grows there).
func _paved(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	if _arena_paint(x, z, 0.0).r > 0.5 or absf(p.length() - PROMENADE.x) < PROMENADE.y:
		return true
	for angle: float in GROUND.bridge_angles():
		var dir := Vector2(cos(angle), sin(angle))
		if p.dot(dir) > 0.0 and absf(p.dot(Vector2(-dir.y, dir.x))) < RADIAL_PATH:
			return true
	# Marble kerbs round the cloud wells.
	for well: Dictionary in GROUND.wells():
		if p.distance_to(well.at) < float(well.radius) + 3.0:
			return true
	return false

func _arena_roots(x: float, z: float, inside: float) -> float:
	var p := Vector2(x, z)
	var lumps := 0.6 + 0.8 * _value_noise(p * 0.05) + 0.5 * _value_noise(p * 0.17 + Vector2(31, 7))
	var depth := LIP + pow(inside, 0.92) * 2.1 * lumps
	# Stalactite points under the deeper parts.
	depth += maxf(0.0, _value_noise(p * 0.11 + Vector2(5, 3)) - 0.55) * 60.0 * smoothstep(4.0, 14.0, inside)
	return minf(depth, MAX_ROOT)

static func _value_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash01(i)
	var b := _hash01(i + Vector2(1, 0))
	var c := _hash01(i + Vector2(0, 1))
	var d := _hash01(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

# --- Classical architecture ---------------------------------------------------

## A lathe surface from a profile of (radius, height) points, optionally fluted,
## over the full turn or from from_angle to to_angle (a closed profile then
## gets end caps when cap is set, so a broken piece is solid at its faces).
func _lathe(profile: Array, segments: int, material: Material, flutes := 0, flute_depth := 0.0, mesh: ArrayMesh = null,
		from_angle := 0.0, to_angle := TAU, cap := false) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := profile.size()
	for s: int in segments + 1:
		var a := lerpf(from_angle, to_angle, float(s) / segments)
		var groove := 0.0
		if flutes > 0:
			groove = pow(absf(sin(a * flutes * 0.5)), 0.6)
		for k: int in rings:
			var point: Vector2 = profile[k]
			var fluted := 1.0 if k > 0 and k < rings - 1 else 0.0
			var r := point.x * (1.0 - flute_depth * groove * fluted)
			verts.append(Vector3(cos(a) * r, point.y, sin(a) * r))
			colors.append(Color(0.8 + 0.2 * (1.0 - groove * fluted), 0, 0))
			uvs.append(Vector2(float(s) / segments, point.y))
	for s: int in segments:
		for k: int in rings - 1:
			var a := s * rings + k
			var b := a + 1
			var c := a + rings
			var d := c + 1
			var mid := (verts[a] + verts[d]) * 0.5
			var out := Vector3(mid.x, 0, mid.z).normalized()
			var dy := verts[b].y - verts[a].y
			var dr := Vector2(verts[b].x, verts[b].z).length() - Vector2(verts[a].x, verts[a].z).length()
			# The face normal of a profile step: outward, tilted by its slope.
			var want := (out * dy - Vector3.UP * dr).normalized() if absf(dy) + absf(dr) > 1e-5 else out
			_tri(indices, verts, a, b, c, want)
			_tri(indices, verts, b, d, c, want)
	var faceted := segments <= 8
	if cap and to_angle - from_angle < TAU - 1e-3:
		faceted = true
		var centroid := Vector2.ZERO
		for point: Vector2 in profile:
			centroid += point / float(rings)
		for end: float in [from_angle, to_angle]:
			var facing := Vector3(sin(end), 0, -cos(end)) * (1.0 if end == from_angle else -1.0)
			var middle := verts.size()
			verts.append(Vector3(cos(end) * centroid.x, centroid.y, sin(end) * centroid.x))
			colors.append(Color(1, 0, 0))
			uvs.append(centroid)
			var first := verts.size()
			for point: Vector2 in profile:
				verts.append(Vector3(cos(end) * point.x, point.y, sin(end) * point.x))
				colors.append(Color(1, 0, 0))
				uvs.append(point)
			for k: int in rings - 1:
				_tri(indices, verts, middle, first + k, first + k + 1, facing)
	if faceted:
		# Faceted: split every triangle so its corners keep the face normal.
		var flat_v := PackedVector3Array()
		var flat_c := PackedColorArray()
		var flat_uv := PackedVector2Array()
		var flat_i := PackedInt32Array()
		for i: int in indices.size():
			flat_v.append(verts[indices[i]])
			flat_c.append(colors[indices[i]])
			flat_uv.append(uvs[indices[i]])
			flat_i.append(i)
		return _commit(flat_v, _flat_normals(flat_v, flat_i), flat_c, flat_uv, flat_i, material, mesh)
	return _commit(verts, _smooth_normals(verts, indices), colors, uvs, indices, material, mesh)

static func _flat_normals(verts: PackedVector3Array, indices: PackedInt32Array) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i: int in range(0, indices.size(), 3):
		var n := (verts[indices[i + 2]] - verts[indices[i]]).cross(verts[indices[i + 1]] - verts[indices[i]]).normalized()
		for k: int in 3:
			normals[indices[i + k]] = n
	return normals

## A straight moulding: a profile of (out, up) points extruded along X.
func _extrude(profile: Array, length: float, material: Material, mesh: ArrayMesh = null) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var outline: Array = []
	for p: Vector2 in profile:
		outline.append(Vector2(p.x, p.y))
	for k: int in range(profile.size() - 1, -1, -1):
		var p: Vector2 = profile[k]
		outline.append(Vector2(-p.x, p.y))
	# Faces along the length.
	for k: int in outline.size():
		var p: Vector2 = outline[k]
		var q: Vector2 = outline[(k + 1) % outline.size()]
		var base := verts.size()
		for x: float in [-length * 0.5, length * 0.5]:
			verts.append(Vector3(x, p.y, p.x))
			verts.append(Vector3(x, q.y, q.x))
			colors.append_array([Color(1, 0, 0), Color(1, 0, 0)])
			uvs.append_array([Vector2(x, p.y), Vector2(x, q.y)])
		var edge := q - p
		var want := Vector3(0, -edge.x, edge.y).normalized()
		_tri(indices, verts, base, base + 1, base + 2, want)
		_tri(indices, verts, base + 1, base + 3, base + 2, want)
	# End caps as fans from the centre.
	for side: float in [-1.0, 1.0]:
		var centre := verts.size()
		verts.append(Vector3(side * length * 0.5, _profile_mid(profile), 0))
		colors.append(Color(1, 0, 0))
		uvs.append(Vector2.ZERO)
		var ring := verts.size()
		for p: Vector2 in outline:
			verts.append(Vector3(side * length * 0.5, p.y, p.x))
			colors.append(Color(1, 0, 0))
			uvs.append(Vector2(p.x, p.y))
		for k: int in outline.size():
			_tri(indices, verts, centre, ring + k, ring + (k + 1) % outline.size(), Vector3(side, 0, 0))
	return _commit(verts, _flat_normals(verts, indices), colors, uvs, indices, material, mesh)

static func _profile_mid(profile: Array) -> float:
	var low := INF
	var high := -INF
	for p: Vector2 in profile:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	return (low + high) * 0.5

## A block of size centred on centre (rotated by yaw), with vertex colour so it
## merges cleanly with the lathed and extruded pieces.
func _cuboid(size: Vector3, material: Material, centre := Vector3.ZERO, yaw := 0.0) -> ArrayMesh:
	var mesh := _extrude([Vector2(size.z * 0.5, -size.y * 0.5), Vector2(size.z * 0.5, size.y * 0.5), Vector2(0, size.y * 0.5)], size.x, material)
	return _merge([[mesh, Transform3D(Basis(Vector3.UP, yaw), centre)]])

## Merges [Mesh, Transform3D] pieces into one mesh, one surface per material.
func _merge(pieces: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for piece: Array in pieces:
		var mesh: Mesh = piece[0]
		var xform: Transform3D = piece[1] if piece.size() > 1 else Transform3D.IDENTITY
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if not tools.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools[material] = tool
			tools[material].append_from(mesh, surface, xform)
	var out := ArrayMesh.new()
	for material: Material in tools:
		tools[material].set_material(material)
		tools[material].commit(out)
	return out

## A fluted marble column of height h and radius r standing at the origin,
## split the way it breaks: its Attic base (which stays standing), drums of
## shaft with entasis, and a gilded necking under an Ionic-flavoured capital.
func _column_set(height: float, radius: float, broken := false, drums := 3) -> Dictionary:
	var key := "set_%.2f_%.2f_%s_%d" % [height, radius, broken, drums]
	if _meshes.has(key):
		return _meshes[key]
	var base_h := radius * 0.9
	var cap_h := radius * 1.3
	var shaft_top := height - cap_h if not broken else height
	var set := {"drums":[], "capital":null}
	set.base = _lathe([Vector2(0, 0), Vector2(radius * 1.55, 0), Vector2(radius * 1.55, base_h * 0.3), Vector2(radius * 1.35, base_h * 0.42),
		Vector2(radius * 1.42, base_h * 0.55), Vector2(radius * 1.22, base_h * 0.72), Vector2(radius * 1.25, base_h * 0.85), Vector2(radius * 1.0, base_h), Vector2(0, base_h)], 28, _marble)
	for d: int in drums:
		var profile: Array = []
		var y0 := lerpf(base_h, shaft_top, float(d) / drums)
		var y1 := lerpf(base_h, shaft_top, float(d + 1) / drums)
		profile.append(Vector2(0, y0))
		for k: int in 5:
			var y := lerpf(y0, y1, float(k) / 4.0)
			var t := (y - base_h) / maxf(shaft_top - base_h, 0.01)
			profile.append(Vector2(radius * (1.0 + 0.05 * sin(t * PI) - 0.12 * t), y))
		profile.append(Vector2(0, y1))
		set.drums.append(_lathe(profile, LATHE_SEGMENTS, _marble, FLUTES, 0.07))
	if not broken:
		var y := shaft_top
		var top_r := radius * 0.88
		var necking := _lathe([Vector2(0, y), Vector2(top_r * 1.05, y), Vector2(top_r * 1.08, y + cap_h * 0.12), Vector2(top_r * 1.02, y + cap_h * 0.2), Vector2(0, y + cap_h * 0.2)], 28, _gold)
		var echinus := _lathe([Vector2(0, y + cap_h * 0.2), Vector2(top_r * 1.02, y + cap_h * 0.2), Vector2(top_r * 1.35, y + cap_h * 0.5),
			Vector2(top_r * 1.5, y + cap_h * 0.68), Vector2(0, y + cap_h * 0.68)], 28, _marble)
		var abacus := _cuboid(Vector3(radius * 3.3, cap_h * 0.32, radius * 3.3), _marble, Vector3(0, y + cap_h * 0.84, 0))
		set.capital = _merge([[necking], [echinus], [abacus]])
	_meshes[key] = set
	return set

## The whole column above its base as one mesh, and the pieces it breaks into.
func _column_pieces(set: Dictionary) -> Array[Mesh]:
	var pieces: Array[Mesh] = []
	for drum: Mesh in set.drums:
		pieces.append(drum)
	if set.capital != null:
		pieces.append(set.capital)
	return pieces

## Distant temples and colossal pillars: unbreakable whole columns.
func _column(height: float, radius: float, broken := false) -> Array[Mesh]:
	var key := "column_%.2f_%.2f_%s" % [height, radius, broken]
	if not _meshes.has(key):
		var set := _column_set(height, radius, broken, 1)
		var whole: Array = []
		for piece: Mesh in _column_pieces(set):
			whole.append([piece])
		var out: Array[Mesh] = [_merge(whole), set.base]
		_meshes[key] = out
	return _meshes[key]

func _place_column(parent: Node, at: Vector3, height: float, radius: float, broken := false, yaw := 0.0) -> void:
	for mesh: Mesh in _column(height, radius, broken):
		_instance(mesh, Transform3D(Basis(Vector3.UP, yaw), at), parent)

## A classical entablature: architrave, gilded frieze, dentilled cornice.
func _entablature_profile(depth: float, height: float) -> Array:
	var d := depth * 0.5
	return [Vector2(d, 0), Vector2(d, height * 0.38), Vector2(d * 1.04, height * 0.4), Vector2(d * 1.04, height * 0.62),
		Vector2(d * 1.12, height * 0.7), Vector2(d * 1.22, height * 0.86), Vector2(d * 1.3, height * 0.9), Vector2(d * 1.3, height), Vector2(0, height)]

# --- Breakable architecture (ArenaProps, #115) ---------------------------------
# Each breakable body is drawn by one MeshInstance3D in the body's frame and
# owns the pieces it bursts into. ArenaPropVisual hides the whole and throws
# the pieces (prop_instances, prop_parts); prop_broken adds dust, glints and
# the crash of falling marble.

## Prop name -> MeshInstance3D / Array[Mesh] pieces / [centre height, size] for effects.
var _units: Dictionary = {}
var _pieces: Dictionary = {}
var _bursts: Dictionary = {}
const CRASH := "res://assets/audio/combat/hammer_crash.wav"

func prop_instances(name: String) -> Array:
	return [[_units[name]]] if _units.has(name) else []

func prop_parts(name: String) -> Array:
	return _pieces.get(name, [])

## A breakable body's art: whole (pieces in its frame) and what it breaks into.
func _unit(root: Node3D, body: Dictionary, whole: Array, pieces: Array[Mesh], burst_height: float) -> void:
	var node := _instance(_merge(whole), body.frame, root)
	node.name = body.name
	_units[body.name] = node
	_pieces[body.name] = pieces
	_bursts[body.name] = Vector2(burst_height, float(body.radius))

func _architecture() -> void:
	var root := Node3D.new()
	root.name = "Architecture"
	add_child(root)
	for item: Dictionary in GROUND.structures():
		match String(item.type):
			"rotunda": _rotunda(root, item)
			"colonnade": _colonnade(root, item)
			"arch": _arch(root, item)
			"obelisk": _obelisk(root, item)
			"stump": _stump(root, item)
			"balustrade": _balustrade(root, item)

func _rotunda(root: Node3D, item: Dictionary) -> void:
	var floor_y: float = item.base.origin.y
	var count: int = item.columns
	var radius: float = item.radius
	var height: float = item.height
	var ent: float = item.entablature
	var top := floor_y + height
	var r_in := radius - 1.7
	var r_out := radius + 1.7
	# The stepped stylobate ring stays whatever falls on it.
	_instance(_lathe([Vector2(radius - 3.0, floor_y - 0.4), Vector2(radius + 3.0, floor_y - 0.4), Vector2(radius + 3.0, floor_y + 0.1),
		Vector2(radius + 2.2, floor_y + 0.1), Vector2(radius + 2.2, floor_y + 0.35), Vector2(radius - 2.2, floor_y + 0.35), Vector2(radius - 2.2, floor_y + 0.1),
		Vector2(radius - 3.0, floor_y + 0.1), Vector2(radius - 3.0, floor_y - 0.4)], 72, _marble), Transform3D.IDENTITY, root)
	var ring: Array = [Vector2(r_in, top), Vector2(r_out, top), Vector2(r_out, top + ent * 0.4), Vector2(r_out + 0.1, top + ent * 0.42),
		Vector2(r_out + 0.1, top + ent * 0.62), Vector2(r_out + 0.5, top + ent * 0.85), Vector2(r_out + 0.6, top + ent), Vector2(r_in, top + ent), Vector2(r_in, top)]
	var band: Array = [Vector2(r_out + 0.12, top + ent * 0.42), Vector2(r_out + 0.16, top + ent * 0.52), Vector2(r_out + 0.12, top + ent * 0.62)]
	var bay := PI / count
	var columns: Array = item.bodies.filter(func(b: Dictionary) -> bool: return b.kind == "column")
	for body: Dictionary in columns:
		var a: float = body.angle
		var set := _column_set(height, float(item.column_radius))
		_instance(set.base, body.frame, root)
		# The column and the bay of the ring entablature it carries (built in
		# the arena frame, then taken into the column's).
		var into: Transform3D = body.frame.affine_inverse()
		var whole: Array = []
		var pieces := _column_pieces(set)
		for piece: Mesh in pieces:
			whole.append([piece])
		for half: Array in [[a - bay, a], [a, a + bay]]:
			var stone := _lathe(ring, 8, _marble, 0, 0.0, null, half[0], half[1], true)
			var gilt := _lathe(band, 8, _gold, 0, 0.0, null, half[0], half[1])
			whole.append([stone, into])
			whole.append([gilt, into])
			pieces.append(_merge([[stone, into], [gilt, into]]))
		_unit(root, body, whole, pieces, height * 0.6)
	# The gilded dome with marble ribs and its lantern: one piece that caves in
	# as eight gold wedges and the lantern when the columns give way.
	var dome_body: Dictionary = item.bodies.filter(func(b: Dictionary) -> bool: return b.kind == "dome")[0]
	var local: Transform3D = dome_body.frame.affine_inverse()
	var rise: float = item.dome_rise
	var dome_base := top + ent
	var outer: Array = []
	var shell: Array = []
	for k: int in 13:
		var t := float(k) / 12.0
		outer.append(Vector2((radius + 1.5) * cos(t * PI * 0.5), dome_base + rise * sin(t * PI * 0.5)))
	shell.append_array(outer)
	for k: int in range(12, -1, -1):
		var t := float(k) / 12.0
		shell.append(Vector2((radius + 0.9) * cos(t * PI * 0.5), dome_base + (rise - 0.6) * sin(t * PI * 0.5)))
	shell.append(outer[0])
	var dome: Array = [[_lathe([Vector2(0, dome_base)] + outer, 96, _gold), local]]
	for i: int in count:
		var rib: Array = []
		for k: int in 13:
			var t := float(k) / 12.0
			rib.append(Vector2((radius + 1.65) * cos(t * PI * 0.5), dome_base + (rise + 0.15) * sin(t * PI * 0.5)))
		dome.append([_rib_mesh(rib, 0.35), local * Transform3D(Basis(Vector3.UP, TAU * float(i) / count), Vector3.ZERO)])
	var lantern_y := dome_base + rise - 0.3
	for i: int in 8:
		var a := TAU * float(i) / 8.0
		for piece: Mesh in _column(4.2, 0.28):
			dome.append([piece, local * Transform3D(Basis.IDENTITY, Vector3(cos(a) * 2.4, lantern_y, sin(a) * 2.4))])
	var lantern := _merge([[_lathe([Vector2(0, lantern_y + 4.2), Vector2(3.2, lantern_y + 4.2), Vector2(3.2, lantern_y + 4.6), Vector2(2.6, lantern_y + 5.4),
		Vector2(1.2, lantern_y + 6.3), Vector2(0.3, lantern_y + 6.8), Vector2(0.18, lantern_y + 8.6), Vector2(0, lantern_y + 8.6)], 32, _gold), local],
		[_orb(0.55, _gold), local * Transform3D(Basis.IDENTITY, Vector3(0, lantern_y + 9.0, 0))]])
	dome.append([lantern])
	var wedges: Array[Mesh] = []
	for k: int in 8:
		wedges.append(_merge([[_lathe(shell, 6, _gold, 0, 0.0, null, TAU * k / 8.0, TAU * (k + 1) / 8.0, true), local]]))
	wedges.append(lantern)
	_unit(root, dome_body, dome, wedges, dome_base + rise * 0.5 - floor_y)
	# A warm glow inside the rotunda, as if the relic in the centre shines.
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, floor_y + 6.0, 0)
	glow.light_color = Color(1.0, 0.82, 0.5)
	glow.light_energy = 2.5
	glow.omni_range = 26.0
	glow.shadow_enabled = false
	root.add_child(glow)

func _orb(radius: float, material: Material) -> ArrayMesh:
	var profile: Array = []
	for k: int in 9:
		var t := float(k) / 8.0
		profile.append(Vector2(radius * sin(t * PI), -radius * cos(t * PI)))
	return _lathe(profile, 20, material)

## A thin gilded rib following a profile in the x-y plane.
func _rib_mesh(profile: Array, width: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for k: int in profile.size():
		var p: Vector2 = profile[k]
		for side: float in [-1.0, 1.0]:
			verts.append(Vector3(p.x, p.y, side * width * 0.5))
			colors.append(Color(1, 0, 0))
			uvs.append(Vector2(side, k))
	for k: int in profile.size() - 1:
		var a := k * 2
		var p: Vector2 = profile[k]
		var want := Vector3(p.x, p.y - profile[0].y, 0).normalized()
		_tri(indices, verts, a, a + 1, a + 2, want)
		_tri(indices, verts, a + 1, a + 3, a + 2, want)
	return _commit(verts, _smooth_normals(verts, indices), colors, uvs, indices, _marble)

func _colonnade(root: Node3D, item: Dictionary) -> void:
	var height: float = item.height
	for body: Dictionary in item.bodies:
		var base: Vector3 = body.frame.origin
		# The plinth and the column's base stay as a stub when it falls.
		_instance(_cuboid(GROUND.PLINTH, _marble, Vector3.UP * (GROUND.PLINTH.y * 0.5 - 0.3)), body.frame, root)
		var lift := GROUND.PLINTH.y - 0.3
		var set := _column_set(height - lift, GROUND.COLUMN_RADIUS)
		_instance(set.base, body.frame * Transform3D(Basis.IDENTITY, Vector3.UP * lift), root)
		var whole: Array = []
		var pieces: Array[Mesh] = []
		for piece: Mesh in _column_pieces(set):
			whole.append([piece, Transform3D(Basis.IDENTITY, Vector3.UP * lift)])
			pieces.append(_merge([[piece, Transform3D(Basis.IDENTITY, Vector3.UP * lift)]]))
		# Its stretch of the entablature, in two blocks, with the gilded frieze.
		var beam: Vector2 = body.beam
		var top: float = float(body.top) - base.y
		for half: Array in [[-beam.x, 0.0], [0.0, beam.y]]:
			var length: float = half[1] - half[0]
			var centre := Vector3((half[0] + half[1]) * 0.5, 0, 0)
			var stone := _extrude(_entablature_profile(GROUND.BEAM.x, GROUND.BEAM.y), length, _marble)
			var gilt := _cuboid(Vector3(length + 0.02, GROUND.BEAM.y * 0.2, GROUND.BEAM.x * 1.05), _gold, Vector3(0, GROUND.BEAM.y * 0.51, 0))
			var block := _merge([[stone, Transform3D(Basis.IDENTITY, centre + Vector3.UP * top)], [gilt, Transform3D(Basis.IDENTITY, centre + Vector3.UP * top)]])
			whole.append([block])
			pieces.append(block)
		_unit(root, body, whole, pieces, height * 0.6)

func _arch(root: Node3D, item: Dictionary) -> void:
	var height: float = item.height
	var lintel := height - GROUND.ATTIC
	for body: Dictionary in item.bodies:
		if body.kind == "pier":
			# The plinth stays; the pier comes down in three blocks and its two
			# engaged columns in drums.
			_instance(_cuboid(Vector3(GROUND.PIER.x + 0.6, 1.2, GROUND.PIER.y + 0.6), _marble), body.frame, root)
			var whole: Array = []
			var pieces: Array[Mesh] = []
			var block_h := (lintel + 0.6) / 3.0
			for k: int in 3:
				var block := _cuboid(Vector3(GROUND.PIER.x, block_h, GROUND.PIER.y), _marble, Vector3(0, -0.6 + block_h * (k + 0.5), 0))
				whole.append([block])
				pieces.append(block)
			var impost := _cuboid(Vector3(GROUND.PIER.x + 0.5, 0.5, GROUND.PIER.y + 0.5), _gold, Vector3(0, lintel - 0.25, 0))
			whole.append([impost])
			for face: float in [-1.0, 1.0]:
				var foot := Transform3D(Basis.IDENTITY, Vector3(0, 0.6, face * (GROUND.PIER.y * 0.5 + 0.1)))
				var set := _column_set(lintel - 0.6, 0.75, false, 2)
				whole.append([set.base, foot])
				for piece: Mesh in _column_pieces(set):
					whole.append([piece, foot])
					pieces.append(_merge([[piece, foot]]))
			_unit(root, body, whole, pieces, lintel * 0.5)
		else:
			# The attic and its gilded sunburst fall as three blocks and the sun.
			var span: float = item.span
			var length := span + GROUND.PIER.x * 2.0
			var whole: Array = []
			var pieces: Array[Mesh] = []
			for k: int in 3:
				var block := _extrude(_entablature_profile(GROUND.PIER.y, GROUND.ATTIC), length / 3.0, _marble)
				var at := Transform3D(Basis.IDENTITY, Vector3(-length / 3.0 + k * length / 3.0, 0, 0))
				whole.append([block, at])
				pieces.append(_merge([[block, at]]))
			var sun: Array = []
			var up := GROUND.ATTIC + 2.4
			sun.append([_lathe([Vector2(0, -0.25), Vector2(2.6, -0.25), Vector2(2.6, 0.25), Vector2(0, 0.25)], 48, _gold), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.UP * up)])
			for k: int in 16:
				var a := TAU * float(k) / 16.0
				var reach := 3.2 if k % 2 == 0 else 2.9
				sun.append([_cuboid(Vector3(0.3, 2.2 if k % 2 == 0 else 1.4, 0.3), _gold), Transform3D(Basis(Vector3.BACK, a - PI * 0.5), Vector3.UP * up + Vector3(cos(a), sin(a), 0) * reach)])
			sun.append([_cuboid(Vector3(1.2, 1.8, 1.2), _marble, Vector3.UP * GROUND.ATTIC)])
			var sunburst := _merge(sun)
			whole.append([sunburst])
			pieces.append(sunburst)
			_unit(root, body, whole, pieces, GROUND.ATTIC * 0.5)

func _obelisk(root: Node3D, item: Dictionary) -> void:
	var height: float = item.height
	var p := GROUND.PEDESTAL
	for body: Dictionary in item.bodies:
		if body.kind != "obelisk":
			# The stepped pedestal never breaks.
			for k: int in 3:
				var grow := 1.0 + (2 - k) * 0.12
				_instance(_cuboid(Vector3(p.x * grow, p.y / 3.0, p.z * grow), _marble, Vector3.UP * (-0.4 + p.y / 6.0 + k * p.y / 3.0)), body.frame, root)
			_instance(_cuboid(Vector3(p.x * 0.8, 0.25, p.z * 0.8), _gold, Vector3.UP * (p.y - 0.35)), body.frame, root)
			continue
		var shaft := height - 2.0
		var bottom := p.y - 0.4
		var turn := Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.ZERO)
		var whole: Array = []
		var pieces: Array[Mesh] = []
		for k: int in 3:
			var y0 := lerpf(bottom, shaft, k / 3.0)
			var y1 := lerpf(bottom, shaft, (k + 1) / 3.0)
			var w0 := lerpf(GROUND.OBELISK.x, GROUND.OBELISK.y, k / 3.0) * sqrt(2.0)
			var w1 := lerpf(GROUND.OBELISK.x, GROUND.OBELISK.y, (k + 1) / 3.0) * sqrt(2.0)
			var segment := _merge([[_lathe([Vector2(0, y0), Vector2(w0, y0), Vector2(w1, y1), Vector2(0, y1)], 4, _marble), turn]])
			whole.append([segment])
			pieces.append(segment)
		var tip := _merge([[_lathe([Vector2(0, shaft), Vector2(GROUND.OBELISK.y * sqrt(2.0), shaft), Vector2(0, height)], 4, _gold), turn]])
		whole.append([tip])
		pieces.append(tip)
		_unit(root, body, whole, pieces, height * 0.5)

func _stump(root: Node3D, item: Dictionary) -> void:
	for body: Dictionary in item.bodies:
		_instance(_cuboid(GROUND.PLINTH, _marble, Vector3.UP * (GROUND.PLINTH.y * 0.5 - 0.3)), body.frame, root)
		var lift := GROUND.PLINTH.y - 0.3
		var set := _column_set(float(item.height) - lift, GROUND.STUMP_RADIUS * 0.9, true, 2)
		var foot := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3.UP * lift)
		_instance(set.base, body.frame * foot, root)
		var whole: Array = []
		var pieces: Array[Mesh] = []
		for piece: Mesh in _column_pieces(set):
			whole.append([piece, foot])
			pieces.append(_merge([[piece, foot]]))
		_unit(root, body, whole, pieces, float(item.height) * 0.5)

func _balustrade(root: Node3D, item: Dictionary) -> void:
	var height: float = item.height
	var posts: Array = item.posts
	var baluster := _lathe([Vector2(0, 0), Vector2(0.17, 0), Vector2(0.17, 0.12), Vector2(0.1, 0.22), Vector2(0.21, 0.5), Vector2(0.09, 0.85),
		Vector2(0.13, 0.95), Vector2(0.13, 1.0), Vector2(0, 1.0)], 12, _marble)
	var depth: float = GROUND.RAIL_DEPTH
	for body: Dictionary in item.bodies:
		var length: float = body.length
		var mid: Vector3 = body.frame.origin
		var whole: Array = []
		var pieces: Array[Mesh] = []
		var low := _cuboid(Vector3(length + 0.2, 0.3, depth), _marble, Vector3.UP * 0.15)
		var post := _cuboid(Vector3(0.9, height + 0.15, 0.9), _marble, Vector3(-length * 0.5, height * 0.5, 0))
		whole.append_array([[low], [post]])
		pieces.append_array([low, post])
		for half: float in [-1.0, 1.0]:
			var rail := _cuboid(Vector3(length * 0.5 + 0.1, 0.22, depth * 1.1), _marble, Vector3(half * length * 0.25, height - 0.11, 0))
			whole.append([rail])
			pieces.append(rail)
		var count := maxi(1, int(length / 0.55))
		for k: int in count:
			var at := Transform3D(Basis().scaled(Vector3(1, height - 0.52, 1)), Vector3(-length * 0.5 + (float(k) + 0.5) * length / count, 0.3, 0))
			whole.append([baluster, at])
			# A few of them fly loose; the rest burst into dust.
			if k % 3 == 1:
				pieces.append(_merge([[baluster, at]]))
		_unit(root, body, whole, pieces, height * 0.5)
	var last: Vector3 = posts[posts.size() - 1]
	_instance(_cuboid(Vector3(0.9, height + 0.15, 0.9), _marble, last + Vector3.UP * (height * 0.5)), Transform3D.IDENTITY, root)

## Witnessed breaks: a burst of marble dust and golden glints, and the crash.
func prop_broken(name: String, prop: Dictionary, blow: Dictionary, moving: bool) -> void:
	if not moving or not _bursts.has(name):
		return
	var burst: Vector2 = _bursts[name]
	var centre: Vector3 = (_units[name] as Node3D).global_position + Vector3.UP * burst.x
	var size := clampf(burst.y, 1.0, 20.0)
	var big := String(prop.kind) in ["dome", "attic", "pier"]
	_dust(centre, size, 90 if big else 40)
	_glints(centre, size)
	AudioPreferences.ensure_buses()
	var crash := AudioStreamPlayer3D.new()
	crash.stream = load(CRASH)
	crash.bus = &"BBEffects"
	crash.pitch_scale = 0.42 if prop.kind == "dome" else (0.6 if big else _rng.randf_range(0.7, 0.9))
	crash.volume_db = 4.0 if big else 0.0
	crash.unit_size = 18.0
	crash.max_distance = 500.0
	add_child(crash)
	crash.global_position = centre
	crash.play()
	crash.finished.connect(crash.queue_free)

var _dust_material: StandardMaterial3D
func _dust(centre: Vector3, size: float, amount: int) -> void:
	if _dust_material == null:
		_dust_material = StandardMaterial3D.new()
		_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_material.vertex_color_use_as_albedo = true
		_dust_material.albedo_texture = _soft_dot()
		_dust_material.proximity_fade_enabled = true
		_dust_material.proximity_fade_distance = 2.0
	var particles := _burst_particles(centre, amount, 2.6, _dust_material, Vector2(3.0, 5.5))
	var process: ParticleProcessMaterial = particles.process_material
	process.emission_sphere_radius = size * 0.6
	process.initial_velocity_min = 2.0
	process.initial_velocity_max = 7.0
	process.gravity = Vector3(0, -0.6, 0)
	process.damping_min = 2.5
	process.damping_max = 4.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	var scale := CurveTexture.new()
	scale.curve = grow
	process.scale_curve = scale
	process.color_ramp = _fade(Color(0.98, 0.95, 0.9, 0.75))

var _glint_material: StandardMaterial3D
func _glints(centre: Vector3, size: float) -> void:
	if _glint_material == null:
		_glint_material = StandardMaterial3D.new()
		_glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glint_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glint_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_glint_material.vertex_color_use_as_albedo = true
		_glint_material.albedo_texture = _soft_dot()
	var particles := _burst_particles(centre, 36, 1.4, _glint_material, Vector2(0.25, 0.25))
	var process: ParticleProcessMaterial = particles.process_material
	process.emission_sphere_radius = size * 0.4
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 11.0
	process.gravity = Vector3(0, -9.8, 0)
	process.color_ramp = _fade(Color(2.4, 1.8, 0.8, 1.0))

func _burst_particles(centre: Vector3, amount: int, lifetime: float, material: Material, quad_size: Vector2) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = amount
	particles.lifetime = lifetime
	particles.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.direction = Vector3.UP
	process.spread = 180.0
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.material = material
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	particles.global_position = centre
	particles.emitting = true
	particles.finished.connect(particles.queue_free)
	return particles

func _fade(colour: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, colour)
	gradient.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	return ramp

var _dot: GradientTexture2D
func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		_dot = GradientTexture2D.new()
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		var glow := Gradient.new()
		glow.set_color(0, Color(1, 1, 1, 1))
		glow.set_color(1, Color(1, 1, 1, 0))
		_dot.gradient = glow
	return _dot

# --- Gardens -----------------------------------------------------------------

## Lush grass tufts on the lawns (not on paving, edges stay crisp).
func _gardens() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SCAN_PROP
	mat.set_shader_parameter("foliage", true)
	mat.set_shader_parameter("albedo_tex", load("res://assets/textures/woodland/grass_patches.png"))
	mat.set_shader_parameter("has_normal", false)
	mat.set_shader_parameter("has_arm", false)
	mat.set_shader_parameter("cutoff", 0.5)
	mat.set_shader_parameter("tint", Color(0.85, 1.3, 0.55))
	var cards: Array[Mesh] = []
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
		cards.append(tool.commit())
	var cfg: RefCounted = GROUND.settings()
	var cell_size := 24.0
	var cells: Dictionary = {}
	var attempts := 60000
	var sdf: PackedFloat32Array = GROUND.grid_sdf()
	var n_grid: int = GROUND.grid_size()
	for n: int in attempts:
		var p := Vector2(_rng.randf_range(-cfg.half, cfg.half), _rng.randf_range(-cfg.half, cfg.half))
		var cell := Vector2i(roundi(p.x + cfg.half), roundi(p.y + cfg.half))
		if sdf[cell.y * n_grid + cell.x] > -1.5 or GROUND.halo_sdf(p) > 0.0:
			continue
		if _paved(p.x, p.y):
			continue
		var key := Vector2i(floori(p.x / cell_size), floori(p.y / cell_size))
		if not cells.has(key):
			cells[key] = []
		var scale := _rng.randf_range(0.6, 1.0)
		cells[key].append([_rng.randi() % cards.size(), Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(scale, scale * _rng.randf_range(0.8, 1.3), scale)),
			Vector3(p.x, GROUND.surface_at(p.x, p.y) - 0.05, p.y))])
	var root := Node3D.new()
	root.name = "Grass"
	add_child(root)
	for key: Vector2i in cells:
		var by_variant: Dictionary = {}
		for entry: Array in cells[key]:
			if not by_variant.has(entry[0]):
				by_variant[entry[0]] = []
			by_variant[entry[0]].append(entry[1])
		for variant: int in by_variant:
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = cards[variant]
			multimesh.instance_count = by_variant[variant].size()
			for k: int in by_variant[variant].size():
				multimesh.set_instance_transform(k, by_variant[variant][k])
			var node := MultiMeshInstance3D.new()
			node.multimesh = multimesh
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.visibility_range_end = 140.0
			node.visibility_range_end_margin = 20.0
			root.add_child(node)

# --- Water -------------------------------------------------------------------

func _waterfalls() -> void:
	var cfg: RefCounted = GROUND.settings()
	var root := Node3D.new()
	root.name = "Waterfalls"
	add_child(root)
	var count := int(cfg.art.waterfalls)
	# Off the Halo's outer rim between the starts, and off the Sanctum into the chasm.
	var places: Array = []
	var outer := count - 2
	for k: int in outer:
		var a := TAU * (float(k) + 0.37) / float(outer)
		places.append([a, GROUND.halo_outer(a), 1.0])
	for a: float in [PI * 0.25, PI * 1.25]:
		places.append([a + 0.12, GROUND.sanctum_radius(a + 0.12), 1.0])
	for place: Array in places:
		var a: float = place[0]
		var out := Vector3(cos(a), 0, sin(a))
		var edge := out * (float(place[1]) - 1.0)
		edge.y = GROUND.height_at(edge.x - out.x * 2.0, edge.z - out.z * 2.0) - 1.2
		var width := _rng.randf_range(5.0, 9.0)
		var length := 230.0
		_instance(_fall_mesh(edge, out, width, length), Transform3D.IDENTITY, root, false)
		# Spray where it leaves the cliff.
		var spray := MultiMesh.new()
		spray.transform_format = MultiMesh.TRANSFORM_3D
		spray.mesh = _puff_mesh()
		spray.instance_count = 6
		for k: int in 6:
			var s := _rng.randf_range(2.0, 4.0)
			spray.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * s), edge + out * (3.0 + k * 1.4) + Vector3.DOWN * (4.0 + k * 5.0)
				+ Vector3(-out.z, 0, out.x) * _rng.randf_range(-2.0, 2.0)))
		var mist := MultiMeshInstance3D.new()
		mist.multimesh = spray
		mist.material_override = _cloud_material(0.55, 1.6, 2.0)
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mist)

func _fall_mesh(edge: Vector3, out: Vector3, width: float, length: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var side := Vector3(-out.z, 0, out.x)
	var rows := 40
	for k: int in rows + 1:
		var t := float(k) / rows
		var spread := width * (1.0 + t * 1.6)
		var centre := edge + out * (1.5 + 14.0 * sqrt(t)) + Vector3.DOWN * length * t
		for s: float in [-0.5, 0.5]:
			verts.append(centre + side * spread * s)
			colors.append(Color.WHITE)
			uvs.append(Vector2(s + 0.5, t))
	for k: int in rows:
		var a := k * 2
		_tri(indices, verts, a, a + 1, a + 2, out)
		_tri(indices, verts, a + 1, a + 3, a + 2, out)
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("fall_length", length)
	return _commit(verts, _smooth_normals(verts, indices), colors, uvs, indices, mat)

# --- Clouds ------------------------------------------------------------------

var _puff: Mesh
func _puff_mesh() -> Mesh:
	if _puff == null:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 28
		sphere.rings = 14
		_puff = sphere
	return _puff

## The cloud sea: a polar disc dense near the arena, out to the horizon.
func _cloud_sea() -> void:
	var cfg: RefCounted = GROUND.settings()
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := 140
	var segments := 220
	var reach := float(cfg.art.view_distance) * 1.4
	for k: int in rings + 1:
		var t := float(k) / rings
		var r := reach * pow(t, 2.2)
		for s: int in segments:
			var a := TAU * float(s) / segments
			verts.append(Vector3(cos(a) * r, 0, sin(a) * r))
			colors.append(Color.WHITE)
			uvs.append(Vector2(float(s) / segments, t))
	for k: int in rings:
		for s: int in segments:
			var a := k * segments + s
			var b := k * segments + (s + 1) % segments
			var c := a + segments
			var d := b + segments
			_tri(indices, verts, a, b, c, Vector3.UP)
			_tri(indices, verts, b, d, c, Vector3.UP)
	var mat := ShaderMaterial.new()
	mat.shader = SEA_SHADER
	mat.set_shader_parameter("sun_dir", _sun_dir)
	mat.set_shader_parameter("far_fade", float(cfg.art.view_distance))
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var mesh := _commit(verts, normals, colors, uvs, indices, mat)
	mesh.custom_aabb = AABB(Vector3(-reach, -50, -reach), Vector3(reach * 2.0, 200, reach * 2.0))
	var sea := _instance(mesh, Transform3D(Basis.IDENTITY, Vector3(0, float(cfg.art.cloud_sea_y), 0)), self, false)
	sea.name = "CloudSea"

## Billowing banks round the cliffs, in the chasm and the wells, and drifting
## layers in the abyss between the islands and the sea.
func _cloud_banks() -> void:
	var cfg: RefCounted = GROUND.settings()
	var near: Array[Transform3D] = []
	var mid: Array[Transform3D] = []
	# Hugging the cliffs of every edge, below the lip so the edge stays readable.
	var samples := 900
	for k: int in samples:
		var a := TAU * float(k) / samples + _rng.randf() * 0.01
		for edge: Array in [[GROUND.halo_outer(a), 1.0], [GROUND.halo_inner(a), -1.0], [GROUND.sanctum_radius(a), 1.0]]:
			var r: float = edge[0]
			var out: float = edge[1]
			if _rng.randf() > (0.2 if out > 0.0 and r > 100.0 else 0.25):
				continue
			var p := Vector2(cos(a), sin(a)) * (r + out * _rng.randf_range(-3.0, 9.0))
			var size := _rng.randf_range(5.0, 13.0)
			# The outer rim's banks hang just under the lip; the chasm stays
			# open to a deep, hazy drop with clouds far down.
			var y := -size * 0.6 - _rng.randf_range(10.0, 34.0)
			if out < 0.0 or r < 50.0:
				y = -_rng.randf_range(70.0, 120.0)
				size *= 1.6
			near.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(size * 1.5, size, size * 1.4)), Vector3(p.x, y, p.y)))
	# Filling the cloud wells far below their rims.
	for well: Dictionary in GROUND.wells():
		for k: int in 8:
			var p: Vector2 = well.at + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * float(well.radius)
			var size := _rng.randf_range(4.0, 8.0)
			near.append(Transform3D(Basis().scaled(Vector3(size * 1.3, size, size * 1.3)), Vector3(p.x, -22.0 - k * 4.0, p.y)))
	# Drifting layers in the abyss below and around the islands.
	for k: int in 520:
		var r := sqrt(_rng.randf()) * 900.0 + 20.0
		var a := _rng.randf() * TAU
		var size := _rng.randf_range(12.0, 40.0)
		var y := _rng.randf_range(float(cfg.art.cloud_sea_y) + 10.0, -70.0)
		if r > 450.0 and _rng.randf() < 0.3:
			y = _rng.randf_range(-60.0, 10.0)
		mid.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(size * 2.2, size, size * 1.8)), Vector3(cos(a) * r, y, sin(a) * r)))
	_puff_layer("CliffClouds", near, _cloud_material(0.85, 1.25, 6.0), 900.0)
	_puff_layer("AbyssClouds", mid, _cloud_material(0.85, 1.3, 14.0), 4000.0)
	# Cumulus towers on the horizon.
	var towers: Array[Transform3D] = []
	for k: int in 26:
		var a := TAU * float(k) / 26.0 + _rng.randf_range(-0.08, 0.08)
		var r := _rng.randf_range(1800.0, 3600.0)
		var base := Vector3(cos(a) * r, float(cfg.art.cloud_sea_y), sin(a) * r)
		var tall := _rng.randf_range(250.0, 650.0)
		var puffs := 14
		for n: int in puffs:
			var t := float(n) / puffs
			var size := lerpf(170.0, 70.0, t) * _rng.randf_range(0.7, 1.2)
			var offset := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * size * 0.8
			towers.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(size * 1.2, size * 0.8, size * 1.2)), base + offset + Vector3.UP * tall * t))
	var tower_mat := _cloud_material(0.97, 0.7, 60.0)
	tower_mat.set_shader_parameter("swell", 0.22)
	_puff_layer("CumulusTowers", towers, tower_mat, 0.0)

func _puff_layer(name_hint: String, xforms: Array[Transform3D], material: Material, range_end: float) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _puff_mesh()
	multimesh.instance_count = xforms.size()
	for k: int in xforms.size():
		multimesh.set_instance_transform(k, xforms[k])
	var node := MultiMeshInstance3D.new()
	node.name = name_hint
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_end > 0.0:
		node.visibility_range_end = range_end
	add_child(node)

# --- The heavens beyond ----------------------------------------------------------

## Distant floating islands crowned with temples, and colossal pillars rising
## out of the cloud sea.
func _distant() -> void:
	var root := Node3D.new()
	root.name = "Heavens"
	add_child(root)
	var islands := [
		[Vector2(-420, -520), 70.0, 40.0], [Vector2(560, -380), 55.0, 85.0], [Vector2(-760, 180), 90.0, 15.0],
		[Vector2(820, 420), 75.0, 60.0], [Vector2(150, -980), 110.0, 120.0], [Vector2(-300, 900), 85.0, 70.0],
		[Vector2(1350, -700), 130.0, 30.0], [Vector2(-1400, -600), 120.0, 140.0], [Vector2(380, 1250), 95.0, 20.0],
		[Vector2(-240, -260), 28.0, 55.0], [Vector2(300, 250), 24.0, 75.0], [Vector2(-1000, 1200), 140.0, 90.0],
	]
	var index := 0
	for spec: Array in islands:
		var centre: Vector2 = spec[0]
		var radius: float = spec[1]
		var top_y: float = spec[2]
		var seed := float(index) * 13.7
		var step := maxf(2.0, radius / 28.0)
		var n := ceili(radius * 2.6 / step) + 1
		var origin := centre - Vector2.ONE * radius * 1.3
		var sdf := PackedFloat32Array()
		var heights := PackedFloat32Array()
		sdf.resize(n * n)
		heights.resize(n * n)
		for z: int in n:
			for x: int in n:
				var p := origin + Vector2(x, z) * step
				var q := p - centre
				var a := q.angle()
				var edge := radius * (1.0 + 0.12 * sin(a * 3.0 + seed) + 0.07 * sin(a * 7.0 + seed * 2.0) + 0.04 * sin(a * 13.0))
				sdf[z * n + x] = q.length() - edge
				heights[z * n + x] = top_y + 3.0 * _value_noise(p * 0.03 + Vector2(seed, 0)) * (1.0 - clampf(q.length() / radius, 0, 1))
		var island_roots := func(x: float, z: float, inside: float) -> float:
			var p := Vector2(x, z)
			var lobes := maxf(0.0, _value_noise(p * 0.035 + Vector2(seed, 9)) - 0.42) * radius * 1.4 * smoothstep(3.0, 12.0, inside)
			return minf(LIP + pow(inside, 1.05) * 2.0 * (0.5 + 0.9 * _value_noise(p * 0.04 + Vector2(seed, 3))) + lobes, radius * 2.4)
		var island_paint := func(x: float, z: float, inside: float) -> Color:
			return Color(0.0, 1.0 - clampf(inside / 3.0, 0, 1), 0.0)
		_island(origin, step, n, n, sdf, heights, island_paint, island_roots, "Distant%d" % index, root)
		# Each carries a small temple of columns, some ruined.
		var temple := Vector3(centre.x, top_y, centre.y)
		var count := 8 if index % 3 != 2 else 6
		var ring := minf(radius * 0.35, 18.0)
		for k: int in count:
			var a := TAU * float(k) / count
			var broken := index % 4 == 1 and k % 3 == 0
			_place_column(root, temple + Vector3(cos(a) * ring, 0, sin(a) * ring), 11.0 if not broken else 5.0, 1.0, broken)
		if index % 2 == 0:
			var dome: Array = [Vector2(0, top_y + 11.0)]
			for k: int in 9:
				var t := float(k) / 8.0
				dome.append(Vector2((ring + 1.4) * cos(t * PI * 0.5), top_y + 11.0 + (ring * 0.5) * sin(t * PI * 0.5)))
			_instance(_lathe(dome, 32, _gold), Transform3D(Basis.IDENTITY, Vector3(centre.x, 0, centre.y)), root)
		# A waterfall over the side of the larger ones.
		if radius > 60.0:
			var a := seed
			var out := Vector3(cos(a), 0, sin(a))
			var edge_r := radius * (1.0 + 0.12 * sin(a * 3.0 + seed) + 0.07 * sin(a * 7.0 + seed * 2.0) + 0.04 * sin(a * 13.0))
			var edge := Vector3(centre.x, top_y - 1.5, centre.y) + out * (edge_r - 1.0)
			_instance(_fall_mesh(edge, out, radius * 0.12, 260.0), Transform3D.IDENTITY, root, false)
		index += 1
	# Colossal pillars rising out of the clouds, a few of them broken.
	var pillars := [[Vector2(-900, -1400), 520.0, false], [Vector2(1500, -1100), 640.0, true], [Vector2(2000, 300), 460.0, false],
		[Vector2(-1900, -200), 600.0, true], [Vector2(-1500, 1300), 700.0, false], [Vector2(700, 1900), 540.0, false],
		[Vector2(200, -2300), 760.0, false]]
	for spec: Array in pillars:
		var at: Vector2 = spec[0]
		var height: float = spec[1]
		var base_y := float(GROUND.settings().art.cloud_sea_y) - 60.0
		var radius := height * 0.055
		for mesh: Mesh in _column(height, radius, spec[2]):
			_instance(mesh, Transform3D(Basis.IDENTITY, Vector3(at.x, base_y, at.y)), root, false)

## Shafts of heavenly light slanting down through the abyss.
func _rays() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = RAY_SHADER
	mat.set_shader_parameter("strength", 0.09)
	var root := Node3D.new()
	root.name = "LightShafts"
	add_child(root)
	var down := -_sun_dir
	for k: int in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(140.0, 700.0)
		var length := _rng.randf_range(500.0, 900.0)
		var radius := _rng.randf_range(10.0, 34.0)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = radius * 0.8
		cylinder.bottom_radius = radius
		cylinder.height = length
		cylinder.radial_segments = 24
		cylinder.rings = 1
		cylinder.cap_top = false
		cylinder.cap_bottom = false
		cylinder.material = mat
		var target := Vector3(cos(a) * r, _rng.randf_range(-120.0, -40.0), sin(a) * r)
		var centre := target - down * length * 0.5
		var y_axis := -down
		var x_axis := y_axis.cross(Vector3.FORWARD).normalized()
		var basis := Basis(x_axis, y_axis, x_axis.cross(y_axis))
		_instance(cylinder, Transform3D(basis, centre), root, false)

## Golden motes drifting in the air around the camera.
func _golden_motes() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "GoldenMotes"
	particles.amount = 500
	particles.lifetime = 9.0
	particles.preprocess = 9.0
	particles.visibility_aabb = AABB(Vector3(-70, -40, -70), Vector3(140, 80, 140))
	particles.local_coords = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(60, 25, 60)
	process.gravity = Vector3(0, 0.25, 0)
	process.initial_velocity_min = 0.1
	process.initial_velocity_max = 0.6
	process.direction = Vector3(0.3, 1, 0.1)
	process.spread = 180.0
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.0, 0.85, 0.5)
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var glow := Gradient.new()
	glow.set_color(0, Color(1, 1, 1, 1))
	glow.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = glow
	mat.albedo_texture = dot
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.45)
	mat.emission_energy_multiplier = 2.0
	quad.material = mat
	particles.draw_pass_1 = quad
	add_child(particles)
	_motes = particles
