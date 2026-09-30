extends SceneTree
## Headless review renders of an assembled bot: a software rasteriser draws the
## garage preview's model (flat shaded, orthographic) to PNG files, so part
## placement and proportions can be checked without opening a window.
## Materials are reduced to one colour each; textures and lighting are not shown.
##
## godot --headless --path battlebots -s res://tools/render_bot_review.gd -- \
##     <out_dir> <body> <weapon> <utility> [drive] [modules=<side>,<top>,<front>,<rear>,<exhaust>] [view ...]
## body: sawblade, scorpion, atlas or box. view: "<yaw>,<pitch>[,<zoom>[,<x>,<y>,<z>]]"
## in degrees (yaw 0 looks at the front), zoom 1 fits the whole bot, x/y/z is
## the point looked at in the hull frame (source metres).
const WIDTH := 960
const HEIGHT := 720
const LIGHT := Vector3(-0.45, 0.8, 0.4)
const BACKGROUND := Color(0.07, 0.11, 0.15)
const DEFAULT_VIEWS := ["35,25", "90,8", "0,10", "0,89"]

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("usage: <out_dir> <body> <weapon> <utility> [drive] [view ...]")
		quit(2)
		return
	# Mounts are reviewed regardless of the power budget (pickups exceed it too).
	var registry := ContentRegistry.new()
	registry.enforce_budget = false
	var draft := _draft(registry, args[1])
	draft.parts.weapon = args[2]
	draft.parts.utility = args[3]
	var views: Array = []
	for index: int in range(4, args.size()):
		if args[index].begins_with("modules="):
			# armor_side, armor_top, armor_front, armor_rear, exhaust choices.
			var choices := args[index].trim_prefix("modules=").split(",")
			var keys := ["armor_side", "armor_top", "armor_front", "armor_rear", "exhaust"]
			for at: int in mini(choices.size(), keys.size()): draft.cosmetics.sawblade[keys[at]] = int(choices[at])
		elif "," in args[index]: views.append(args[index])
		else: draft.parts.drive = args[index]
	if views.is_empty(): views = DEFAULT_VIEWS
	var validation := registry.validate(draft)
	if not validation.valid:
		push_error("Invalid build: " + "; ".join(validation.reasons))
		quit(3)
		return
	var preview := GarageBotPreview.new()
	preview.size = Vector2(640, 480)
	preview._registry.enforce_budget = false
	get_root().add_child(preview)
	await process_frame
	preview.show_loadout(draft)
	await process_frame
	await process_frame
	var triangles := _triangles(preview.model)
	var label := "%s_%s_%s" % [args[1], args[2], args[3]]
	DirAccess.make_dir_recursive_absolute(args[0])
	for index: int in views.size():
		var path := "%s/%s_%d.png" % [args[0], label, index]
		_render(triangles, views[index]).save_png(path)
		print("REVIEW RENDER ", path)
	preview.queue_free()
	await process_frame
	quit()

func _draft(registry: ContentRegistry, body: String) -> Dictionary:
	match body:
		"scorpion": return registry.scorpion()
		"atlas": return registry.atlas()
		"box": return registry.starter()
	return SawbladeConfig.starter(registry)

