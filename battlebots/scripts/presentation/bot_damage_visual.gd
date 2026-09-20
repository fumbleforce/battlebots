class_name BotDamageVisual
extends Node3D
## Snapshot-only cosmetic state. Never modifies materials owned by another bot.
const OVERLAY := preload("res://scripts/presentation/component_damage.gdshader")
const MAXIMUM := {"drive_left": 100.0, "drive_right": 100.0, "weapon": 140.0}
const SMOKE_PARTICLES := 6
var components: Dictionary = {}

func bind_component(zone: String, meshes: Array, anchor: Node3D) -> void:
	assert(MAXIMUM.has(zone))
	_clear_component(zone)
	var surfaces: Array = []
	for mesh: MeshInstance3D in meshes:
		surfaces.append({"mesh": mesh, "original": mesh.material_overlay})
	var overlay := ShaderMaterial.new()
	overlay.shader = OVERLAY
	var smoke := _smoke()
	add_child(smoke)
	smoke.top_level = true
	if is_instance_valid(anchor): smoke.global_transform = Transform3D(Basis.IDENTITY, anchor.global_position)
	components[zone] = {"surfaces": surfaces, "overlay": overlay, "anchor": anchor,
		"smoke": smoke, "stage": -1}

func _clear_component(zone: String) -> void:
	if not components.has(zone): return
	var record: Dictionary = components[zone]
	for surface: Dictionary in record.surfaces:
		if is_instance_valid(surface.mesh): surface.mesh.material_overlay = surface.original
	record.smoke.free()
	components.erase(zone)

func _exit_tree() -> void:
	for zone: String in components.keys(): _clear_component(zone)

func stage_for(zone: String) -> int:
	return int(components.get(zone, {}).get("stage", -1))

func show_state(view: BotView) -> void:
	for zone: String in components:
		var stage := _stage(view, zone)
		var record: Dictionary = components[zone]
		if stage == record.stage: continue
		record.stage = stage
		record.overlay.set_shader_parameter("damage_stage", float(stage))
		for surface: Dictionary in record.surfaces:
			if is_instance_valid(surface.mesh):
				surface.mesh.material_overlay = record.overlay if stage > 0 else surface.original
		var smoking := stage == 2 and is_instance_valid(record.anchor)
		if smoking:
			record.smoke.global_position = record.anchor.global_position
			record.smoke.restart()
		record.smoke.emitting = smoking
		# A repair/new baseline removes the previous plume immediately.
		record.smoke.visible = smoking

func _stage(view: BotView, zone: String) -> int:
	if view == null: return -1
	if view.eliminated: return 2
	var value: Variant = view.zones.get(zone)
	if not (value is int or value is float): return -1
	var health := float(value)
	if not is_finite(health) or health < 0.0 or health > MAXIMUM[zone]: return -1
	if health == 0.0: return 2
	return 1 if health <= MAXIMUM[zone] * 0.5 else 0

func _process(_delta: float) -> void:
	for record: Dictionary in components.values():
		if is_instance_valid(record.anchor):
			record.smoke.global_position = record.anchor.global_position
		else:
			record.smoke.emitting = false
			record.smoke.visible = false

func _smoke() -> CPUParticles3D:
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.visible = false
	smoke.amount = SMOKE_PARTICLES
	smoke.lifetime = 1.5
	smoke.local_coords = false
	smoke.direction = Vector3.UP
	smoke.spread = 22.0
	smoke.gravity = Vector3(0, 0.15, 0)
	smoke.initial_velocity_min = 0.45
	smoke.initial_velocity_max = 0.75
	smoke.scale_amount_min = 0.5
	smoke.scale_amount_max = 1.2
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 0.04
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0.13, 0.13, 0.14, 0.45), Color(0.23, 0.23, 0.24, 0)])
	smoke.color_ramp = fade
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1, 0.5)
	texture.gradient = Gradient.new()
	texture.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45)
	quad.material = material
	smoke.mesh = quad
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return smoke
