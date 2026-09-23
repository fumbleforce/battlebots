extends "res://scripts/arena/foundry_visuals.gd"
## Lunar scenery and ballistic dust. Physical terrain lives in moon_surface.gd.
const REGOLITH = preload("res://assets/textures/moon/regolith_albedo.png")
const GROUND = preload("res://assets/materials/arena/moon_ground.gdshader")
# Exclusive render layer for exterior geology. Never a physics/collision layer.
const BACKDROP_LAYER := 1 << 1
var _terrain_noise := FastNoiseLite.new()

func _build() -> void:
	_terrain_noise.seed = 2049
	_terrain_noise.frequency = 0.055
	_terrain_noise.fractal_octaves = 5
	_material("steel", Color("777e83"))
	_material("dark", Color("202931"))
	_material("concrete", Color("a6a8a5"))
	_material("rust", Color("776854"))
	_material("hazard", Color.WHITE)
	_material("foil", Color("baa06b"))
	_material("white", Color("e0ecff"), 3.0)
	_material("amber", Color("ffae44"), 2.0)
	_material("cyan", Color("70d3e8"), 1.5)
	var arena := get_node(arena_path)
	var ground := preload("res://scripts/arena/lunar_materials.gd").ground()
	_materials.regolith = ground
	var playable := ground.duplicate() as ShaderMaterial
	playable.set_shader_parameter("playable", true)
	(arena.get_node("Floor/Mesh") as MeshInstance3D).material_override = playable
	for wall: Node in arena.get_node("Walls").get_children():
		(wall.get_node("Mesh") as MeshInstance3D).material_override = _materials.concrete
	(arena.get_node("Markings") as Node3D).hide()
	_lunar_lighting(arena)
	_terrain()
	_boulders()
	for side: int in range(8):
		_side = Transform3D(Basis(Vector3.UP, side*PI/4), Vector3.ZERO)
		_perimeter(side)
	_side = Transform3D.IDENTITY
	_earth()
	_flush()
	for child: Node in get_children():
		if child is MultiMeshInstance3D and child.name not in ["WhiteBatch","AmberBatch","CyanBatch"]:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_pebbles()
	var effects := preload("res://scripts/arena/lunar_effects.gd").new()
	effects.name = "LunarEffects"
	add_child(effects)

func _pebbles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3911
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 1.5
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _materials.regolith
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = 4800
	for i: int in range(multi.instance_count):
		var p := Vector3(rng.randf_range(-24,24),0,rng.randf_range(-24,24))
		if absf(p.x)+absf(p.z)>34:
			p *= 0.65
		p.y = preload("res://scripts/arena/moon_surface.gd").height_at(p.x,p.z)+0.005
		var scale := rng.randf_range(0.012,0.065)
		multi.set_instance_transform(i,Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled_local(Vector3(scale,scale*0.6,scale)),p))
	var pebbles := MultiMeshInstance3D.new()
	pebbles.name = "SurfacePebbles"
	pebbles.multimesh = multi
	add_child(pebbles)

func _height(x: float, z: float) -> float:
	var p := Vector2(x,z)
	var r := p.length()
	var n := _terrain_noise.get_noise_2d(x,z)
	var ramp := smoothstep(29.0,48.0,r)
	var ridge := exp(-pow((r-66.0)/19.0,2.0))
	var angular := 0.5+0.5*sin(atan2(z,x)*7.0+0.8)
	var y := -0.18+ramp*(2.5+ridge*(7.0+angular*5.0)+n*9.0)
	# Two broad crater bowls with raised rims, entirely beyond the combat boundary.
	for center: Vector2 in [Vector2(-43,-31),Vector2(37,40),Vector2(20,-55)]:
		var d := p.distance_to(center)
		y += exp(-pow((d-10.0)/2.0,2.0))*2.5-exp(-pow(d/7.0,2.0))*3.0
	return y

