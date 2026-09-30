extends SceneTree
## Measures how far each turret attachment may depress on the bodies that carry
## it on a data/weapon_mounts.json race (#108), and writes the result into that
## file's "depression" tables (docs/art/WEAPON_FEEL.md: audit clearance, then
## turn the result into rules). The Atlas MX keeps its own audit
## (tools/build-atlas-turret.py, AtlasGeometry.TURRET_DEPRESSION).
##
## For every body, turret model and bearing (5 degree steps, verified at the
## half steps the runtime rule interpolates over) the elevating group is swept
## down from its upper stop; the lowest elevation at which none of its surface
## comes within MARGIN of the body's hull is recorded. The hull is the body's
## own visual with every armour and exhaust option fitted and without the
## primary weapon (as on the Atlas, weapons are not part of the clearance).
##
## godot --headless --path battlebots -s res://tools/audit_turret_clearance.gd [-- --check]
## --check reports differences from the stored tables without writing.
const WEAPON_MOUNTS = preload("res://scripts/core/weapon_mounts.gd")
const TURRET_MODULE = preload("res://scripts/presentation/turret_module_visual.gd")
const TURRET := "res://assets/models/atlas_runtime/atlas_turret.glb"
## Clearance kept between barrel and hull, and the hull sampling grid (hull source metres).
const MARGIN := 0.02
## Spacing of the elevating group's sample points (turret source metres).
const BARREL_SPACING := 0.04
## Lowest depression the servo is ever allowed (matches the Atlas audit).
const LOWEST := -20
const MODELS := ["cannon", "plasma", "cannon_dual", "cannon_quad", "plasma_dual", "plasma_quad",
	"flamer", "tesla", "railgun", "harpoon", "mortar"]
## Every armour and exhaust option at its largest.
const FULL_MODULES := {"armor_side": 2, "armor_top": 1, "armor_front": 1, "armor_rear": 1, "exhaust": 3}

func _initialize() -> void:
	await process_frame
	var registry := ContentRegistry.new()
	var check := "--check" in OS.get_cmdline_user_args()
	var barrels := {}
	for model: String in MODELS:
		barrels[model] = await _barrel_points(model)
	var tables := {}
	var changed := false
	for body: String in WEAPON_MOUNTS.BODIES:
		var draft := _draft(registry, body)
		var size: Vector3 = registry.validate(draft).stats.size / BotScale.FACTOR
		var frame := WEAPON_MOUNTS.turret(draft, size)
		# Nothing below the deepest a barrel can reach matters.
		var reach := 0.0
		for model: String in MODELS:
			for point: Vector3 in barrels[model]: reach = maxf(reach, point.length())
		var floor_y := (frame * AtlasGeometry.TURRET_PITCH_PIVOT).y - reach * WEAPON_MOUNTS.scale_of(frame) - MARGIN * 2.0
		var hull_points := await _hull_points(draft, body, size, floor_y)
		tables[body] = {}
		for model: String in MODELS:
			var table := _audit(hull_points, barrels[model], frame, model)
			tables[body][model] = table
			var stored: Array = WEAPON_MOUNTS.data().depression.get(body, {}).get(model, [])
			var same := stored.size() == table.size()
			for index: int in (table.size() if same else 0):
				same = same and int(stored[index]) == int(table[index])
			changed = changed or not same
			print("%s %s: nose %d, flanks %d/%d, rear %d%s" % [body, model, table[0], table[18], table[54], table[36], "" if same else "  (differs from the stored table)"])
	if check:
		print("TURRET CLEARANCE AUDIT %s" % ("DIFFERS" if changed else "MATCHES"))
		quit(1 if changed else 0)
		return
	_write(tables)
	print("TURRET CLEARANCE AUDIT WRITTEN")
	quit()

func _draft(registry: ContentRegistry, body: String) -> Dictionary:
	var draft := registry.starter()
	match body:
		"scorpion":
			draft = registry.scorpion()
		"sawblade":
			draft = SawbladeConfig.starter(registry)
			for key: String in FULL_MODULES: draft.cosmetics.sawblade[key] = FULL_MODULES[key]
	# A lifter is valid on every body; the weapon itself is not audited.
	draft.parts.weapon = "lifter"
	draft.parts.utility = "turret_cannon"
	return draft

## Surface sample cells of the hull within a turret's reach, as a set of grid
## cells (MARGIN wide, dilated by one cell) in the hull's source frame.
func _hull_points(draft: Dictionary, body: String, size: Vector3, floor_y: float) -> Dictionary:
	var root := Node3D.new()
	get_root().add_child(root)
	var skip: Array[Node] = []
	match body:
		"sawblade":
			var visual := SawbladeVisual.new()
			root.add_child(visual)
			visual.assemble(draft, size)
			visual.clear_turret_race()
			for key: String in visual.nodes:
				if key.begins_with("Module_weapon_"): skip.append(visual.nodes[key])
			if visual.fallback_weapon != null: skip.append(visual.fallback_weapon)
		"scorpion":
			var visual := ScorpionVisual.new()
			root.add_child(visual)
			visual.assemble(draft, size)
			visual.walker_legs.terrain = false
			visual.walker_legs.reset_feet()
			skip.append(visual.nodes.TailBase)
			skip.append(visual.nodes.GunMount)
			if visual.fallback_weapon != null: skip.append(visual.fallback_weapon)
		_:
			var box := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = size
			box.mesh = mesh
			root.add_child(box)
	await process_frame
	var cells := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var skipped := false
		for other: Node in skip:
			skipped = skipped or other == mesh or other.is_ancestor_of(mesh)
		if skipped: continue
		for point: Vector3 in _surface_points(mesh, mesh.global_transform, MARGIN, floor_y):
			var cell := Vector3i((point / MARGIN).floor())
			for x: int in [-1, 0, 1]:
				for y: int in [-1, 0, 1]:
					for z: int in [-1, 0, 1]:
						cells[cell + Vector3i(x, y, z)] = true
	root.free()
	return cells

