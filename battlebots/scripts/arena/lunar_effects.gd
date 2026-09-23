extends Node3D
## Client-only ambient choreography and bounded movement-driven surface effects.
const SURFACE = preload("res://scripts/arena/moon_surface.gd")
const TRACK_LIMIT := 192
const BOT_LIMIT := 10
const CLOUD_LIMIT := 48
const CLOUD_LIFETIME := 2.8
const CLOUD_INTERVAL := 0.32
var ballistic_dust: Dictionary = {}
var side_dust: Dictionary = {}
var observations: Dictionary = {}
var clouds: Array[Dictionary] = []
var cloud_cursor := 0
var _round_source: WeakRef
var elapsed := 0.0
var vents: Array[GPUParticles3D] = []
var volumes: Array[FogVolume] = []
var beacons: Array[SpotLight3D] = []
var fine_dust: Dictionary = {}
var last_track: Dictionary = {}
var tracks: Array[MeshInstance3D] = []
var ages := PackedFloat32Array()
var cursor := 0

func _ready() -> void:
	# Follow B's interpolated presentation pose after its normal frame update.
	process_priority = 100
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	for side: int in [0,2,6]:
		var turn := Basis(Vector3.UP,side*PI/4)
		var volume := FogVolume.new()
		volume.name = "BayDust%d" % side
		volume.size = Vector3(13,8,9)
		volume.position = turn*Vector3(-4,6,-30)
		volume.rotation.y = side*PI/4
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/materials/arena/lunar_fog.gdshader")
		volume.material = material
		add_child(volume)
		volumes.append(volume)
		var vent := puff_emitter(110)
		vent.name = "Vent%d" % side
		vent.position = turn*Vector3(-2,8.9,-32)
		var motion := vent.process_material as ParticleProcessMaterial
		motion.direction = turn*Vector3(0,.3,1)
		motion.initial_velocity_min = .8
		motion.initial_velocity_max = 1.8
		motion.gravity = Vector3(0,.06,0)
		motion.scale_min = .4
		motion.scale_max = 1.4
		vent.lifetime = 3
		vents.append(vent)
		var beacon := SpotLight3D.new()
		beacon.name = "MaintenanceBeacon%d" % side
		beacon.position = turn*Vector3(-4,9.7,-32)
		beacon.light_color = Color("ff9b32")
		beacon.light_energy = 6
		beacon.spot_range = 17
		beacon.spot_angle = 28
		beacon.light_volumetric_fog_energy = 0 # Moving beams must not leave temporal ghosts.
		beacon.shadow_enabled = false
		add_child(beacon)
		beacons.append(beacon)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(.3,.55)
	for i: int in range(TRACK_LIMIT):
		var mark := MeshInstance3D.new()
		mark.mesh = mesh
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/materials/arena/lunar_track.gdshader")
		mark.material_override = m
		mark.visible = false
		add_child(mark)
		tracks.append(mark)
		ages.append(100)

func puff_emitter(amount: int) -> GPUParticles3D:
	var emitter := GPUParticles3D.new()
	emitter.amount = amount
	emitter.lifetime = 1.7
	emitter.local_coords = false
	emitter.emitting = false
	emitter.visibility_aabb = AABB(Vector3(-5,-2,-5),Vector3(10,8,10))
	var motion := ParticleProcessMaterial.new()
	motion.direction = Vector3.UP
	motion.spread = 65
	motion.initial_velocity_min = .3
	motion.initial_velocity_max = 1.0
	motion.gravity = Vector3(0,-1.62,0)
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(.65,.02,.15)
	motion.scale_min = .06
	motion.scale_max = .24
	var gradient := Gradient.new()
	gradient.set_color(0,Color(1,1,1,0))
	gradient.set_color(1,Color(1,1,1,0))
	gradient.add_point(.15,Color.WHITE)
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	motion.color_ramp = ramp
	emitter.process_material = motion
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/arena/lunar_dust.gdshader")
	quad.material = material
	emitter.draw_pass_1 = quad
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(emitter)
	return emitter

