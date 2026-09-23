class_name CoolingZoneVisuals
extends Node3D
## Arena cooling zones (#68) drawn at AuthorityWorld.cooling_zones(): a frosted
## vent grate ringed by a cold cyan band, cold vapour rising through it, a
## pale light and a hovering COOLING label. The authority decides who is
## cooled; this is presentation only.
const COLOR := Color("8fe6ff")
var session: MvpSession
var _arena := ""

func bind_session(value: MvpSession) -> void:
	session = value

func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(session) or not is_instance_valid(session.world):
		return
	if session.world.arena_id == _arena:
		return
	_arena = session.world.arena_id
	for child: Node in get_children(): child.queue_free()
	var radius := HeatRelief.settings().value("zones", "radius")
	for point: Vector3 in session.world.cooling_zones():
		add_child(_zone(point, radius))

func _zone(point: Vector3, radius: float) -> Node3D:
	var zone := Node3D.new()
	zone.name = "CoolingZone"
	zone.position = point + Vector3.UP * 0.03
	var grate := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.06
	disc.radial_segments = 48
	grate.mesh = disc
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("27323a")
	metal.metallic = 0.85
	metal.roughness = 0.4
	metal.emission_enabled = true
	metal.emission = COLOR
	metal.emission_energy_multiplier = 0.15
	grate.material_override = metal
	zone.add_child(grate)
	# Vent slats read as a grate from the chase and artillery cameras.
	var slat_material := _glow(0.9, 1.6)
	for index: int in range(-5, 6):
		var slat := MeshInstance3D.new()
		var bar := BoxMesh.new()
		var x := float(index) / 6.0 * radius
		bar.size = Vector3(0.18, 0.02, 2.0 * sqrt(maxf(radius * radius - x * x, 0.0)) * 0.92)
		slat.mesh = bar
		slat.material_override = slat_material
		slat.position = Vector3(x, 0.045, 0)
		zone.add_child(slat)
	var band := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.35
	torus.outer_radius = radius
	torus.rings = 64
	torus.ring_segments = 6
	band.mesh = torus
	band.scale = Vector3(1, 0.25, 1)
	band.material_override = _glow(1.0, 3.0)
	band.position.y = 0.08
	zone.add_child(band)
	zone.add_child(_vapour(radius))
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 1.6
	light.omni_range = radius * 1.6
	light.position.y = 2.5
	zone.add_child(light)
	var label := Label3D.new()
	label.text = "COOLING"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 96
	label.outline_size = 12
	label.modulate = COLOR.lightened(0.3)
	label.outline_modulate = Color(0.03, 0.05, 0.07, 0.9)
	label.position.y = 4.5
	zone.add_child(label)
	return zone

func _vapour(radius: float) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 70
	emitter.lifetime = 3.0
	emitter.visibility_aabb = AABB(Vector3(-radius, -1, -radius), Vector3(radius * 2, 10, radius * 2))
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = radius * 0.8
	motion.direction = Vector3.UP
	motion.spread = 12.0
	motion.initial_velocity_min = 0.6
	motion.initial_velocity_max = 1.4
	motion.gravity = Vector3(0, 0.3, 0)
	motion.scale_min = 1.2
	motion.scale_max = 2.4
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	fade.colors = PackedColorArray([Color(0.8, 0.95, 1.0, 0.0), Color(0.8, 0.95, 1.0, 0.22), Color(0.8, 0.95, 1.0, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mist := StandardMaterial3D.new()
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mist.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(0.5, 0.0)
	var falloff := Gradient.new()
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	soft.gradient = falloff
	mist.albedo_texture = soft
	quad.material = mist
	emitter.draw_pass_1 = quad
	emitter.position.y = 0.2
	return emitter

func _glow(alpha: float, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(COLOR, alpha)
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = energy
	return material
