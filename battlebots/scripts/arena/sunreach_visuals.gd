extends Node3D
## Painterly Sunreach art. Gameplay is entirely in sunreach_ground.gd and its bake.
const GROUND = preload("res://scripts/arena/sunreach_ground.gd")
const SURFACE = preload("res://assets/materials/arena/sunreach_surface.gdshader")
const WATER = preload("res://assets/materials/arena/sunreach_water.gdshader")
@export var arena_path: NodePath = NodePath("..")
var _view_distance := 2500.0

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
	var arena := get_node(arena_path)
	for wall: Node in arena.get_node("Walls").get_children():
		var mesh := wall.get_node_or_null("Mesh") as MeshInstance3D
		if mesh: mesh.hide()
	arena.get_node("Markings").hide()
	var art: Node3D = load("res://assets/models/sunreach/sunreach.glb").instantiate()
	art.name = "SunreachLandscape"
	add_child(art)
	var materials: Dictionary = {}
	for node: Node in art.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var key := source.resource_name.trim_prefix("Sunreach_")
			if not materials.has(key): materials[key] = _material(key)
			mesh.set_surface_override_material(surface, materials[key])
		if String(mesh.name).begins_with("grass") or String(mesh.name).begins_with("flower") or String(mesh.name).begins_with("gravel"):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = 260.0
			mesh.visibility_range_end_margin = 20.0
		if String(mesh.name).begins_with("water") or String(mesh.name).begins_with("foam"):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lighting(arena)

func _material(kind: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if kind in ["water", "foam"]:
		mat.shader = WATER
		mat.set_shader_parameter("waterfall", kind == "foam")
		var n := roundi(float(GROUND.settings().half) * 2.0) + 1
		var heights := Image.create_from_data(n, n, false, Image.FORMAT_RF, GROUND.grid_heights().to_byte_array())
		mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(heights))
		mat.set_shader_parameter("water_level", float(GROUND.settings().water_level))
		mat.set_shader_parameter("arena_half", float(GROUND.settings().half))
		return mat
	mat.shader = SURFACE
	var mode := 0
	var texture := "rock_boulder_dry_diff_2k.jpg"
	if kind in ["cliff", "stone"]: mode = 1
	if kind in ["wood", "bark"]:
		mode = 2
		texture = "pine_bark_diff_1k.jpg"
	if kind in ["leaf", "pine"]: mode = 3
	if kind in ["grass", "flower"]: mode = 4
	mat.set_shader_parameter("kind", mode)
	mat.set_shader_parameter("paint_texture", load("res://assets/textures/woodland/" + texture))
	return mat

func _lighting(arena: Node) -> void:
	var cfg: Dictionary = GROUND.settings().art
	_view_distance = float(cfg.view_distance)
	var env_node: WorldEnvironment = arena.get_node("WorldEnvironment")
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://assets/materials/arena/sunreach_sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aac8db")
	env.ambient_light_energy = float(cfg.ambient_energy)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color("a9cbd9")
	env.fog_density = float(cfg.fog_density)
	env.fog_sky_affect = 0.15
	env_node.environment = env
	var sun := arena.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-53, -35, 0)
	sun.light_color = Color("fff0cd")
	sun.light_energy = float(cfg.sun_energy)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 240.0
	sun.light_angular_distance = 1.2

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera: camera.far = maxf(camera.far, _view_distance)