func _process(delta: float) -> void:
	elapsed += delta
	for i: int in range(vents.size()):
		var phase := fmod(elapsed+i*3.7,14.0)
		vents[i].emitting = phase<3.2
		(volumes[i].material as ShaderMaterial).set_shader_parameter("pulse",.3+.7*(1.-smoothstep(3.,7.,phase)))
		beacons[i].rotation = Vector3(-.45,elapsed*.24+i*PI/2,0)
		beacons[i].light_energy = 2.0+4.0*(1.-smoothstep(3.2,4.5,phase))
	for i: int in range(tracks.size()):
		if not tracks[i].visible:
			continue
		ages[i] += delta
		tracks[i].visible = ages[i]<35
		(tracks[i].material_override as ShaderMaterial).set_shader_parameter("opacity",1.-smoothstep(18.,35.,ages[i]))
	var arena := get_parent().get_node("../..")
	var world := arena.get_parent() as AuthorityWorld
	if world == null:
		return
	if _round_source != null and _round_source.get_ref() != world.weapons:
		clear_trails()
	_round_source = weakref(world.weapons)
	_update_clouds(delta)
	for id: int in observations.keys():
		if not world.bots.has(id) or observations[id].bot.get_ref() != world.bots[id]:
			_remove_bot(id)
	for id: int in world.bots:
		update_bot(world.bots[id], delta)

func update_bot(bot: MvpBot, delta: float) -> void:
	var id := bot.entity_id
	if not observations.has(id):
		if observations.size() >= BOT_LIMIT: return
		_create_bot(bot)
	var history: Dictionary = observations[id]
	var pose := bot.presentation.global_transform
	var p := pose.origin
	var velocity: Vector3 = bot.body.linear_velocity if bot.simulated else bot.remote_state.get("velocity",Vector3.ZERO)
	var angular: Vector3 = bot.body.angular_velocity if bot.simulated else bot.remote_state.get("angular",Vector3.ZERO)
	var grounded: bool = bot.body.grounded if bot.simulated else bot.remote_state.get("grounded",false)
	var eliminated: bool = bot.combat.eliminated if bot.simulated else bot.remote_state.get("eliminated",true)
	var size: Vector3 = history.size
	var discontinuity: bool = p.distance_to(history.position) > maxf(4.0, velocity.length()*maxf(delta,0.0)*2.0+1.0) or bot.server_tick < history.tick or (history.eliminated and not eliminated)
	if discontinuity:
		_reset_bot_trail(id)
	var flat_velocity := Vector3(velocity.x,0,velocity.z)
	var speed := flat_velocity.length()
	# A pivot also scuffs the surface even when the hull centre hardly moves.
	var contact_speed := speed + absf(angular.y)*size.x*.4
	var moving := grounded and not eliminated and contact_speed > .65 and pose.basis.y.dot(Vector3.UP) > .25 and not discontinuity
	var strength := clampf(contact_speed/8.0,0.0,1.0)
	var yaw := pose.basis.get_euler().y
	var flat_basis := Basis(Vector3.UP,yaw)
	var local_speed := flat_basis.inverse()*flat_velocity
	var trailing_end := -signf(local_speed.z)*size.z*.32 if absf(local_speed.z)>.3 else 0.0
	var contacts: Array[Vector3] = []
	for i: int in 2:
		var side := -1.0 if i==0 else 1.0
		var at := p+flat_basis*Vector3(side*size.x*.48,0,trailing_end)
		at.y = SURFACE.height_at(at.x,at.z)+.07
		contacts.append(at)
		var valid := moving and ArenaBounds.contains(at,25.0,.15)
		var outward := flat_basis.x*side
		var direction := (outward*.65-flat_velocity*.12+Vector3.UP*.8).normalized()
		for emitter: GPUParticles3D in [side_dust[id][i],ballistic_dust[id][i]]:
			emitter.global_transform = Transform3D(flat_basis,at)
			emitter.emitting = valid
			emitter.amount_ratio = maxf(.12,strength)
			var motion := emitter.process_material as ParticleProcessMaterial
			# Particle process directions are in the emitter's local frame.
			motion.direction = flat_basis.inverse()*direction
			motion.initial_velocity_min = .45+strength*.45
			motion.initial_velocity_max = 1.1+strength*1.25
	var travelled := p.distance_to(last_track.get(id,p))
	if moving and travelled > .65 and travelled < 4.0:
		for at: Vector3 in contacts:
			if ArenaBounds.contains(at,25.0,.4): stamp(at,yaw,clampf(size.x*.16,.35,1.05))
		last_track[id] = p
	elif not last_track.has(id) or not moving or travelled >= 4.0:
		last_track[id] = p
	history.clock += minf(delta,.1)
	if moving and history.clock >= CLOUD_INTERVAL:
		history.clock = 0.0
		for at: Vector3 in contacts:
			if ArenaBounds.contains(at,25.0,.5): _spawn_cloud(id,at,size,strength)
	elif not moving: history.clock = CLOUD_INTERVAL
	history.position = p
	history.tick = bot.server_tick
	history.eliminated = eliminated

