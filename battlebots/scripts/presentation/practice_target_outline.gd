extends Node
## Practice target panel (#97): a red screen-space outline round the targeted
## NPC; the item card (#105) outlines the selected item pickup in yellow with
## a second one (ITEM_*). Each shown mesh of the outlined node gets a plain
## white copy, on black, in a mask viewport of its own (its own World3D: no lights,
## shadows or scenery, and the game's cameras never see the copies), filmed
## by a camera that follows the game's. A full-screen line then colours every
## pixel within WIDTH_PX of the mask and outside it. So the line is one even
## width round the whole silhouette, whatever the meshes' shape, and costs
## nothing per vertex. It also shows through walls, like a selection should.
## Presentation only; the outlined node is left alone.
const COLOR := Color(1.0, 0.12, 0.1)
const ITEM_COLOR := Color(1.0, 0.85, 0.1)
## Line width in pixels on a 1080-line window, scaled with the window height.
const WIDTH_PX := 3.0
const COPY_NAME := "PracticeTargetOutline"
const ITEM_COPY_NAME := "PracticeItemOutline"
## Seconds between full re-scans of the outlined node's meshes; a replaced or
## changed mesh re-dresses at once.
const RESCAN_SECONDS := 0.25
const MASK_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled;
void fragment() {
	ALBEDO = vec3(1.0);
}
"""
## Samples DIRECTIONS points round each pixel at every whole pixel out to width.
const LINE_SHADER := """
shader_type canvas_item;
uniform sampler2D mask : filter_nearest;
uniform vec4 outline_color : source_color;
uniform float width = 3.0;
const int DIRECTIONS = 16;
void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(mask, 0));
	float edge = 0.0;
	if (texture(mask, SCREEN_UV).r < 0.5) {
		for (int ring = 1; ring <= int(ceil(width)) && edge < 0.5; ring++) {
			float radius = min(float(ring), width);
			for (int turn = 0; turn < DIRECTIONS; turn++) {
				float angle = TAU * float(turn) / float(DIRECTIONS);
				if (texture(mask, SCREEN_UV + vec2(cos(angle), sin(angle)) * radius * texel).r > 0.5) {
					edge = 1.0;
					break;
				}
			}
		}
	}
	COLOR = vec4(outline_color.rgb, edge);
}
"""
var _bot: Node
## Source mesh -> its white copy in the mask world.
var _copies: Dictionary = {}
var _rescan_at := 0
var _viewport: SubViewport
var _camera: Camera3D
var _line: ColorRect
var _mask_material: ShaderMaterial
## Its copies' name prefix; also the node's name.
var copy_name := COPY_NAME
## Meshes by these names are left out (the token inside an item's glass cage).
var skip_names: Array[String] = []

func _init(color := COLOR, prefix := COPY_NAME) -> void:
	copy_name = prefix
	name = prefix
	# After the cameras and bots have moved this frame.
	process_priority = 1000
	_mask_material = _material(MASK_SHADER)
	_viewport = SubViewport.new()
	_viewport.name = "Mask"
	_viewport.own_world_3d = true
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_camera = Camera3D.new()
	# White copies on black: the line reads brightness, not alpha, which the
	# mask's clear does not keep transparent past its first frame.
	var black := Environment.new()
	black.background_mode = Environment.BG_COLOR
	black.background_color = Color.BLACK
	_camera.environment = black
	_viewport.add_child(_camera)
	var layer := CanvasLayer.new()
	# Over the arena, under every panel and HUD.
	layer.layer = -1
	add_child(layer)
	_line = ColorRect.new()
	_line.name = "Line"
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_line.material = _material(LINE_SHADER)
	_line.material.set_shader_parameter("outline_color", color)
	_line.hide()
	layer.add_child(_line)

static func _material(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material

func _ready() -> void:
	_line.material.set_shader_parameter("mask", _viewport.get_texture())

## Outlines bot, or nothing for null. Called every frame: a part swap replaces
## the bot node and a damaged bot can gain or lose meshes, so it re-dresses.
func show_on(bot: Node) -> void:
	if not is_instance_valid(bot):
		clear()
		return
	# A replaced mesh (an item's new contents) re-dresses at once; the full scan
	# for added, removed, shown or hidden meshes runs every RESCAN_SECONDS.
	var intact := bot == _bot and _copies.keys().all(func(source: Variant) -> bool:
		return is_instance_valid(source) and (source as MeshInstance3D).mesh == (_copies[source] as MeshInstance3D).mesh)
	var now := Time.get_ticks_msec()
	if intact and now < _rescan_at:
		return
	_rescan_at = now + int(RESCAN_SECONDS * 1000.0)
	var meshes := _meshes(bot)
	if intact and meshes.size() == _copies.size() and meshes.all(func(mesh: MeshInstance3D) -> bool: return _copies.has(mesh)):
		return
	clear()
	_bot = bot
	for mesh: MeshInstance3D in meshes:
		var copy := MeshInstance3D.new()
		copy.name = copy_name + "Mask"
		copy.mesh = mesh.mesh
		copy.skin = mesh.skin
		copy.material_override = _mask_material
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_viewport.add_child(copy)
		if not mesh.skeleton.is_empty() and mesh.has_node(mesh.skeleton):
			copy.skeleton = copy.get_path_to(mesh.get_node(mesh.skeleton))
		_copies[mesh] = copy
	_follow()

## The meshes it outlines now.
func sources() -> Array:
	return _copies.keys()

## Whether it outlines node or anything under it.
func outlines(node: Node) -> bool:
	return is_instance_valid(node) and _copies.keys().any(func(source: Variant) -> bool:
		return is_instance_valid(source) and (source == node or node.is_ancestor_of(source)))

func clear() -> void:
	for copy: Node in _copies.values():
		copy.queue_free()
	_copies.clear()
	_bot = null
	_follow()

func _process(_delta: float) -> void:
	_follow()

## The mask camera films from the game's camera; the copies follow their meshes.
func _follow() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var shown := not _copies.is_empty() and camera != null
	_line.visible = shown
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	if not shown:
		return
	var window := get_tree().root.size
	_viewport.size = window
	_line.material.set_shader_parameter("width", WIDTH_PX * float(window.y) / 1080.0)
	_camera.global_transform = camera.global_transform
	_camera.projection = camera.projection
	_camera.fov = camera.fov
	_camera.size = camera.size
	_camera.near = camera.near
	_camera.far = camera.far
	_camera.keep_aspect = camera.keep_aspect
	_camera.h_offset = camera.h_offset
	_camera.v_offset = camera.v_offset
	for source: Variant in _copies:
		var copy: MeshInstance3D = _copies[source]
		copy.visible = is_instance_valid(source) and (source as MeshInstance3D).is_visible_in_tree()
		if copy.visible:
			copy.global_transform = (source as MeshInstance3D).global_transform

## The bot's own shown meshes: not hidden ones (an item model hides every
## module of the bot it is cut from but its own), and nothing that has come
## off it. Broken-off weapons and drives, wreck pieces and bursts fly under
## top_level roots (bot_part_loss, bot_destruction_visual) parented to the bot.
func _meshes(bot: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in bot.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if str(mesh.name) not in skip_names and mesh.mesh != null and mesh.is_visible_in_tree() and not _detached(mesh, bot):
			meshes.append(mesh)
	return meshes

static func _detached(node: Node, bot: Node) -> bool:
	while node != null and node != bot:
		if node is Node3D and (node as Node3D).top_level:
			return true
		node = node.get_parent()
	return false

func _exit_tree() -> void:
	clear()
