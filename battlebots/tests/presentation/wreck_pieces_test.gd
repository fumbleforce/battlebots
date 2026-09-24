extends Node3D
## #72 generic wreck break-up: deterministic plans from the killing blow, mesh
## classification against the pieces, the cut material stand-ins, the
## destruction visual lifecycle and the client debris budget.
const PIECES := preload("res://scripts/presentation/wreck_pieces.gd")
const PIECE := preload("res://scripts/presentation/wreck_piece.gd")
const TUNING := preload("res://scripts/core/destruction_tuning.gd")
const EFFECT_PATH := "res://scripts/presentation/bot_destruction_visual.gd"
const BOUNDS := AABB(Vector3(-2.4, -0.8, -3.0), Vector3(4.8, 1.6, 6.0))
var failures: Array[String] = []

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func death(kind: String, point: Vector3, axis: Vector3, force := 1.0) -> Dictionary:
	return {"kind":kind, "point":point, "axis":axis.normalized(), "force":force}

func holds(region: Dictionary, point: Vector3) -> bool:
	for plane: Plane in region.planes:
		if plane.distance_to(point) > 0.0001: return false
	return true

func plans() -> void:
	var tuning: RefCounted = TUNING.settings()
	var saw := PIECES.plan(death("saw", Vector3(0.3, 0.2, -3.0), Vector3.RIGHT), BOUNDS, 4, 1.0, tuning)
	check(saw.regions.size() == 2 and saw.tunnel.is_empty(), "A saw kill makes two halves: %d" % saw.regions.size())
	if saw.regions.size() == 2:
		var cut: Plane = saw.regions[0].planes[0]
		check(absf(cut.normal.dot(Vector3.RIGHT)) > 0.999, "The saw halves along its blade plane")
		check(saw.regions[1].planes[0].normal.is_equal_approx(-cut.normal) and is_equal_approx(saw.regions[1].planes[0].d, -cut.d), "The halves share one seam")
		check(saw.regions[0].velocity.dot(saw.regions[1].velocity) < 0.0, "The halves fall apart in opposite directions")
		check(absf(cut.d) <= BOUNDS.size.x * 0.5 * PIECES.SPLIT_REACH + 0.001, "A glancing saw still cuts near the middle")
	var blast := PIECES.plan(death("mortar", Vector3(0, -0.8, 1.0), Vector3.UP, 3.0), BOUNDS, 4, 1.0, tuning)
	check(blast.regions.size() == 5, "A mortar kill shatters into five shards: %d" % blast.regions.size())
	# Every interior grid point belongs to exactly one shard.
	var overlaps := 0
	var orphans := 0
	for x: int in 7:
		for y: int in 5:
			for z: int in 7:
				var sample := BOUNDS.position + BOUNDS.size * Vector3(x + 0.37, y + 0.41, z + 0.29) / Vector3(7, 5, 7)
				var owners: int = blast.regions.filter(func(region: Dictionary) -> bool: return holds(region, sample)).size()
				if owners > 1: overlaps += 1
				if owners == 0: orphans += 1
	check(overlaps == 0 and orphans == 0, "Shards partition the wreck without gaps or overlaps: %d/%d" % [overlaps, orphans])
	var outward := 0
	for region: Dictionary in blast.regions:
		if region.velocity.y > 0.0: outward += 1
	check(outward == blast.regions.size(), "A blast from below throws every shard upward")
	var again := PIECES.plan(death("mortar", Vector3(0, -0.8, 1.0), Vector3.UP, 3.0), BOUNDS, 4, 1.0, tuning)
	var same: bool = again.regions.size() == blast.regions.size()
	for index: int in mini(again.regions.size(), blast.regions.size()):
		same = same and again.regions[index].centroid.is_equal_approx(blast.regions[index].centroid)
	check(same, "Every client breaks the same death the same way")
	var other := PIECES.plan(death("mortar", Vector3(0, -0.8, 1.0), Vector3.UP, 3.0), BOUNDS, 9, 1.0, tuning)
	check(not other.regions[1].centroid.is_equal_approx(blast.regions[1].centroid), "Different bots shatter differently")
	var rail := PIECES.plan(death("railgun", Vector3(0, 0, 3.0), Vector3.FORWARD, 1.0), BOUNDS, 4, 1.0, tuning)
	check(rail.regions.size() == 1 and rail.tunnel.size() == 4, "A plain railgun kill bores a tunnel through an intact wreck")
	if rail.tunnel.size() == 4:
		check(PIECES._segment_distance(Vector3(0, 0, 0), rail.tunnel[0], rail.tunnel[1]) < 0.01, "The bore runs straight through along the shot")
	var overkill := PIECES.plan(death("railgun", Vector3(0, 0, 3.0), Vector3.FORWARD, 5.0), BOUNDS, 4, 1.0, tuning)
	check(overkill.regions.size() == 2 and overkill.tunnel.size() == 4, "A heavily overkilled railgun wreck also splits along the bore")
	if overkill.regions.size() == 2:
		check(absf(overkill.regions[0].planes[0].normal.dot(Vector3.FORWARD)) < 0.01, "The railgun split contains the shot line")
	var scaled := PIECES.plan(death("saw", Vector3.ZERO, Vector3.RIGHT), BOUNDS, 4, 3.0, tuning)
	check(scaled.regions[0].velocity.length() > saw.regions[0].velocity.length() * 2.5, "Separation speed follows the bot's geometry scale")