func _create_bot(bot: MvpBot) -> void:
	var id := bot.entity_id
	var size := bot.collision_bounds().size
	observations[id] = {"bot":weakref(bot),"position":bot.presentation.global_position,"tick":bot.server_tick,"eliminated":false,"clock":0.0,"size":size}
	var puffs: Array[GPUParticles3D] = []
	var grains: Array[GPUParticles3D] = []
	for i: int in 2:
		var puff := puff_emitter(180)
		puff.name = "DrivingDust%d_%d" % [id,i]
		puff.lifetime = 2.2
		puff.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		puff.visibility_aabb = AABB(Vector3(-9,-3,-9),Vector3(18,9,18))
		var motion := puff.process_material as ParticleProcessMaterial
		motion.emission_box_extents = Vector3(.24,.025,size.z*.22)
		motion.gravity = Vector3(0,-.5,0)
		motion.scale_min = .55
		motion.scale_max = 1.15
		var growth := Curve.new()
		growth.max_value = 2.0
		growth.add_point(Vector2(0,.35))
		growth.add_point(Vector2(.35,1.0))
		growth.add_point(Vector2(1,1.65))
		var growth_texture := CurveTexture.new()
		growth_texture.curve = growth
		motion.scale_curve = growth_texture
		motion.angle_min = -180
		motion.angle_max = 180
		motion.angular_velocity_min = -35
		motion.angular_velocity_max = 35
		motion.turbulence_enabled = true
		motion.turbulence_noise_strength = .45
		motion.turbulence_noise_scale = 2.5
		motion.turbulence_influence_min = .025
		motion.turbulence_influence_max = .09
		puffs.append(puff)
		grains.append(_grain_emitter(size))
	side_dust[id] = puffs
	fine_dust[id] = puffs[0] # Published review fixture handle.
	ballistic_dust[id] = grains

func _grain_emitter(size: Vector3) -> GPUParticles3D:
	var dust := GPUParticles3D.new()
	dust.name = "BallisticDust"
	dust.amount = 96
	dust.lifetime = 1.5
	dust.local_coords = false
	dust.emitting = false
	dust.visibility_aabb = AABB(Vector3(-9,-3,-9),Vector3(18,9,18))
	var motion := ParticleProcessMaterial.new()
	motion.spread = 48
	motion.gravity = Vector3(0,-1.62,0)
	motion.scale_min = .022
	motion.scale_max = .07
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(.24,.025,size.z*.22)
	motion.color = Color(.52,.51,.48)
	dust.process_material = motion
	var grain := SphereMesh.new()
	grain.radius = .5
	grain.height = 1
	grain.radial_segments = 6
	grain.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.6,.59,.57)
	material.roughness = 1
	material.vertex_color_use_as_albedo = true
	grain.material = material
	dust.draw_pass_1 = grain
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)
	return dust