## Sample points of the model's elevating group, relative to the trunnion.
func _barrel_points(model: String) -> PackedVector3Array:
	var module := TURRET_MODULE.new()
	get_root().add_child(module)
	module.assemble(TURRET, AtlasGeometry.family(model), model, 1.0)
	module.effects.set_process(false)
	await process_frame
	var inverse := module.pitch_node.global_transform.affine_inverse()
	var seen := {}
	var points := PackedVector3Array()
	for node: Node in module.pitch_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		for point: Vector3 in _surface_points(mesh, inverse * mesh.global_transform, BARREL_SPACING, -INF):
			var cell := Vector3i((point / BARREL_SPACING).floor())
			if not seen.has(cell):
				seen[cell] = true
				points.append(point)
	module.free()
	return points

## Vertices plus points spread over every triangle at most `spacing` apart;
## triangles wholly below floor_y are left out.
func _surface_points(mesh: MeshInstance3D, to_frame: Transform3D, spacing: float, floor_y: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for surface: int in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
		var vertices: PackedVector3Array = to_frame * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = vertices.size() if indices == null or indices.is_empty() else indices.size()
		for at: int in range(0, count - 2, 3):
			var a := vertices[at if indices == null or indices.is_empty() else indices[at]]
			var b := vertices[at + 1 if indices == null or indices.is_empty() else indices[at + 1]]
			var c := vertices[at + 2 if indices == null or indices.is_empty() else indices[at + 2]]
			if maxf(a.y, maxf(b.y, c.y)) < floor_y: continue
			var steps := maxi(1, ceili(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / spacing))
			for i: int in steps + 1:
				for j: int in steps + 1 - i:
					points.append(a + (b - a) * (float(i) / steps) + (c - a) * (float(j) / steps))
	return points

## Depression table (whole degrees) for one model on one body.
func _audit(hull: Dictionary, barrel: PackedVector3Array, frame: Transform3D, model: String) -> Array:
	var highest := floori(rad_to_deg(AtlasGeometry.turret_pitch_max(model)))
	var table: Array = []
	for index: int in WEAPON_MOUNTS.DEPRESSION_SAMPLES:
		table.append(_floor_at(hull, barrel, frame, deg_to_rad(index * AtlasGeometry.TURRET_DEPRESSION_STEP), highest))
	# The runtime takes the stricter of the two samples around a bearing: make
	# that hold at the half steps too.
	for index: int in table.size():
		var between := _floor_at(hull, barrel, frame, deg_to_rad((index + 0.5) * AtlasGeometry.TURRET_DEPRESSION_STEP), highest)
		var next := (index + 1) % table.size()
		if between > maxi(table[index], table[next]):
			table[index] = between
	return table

## Lowest whole-degree elevation that is clear at this bearing, scanning down
## from the upper stop (everything above it is clear too).
func _floor_at(hull: Dictionary, barrel: PackedVector3Array, frame: Transform3D, yaw: float, highest: int) -> int:
	var lowest := highest
	for pitch: int in range(highest, LOWEST - 1, -1):
		if _collides(hull, barrel, frame, yaw, deg_to_rad(pitch)): break
		lowest = pitch
	return lowest

func _collides(hull: Dictionary, barrel: PackedVector3Array, frame: Transform3D, yaw: float, pitch: float) -> bool:
	var turn := Basis(Vector3.UP, yaw)
	var trunnion := AtlasGeometry.TURRET_YAW_PIVOT + turn * (AtlasGeometry.TURRET_PITCH_PIVOT - AtlasGeometry.TURRET_YAW_PIVOT)
	var pose := frame * Transform3D(turn * Basis(Vector3.RIGHT, pitch), trunnion)
	for point: Vector3 in barrel:
		if hull.has(Vector3i((pose * point / MARGIN).floor())): return true
	return false

## Replaces the generated "depression" object at the end of the data file,
## leaving the hand-written mounts above it untouched.
func _write(tables: Dictionary) -> void:
	var source := FileAccess.get_file_as_string(WEAPON_MOUNTS.PATH)
	var at := source.find("\t\"depression\":")
	assert(at >= 0, "weapon_mounts.json lacks its depression object")
	var text := source.substr(0, at) + "\t\"depression\": {\n"
	var bodies: Array = tables.keys()
	for b: int in bodies.size():
		text += "\t\t\"%s\": {\n" % bodies[b]
		var models: Array = tables[bodies[b]].keys()
		for m: int in models.size():
			text += "\t\t\t\"%s\": %s%s\n" % [models[m], JSON.stringify(tables[bodies[b]][models[m]]), "," if m < models.size() - 1 else ""]
		text += "\t\t}%s\n" % ("," if b < bodies.size() - 1 else "")
	text += "\t}\n}\n"
	var file := FileAccess.open(WEAPON_MOUNTS.PATH, FileAccess.WRITE)
	file.store_string(text)
