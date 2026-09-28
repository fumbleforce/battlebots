extends Node
## Practice Duel target panel (#97): a red silhouette outline round the
## targeted NPC. Each of the bot's meshes gets two child copies, drawn in the
## transparent pass: an invisible mask that marks the bot's pixels in the
## stencil buffer, then (later, by render priority) a red hull grown along the
## normals that draws only where no mask was written. So only the rim outside
## the whole bot's silhouette shows, never the seams between its parts.
## Presentation only; the bot's own materials and overlays (the damage and
## wreck visuals use material_overlay) are left alone. The item card (#105)
## outlines the selected item pickup in yellow with a second one (ITEM_*).
const COLOR := Color(1.0, 0.12, 0.1)
const ITEM_COLOR := Color(1.0, 0.85, 0.1)
## Rim width in metres, whatever the mesh's scale.
const WIDTH := 0.05
## Stencil value the masks write (any value no other effect uses).
const STENCIL := 97
const ITEM_STENCIL := 105
const COPY_NAME := "PracticeTargetOutline"
const ITEM_COPY_NAME := "PracticeItemOutline"
const MASK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
stencil_mode write, write_depth_fail, compare_always, %d;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""
## Grows the hull along each vertex's rim direction (_rim_mesh), carried in
## CUSTOM0; skinned meshes, whose CUSTOM0 would not follow the bones, grow
## along NORMAL instead (%s is the attribute).
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
stencil_mode read, compare_not_equal, %d;
uniform vec4 outline_color : source_color;
uniform float width;
void vertex() {
	float scale = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += %s * width / scale;
}
void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = 1.0;
}
"""
## The rim leaves a sharp corner at most this many WIDTHs out.
const MAX_CORNER_REACH := 3.0
## Rim meshes kept before the cache starts over.
const RIM_CACHE_SIZE := 256
var _bot: Node
var _copies: Array[MeshInstance3D] = []
var _mask: ShaderMaterial
var _rim: ShaderMaterial
var _skinned_rim: ShaderMaterial
## Source mesh -> its rim copy (_rim_mesh), built once.
var _rim_meshes: Dictionary = {}
## Its copies' name prefix; also the node's name.
var copy_name := COPY_NAME
## Meshes by these names are left out (the token inside an item's glass cage).
var skip_names: Array[String] = []

func _init(color := COLOR, stencil := STENCIL, prefix := COPY_NAME) -> void:
	copy_name = prefix
	name = prefix
	_mask = _material(MASK_SHADER % stencil, 0)
	_rim = _material(RIM_SHADER % [stencil, "CUSTOM0.xyz"], 1)
	_skinned_rim = _material(RIM_SHADER % [stencil, "NORMAL"], 1)
	for rim: ShaderMaterial in [_rim, _skinned_rim]:
		rim.set_shader_parameter("outline_color", color)
		rim.set_shader_parameter("width", WIDTH)

static func _material(code: String, priority: int) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = priority
	return material

## Outlines bot, or nothing for null. Called every frame: a part swap replaces
## the bot node and a damaged bot can gain or lose meshes, so it re-dresses.
func show_on(bot: Node) -> void:
	if not is_instance_valid(bot):
		clear()
		return
	var meshes := _meshes(bot)
	# A changed mesh (an item's new contents) re-dresses too.
	if bot == _bot and meshes.size() * 2 == _copies.size() and _copies.all(func(copy: MeshInstance3D) -> bool:
			return is_instance_valid(copy) and copy.get_meta(&"source") == (copy.get_parent() as MeshInstance3D).mesh):
		return
	clear()
	_bot = bot
	for mesh: MeshInstance3D in meshes:
		var skinned := mesh.skin != null or not mesh.skeleton.is_empty()
		for layer: Array in [["Mask", _mask], ["Rim", _skinned_rim if skinned else _rim]]:
			var copy := MeshInstance3D.new()
			copy.name = copy_name + str(layer[0])
			copy.mesh = _rim_mesh(mesh.mesh) if layer[1] == _rim else mesh.mesh
			copy.set_meta(&"source", mesh.mesh)
			copy.skin = mesh.skin
			if not mesh.skeleton.is_empty():
				copy.skeleton = NodePath("../" + str(mesh.skeleton))
			copy.material_override = layer[1]
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.add_to_group(preload("res://scripts/presentation/wreck_pieces.gd").SKIP_GROUP)
			mesh.add_child(copy)
			_copies.append(copy)

## source with each vertex's rim direction in CUSTOM0. Hard-edged meshes (a
## box, a saw's teeth) split each corner into one vertex per face, each with
## that face's normal; grown along those the faces part at the edges and the
## rim breaks up (#105). So every vertex at a position takes the same
## direction: the mean of the faces' normals there, lengthened so each face
## still moves out a full WIDTH (a box grows into a box WIDTH larger all
## round), and at most MAX_CORNER_REACH at a needle-sharp tip.
func _rim_mesh(source: Mesh) -> Mesh:
	if _rim_meshes.has(source):
		return _rim_meshes[source]
	# Swapped-out parts' meshes are not kept for ever.
	if _rim_meshes.size() >= RIM_CACHE_SIZE:
		_rim_meshes.clear()
	var rim := ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		# Position -> the distinct face normals meeting there.
		var faces: Dictionary = {}
		for index: int in vertices.size():
			var key := Vector3i((vertices[index] * 10000.0).round())
			var normal := normals[index] if index < normals.size() else Vector3.ZERO
			var seen: Array = faces.get_or_add(key, [])
			if not normal.is_zero_approx() and not seen.any(func(other: Vector3) -> bool: return other.dot(normal) > 0.999):
				seen.append(normal)
		var directions: Dictionary = {}
		for key: Vector3i in faces:
			var seen: Array = faces[key]
			var sum := Vector3.ZERO
			for normal: Vector3 in seen:
				sum += normal
			if sum.is_zero_approx():
				directions[key] = seen[0] if not seen.is_empty() else Vector3.ZERO
				continue
			var mean := sum.normalized()
			var nearest := 1.0
			for normal: Vector3 in seen:
				nearest = minf(nearest, mean.dot(normal))
			directions[key] = mean / maxf(nearest, 1.0 / MAX_CORNER_REACH)
		var custom := PackedFloat32Array()
		custom.resize(vertices.size() * 3)
		for index: int in vertices.size():
			var direction: Vector3 = directions[Vector3i((vertices[index] * 10000.0).round())]
			custom[index * 3] = direction.x
			custom[index * 3 + 1] = direction.y
			custom[index * 3 + 2] = direction.z
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		for channel: int in [Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[channel] = null
		# Primitive meshes (BoxMesh, PrismMesh) are always triangles.
		var primitive := (source as ArrayMesh).surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		rim.add_surface_from_arrays(primitive, arrays, [], {},
			Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	_rim_meshes[source] = rim
	return rim

func clear() -> void:
	for copy: MeshInstance3D in _copies:
		if is_instance_valid(copy):
			copy.queue_free()
	_copies.clear()
	_bot = null

## The bot's own meshes: not the outline's copies, and nothing that has come
## off it. Broken-off weapons and drives, wreck pieces and bursts fly under
## top_level roots (bot_part_loss, bot_destruction_visual) parented to the bot.
func _meshes(bot: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in bot.find_children("*", "MeshInstance3D", true, false):
		if not str(node.name).begins_with(copy_name) and str(node.name) not in skip_names and (node as MeshInstance3D).mesh != null and not _detached(node, bot):
			meshes.append(node)
	return meshes

static func _detached(node: Node, bot: Node) -> bool:
	while node != null and node != bot:
		if node is Node3D and (node as Node3D).top_level:
			return true
		node = node.get_parent()
	return false

func _exit_tree() -> void:
	clear()
