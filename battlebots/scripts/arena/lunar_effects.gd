extends Node3D
## Client-only ambient choreography and bounded movement-driven surface effects.
const SURFACE = preload("res://scripts/arena/moon_surface.gd")
const TRACK_LIMIT := 192
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
	for id: int in fine_dust.keys():
		if not world.bots.has(id):
			fine_dust[id].queue_free()
			fine_dust.erase(id)
			last_track.erase(id)
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		var velocity: Vector3 = bot.body.linear_velocity if bot.simulated else bot.remote_state.get("velocity",Vector3.ZERO)
		var grounded: bool = bot.body.grounded if bot.simulated else bot.remote_state.get("grounded",false)
		var eliminated: bool = bot.combat.eliminated if bot.simulated else bot.remote_state.get("eliminated",true)
		var moving := grounded and not eliminated and Vector2(velocity.x,velocity.z).length()>.75
		if not fine_dust.has(id):
			if fine_dust.size()>=10: continue
			fine_dust[id] = puff_emitter(150)
		var p := bot.body.global_position
		var dust: GPUParticles3D = fine_dust[id]
		dust.global_position = p+bot.body.global_basis.z*.65-Vector3.UP*.23
		dust.emitting = moving
		var previous: Vector3 = last_track.get(id,p)
		if moving and p.distance_to(previous)>.42 and p.distance_to(previous)<3:
			for side: float in [-.6,.6]:
				var at := p+bot.body.global_basis.x*side
				if absf(at.x)<24 and absf(at.z)<24 and absf(at.x)+absf(at.z)<34:
					stamp(at,bot.body.global_rotation.y)
			last_track[id] = p
		elif not last_track.has(id) or not moving or p.distance_to(previous)>=3:
			last_track[id] = p

func stamp(at: Vector3, yaw: float) -> void:
	var mark := tracks[cursor]
	at.y = SURFACE.height_at(at.x,at.z)+.016
	var normal := Vector3(SURFACE.height_at(at.x-.05,at.z)-SURFACE.height_at(at.x+.05,at.z),.1,SURFACE.height_at(at.x,at.z-.05)-SURFACE.height_at(at.x,at.z+.05)).normalized()
	var forward := Vector3(sin(yaw),0,cos(yaw))
	var right := normal.cross(forward).normalized()
	mark.global_transform = Transform3D(Basis(right,normal,right.cross(normal)),at)
	mark.visible = true
	ages[cursor] = 0
	(mark.material_override as ShaderMaterial).set_shader_parameter("opacity",1.)
	cursor = (cursor+1)%TRACK_LIMIT