func _spawn_cloud(id: int, at: Vector3, footprint: Vector3, strength: float) -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus": return
	var item: Dictionary
	if clouds.size() < CLOUD_LIMIT:
		var volume := FogVolume.new()
		volume.name = "DrivingCloud%d" % clouds.size()
		var material := ShaderMaterial.new()
		material.shader = preload("res://assets/materials/arena/lunar_driving_fog.gdshader")
		volume.material = material
		add_child(volume)
		item = {"volume":volume,"age":0.0,"owner":id,"origin":at,"size":Vector3.ONE,"strength":strength}
		clouds.append(item)
	else:
		item = clouds[cloud_cursor]
		cloud_cursor = (cloud_cursor+1)%CLOUD_LIMIT
	item.age = 0.0
	item.owner = id
	item.origin = at
	item.size = Vector3(clampf(footprint.x*.6,1.4,3.4),1.5,clampf(footprint.z*.5,1.8,3.8))
	item.strength = strength
	item.volume.visible = true
	item.volume.global_position = at+Vector3.UP*.45
	item.volume.size = item.size
	item.volume.material.set_shader_parameter("density",0.0)

func _update_clouds(delta: float) -> void:
	for item: Dictionary in clouds:
		item.age += maxf(delta,0.0)
		if item.age >= CLOUD_LIFETIME:
			item.volume.hide()
			continue
		var age: float = item.age
		item.volume.size = item.size*(1.0+age*.36)
		item.volume.global_position = item.origin+Vector3.UP*(.45+.3*age-.08*age*age)
		var fade := smoothstep(0.0,.18,age)*(1.0-smoothstep(.5,CLOUD_LIFETIME,age))
		item.volume.material.set_shader_parameter("density",.1*item.strength*fade)
		item.volume.material.set_shader_parameter("age",age)

func _reset_bot_trail(id: int) -> void:
	for emitter: GPUParticles3D in side_dust[id]+ballistic_dust[id]:
		emitter.emitting = false
		emitter.restart()
		emitter.emitting = false
	for item: Dictionary in clouds:
		if item.owner == id:
			item.age = CLOUD_LIFETIME
			item.volume.hide()
	last_track.erase(id)

func _remove_bot(id: int) -> void:
	_reset_bot_trail(id)
	for emitter: GPUParticles3D in side_dust[id]+ballistic_dust[id]: emitter.queue_free()
	side_dust.erase(id)
	ballistic_dust.erase(id)
	fine_dust.erase(id)
	observations.erase(id)

func clear_trails() -> void:
	for id: int in observations.keys(): _remove_bot(id)
	for track: MeshInstance3D in tracks: track.hide()
	for item: Dictionary in clouds: item.volume.queue_free()
	clouds.clear()
	cloud_cursor = 0

func stamp(at: Vector3, yaw: float, width := .3) -> void:
	var mark := tracks[cursor]
	at.y = SURFACE.height_at(at.x,at.z)+.016
	var normal := Vector3(SURFACE.height_at(at.x-.05,at.z)-SURFACE.height_at(at.x+.05,at.z),.1,SURFACE.height_at(at.x,at.z-.05)-SURFACE.height_at(at.x,at.z+.05)).normalized()
	var forward := Vector3(sin(yaw),0,cos(yaw))
	var right := normal.cross(forward).normalized()
	mark.global_transform = Transform3D(Basis(right,normal,right.cross(normal)),at)
	mark.scale = Vector3(width/.3,1,1.6)
	mark.visible = true
	ages[cursor] = 0
	(mark.material_override as ShaderMaterial).set_shader_parameter("opacity",1.)
	cursor = (cursor+1)%TRACK_LIMIT