func materials() -> void:
	var standard := StandardMaterial3D.new()
	standard.albedo_color = Color(0.8, 0.2, 0.1)
	standard.metallic = 0.6
	var converted := PIECES.material_for(standard)
	check(converted != null and converted.shader == PIECES.SURFACE, "Standard surfaces get the cut stand-in")
	if converted != null:
		check(converted.get_shader_parameter("albedo_tint") == Color(0.8, 0.2, 0.1) and is_equal_approx(converted.get_shader_parameter("metallic_factor"), 0.6),
			"The stand-in mirrors the source parameters")
	check(PIECES.material_for(standard) == converted, "Stand-ins are shared between pieces")
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	check(PIECES.material_for(glass) == null, "Transparent surfaces are not cut")
	var atlas := ShaderMaterial.new()
	atlas.shader = PIECES.ATLAS_PAINT
	atlas.set_shader_parameter("paint", Color(0.1, 0.9, 0.3))
	var painted := PIECES.material_for(atlas)
	check(painted != null and painted.get_shader_parameter("paint") == Color(0.1, 0.9, 0.3), "Atlas paint keeps its colours when cut")
	var saw_paint := ShaderMaterial.new()
	saw_paint.shader = PIECES.SAWBLADE_PAINT
	var sawn := PIECES.material_for(saw_paint)
	check(sawn != null and sawn.get_shader_parameter("source_mode") == 1, "Sawblade paint is cut in its atlas mode")
	var unknown := ShaderMaterial.new()
	unknown.shader = Shader.new()
	check(PIECES.material_for(unknown) == null, "Unknown shaders are not guessed at")

## Three boxes: left of the saw seam, right of it and straddling it.
func fixture() -> Dictionary:
	var visual := Node3D.new()
	visual.position = Vector3(10, 2, -4)
	visual.rotation.y = 0.7
	add_child(visual)
	var body := Node3D.new()
	body.scale = Vector3.ONE * 3.0
	visual.add_child(body)
	var meshes := {}
	for label: String in ["left", "right", "middle", "odd"]:
		var mesh := MeshInstance3D.new()
		mesh.name = label
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.3, 1.6) if label != "middle" else Vector3(1.4, 0.3, 1.6)
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.3, 0.4, 0.5)
		mesh.set_surface_override_material(0, material)
		body.add_child(mesh)
		meshes[label] = mesh
	meshes.left.position.x = -0.6
	meshes.right.position.x = 0.6
	meshes.odd.position = Vector3(0.1, 0.4, 0.0)
	var odd := ShaderMaterial.new()
	odd.shader = Shader.new()
	meshes.odd.set_surface_override_material(0, odd)
	return {"visual":visual, "meshes":meshes}

