class_name TurretShotEffects
extends Node3D
## Accepted shot snapshots only: recoil, muzzle blast, travelling shell or
## plasma bolt, cosmetic arrival/burn effects and procedural reports. Confirmed
## hit sparks and damage come from combat events; nothing here awards a hit.
const PROJECTILES := 6
const IMPACTS := 4
const BLASTS := 2
const FOG_PUFFS := 6
const FOG_LIFETIME := 2.6
const BURN_LIFETIME := 3.2
const RATE := 24000
const SPEED := {"cannon":240.0, "plasma":85.0}
const MORTAR_BLAST_SCALE := 1.7
## The incoming-shell whistle starts this long before the shell lands.
const WHISTLE_LEAD := 1.3
## Recoil travel in model (source) metres and its return time.
const RECOIL_TRAVEL := 0.10
const RECOIL_RETURN := 0.45
const PLASMA_CORE := Color(0.92, 0.97, 1.0)
const PLASMA_CORONA := Color(0.55, 0.45, 1.0)
const PLASMA_GLOW := Color(0.35, 0.8, 1.0)
var kind := ""
var muzzles: Array[Node3D] = []
var recoils: Array[Node3D] = []
var shot_count := 0
var playback_enabled := true
var _scale := 1.0
var _recoil_rest: Array[Transform3D] = []
var _recoil_age: Array[float] = []
var _seen := -1
var _tick := -1
var _flash: MeshInstance3D
var _flash_ball: MeshInstance3D
var _flash_age := 1.0
var _light: OmniLight3D
var _projectiles: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _impact_count := 0
var _blasts: Array[GPUParticles3D] = []
var _fog: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _impact_voices: Array[AudioStreamPlayer3D] = []
var _whistles: Array[AudioStreamPlayer3D] = []
var _gun_scale := 1.0
var _time := 0.0
static var _streams: Dictionary = {}
static var _smoke_materials: Dictionary = {}
static var _burn_textures: Dictionary = {}

## One muzzle (and, for cannons, one recoiling barrel) per barrel.
func configure(weapon: String, muzzle_nodes: Array[Node3D], recoil_nodes: Array[Node3D], geometry_scale: float) -> void:
	kind = weapon
	muzzles = muzzle_nodes
	recoils = recoil_nodes
	_scale = geometry_scale
	for node: Node3D in recoils:
		_recoil_rest.append(node.transform if node != null else Transform3D.IDENTITY)
		_recoil_age.append(1.0)
	# The mortar is a heavy gun: cannon shells, smoke and detonations, lobbed
	# along the real arc, with a bigger blast and a whistle on the way down.
	var cannon := kind in ["cannon", "mortar"]
	for index: int in PROJECTILES:
		_projectiles.append(_make_projectile(cannon))
	_gun_scale = _scale
	if kind == "mortar": _scale *= MORTAR_BLAST_SCALE
	for index: int in IMPACTS:
		_impacts.append(_make_impact(cannon))
	_scale = _gun_scale
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = (0.16 if cannon else 0.09) * _scale
	cone.height = (0.75 if cannon else 0.45) * _scale
	cone.radial_segments = 9
	_flash = _mesh(cone, _glow(Color(1.0, 0.62, 0.22) if cannon else PLASMA_GLOW, 6.0 if cannon else 5.0))
	var ball := SphereMesh.new()
	ball.radius = (0.08 if cannon else 0.11) * _scale
	ball.height = ball.radius * 2.0
	_flash_ball = _mesh(ball, _glow(Color(1.0, 0.85, 0.6) if cannon else PLASMA_CORE, 6.0))
	_light = _omni(Color(1.0, 0.6, 0.25) if cannon else Color(0.55, 0.8, 1.0), (4.5 if cannon else 6.0) * _scale)
	# Lit, depth-softened billowing cards (the #31 plume technique) in a
	# pooled one-shot burst per shot, plus volumetric fog cores on Forward+.
	for index: int in (BLASTS if cannon else 0):
		var blast := _make_blast(cannon)
		blast.name = "MuzzleSmoke%d" % index
		add_child(blast)
		blast.top_level = true
		_blasts.append(blast)
	add_to_group(&"bot_action_audio")
	AudioPreferences.ensure_buses()
	for index: int in 4:
		_voices.append(_voice("TurretReport%d" % index, _stream(kind), 1.0 if cannon else -1.0,
			14.0 if cannon else 9.0, 180.0 if cannon else 120.0))
	for index: int in 4:
		_impact_voices.append(_voice("TurretImpact%d" % index, _stream(kind + "_impact"), 0.0 if cannon else -2.0, 12.0 if cannon else 8.0, 160.0 if cannon else 100.0))
	if kind == "mortar":
		for index: int in 2:
			_whistles.append(_voice("MortarWhistle%d" % index, _stream("mortar_whistle"), -3.0, 12.0, 160.0))

