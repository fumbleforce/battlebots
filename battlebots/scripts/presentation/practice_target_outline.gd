extends Node
## Practice Duel target panel (#97): a red outline round the targeted NPC.
## Each of the bot's meshes gets a child copy drawn in flat red, grown along
## its normals and culled front-facing (an inverted hull), so only a rim shows
## round the bot. Presentation only; the bot's own materials and overlays (the
## damage and wreck visuals use material_overlay) are left alone.
const COLOR := Color(1.0, 0.12, 0.1)
## Rim width in metres, whatever the mesh's scale.
const WIDTH := 0.05
const COPY_NAME := "PracticeTargetOutline"
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 outline_color : source_color;
uniform float width;
void vertex() {
	float scale = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += NORMAL * width / scale;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""
var _bot: Node
var _copies: Array[MeshInstance3D] = []
var _material: ShaderMaterial

func _init() -> void:
	name = "PracticeTargetOutline"
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("outline_color", COLOR)
	_material.set_shader_parameter("width", WIDTH)

## Outlines bot, or nothing for null. Called every frame: a part swap replaces
## the bot node and a damaged bot can gain or lose meshes, so it re-dresses.
func show_on(bot: Node) -> void:
	if not is_instance_valid(bot):
		clear()
		return
	var meshes := _meshes(bot)
	if bot == _bot and meshes.size() == _copies.size() and _copies.all(func(copy: MeshInstance3D) -> bool: return is_instance_valid(copy)):
		return
	clear()
	_bot = bot
	for mesh: MeshInstance3D in meshes:
		var copy := MeshInstance3D.new()
		copy.name = COPY_NAME
		copy.mesh = mesh.mesh
		copy.skin = mesh.skin
		if not mesh.skeleton.is_empty():
			copy.skeleton = NodePath("../" + str(mesh.skeleton))
		copy.material_override = _material
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.add_child(copy)
		_copies.append(copy)

func clear() -> void:
	for copy: MeshInstance3D in _copies:
		if is_instance_valid(copy):
			copy.queue_free()
	_copies.clear()
	_bot = null

func _meshes(bot: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in bot.find_children("*", "MeshInstance3D", true, false):
		if node.name != COPY_NAME and not str(node.name).begins_with(COPY_NAME) and (node as MeshInstance3D).mesh != null:
			meshes.append(node)
	return meshes

func _exit_tree() -> void:
	clear()