func copies(bodies: Array[RigidBody3D], source: MeshInstance3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for body: RigidBody3D in bodies:
		for child: Node in body.get_children():
			if child is MeshInstance3D and child.mesh == source.mesh:
				found.append(child)
	return found

func build() -> void:
	var setup := fixture()
	var visual: Node3D = setup.visual
	var frame := visual.global_transform
	var captured := PIECES.capture(visual, frame)
	check(captured.size() == 4, "Every visible mesh is captured: %d" % captured.size())
	var bounds := PIECES.bounds_of(captured)
	var layout := PIECES.plan(death("saw", Vector3(0.0, 0.0, -2.4), Vector3.RIGHT), bounds, 3, 1.0)
	var soot := StandardMaterial3D.new()
	var bodies := PIECES.build(captured, frame, layout, soot)
	check(bodies.size() == 2, "The saw wreck becomes two physics pieces")
	var left := copies(bodies, setup.meshes.left)
	var right := copies(bodies, setup.meshes.right)
	var middle := copies(bodies, setup.meshes.middle)
	var odd := copies(bodies, setup.meshes.odd)
	check(left.size() == 1 and right.size() == 1, "Meshes wholly on one side of the seam go to one piece")
	check(left.size() == 1 and left[0].material_overlay == soot and not left[0].get_surface_override_material(0) is ShaderMaterial,
		"Whole meshes keep their own material under the wreck soot")
	check(middle.size() == 2, "A mesh across the seam is in both halves")
	if middle.size() == 2:
		var first: Vector4 = middle[0].get_instance_shader_parameter("cut_plane_0")
		var second: Vector4 = middle[1].get_instance_shader_parameter("cut_plane_0")
		check(middle[0].get_surface_override_material(0) is ShaderMaterial and middle[0].material_overlay == null,
			"Cut meshes use the cut stand-in, never an overlay that would draw the cut-away part")
		check(Vector3(first.x, first.y, first.z).is_equal_approx(-Vector3(second.x, second.y, second.z)) and is_equal_approx(first.w, -second.w),
			"Both halves cut the mesh along the same seam")
		# The seam normal in the mesh's own space: the blade axle, unscaled.
		check(absf(Vector3(first.x, first.y, first.z).dot(Vector3.RIGHT)) > 0.999, "Cut planes are moved into each mesh's object space")
		var state: Vector4 = middle[0].get_instance_shader_parameter("cut_state")
		check(state.x > 0.0 and state.w > 0.0, "Fresh saw seams glow and the wreck is sooted")
	check(odd.size() == 1, "A surface the cut cannot stand in for goes whole to exactly one piece")
	for body: RigidBody3D in bodies:
		check(body.collision_layer == 0 and body.collision_mask == BaselineConfig.WORLD_LAYER, "Pieces collide with the world only")
		check(body.get_children().any(func(child: Node) -> bool: return child is CollisionShape3D and child.shape is ConvexPolygonShape3D),
			"Each piece gets a hull clipped to its own region")
		body.free()
	visual.queue_free()

func view(destroyed: bool, dead: Dictionary = {}) -> BotView:
	var result := BotView.new()
	result.entity_id = 12
	result.pose = Transform3D(Basis(Vector3.UP, 0.7), Vector3(10, 2, -4))
	result.eliminated = destroyed
	result.core_fraction = 0.0 if destroyed else 1.0
	result.death = dead
	return result

func lifecycle() -> void:
	var setup := fixture()
	var visual: Node3D = setup.visual
	var effect: Node3D = load(EFFECT_PATH).new()
	add_child(effect)
	effect.configure(visual, Vector3(1.6, 0.5, 2.0) * 3.0)
	var dead := death("saw", Vector3(0, 0, -2.4), Vector3.RIGHT)
	effect.observe(view(false))
	effect.observe(view(true, dead))
	var pieces: Array[Node] = effect.broken_pieces()
	check(pieces.size() == 2 and effect.active, "A witnessed saw kill halves the bot and still plays the burst")
	check(not setup.meshes.middle.visible and not setup.meshes.left.visible, "The intact bot is replaced by its pieces")
	check(pieces.size() == 2 and pieces[0].linear_velocity.length() > 0.1, "Witnessed pieces fly apart")
	effect.reset_observation()
	await get_tree().process_frame
	check(effect.broken_pieces().is_empty() and setup.meshes.middle.visible, "A new round restores the whole bot")
	# Reconnect: the first baseline is already a wreck. It breaks silently, at rest.
	effect.observe(view(true, dead))
	pieces = effect.broken_pieces()
	check(pieces.size() == 2 and not effect.active, "A wreck seen first on reconnect breaks without replaying the burst")
	check(pieces.size() == 2 and pieces[0].linear_velocity.is_zero_approx(), "Reconnect pieces start at rest")
	effect.reset_observation()
	# A knockout without a combat death (immobilized, forfeit) keeps the intact wreck.
	effect.observe(view(false))
	effect.observe(view(true))
	check(effect.broken_pieces().is_empty() and setup.meshes.middle.visible, "Non-combat knockouts do not break the bot")
	effect.queue_free()
	visual.queue_free()
	await get_tree().process_frame

func budget() -> void:
	var root := Node3D.new()
	add_child(root)
	var made: Array[RigidBody3D] = []
	for index: int in 5:
		var piece: RigidBody3D = PIECE.new()
		var shape := CollisionShape3D.new()
		var hull := ConvexPolygonShape3D.new()
		hull.points = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK])
		shape.shape = hull
		piece.add_child(shape)
		root.add_child(piece)
		made.append(piece)
	PIECE.enforce_budget(get_tree(), 3, 0.2)
	check(made[0].sinking and made[1].sinking and not made[2].sinking and not made[4].sinking, "The budget sinks the oldest pieces first")
	check(made[0].collision_mask == 0 and made[0].freeze, "Sinking pieces leave the world")
	for frame: int in 30:
		await get_tree().process_frame
	check(not is_instance_valid(made[0]) and is_instance_valid(made[2]), "Sunk pieces free themselves")
	root.queue_free()

func config() -> void:
	var problems: Array[String] = []
	check(TUNING.from_json("{}", problems) == null and not problems.is_empty(), "Missing destruction tuning is rejected")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TUNING.PATH))
	data.styles.saw.pieces = 9
	problems.clear()
	check(TUNING.from_json(JSON.stringify(data), problems) == null, "Piece counts beyond the shader's four planes are rejected")
	data = JSON.parse_string(FileAccess.get_file_as_string(TUNING.PATH))
	data.kinds.saw = "nonsense"
	problems.clear()
	check(TUNING.from_json(JSON.stringify(data), problems) == null, "Kinds must name a known style")
	check(TUNING.settings().style_name("never_heard_of_it") == TUNING.settings().default_style, "Unknown kinds use the default style")

func run() -> void:
	config()
	plans()
	materials()
	build()
	await lifecycle()
	await budget()
	for failure: String in failures:
		push_error(failure)
	print("WRECK PIECES PASS" if failures.is_empty() else "WRECK PIECES FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