func _voice(label: String, stream: AudioStreamWAV, gain: float, unit: float, reach: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.stream = stream
	voice.bus = &"BBEffects"
	voice.volume_db = gain
	voice.unit_size = unit
	voice.max_distance = reach
	add_child(voice)
	voice.top_level = true
	return voice

func _omni(color: Color, reach: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = reach
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)
	light.top_level = true
	return light

func _mesh(shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.top_level = true
	node.hide()
	return node

func _make_projectile(cannon: bool) -> Dictionary:
	var record := {"from":Vector3.ZERO, "to":Vector3.ZERO, "age":10.0, "flight":0.0, "impacted":true, "whistled":true}
	if cannon:
		# A heavy glowing shell with a riding light and a rolling smoke trail.
		var shell := CapsuleMesh.new()
		shell.radius = 0.075 * _scale
		shell.height = 0.7 * _scale
		record.head = _mesh(shell, _glow(Color(1.0, 0.85, 0.55), 12.0))
		var streak := CylinderMesh.new()
		streak.top_radius = 0.045 * _scale
		streak.bottom_radius = 0.004 * _scale
		streak.height = 1.0
		streak.radial_segments = 10
		record.trail = _mesh(streak, _glow(Color(1.0, 0.55, 0.18, 0.8), 5.0))
		record.light = _omni(Color(1.0, 0.65, 0.3), 6.0 * _scale)
		var smoke := _make_blast(true)
		smoke.one_shot = false
		smoke.explosiveness = 0.0
		smoke.amount = 48
		smoke.lifetime = 1.6
		var motion := smoke.process_material as ParticleProcessMaterial
		motion.spread = 180.0
		motion.initial_velocity_min = 0.1 * _scale
		motion.initial_velocity_max = 0.5 * _scale
		motion.scale_min = 0.35 * _scale
		motion.scale_max = 0.6 * _scale
		add_child(smoke)
		smoke.top_level = true
		record.embers = smoke
		return record
	# White-hot elongated core inside a violet corona, a long cyan wake, a light
	# that rides with the bolt and shedding embers: it should read as searing.
	var core := CapsuleMesh.new()
	core.radius = 0.035 * _scale
	core.height = 0.4 * _scale
	record.head = _mesh(core, _glow(PLASMA_CORE, 14.0))
	var corona := SphereMesh.new()
	corona.radius = 0.1 * _scale
	corona.height = 0.2 * _scale
	record.corona = _mesh(corona, _glow(Color(PLASMA_CORONA, 0.5), 3.5))
	var wake := CylinderMesh.new()
	wake.top_radius = 0.05 * _scale
	wake.bottom_radius = 0.005 * _scale
	wake.height = 1.0
	wake.radial_segments = 10
	record.trail = _mesh(wake, _glow(Color(PLASMA_GLOW, 0.7), 5.0))
	record.light = _omni(Color(0.55, 0.78, 1.0), 7.0 * _scale)
	var embers := _sparks(60, 0.45, Color(0.85, 0.95, 1.0), Color(0.45, 0.35, 1.0))
	var motion := embers.process_material as ParticleProcessMaterial
	motion.spread = 180.0
	motion.initial_velocity_min = 0.2 * _scale
	motion.initial_velocity_max = 0.9 * _scale
	motion.gravity = Vector3(0, -1.5, 0) * _scale
	embers.one_shot = false
	embers.explosiveness = 0.0
	record.embers = embers
	return record

## Pooled cosmetic arrival: light, molten spark spray, a flash and a burn mark
## projected onto whatever the shot struck (enemy hull, wall or floor).
func _make_impact(cannon: bool) -> Dictionary:
	var record := {"age":10.0, "at":Vector3.ZERO}
	record.light = _omni(Color(1.0, 0.62, 0.3) if cannon else Color(0.8, 0.85, 1.0), (10.0 if cannon else 4.0) * _scale)
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	record.flash = _mesh(ball, _glow(Color(1.0, 0.75, 0.45, 0.9) if cannon else Color(0.9, 0.95, 1.0, 0.9), 5.0))
	# Sparks stay gun-sized even for the bigger mortar blast: enlarged spark
	# sprites read as glowing balls (WEAPON_FEEL.md, effects).
	var blast_scale := _scale
	_scale = _gun_scale
	record.sparks = _sparks(90 if cannon else 70, 1.1 if cannon else 0.9, Color(1.0, 0.9, 0.7), Color(1.0, 0.35, 0.05))
	_scale = blast_scale
	if cannon:
		(record.sparks.process_material as ParticleProcessMaterial).initial_velocity_max = 5.5 * _scale
		record.fireball = _fireball()
		record.column = _smoke_column()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 6
		record.shock = _mesh(torus, _glow(Color(1.0, 0.8, 0.55, 0.35), 2.0))
	var decal := Decal.new()
	decal.size = Vector3(1.0, 1.4, 1.0) * (2.2 if cannon else 0.8) * _scale
	decal.texture_albedo = _burn_texture(false)
	decal.texture_emission = _burn_texture(true)
	decal.emission_energy = 0.0
	decal.upper_fade = 0.2
	decal.lower_fade = 0.2
	decal.cull_mask = 0xFFFFF
	add_child(decal)
	decal.top_level = true
	decal.hide()
	record.decal = decal
	return record

## Rolling fireball: soft additive billows that flash white, burn orange and
## die dark red while expanding.
func _fireball() -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 40
	emitter.lifetime = 0.75
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 60
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-8, -4, -8) * _scale, Vector3(16, 12, 16) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.3 * _scale
	motion.direction = Vector3.UP
	motion.spread = 180.0
	motion.initial_velocity_min = 0.6 * _scale
	motion.initial_velocity_max = 2.0 * _scale
	motion.damping_min = 4.0
	motion.damping_max = 6.0
	motion.gravity = Vector3(0, 1.2, 0) * _scale
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.scale_min = 0.9 * _scale
	motion.scale_max = 1.6 * _scale
	motion.scale_curve = _curve([Vector2(0, 0.35), Vector2(0.25, 1.0), Vector2(1, 1.4)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.45, 0.8, 1.0])
	gradient.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.7, 0.25, 1.0),
		Color(0.9, 0.3, 0.06, 0.8), Color(0.35, 0.08, 0.02, 0.35), Color(0.1, 0.03, 0.01, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(2.2, 2.2, 2.2, 1.0)
	material.albedo_texture = _soft_texture()
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	emitter.top_level = true
	return emitter

## Dark lit smoke rising from the blast (the #31 billow shader).
func _smoke_column() -> GPUParticles3D:
	var emitter := _make_blast(true)
	emitter.amount = 36
	emitter.lifetime = 3.6
	var motion := emitter.process_material as ParticleProcessMaterial
	motion.direction = Vector3.UP
	motion.spread = 40.0
	motion.initial_velocity_min = 1.0 * _scale
	motion.initial_velocity_max = 3.0 * _scale
	motion.damping_min = 1.2
	motion.damping_max = 2.0
	motion.gravity = Vector3(0.1, 0.35, 0.0) * _scale
	motion.scale_min = 1.1 * _scale
	motion.scale_max = 1.9 * _scale
	add_child(emitter)
	emitter.top_level = true
	return emitter

static var _soft: GradientTexture2D
static func _soft_texture() -> GradientTexture2D:
	if _soft != null: return _soft
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	_soft = GradientTexture2D.new()
	_soft.gradient = gradient
	_soft.fill = GradientTexture2D.FILL_RADIAL
	_soft.fill_from = Vector2(0.5, 0.5)
	_soft.fill_to = Vector2(1.0, 0.5)
	_soft.width = 64
	_soft.height = 64
	return _soft

func _sparks(amount: int, lifetime: float, hot: Color, cool: Color) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.one_shot = true
	emitter.explosiveness = 0.95
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 60
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-6, -6, -6) * _scale, Vector3(12, 12, 12) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 75.0
	motion.initial_velocity_min = 2.0 * _scale
	motion.initial_velocity_max = 6.5 * _scale
	motion.gravity = Vector3(0, -9.8, 0)
	motion.damping_min = 0.5
	motion.damping_max = 1.5
	motion.scale_min = 0.5
	motion.scale_max = 1.2
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color(hot, 1.0), Color(cool, 0.9), Color(cool.darkened(0.6), 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.025 * _scale
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(2.5, 2.5, 2.5, 1.0)
	quad.material = material
	emitter.draw_pass_1 = quad
	add_child(emitter)
	emitter.top_level = true
	return emitter

static func _burn_texture(emission: bool) -> GradientTexture2D:
	if _burn_textures.has(emission): return _burn_textures[emission]
	var gradient := Gradient.new()
	if emission:
		# Molten centre cooling through orange to nothing at the rim.
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.55, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 0.95, 0.75, 1), Color(1.0, 0.55, 0.12, 1), Color(0.6, 0.12, 0.02, 1), Color(0, 0, 0, 1)])
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 0.8, 1.0])
		gradient.colors = PackedColorArray([Color(0.03, 0.025, 0.02, 0.95), Color(0.05, 0.04, 0.035, 0.8), Color(0.08, 0.07, 0.06, 0.35), Color(0.1, 0.1, 0.1, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	_burn_textures[emission] = texture
	return texture

func _make_blast(cannon: bool) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = 40 if cannon else 14
	emitter.lifetime = 2.6 if cannon else 1.3
	emitter.one_shot = true
	emitter.explosiveness = 0.92
	emitter.emitting = false
	emitter.local_coords = false
	emitter.fixed_fps = 30
	emitter.interpolate = true
	emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-4, -2, -6) * _scale, Vector3(8, 6, 8) * _scale)
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.12 * _scale
	# Local -Z is the barrel: a forward jet plus the brake's sideways vents.
	motion.direction = Vector3.FORWARD
	motion.spread = 70.0 if cannon else 35.0
	motion.initial_velocity_min = (0.8 if cannon else 0.5) * _scale
	motion.initial_velocity_max = (3.2 if cannon else 1.8) * _scale
	motion.damping_min = 2.0
	motion.damping_max = 3.5
	motion.gravity = Vector3(0.05, 0.16, 0.0) * _scale
	motion.angle_min = -180.0
	motion.angle_max = 180.0
	motion.angular_velocity_min = -30.0
	motion.angular_velocity_max = 30.0
	motion.scale_min = (0.9 if cannon else 0.45) * _scale
	motion.scale_max = (1.4 if cannon else 0.75) * _scale
	motion.scale_curve = _curve([Vector2(0, 0.25), Vector2(0.15, 0.7), Vector2(0.6, 1.1), Vector2(1, 1.45)])
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.04, 0.3, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	motion.turbulence_enabled = true
	motion.turbulence_noise_strength = 0.6
	motion.turbulence_noise_scale = 2.0
	motion.turbulence_influence_min = 0.03
	motion.turbulence_influence_max = 0.09
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _smoke_material(cannon)
	emitter.draw_pass_1 = quad
	return emitter

static func _curve(points: Array[Vector2]) -> CurveTexture:
	var curve := Curve.new()
	curve.max_value = 1.5
	for point: Vector2 in points: curve.add_point(point)
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture

static func _smoke_material(cannon: bool) -> ShaderMaterial:
	if _smoke_materials.has(cannon): return _smoke_materials[cannon]
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/turret_blast_smoke.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = 36036
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.027
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	material.set_shader_parameter("smoke_noise", texture)
	if not cannon:
		# Plasma leaves superheated ionised vapour, not propellant smoke.
		material.set_shader_parameter("shadow_color", Color(0.30, 0.34, 0.50))
		material.set_shader_parameter("lit_color", Color(0.70, 0.78, 0.95))
		material.set_shader_parameter("opacity", 0.6)
	_smoke_materials[cannon] = material
	return material

func _deposit_fog(at: Vector3, direction: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus": return
	for step: int in 3:
		var puff: Dictionary
		if _fog.size() < FOG_PUFFS:
			var volume := FogVolume.new()
			volume.name = "MuzzleFog%d" % _fog.size()
			var material := ShaderMaterial.new()
			material.shader = preload("res://scripts/presentation/turret_blast_fog.gdshader")
			volume.material = material
			add_child(volume)
			volume.top_level = true
			puff = {"volume":volume, "age":FOG_LIFETIME, "origin":Vector3.ZERO, "direction":Vector3.ZERO}
			_fog.append(puff)
		else:
			puff = _fog[(shot_count * 3 + step) % FOG_PUFFS]
		puff.age = 0.0
		puff.origin = at + direction * (0.25 + step * 0.45) * _scale
		puff.direction = direction
		puff.volume.visible = true

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r * energy * 0.25, color.g * energy * 0.25, color.b * energy * 0.25, color.a)
	return material

func show_state(view: BotView, delta: float) -> void:
	var baseline := _seen < 0 or view.server_tick < _tick or view.shot_sequence < _seen
	if baseline:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick
	elif view.shot_sequence > _seen:
		_seen = view.shot_sequence
		# One visible shot per accepted snapshot; late/stale records stay silent.
		if not view.eliminated and view.last_shot_tick >= 0 and view.last_shot_tick <= view.server_tick \
			and view.server_tick - view.last_shot_tick <= 12:
			_fire(view.last_shot_from, view.last_shot_to, view.shot_sequence)
	_tick = view.server_tick
	if view.eliminated:
		clear_effects()
		_seen = view.shot_sequence
		_tick = view.server_tick
	_advance(delta)

func _fire(from: Vector3, to: Vector3, sequence := 1) -> void:
	var direction := to - from
	if direction.length_squared() < 0.0001 or not from.is_finite() or not to.is_finite(): return
	var distance := direction.length()
	direction /= distance
	var projectile: Dictionary = _projectiles[shot_count % PROJECTILES]
	projectile.from = from
	projectile.to = to
	projectile.age = 0.0
	projectile.flight = distance / float(SPEED.get(kind, 150.0))
	projectile.impacted = false
	projectile.whistled = kind != "mortar"
	if kind == "mortar":
		projectile.flight = AtlasGeometry.mortar_flight(from, to)
		direction = (AtlasGeometry.mortar_point(from, to, projectile.flight, 0.01) - from).normalized()
	if projectile.has("embers"):
		var embers: GPUParticles3D = projectile.embers
		embers.global_position = from
		embers.one_shot = false
		embers.restart()
		embers.emitting = true
	_flash.global_transform = Transform3D(_frame(direction), from + direction * _flash.mesh.height * 0.5)
	_flash_ball.global_position = from
	_flash_age = 0.0
	_light.global_position = from
	if not _recoil_age.is_empty():
		_recoil_age[posmod(sequence - 1, _recoil_age.size())] = 0.0
	if not _blasts.is_empty():
		var blast := _blasts[shot_count % _blasts.size()]
		# Orient local -Z along the barrel at the muzzle, then fire one burst.
		blast.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT), from)
		blast.restart()
		blast.emitting = true
	if kind in ["cannon", "mortar"]:
		_deposit_fog(from, direction)
	if playback_enabled and not _voices.is_empty():
		var voice := _voices[shot_count % _voices.size()]
		voice.stop()
		voice.global_position = from
		voice.pitch_scale = 0.96 + float(shot_count % 5) * 0.02
		voice.play()
	shot_count += 1