## [{a, b, c, color}] in the model's frame.
func _triangles(model: Node3D) -> Array:
	var found: Array = []
	var inverse := model.global_transform.affine_inverse()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var to_model := inverse * mesh.global_transform
		for surface: int in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
			var points: PackedVector3Array = to_model * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var color := _color(mesh, surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.is_empty():
				for at: int in range(0, points.size() - 2, 3):
					found.append([points[at], points[at + 1], points[at + 2], color])
			else:
				for at: int in range(0, indices.size() - 2, 3):
					found.append([points[indices[at]], points[indices[at + 1]], points[indices[at + 2]], color])
	return found

func _color(mesh: MeshInstance3D, surface: int) -> Color:
	var material := mesh.get_active_material(surface)
	if material is ShaderMaterial:
		var paint: Variant = material.get_shader_parameter("paint")
		if paint is Color: return paint
	if material is StandardMaterial3D:
		var label := material.resource_name.to_lower()
		if material.albedo_texture == null: return material.albedo_color
		# Baked surfaces: a representative colour per material family.
		if "primary" in label or "orange" in label or "ceramic" in label: return Color(0.86, 0.5, 0.1)
		if "secondary" in label: return Color(0.2, 0.22, 0.24)
		if "track" in label or "rubber" in label: return Color(0.09, 0.09, 0.1)
		return Color(0.5, 0.52, 0.54)
	return Color(0.6, 0.6, 0.6)

func _render(triangles: Array, view: String) -> Image:
	var values := view.split_floats(",")
	var yaw := deg_to_rad(values[0])
	var pitch := deg_to_rad(values[1] if values.size() > 1 else 20.0)
	var zoom := values[2] if values.size() > 2 else 1.0
	# The camera looks from the front-right for positive yaw; -Z is the bot's front.
	var back := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var right := Vector3.UP.cross(back).normalized()
	if right.is_zero_approx(): right = Vector3.LEFT
	var up := back.cross(right).normalized()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for triangle: Array in triangles:
		for corner: int in 3:
			var at := Vector2((triangle[corner] as Vector3).dot(right), (triangle[corner] as Vector3).dot(up))
			low = low.min(at)
			high = high.max(at)
	var centre := (low + high) * 0.5
	if values.size() > 5:
		var focus := Vector3(values[3], values[4], values[5])
		centre = Vector2(focus.dot(right), focus.dot(up))
	var pixels := minf(WIDTH / maxf(high.x - low.x, 0.001), HEIGHT / maxf(high.y - low.y, 0.001)) * 0.94 * zoom
	var depth := PackedFloat32Array()
	depth.resize(WIDTH * HEIGHT)
	depth.fill(-INF)
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	image.fill(BACKGROUND)
	var light := LIGHT.normalized()
	for triangle: Array in triangles:
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var normal := (b - a).cross(c - a)
		if normal.is_zero_approx(): continue
		normal = normal.normalized()
		# Godot front faces wind clockwise; shade both sides so open parts read.
		var shade := 0.3 + 0.7 * absf(normal.dot(light)) * (1.0 if normal.dot(back) * normal.dot(light) <= 0.0 else 0.55)
		var color: Color = (triangle[3] as Color) * shade
		color.a = 1.0
		var ax := (a.dot(right) - centre.x) * pixels + WIDTH * 0.5
		var ay := HEIGHT * 0.5 - (a.dot(up) - centre.y) * pixels
		var bx := (b.dot(right) - centre.x) * pixels + WIDTH * 0.5
		var by := HEIGHT * 0.5 - (b.dot(up) - centre.y) * pixels
		var cx := (c.dot(right) - centre.x) * pixels + WIDTH * 0.5
		var cy := HEIGHT * 0.5 - (c.dot(up) - centre.y) * pixels
		var az := a.dot(back)
		var bz := b.dot(back)
		var cz := c.dot(back)
		var area := (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
		if absf(area) < 0.000001: continue
		var x0 := maxi(0, floori(minf(ax, minf(bx, cx))))
		var x1 := mini(WIDTH - 1, ceili(maxf(ax, maxf(bx, cx))))
		var y0 := maxi(0, floori(minf(ay, minf(by, cy))))
		var y1 := mini(HEIGHT - 1, ceili(maxf(ay, maxf(by, cy))))
		for y: int in range(y0, y1 + 1):
			var py := y + 0.5
			for x: int in range(x0, x1 + 1):
				var px := x + 0.5
				var w0 := ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
				var w1 := ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area
				var w2 := 1.0 - w0 - w1
				if w0 < 0.0 or w1 < 0.0 or w2 < 0.0: continue
				var z := w0 * az + w1 * bz + w2 * cz
				var at := y * WIDTH + x
				if z <= depth[at]: continue
				depth[at] = z
				image.set_pixel(x, y, color)
	return image
