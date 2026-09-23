extends SceneTree
## Bakes Woodland's deterministic load-time data; commit the outputs.
## godot --headless --path battlebots --script res://tools/bake_woodland_cache.gd
## - terrain_heights.res: the authoritative height grid (verified in tests).
## - scatter_cache.res: grass, debris, pebble, fern and rock placements.
## Re-run after changing woodland_ground.gd terrain, the masks or scatter rules.
const GROUND = preload("res://scripts/arena/woodland_ground.gd")
const FLORA = preload("res://scripts/arena/woodland_flora.gd")

func _initialize() -> void:
	var t := Time.get_ticks_msec()
	var heights := GROUND.grid_heights(false)
	var height_res := Resource.new()
	height_res.set_meta(&"heights", heights)
	var ok := ResourceSaver.save(height_res, GROUND.HEIGHT_CACHE, ResourceSaver.FLAG_COMPRESS) == OK
	print("BAKE heights ", heights.size(), " in ", Time.get_ticks_msec() - t, " ms ", ok)
	t = Time.get_ticks_msec()
	var flora = FLORA.new()
	flora._heights = heights
	var counts := {"grass":8, "fern":flora._variants("scatter_fern").size(), "pebble":flora._variants("scatter_pebbles").size(),
		"rock":flora._variants("scatter_rocks").size()}
	var poses: Dictionary = flora.compute_scatter(counts)
	var scatter_res := Resource.new()
	scatter_res.set_meta(&"scatter", FLORA.pack_scatter(poses))
	scatter_res.set_meta(&"counts", counts)
	ok = ResourceSaver.save(scatter_res, FLORA.SCATTER_CACHE, ResourceSaver.FLAG_COMPRESS) == OK
	var sizes := {}
	for key: String in poses: sizes[key] = poses[key].size()
	print("BAKE scatter ", sizes, " in ", Time.get_ticks_msec() - t, " ms ", ok)
	flora.free()
	quit()
