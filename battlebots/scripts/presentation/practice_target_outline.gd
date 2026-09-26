extends Node
## Practice Duel target panel (#97): a red silhouette outline round the
## targeted NPC. Each of the bot's meshes gets two child copies, drawn in the
## transparent pass: an invisible mask that marks the bot's pixels in the
## stencil buffer, then (later, by render priority) a red hull grown along the
## normals that draws only where no mask was written. So only the rim outside
## the whole bot's silhouette shows, never the seams between its parts.
## Presentation only; the bot's own materials and overlays (the damage and
## wreck visuals use material_overlay) are left alone.
const COLOR := Color(1.0, 0.12, 0.1)
## Rim width in metres, whatever the mesh's scale.
const WIDTH := 0.05
## Stencil value the masks write (any value no other effect uses).
const STENCIL := 97
const COPY_NAME := "PracticeTargetOutline"
const MASK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
stencil_mode write, write_depth_fail, compare_always, %d;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""
const RIM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;
stencil_mode read, compare_not_equal, %d;
uniform vec4 outline_color : source_color;
uniform float width;
void vertex() {
	float scale = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += NORMAL * width / scale;
}
void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = 1.0;
}
"""
var _bot: Node
var _copies: Array[MeshInstance3D] = []
var _mask: ShaderMaterial
var _rim: ShaderMaterial

func _init() -> void:
	name = "PracticeTargetOutline"
	_mask = _material(MASK_SHADER % STENCIL, 0)
	_rim = _material(RIM_SHADER % STENCIL, 1)
	_rim.set_shader_parameter("outline_color", COLOR)
	_rim.set_shader_parameter("width", WIDTH)

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
	if bot == _bot and meshes.size() * 2 == _copies.size() and _copies.all(func(copy: MeshInstance3D) -> bool: return is_instance_valid(copy)):
		return
	clear()
	_bot = bot
	for mesh: MeshInstance3D in meshes:
		for layer: Array in [["Mask", _mask], ["Rim", _rim]]:
			var copy := MeshInstance3D.new()
			copy.name = COPY_NAME + str(layer[0])
			copy.mesh = mesh.mesh
			copy.skin = mesh.skin
			if not mesh.skeleton.is_empty():
				copy.skeleton = NodePath("../" + str(mesh.skeleton))
			copy.material_override = layer[1]
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.add_to_group(preload("res://scripts/presentation/wreck_pieces.gd").SKIP_GROUP)
			mesh.add_child(copy)
			_copies.append(copy)

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
		if not str(node.name).begins_with(COPY_NAME) and (node as MeshInstance3D).mesh != null and not _detached(node, bot):
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
