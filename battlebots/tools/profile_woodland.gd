extends SceneTree
## GPU cost attribution for the Woodland arena: disables one feature at a time
## on fixed views and reports GPU ms. Native renderer only.
## godot --path battlebots --script res://tools/profile_woodland.gd -- [--size=2560x1440]
func _initialize() -> void:
	call_deferred("_run")

func _gpu(frames := 45) -> float:
	var vp := root.get_viewport_rid()
	var samples: Array[float] = []
	for i in frames:
		await process_frame
		await RenderingServer.frame_post_draw
		if i > 10: samples.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	# Minimum is far less sensitive to other GPU work than the median.
	samples.sort()
	return samples[0]

## Paired measurement: feature on, off, on again. Returns ms saved when off.
func _saves(off: Callable, on: Callable) -> float:
	var before := await _gpu(25)
	off.call()
	var without := await _gpu(25)
	on.call()
	var after := await _gpu(25)
	return (before + after) * 0.5 - without

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(2560, 1440)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--size="):
			var parts := arg.substr(7).split("x")
			root.size = Vector2i(int(parts[0]), int(parts[1]))
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var world := AuthorityWorld.new()
	world.arena_id = "woodland"
	root.add_child(world)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 68
	cam.far = 12000
	for i in 30: await process_frame
	var art := world.arena.get_node("FoundryVisuals/EnvironmentArt")
	var env: Environment = (world.arena.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun: DirectionalLight3D = world.arena.get_node("Sun")
	var views := {"chase":[Vector3(-62, 6.0, 72), Vector3(-45, 1.0, 30)], "glare":[Vector3(12, 5.0, 84), Vector3(-14, 0.0, 58)],
		"mesa":[Vector3(40, 14.0, 42), Vector3(0, 3.0, 0)]}
	var groups := {}
	var nodes: Array = art.get_children()
	nodes.append_array(art.get_node("Flora").get_children())
	for n in nodes:
		if not n is Node3D or n.name == "Flora": continue
		var key := String(n.name).split("_")[0].rstrip("0123456789")
		if not groups.has(key): groups[key] = []
		groups[key].append(n)
	for view: String in views:
		cam.position = views[view][0]
		cam.look_at(views[view][1])
		for i in 60: await process_frame
		var base := await _gpu()
		print("VIEW ", view, " base gpu ", snappedf(base, 0.01))
		var rows := []
		for prop in ["ssil_enabled", "ssao_enabled", "ssr_enabled", "volumetric_fog_enabled", "glow_enabled", "fog_enabled"]:
			var was = env.get(prop)
			rows.append([await _saves(func(): env.set(prop, false), func(): env.set(prop, was)), "env " + prop])
		rows.append([await _saves(func(): sun.shadow_enabled = false, func(): sun.shadow_enabled = true), "sun shadows"])
		var angular := sun.light_angular_distance
		rows.append([await _saves(func(): sun.light_angular_distance = 0.0, func(): sun.light_angular_distance = angular), "sun angular size 0 (no PCSS)"])
		var splits := sun.directional_shadow_mode
		rows.append([await _saves(func(): sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, func(): sun.directional_shadow_mode = splits), "2 shadow splits"])
		var reach := sun.directional_shadow_max_distance
		rows.append([await _saves(func(): sun.directional_shadow_max_distance = reach * 0.6, func(): sun.directional_shadow_max_distance = reach), "shadow distance x0.6"])
		for key in groups:
			var casters: Array = []
			for n in groups[key]:
				for g in [n] + n.find_children("*", "GeometryInstance3D", true, false):
					if g is GeometryInstance3D and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						casters.append([g, g.cast_shadow])
						g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for c in casters: c[0].cast_shadow = c[1]
			if casters.is_empty(): continue
			var cast_off := func(): for c in casters: c[0].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var cast_on := func(): for c in casters: c[0].cast_shadow = c[1]
			rows.append([await _saves(cast_off, cast_on), "no shadows from " + key])
		for key in groups:
			var list: Array = groups[key]
			rows.append([await _saves(func(): for n in list: n.visible = false, func(): for n in list: n.visible = true), "hide " + key])
		rows.sort()
		rows.reverse()
		for r in rows.slice(0, 12): print("   saves ", snappedf(r[0], 0.01), " ms  ", r[1])
	quit()
