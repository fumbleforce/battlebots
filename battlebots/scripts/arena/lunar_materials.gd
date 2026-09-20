extends RefCounted
## Shared visual material binding, never used by authoritative collision.
static func ground(playable: bool=false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/materials/arena/moon_ground.gdshader")
	m.set_shader_parameter("regolith",preload("res://assets/textures/moon/regolith_albedo.png"))
	m.set_shader_parameter("rock_color",preload("res://assets/textures/lunar/surface2_color.png"))
	m.set_shader_parameter("rock_normal",preload("res://assets/textures/lunar/surface2_normal.png"))
	m.set_shader_parameter("fine_normal",preload("res://assets/textures/lunar/surface0_normal.png"))
	m.set_shader_parameter("relief",preload("res://assets/textures/lunar/surface0_relief.png"))
	m.set_shader_parameter("compact_color",preload("res://assets/textures/lunar/surface1_color.png"))
	m.set_shader_parameter("playable",playable)
	return m
