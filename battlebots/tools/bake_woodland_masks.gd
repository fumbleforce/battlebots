extends SceneTree
## Bakes the Woodland ground masks once; commit the output.
## godot --headless --path battlebots --script res://tools/bake_woodland_masks.gd
## Writes assets/textures/woodland/ground_masks.png covering the 240 m octagon:
## R tank-rut groove, G grass density, B wetness, A scorch. The dirt shader and
## the scatter placement both read it, so grass, pebbles and puddles agree with
## the tracks. Presentation only: collision never reads it.
const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const SIZE := 1024
const HALF := GROUND.HALF
const PX := HALF * 2.0 / SIZE
const GAUGE := 4.6 # Centre-to-centre distance between a tank's two tracks.
const TRACK := 1.25 # Width of one track groove.
var ruts := PackedFloat32Array()

func _initialize() -> void:
	ruts.resize(SIZE * SIZE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var paths: Array[PackedVector2Array] = []
	# Laps around the mesa foot at several radii.
	for lap: int in range(3):
		var r := GROUND.MESA_RADIUS + 12.0 + lap * 11.0
		var path := PackedVector2Array()
		var phase := rng.randf() * TAU
		for k: int in range(97):
			var a := TAU * k / 96.0
			var wob := sin(a * 3.0 + phase) * 3.0 + sin(a * 7.0 + phase * 2.0) * 1.2
			path.append(Vector2(cos(a), sin(a)) * (r + wob) * Vector2(1.0 + lap * 0.04, 1.0 - lap * 0.03))
		paths.append(path)
	# Lanes from every team spawn toward the fight, swerving, both teams mirrored.
	for spawn: Vector2 in GROUND.spawn_points():
		for lane: int in range(1):
			var path := PackedVector2Array()
			var p := spawn
			var heading := (-spawn).normalized().rotated(rng.randf_range(-0.6, 0.6))
			for step: int in range(70):
				path.append(p)
				heading = heading.rotated(rng.randf_range(-0.12, 0.12) + sin(step * 0.2 + lane) * 0.05)
				# Steer back inside and around the mesa.
				if p.length() < GROUND.MESA_RADIUS + 10.0:
					heading = heading.lerp(p.normalized().orthogonal(), 0.25).normalized()
				if GROUND.octagon_distance(p) < 12.0:
					heading = heading.lerp(-p.normalized(), 0.3).normalized()
				p += heading * 2.0
			paths.append(path)
	# Figure-of-eight skid patterns across the open ground.
	for n: int in range(4):
		var c := Vector2(rng.randf_range(-80, 80), rng.randf_range(-80, 80))
		if c.length() < GROUND.MESA_RADIUS + 16.0:
			continue
		var path := PackedVector2Array()
		var size := rng.randf_range(10.0, 18.0)
		var rot := rng.randf() * TAU
		for k: int in range(81):
			var t := TAU * k / 80.0
			path.append(c + Vector2(sin(t) * size, sin(t) * cos(t) * size * 0.7).rotated(rot))
		paths.append(path)
	for path: PackedVector2Array in paths:
		for side: float in [-0.5, 0.5]:
			_stamp(path, side * GAUGE)
	var patches := FastNoiseLite.new()
	patches.seed = 77
	patches.frequency = 0.035
	patches.fractal_octaves = 4
	var wet_noise := FastNoiseLite.new()
	wet_noise.seed = 78
	wet_noise.frequency = 0.02
	wet_noise.fractal_octaves = 3
	var scorch_cells := FastNoiseLite.new()
	scorch_cells.seed = 79
	scorch_cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	scorch_cells.frequency = 0.04
	scorch_cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y: int in range(SIZE):
		for x: int in range(SIZE):
			var p := Vector2(-HALF + (x + 0.5) * PX, -HALF + (y + 0.5) * PX)
			var h := GROUND.height_at(p.x, p.y)
			# Tracks fade out on slopes: tanks skid there, they do not cut grooves.
			var slope := Vector2(GROUND.height_at(p.x + 1.0, p.y) - GROUND.height_at(p.x - 1.0, p.y),
				GROUND.height_at(p.x, p.y + 1.0) - GROUND.height_at(p.x, p.y - 1.0)).length() * 0.5
			var rut := ruts[y * SIZE + x] * (1.0 - smoothstep(0.08, 0.2, slope))
			var edge := GROUND.octagon_distance(p)
			var grass := 1.0 - smoothstep(2.0, 10.0, edge)
			for outcrop: Dictionary in GROUND.OUTCROPS:
				var size: float = outcrop.size
				var centre: Vector2 = outcrop.at
				for sign: float in [1.0, -1.0]:
					grass = maxf(grass, 1.0 - smoothstep(size * 3.2, size * 7.0, p.distance_to(centre * sign)))
			grass = maxf(grass, smoothstep(1.0, 2.2, h) * 0.9)
			grass = maxf(grass, smoothstep(0.1, 0.5, patches.get_noise_2dv(p)) * 0.8)
			grass *= smoothstep(-0.35, 0.1, patches.get_noise_2dv(p * 1.7 + Vector2(40, 0)))
			grass *= 1.0 - smoothstep(0.05, 0.4, rut)
			var wet := smoothstep(0.2, 0.55, wet_noise.get_noise_2dv(p)) * (1.0 - smoothstep(0.8, 2.0, h))
			wet = maxf(wet, rut * smoothstep(0.0, 0.4, wet_noise.get_noise_2dv(p * 2.0 + Vector2(9, 9))))
			# Cell distance runs about -0.88 (centre) to -0.2; scorches mark cell centres.
			var scorch := 1.0 - smoothstep(-0.86, -0.72, scorch_cells.get_noise_2dv(p))
			scorch *= smoothstep(-0.1, 0.25, patches.get_noise_2dv(p * 0.5 + Vector2(-70, 30)))
			image.set_pixel(x, y, Color(rut, clampf(grass, 0.0, 1.0), clampf(wet, 0.0, 1.0), clampf(scorch, 0.0, 1.0)))
	var path := "res://assets/textures/woodland/ground_masks.png"
	var error := image.save_png(path)
	print("MASKS ", path, " ", error == OK)
	quit(0 if error == OK else 1)

## Raster one track: a rounded groove profile with slightly raised lips.
func _stamp(path: PackedVector2Array, offset: float) -> void:
	for i: int in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var normal := (b - a).normalized().orthogonal()
		a += normal * offset
		b += normal * offset
		if i + 2 < path.size():
			var nn := (path[i + 2] - path[i + 1]).normalized().orthogonal()
			b = path[i + 1] + (normal + nn).normalized() * offset
		var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * TRACK
		var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * TRACK
		for y: int in range(clampi(int((low.y + HALF) / PX), 0, SIZE - 1), clampi(int((high.y + HALF) / PX) + 1, 0, SIZE)):
			for x: int in range(clampi(int((low.x + HALF) / PX), 0, SIZE - 1), clampi(int((high.x + HALF) / PX) + 1, 0, SIZE)):
				var p := Vector2(-HALF + (x + 0.5) * PX, -HALF + (y + 0.5) * PX)
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var groove := 1.0 - smoothstep(TRACK * 0.1, TRACK * 0.85, d)
				var i2 := y * SIZE + x
				ruts[i2] = maxf(ruts[i2], groove)