func _impact(at: Vector3, direction: Vector3) -> void:
	var record: Dictionary = _impacts[_impact_count % IMPACTS]
	_impact_count += 1
	record.age = 0.0
	record.at = at
	var light: OmniLight3D = record.light
	light.global_position = at - direction * 0.9 * _scale
	var sparks: GPUParticles3D = record.sparks
	# Spray back out of the struck surface.
	sparks.global_transform = Transform3D(Basis.looking_at(-direction, Vector3.UP if absf(direction.y) < 0.98 else Vector3.RIGHT)
		* Basis(Vector3.RIGHT, -PI * 0.5), at - direction * 0.05 * _scale)
	sparks.restart()
	sparks.emitting = true
	# Decals project along local -Y: point it down the shot into the surface.
	var decal: Decal = record.decal
	var up := -direction
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	decal.global_transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized()
		* Basis(Vector3.UP, randf() * TAU), at)
	decal.visible = true
	if record.has("fireball"):
		var fireball: GPUParticles3D = record.fireball
		fireball.global_position = at - direction * 0.4 * _scale
		fireball.restart()
		fireball.emitting = true
		var column: GPUParticles3D = record.column
		column.global_transform = Transform3D(Basis.IDENTITY, at - direction * 0.6 * _scale)
		column.restart()
		column.emitting = true
	if playback_enabled and not _impact_voices.is_empty():
		var voice := _impact_voices[_impact_count % _impact_voices.size()]
		voice.stop()
		voice.global_position = at
		voice.pitch_scale = 0.94 + float(_impact_count % 4) * 0.03
		voice.play()