func _terrain() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 320
	const RINGS := 80
	for ring: int in range(RINGS+1):
		for sector: int in range(SEGMENTS+1):
			var angle := sector*TAU/SEGMENTS
			var d := Vector2(cos(angle),sin(angle))
			var edge := 25.8/maxf(maxf(absf(d.x),absf(d.y)),(absf(d.x)+absf(d.y))/sqrt(2.0))
			var r := lerpf(edge,112.0,float(ring)/RINGS)
			var p := d*r
			vertices.append(Vector3(p.x,_height(p.x,p.y),p.y))
			normals.append(Vector3(_height(p.x-0.1,p.y)-_height(p.x+0.1,p.y),0.2,
				_height(p.x,p.y-0.1)-_height(p.x,p.y+0.1)).normalized())
	for ring: int in range(RINGS):
		for sector: int in range(SEGMENTS):
			var a := ring*(SEGMENTS+1)+sector
			var b := a+SEGMENTS+1
			indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_materials.regolith)
	var landscape := MeshInstance3D.new()
	landscape.name = "CraterRidges"
	landscape.mesh = mesh
	landscape.layers = BACKDROP_LAYER
	add_child(landscape)

func _boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 62026
	for variant: int in range(8):
		var source := load("res://assets/models/lunar/rock_%02d.glb" % variant).instantiate() as Node3D
		var template := source.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
		var mesh := template.mesh.duplicate() as ArrayMesh
		for surface: int in range(mesh.get_surface_count()):
			mesh.surface_set_material(surface,_materials.regolith)
		source.free()
		# Separate octants give each batch meaningful culling bounds.
		for sector: int in range(8):
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = 12
			for i: int in range(12):
				var angle := (sector+rng.randf())*TAU/8
				var d := Vector2(cos(angle),sin(angle))
				var edge := 25.0/maxf(maxf(absf(d.x),absf(d.y)),(absf(d.x)+absf(d.y))/sqrt(2.0))
				var r := edge+rng.randf_range(5,39)
				var p := Vector3(d.x*r,0,d.y*r)
				var scale := rng.randf_range(.45,3.2)
				p.y = _height(p.x,p.z)+scale*.24
				var basis := Basis.from_euler(Vector3(rng.randf()*.4,rng.randf()*TAU,rng.randf()*.2)).scaled_local(Vector3(scale,scale,scale))
				multi.set_instance_transform(i,Transform3D(basis,p))
			var rocks := MultiMeshInstance3D.new()
			rocks.name = "FracturedRock_%d_%d" % [variant,sector]
			rocks.multimesh = multi
			rocks.layers = BACKDROP_LAYER
			rocks.visibility_range_end = 135
			add_child(rocks)
func _perimeter(side: int) -> void:
	# Segmented pressure-resistant retaining walls visibly match the shared collider.
	for panel: int in range(6):
		var x := -8.63+panel*3.452
		_box("concrete",Vector3(x,1.48,-24.96),Vector3(3.37,2.92,0.10))
		_box("dark",Vector3(x,0.26,-24.88),Vector3(3.4,0.45,0.14))
		_box("hazard",Vector3(x,2.64,-24.88),Vector3(3.35,0.48,0.10))
		for dx: float in [-1.43,1.43]:
			_box("steel",Vector3(x+dx,1.45,-24.87),Vector3(0.075,2.1,0.12))
			for y: float in [0.55,2.2]:
				_box("dark",Vector3(x+dx,y,-24.79),Vector3(0.13,0.13,0.05))
	_box("steel",Vector3(0,3.06,-25.1),Vector3(20.85,0.15,0.4))
	for x: float in [-9,0,9]:
		_box("cyan" if side % 2 == 0 else "amber",Vector3(x,2.12,-24.82),Vector3(0.7,0.07,0.025))
	# Exterior maintenance catwalk and safety handrail.
	_box("dark",Vector3(0,3.12,-26.6),Vector3(21.7,0.22,2.1))
	for y: float in [3.65,4.15]:
		_box("steel",Vector3(0,y,-27.55),Vector3(22.2,0.055,0.055))
	for x: float in [-10,-5,0,5,10]:
		_box("steel",Vector3(x,3.65,-27.55),Vector3(0.065,1.1,0.065))
	if side % 2 == 0:
		_outpost(side)
	else:
		_solar_array()
	_tower(-9.6,side)