func _frame(direction: Vector3) -> Basis:
	var right := direction.cross(Vector3.UP).normalized()
	if right.is_zero_approx(): right = Vector3.RIGHT
	return Basis(right, direction, right.cross(direction))

func _advance(delta: float) -> void:
	_time += delta
	var plasma := kind == "plasma"
	_flash_age += delta
	var flash_time := 0.07 if not plasma else 0.09
	_flash.visible = _flash_age < flash_time
	_flash_ball.visible = _flash_age < flash_time * 1.3
	if _flash_ball.visible:
		_flash_ball.scale = Vector3.ONE * lerpf(1.0, 1.5, _flash_age / (flash_time * 1.3))
	_light.light_energy = maxf(0.0, 1.0 - _flash_age / (flash_time * 2.5)) * (6.0 if not plasma else 7.0)
	for index: int in recoils.size():
		_recoil_age[index] += delta
		if recoils[index] == null: continue
		# Fast rearward kick, eased return into battery.
		var t := clampf(_recoil_age[index] / RECOIL_RETURN, 0.0, 1.0)
		var travel := RECOIL_TRAVEL * (1.0 - t) * (1.0 - t) if kind == "cannon" else 0.0
		recoils[index].transform = _recoil_rest[index].translated_local(Vector3(0, 0, travel))
	for projectile: Dictionary in _projectiles:
		projectile.age += delta
		var flight: float = projectile.flight
		var travelling: bool = projectile.age < flight
		var from: Vector3 = projectile.from
		var to: Vector3 = projectile.to
		var direction := (to - from).normalized() if to != from else Vector3.FORWARD
		var lobbed := kind == "mortar"
		if lobbed:
			var ahead := AtlasGeometry.mortar_point(from, to, flight, minf(projectile.age + 0.02, flight))
			var here := AtlasGeometry.mortar_point(from, to, flight, minf(projectile.age, flight))
			if ahead.distance_squared_to(here) > 0.000001: direction = (ahead - here).normalized()
			if not projectile.whistled and projectile.age >= flight - WHISTLE_LEAD and travelling:
				projectile.whistled = true
				if playback_enabled and not _whistles.is_empty():
					var whistle := _whistles[shot_count % _whistles.size()]
					whistle.stop()
					whistle.global_position = to + Vector3.UP * 6.0 * _scale
					whistle.play(maxf(0.0, WHISTLE_LEAD - (flight - projectile.age)))
		projectile.head.visible = travelling
		projectile.trail.visible = travelling
		if projectile.has("corona"): projectile.corona.visible = travelling
		if travelling:
			var at := from.lerp(to, projectile.age / maxf(flight, 0.0001))
			if lobbed: at = AtlasGeometry.mortar_point(from, to, flight, projectile.age)
			projectile.head.global_transform = Transform3D(_frame(direction), at)
			var tail := at - direction * minf(at.distance_to(from), (6.0 if not plasma else 4.5) * _scale)
			var length := maxf(0.01, at.distance_to(tail))
			projectile.trail.global_transform = Transform3D(_frame(direction).scaled_local(Vector3(1, length, 1)), (at + tail) * 0.5)
			if plasma:
				# Unstable plasma: the corona and light flicker as the bolt burns.
				var flicker := 0.85 + 0.3 * absf(sin(_time * 53.0 + projectile.from.x)) * randf_range(0.7, 1.0)
				projectile.corona.global_transform = Transform3D(_frame(direction).scaled_local(Vector3(flicker, 2.3 * flicker, flicker)), at)
				projectile.light.global_position = at
				projectile.light.light_energy = 4.0 * flicker
				projectile.embers.global_position = at
			else:
				projectile.light.global_position = at
				projectile.light.light_energy = 3.0
				projectile.embers.global_position = at - direction * 0.5 * _scale
		elif projectile.has("light"):
			projectile.light.light_energy = 0.0
			if projectile.embers.emitting: projectile.embers.emitting = false
		if not travelling and not projectile.impacted and projectile.age < flight + 0.5:
			projectile.impacted = true
			_impact(to, direction)
	var blast := MORTAR_BLAST_SCALE if kind == "mortar" else 1.0
	for record: Dictionary in _impacts:
		record.age += delta
		var age: float = record.age
		var light: OmniLight3D = record.light
		light.light_energy = maxf(0.0, 1.0 - age / (0.35 if plasma else 0.6)) * (4.0 if plasma else 10.0)
		if plasma and age < 0.35:
			light.light_color = Color(0.8, 0.85, 1.0).lerp(Color(1.0, 0.55, 0.2), age / 0.35)
		if record.has("shock"):
			var shock: MeshInstance3D = record.shock
			shock.visible = age < 0.45
			if shock.visible:
				# Blast ring racing out along the ground from the explosion.
				var ring := lerpf(0.3, 3.0, sqrt(age / 0.45)) * _scale * blast
				shock.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(ring, ring * 0.12, ring)), Vector3(record.at.x, record.at.y - 0.2 * _scale, record.at.z))
				(shock.material_override as StandardMaterial3D).albedo_color.a = 0.35 * (1.0 - age / 0.45)
		var flash: MeshInstance3D = record.flash
		flash.visible = age < (0.12 if plasma else 0.16)
		if flash.visible:
			var radius := lerpf(0.1, 0.4, age / 0.12) * _scale if plasma else lerpf(0.4, 1.4, age / 0.16) * _scale * blast
			flash.global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), record.at)
			(flash.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - age / (0.12 if plasma else 0.16))
		var decal: Decal = record.decal
		decal.visible = age < BURN_LIFETIME
		if decal.visible:
			# The burn glows white-hot, then cools to a charred mark.
			var heat := 1.0 - smoothstep(0.0, BURN_LIFETIME * 0.7, age)
			decal.emission_energy = heat * (8.0 if plasma else 3.0)
			decal.modulate = Color(1, 1, 1, 1.0 - smoothstep(BURN_LIFETIME * 0.6, BURN_LIFETIME, age))
	for puff: Dictionary in _fog:
		puff.age += delta
		if puff.age >= FOG_LIFETIME:
			puff.volume.hide()
			continue
		var age: float = puff.age
		var size := (0.5 + age * 0.9) * _scale
		puff.volume.size = Vector3(size, size * 0.85, size)
		puff.volume.global_position = puff.origin + Vector3(puff.direction) * (1.0 - exp(-age * 3.0)) * 0.9 * _scale + Vector3.UP * 0.18 * age * _scale
		var fade := smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.4, FOG_LIFETIME, age))
		var material := puff.volume.material as ShaderMaterial
		material.set_shader_parameter("density", 0.55 * fade)
		material.set_shader_parameter("age", age)