func _outpost(side: int) -> void:
	if side not in [0,2,6]:
		_solar_array()
		return
	var bay := preload("res://assets/models/lunar/baked_service_bay.tscn").instantiate()
	bay.name = "ServiceBay%d" % side
	for child: Node in bay.get_children():
		if child is DirectionalLight3D: child.free()
	bay.transform = _side*Transform3D(Basis.IDENTITY,Vector3(0,3.25,-30.5))
	add_child(bay)
	var finishes := {}
	for mesh: MeshInstance3D in bay.find_children("*","MeshInstance3D",true,false):
		for index: int in range(mesh.mesh.get_surface_count()):
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			if original==null or original.emission_enabled: continue
			if not finishes.has(original):
				var finish := ShaderMaterial.new()
				finish.shader = preload("res://assets/materials/arena/lunar_alloy.gdshader")
				finish.set_shader_parameter("paint",original.albedo_color)
				finish.set_shader_parameter("metalness",original.metallic)
				finish.set_shader_parameter("rough",original.roughness)
				finish.set_shader_parameter("grain",preload("res://assets/textures/lunar/surface3_relief.png"))
				finishes[original] = finish
			mesh.set_surface_override_material(index,finishes[original])
	_text("SELENE  /  %02d" % (side+1),Vector3(1,7.1,-28.86),64,.009,Color("20292f"))
	if side == 0:
		_dish(Vector3(1.7,9.5,-30.5))
	var probe := ReflectionProbe.new()
	probe.position = _side*Vector3(0,6,-30)
	probe.size = Vector3(15,10,15)
	probe.max_distance = 22
	probe.intensity = .65
	add_child(probe)
func _tower(x: float, side: int) -> void:
	for dx: float in [-0.38,0.38]:
		_box("steel",Vector3(x+dx,7.2,-26.0),Vector3(0.12,8.1,0.18))
	for i: int in range(6):
		var y := 3.2+i*1.3
		_beam("steel",Vector3(x-0.38,y,-26),Vector3(x+0.38,y+1.3,-26),0.055)
		_beam("steel",Vector3(x+0.38,y,-26),Vector3(x-0.38,y+1.3,-26),0.055)
	# Lamp housing and all six lenses share the actual beam direction. The
	# lenses face local +Z; Godot spotlights emit along local -Z.
	var mount := Vector3(x,11.45,-25.8)
	var target := Vector3(x*0.3,0,-9)
	var aim := Basis.looking_at(target-mount,Vector3.UP,true)
	var fixture_rotation := aim.get_euler()
	_box("dark",mount,Vector3(2.4,1.4,0.4),fixture_rotation)
	for dx: float in [-0.75,0,0.75]:
		for y: float in [-0.35,0.35]:
			_box("white",mount+aim*Vector3(dx,y,0.24),Vector3(0.5,0.46,0.04),fixture_rotation)
	var light := SpotLight3D.new()
	light.name = "ArenaFloodlight%d" % side
	add_child(light)
	light.position = _side*(mount+aim*Vector3(0,0,0.27))
	light.look_at(_side*target)
	light.light_cull_mask &= ~BACKDROP_LAYER
	# Warm practical pools separate the inhabited base from the cool crater rim.
	light.light_color = Color("ffe1b6")
	light.light_energy = 3.0
	light.light_volumetric_fog_energy = 8.0
	# The old 47-degree half-cone reached above the horizon. Keep the beam
	# pointed down and its reach inside the opposite retaining wall.
	light.spot_angle = 28
	light.spot_range = 32
	light.shadow_enabled = true