func set_playback_enabled(enabled: bool) -> void:
	playback_enabled = enabled
	if not enabled:
		for voice: AudioStreamPlayer3D in _voices + _impact_voices + _whistles: voice.stop()

## Also forgets the shot baseline: the next accepted view is silent.
func clear_effects() -> void:
	_seen = -1
	_tick = -1
	_flash_age = 1.0
	for index: int in recoils.size():
		_recoil_age[index] = 1.0
		if recoils[index] != null: recoils[index].transform = _recoil_rest[index]
	for projectile: Dictionary in _projectiles:
		projectile.age = 10.0
		projectile.impacted = true
		for key: String in ["head", "trail", "corona"]:
			if projectile.has(key): projectile[key].hide()
		if projectile.has("light"): projectile.light.light_energy = 0.0
		if projectile.has("embers"): projectile.embers.emitting = false
	for record: Dictionary in _impacts:
		record.age = 10.0
		record.light.light_energy = 0.0
		record.flash.hide()
		record.decal.hide()
		record.sparks.emitting = false
		if record.has("shock"): record.shock.hide()
		if record.has("fireball"):
			record.fireball.emitting = false
			record.column.emitting = false
	for blast: GPUParticles3D in _blasts:
		blast.emitting = false
		blast.restart()
		blast.emitting = false
	for puff: Dictionary in _fog:
		puff.age = FOG_LIFETIME
		puff.volume.hide()
	if _flash != null: _flash.hide()
	if _flash_ball != null: _flash_ball.hide()
	if _light != null: _light.light_energy = 0.0
	for voice: AudioStreamPlayer3D in _voices + _impact_voices + _whistles: voice.stop()