func _solar_array() -> void:
	for x: float in [-5.0,5.0]:
		_box("steel",Vector3(x,4.8,-31),Vector3(0.25,3,0.25))
		_box("dark",Vector3(x,6.3,-31),Vector3(7,0.18,3.2),Vector3(0.28,0,0))
		for cell: int in range(7):
			_box("steel",Vector3(x-3+cell,6.44,-31),Vector3(0.035,0.035,3.2),Vector3(0.28,0,0))
		_box("foil",Vector3(x,3.8,-29),Vector3(2.5,1.3,1.6))

func _dish(at: Vector3) -> void:
	_pipe(at-Vector3(0,1,0),0.12,2.4,Vector3.ZERO,"steel")
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dish_material := StandardMaterial3D.new()
	dish_material.albedo_color = Color(0.55,0.57,0.59)
	dish_material.metallic = 0.45
	dish_material.roughness = 0.65
	dish_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.set_material(dish_material)
	for ring: int in range(8):
		for segment: int in range(48):
			var points: Array[Vector3] = []
			for pair: Vector2 in [Vector2(ring,segment),Vector2(ring+1,segment),Vector2(ring+1,segment+1),Vector2(ring,segment+1)]:
				var radius := pair.x*0.26
				var a := pair.y*TAU/48
				points.append(Vector3(cos(a)*radius,sin(a)*radius,radius*radius*0.16))
			for i: int in [0,1,2,0,2,3]:
				mesh.add_vertex(points[i])
	mesh.generate_normals()
	var dish := MeshInstance3D.new()
	dish.mesh = mesh.commit()
	dish.transform = _side*Transform3D(Basis.from_euler(Vector3(-0.65,0.25,0)),at)
	add_child(dish)
	_beam("steel",at+Vector3(-1.4,0,0.4),at+Vector3(0,0,1.8),0.06)
	_beam("steel",at+Vector3(1.4,0,0.4),at+Vector3(0,0,1.8),0.06)
	_box("dark",at+Vector3(0,0,1.8),Vector3(0.25,0.25,0.4))

func _earth() -> void:
	var earth := MeshInstance3D.new()
	earth.name = "Earth"
	var sphere := SphereMesh.new()
	sphere.radius = 7.5
	sphere.height = 15
	sphere.radial_segments = 96
	sphere.rings = 48
	var material := ShaderMaterial.new()
	material.shader = preload("res://assets/materials/arena/moon_earth.gdshader")
	material.set_shader_parameter("earth_texture",preload("res://assets/textures/moon/earth_albedo.png"))
	sphere.material = material
	earth.mesh = sphere
	earth.position = Vector3(0,43,-88)
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)

func _lunar_lighting(arena: Node) -> void:
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://assets/materials/arena/moon_sky.gdshader")
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Keep shadowed ridges dark; local lamps, rather than broad fill, lead the eye.
	env.ambient_light_color = Color("9baecb")
	env.ambient_light_energy = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.7
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_sky_affect = 0.0
	(arena.get_node("WorldEnvironment") as WorldEnvironment).environment = env
	var sun := arena.get_node("Sun") as DirectionalLight3D
	sun.rotation_degrees = Vector3(-16,-65,0)
	sun.light_color = Color("c3d1e5")
	sun.light_energy = 0.55
	sun.light_cull_mask &= ~BACKDROP_LAYER
	sun.light_volumetric_fog_energy = .04
	sun.directional_shadow_max_distance = 140
	sun.shadow_enabled = true
	# A restrained backdrop key lets only ridge contours register. Separating
	# receivers preserves the existing floor, bot and service-bay illumination.
	var rim := DirectionalLight3D.new()
	rim.name = "CraterRimLight"
	rim.rotation = sun.rotation
	rim.light_color = sun.light_color
	rim.light_energy = 0.07
	rim.light_cull_mask = BACKDROP_LAYER
	rim.shadow_enabled = true
	rim.directional_shadow_max_distance = 140
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	rim.light_bake_mode = Light3D.BAKE_DISABLED
	rim.light_indirect_energy = 0.0
	rim.light_volumetric_fog_energy = 0.0
	add_child(rim)