## First-pass procedural sounds (A may replace them with recorded assets).
static func _stream(label: String) -> AudioStreamWAV:
	if _streams.has(label): return _streams[label]
	var length: float = {"cannon":1.9, "plasma":0.9, "cannon_impact":1.8, "plasma_impact":1.2,
		"mortar":1.6, "mortar_impact":2.6, "mortar_whistle":WHISTLE_LEAD}.get(label, 0.5)
	var samples := PackedFloat32Array()
	samples.resize(roundi(RATE * length))
	var state := hash(label) & 0x7fffffff
	var low := 0.0
	var high := 0.0
	var phase := 0.0
	var phase2 := 0.0
	var gate := 0.0
	var rumble := 0.0
	var peak := 0.0001
	for index: int in samples.size():
		var t := index / float(RATE)
		state = (state * 1664525 + 1013904223) & 0x7fffffff
		var noise := state / 1073741824.0 - 1.0
		low += (noise - low) * (0.05 if label.begins_with("cannon") or label.begins_with("mortar") else (0.06 if label.begins_with("plasma") else 0.3))
		high += (noise - high) * 0.02
		var hiss := noise - high
		# Random electrical/sizzle bursts: short gated crackles.
		if (state & 0x3ff) < 6: gate = 1.0
		gate *= 0.9965
		var value := 0.0
		match label:
			"cannon":
				# Big-gun report: a hard muzzle crack, a saturated chest-hit boom
				# falling 60->28 Hz, a heavy blast body, a long rolling rumble and
				# the breech clank as the barrel runs back into battery.
				phase += TAU * lerpf(60.0, 28.0, minf(1.0, t / 0.45)) / RATE
				var crack := hiss * exp(-t * 140.0) * 1.4
				var boom := tanh(sin(phase) * 3.0) * exp(-t * 3.2) * 1.3
				var body := low * exp(-t * 5.5) * 3.2
				rumble += (noise - rumble) * 0.012
				var roll := rumble * exp(-t * 1.4) * 5.0
				var clank := (sin(TAU * 1830.0 * t) * 0.6 + sin(TAU * 2710.0 * t) * 0.4) * exp(-maxf(0.0, t - 0.34) * 40.0) * float(t > 0.34) * 0.18
				value = tanh((crack + boom + body + roll + clank) * 1.8)
			"plasma":
				# Punchy low discharge: a saturated sub thump dropping 95->38 Hz,
				# a dark low-passed air push, a low falling arc and only a little
				# crackle. Bright hiss read as a thin "tap", so it is kept low.
				phase += TAU * lerpf(95.0, 38.0, minf(1.0, t / 0.22)) / RATE
				var thump := tanh(sin(phase) * 2.2) * exp(-t * 7.5) * 1.1
				var push := low * exp(-t * 16.0) * 2.6
				var frequency := lerpf(520.0, 70.0, minf(1.0, t / 0.35))
				phase2 += TAU * frequency / RATE
				var arc := (sin(phase2) + 0.45 * sin(phase2 * 2.0) + 0.25 * sin(phase2 * 3.0)) * exp(-t * 6.0) * 0.45
				var crackle := (low - high) * gate * exp(-t * 6.0) * 0.5
				value = tanh((thump + push + arc + crackle) * 1.6)
			"mortar":
				# Hollow tube thoomp: a deep saturated pop falling 48->22 Hz, the
				# tube ringing at its air-column note, a blast of low air and a
				# rolling tail. Less crack than the cannon: it lobs, not fires flat.
				phase += TAU * lerpf(48.0, 22.0, minf(1.0, t / 0.35)) / RATE
				var pop := tanh(sin(phase) * 3.5) * exp(-t * 4.0) * 1.4
				var tube := sin(TAU * 170.0 * t) * exp(-t * 9.0) * 0.35 + sin(TAU * 340.0 * t) * exp(-t * 14.0) * 0.12
				rumble += (noise - rumble) * 0.012
				value = tanh((hiss * exp(-t * 90.0) * 0.6 + pop + tube + low * exp(-t * 5.0) * 3.0 + rumble * exp(-t * 1.6) * 4.0) * 1.8)
			"mortar_whistle":
				# Incoming shell: a falling whistle with air rush, rising in level.
				phase += TAU * lerpf(1500.0, 520.0, t / WHISTLE_LEAD) / RATE
				value = (sin(phase) * 0.7 + (low - high) * 0.5) * lerpf(0.25, 1.0, t / WHISTLE_LEAD)
			"plasma_impact":
				# Searing contact: a deep thud, a dark burning roar and spitting metal.
				phase += TAU * lerpf(80.0, 42.0, minf(1.0, t / 0.2)) / RATE
				var thud := tanh(sin(phase) * 2.0) * exp(-t * 9.0) * 1.0
				var roar := low * exp(-t * 3.0) * 1.6
				var spit := (low - high) * gate * exp(-t * 2.5) * 0.45
				value = tanh((thud + roar + spit + hiss * exp(-t * 40.0) * 0.25) * 1.5)
			_:
				# Shell detonation: crack, a deep saturated blast, debris crunch
				# and a long rumbling tail.
				phase += TAU * lerpf(55.0, 26.0, minf(1.0, t / 0.5)) / RATE
				rumble += (noise - rumble) * 0.015
				var blast := tanh(sin(phase) * 3.2) * exp(-t * 3.5) * 1.3
				var debris := (low - high) * gate * exp(-t * 3.0) * 0.8
				value = tanh((hiss * exp(-t * 110.0) * 1.2 + blast + low * exp(-t * 6.0) * 3.0
					+ rumble * exp(-t * 1.3) * 5.0 + debris) * 1.8)
		var edges := smoothstep(0.0, 0.001, t) * (1.0 - smoothstep(length - 0.06, length, t))
		samples[index] = value * edges
		peak = maxf(peak, absf(samples[index]))
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index: int in samples.size():
		pcm.encode_s16(index * 2, roundi(clampf(samples[index] / peak * 0.88, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = pcm
	_streams[label] = stream
	return stream
