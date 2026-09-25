extends Node3D
## Practice Duel debug views (#93): draws the marks the offline authority
## records on the player's PracticeTuning (scripts/simulation/practice_tuning.gd)
## while the Esc menu's Debug toggles are on. Shot paths are lines; impacts are
## red see-through spheres the size of the area of effect, or small cubes for
## weapons without one. Each mark stays for the tuning's debug_linger seconds
## of unpaused play; turning a toggle off clears its marks. With hitboxes on,
## every other bot shows its real collision shapes (what a shot or sweep can
## strike) and, over its collision bounds, the armour zones MvpBot.zone_at()
## sorts each hit into, labelled with what each zone has left. Presentation only.
const PATH_COLOR := Color(1.0, 0.85, 0.2, 0.9)
const IMPACT_COLOR := Color(1.0, 0.1, 0.1, 0.3)
## Edge of the cube marking an impact without an area of effect (m).
const IMPACT_CUBE_SIZE := 0.35
## Sphere tessellation.
const SPHERE_SEGMENTS := 24
const SPHERE_RINGS := 12
## Hitboxes: collision shapes, zone boundaries and the zone labels.
const SHAPE_COLOR := Color(0.3, 1.0, 0.4, 0.9)
const ZONE_COLOR := Color(0.2, 0.8, 1.0, 0.95)
const LABEL_FONT := 40
const LABEL_PIXEL := 0.004
## Zone name -> its label in bounds-centred shares of the half size; the
## drive pods' and sides' heights are placed per bot.
const ZONE_LABELS := {"top":Vector3(0, 1, 0), "underside":Vector3(0, -1, 0), "weapon":Vector3(0, 0, -1),
	"front":Vector3(0.72, 0, -1), "rear":Vector3(0, 0, 1), "left":Vector3(-1, 0, 0), "right":Vector3(1, 0, 0),
	"drive_left":Vector3(-1, 0, 0), "drive_right":Vector3(1, 0, 0)}
## [MeshInstance3D, type, age] per mark on screen.
var _shown: Array = []
var _path_material := StandardMaterial3D.new()
var _impact_material := StandardMaterial3D.new()
var _shape_material := StandardMaterial3D.new()
var _zone_material := StandardMaterial3D.new()
## Bot instance id -> {rig:Node3D, signature, labels:{zone:Label3D}}.
var _hitboxes: Dictionary = {}

func _init() -> void:
	name = "PracticeDebugDraw"
	top_level = true
	for material: StandardMaterial3D in [_path_material, _impact_material]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
	_path_material.albedo_color = PATH_COLOR
	_impact_material.albedo_color = IMPACT_COLOR
	for material: StandardMaterial3D in [_shape_material, _zone_material]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Seen through the bot's own model, which covers most of its shapes.
		material.no_depth_test = true
	_shape_material.albedo_color = SHAPE_COLOR
	_zone_material.albedo_color = ZONE_COLOR

## Called every frame with the local player's tuning (null outside Practice)
## and the other bots (MvpBot) whose hitboxes may show.
func render(tuning: RefCounted, delta: float, others: Array = []) -> void:
	if tuning == null:
		clear()
		return
	_render_hitboxes(others if tuning.debug_hitboxes else [])
	for mark: Dictionary in tuning.take_debug_marks():
		_add(mark)
	var keep: Array = []
	for entry: Array in _shown:
		entry[2] += delta
		var on: bool = tuning.debug_trajectories if entry[1] == "path" else tuning.debug_impacts
		if on and entry[2] < tuning.debug_linger:
			keep.append(entry)
		else:
			entry[0].queue_free()
	_shown = keep

func clear() -> void:
	for entry: Array in _shown:
		entry[0].queue_free()
	_shown.clear()
	_render_hitboxes([])

func _add(mark: Dictionary) -> void:
	var item := MeshInstance3D.new()
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mark.type == "path":
		var line := ImmediateMesh.new()
		line.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _path_material)
		for point: Vector3 in mark.points:
			line.surface_add_vertex(point)
		line.surface_end()
		item.mesh = line
	else:
		var radius: float = mark.radius
		if radius > 0.0:
			var sphere := SphereMesh.new()
			sphere.radius = radius
			sphere.height = radius * 2.0
			sphere.radial_segments = SPHERE_SEGMENTS
			sphere.rings = SPHERE_RINGS
			item.mesh = sphere
		else:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE * IMPACT_CUBE_SIZE
			item.mesh = cube
		item.material_override = _impact_material
		item.position = mark.position
	add_child(item)
	_shown.append([item, mark.type, 0.0])

func _render_hitboxes(others: Array) -> void:
	var seen: Dictionary = {}
	for bot: MvpBot in others:
		if not is_instance_valid(bot) or not is_instance_valid(bot.body) or not bot.body.is_inside_tree():
			continue
		var key := bot.get_instance_id()
		seen[key] = true
		var bounds := bot.collision_bounds()
		var signature := "%s|%d|%s" % [bounds, bot.body.get_child_count(), bot.loadout.parts]
		var entry: Dictionary = _hitboxes.get(key, {})
		if entry.get("signature") != signature:
			if entry.has("rig"): entry.rig.queue_free()
			entry = _build_hitbox(bot, bounds)
			entry.signature = signature
			_hitboxes[key] = entry
		entry.rig.global_transform = bot.body.global_transform
		for zone: String in entry.labels:
			var label: Label3D = entry.labels[zone]
			var left: float = bot.combat.zones.get(zone, 0.0)
			var fitted: float = bot.combat.stats.plates.get(zone, -1.0)
			if fitted == 0.0:
				label.text = "%s  bare" % zone.to_upper()
			else:
				label.text = "%s  %.0f" % [zone.to_upper(), left]
	for key: int in _hitboxes.keys():
		if not seen.has(key):
			_hitboxes[key].rig.queue_free()
			_hitboxes.erase(key)

## One bot's hitbox rig in its body frame: every collision shape, then the zone
## boundaries on the surface of its collision bounds.
func _build_hitbox(bot: MvpBot, bounds: AABB) -> Dictionary:
	var rig := Node3D.new()
	rig.name = "Hitboxes_%d" % bot.entity_id
	add_child(rig)
	for child: Node in bot.body.get_children():
		var collider := child as CollisionShape3D
		if collider == null or collider.shape == null or collider.disabled:
			continue
		var outline := MeshInstance3D.new()
		outline.mesh = collider.shape.get_debug_mesh()
		outline.transform = collider.transform
		outline.material_override = _shape_material
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(outline)
	var c := bounds.get_center()
	var h := bounds.size * 0.5
	var slab := h.y * MvpBot.ZONE_SLAB
	var drive_top := clampf(MvpBot.ZONE_DRIVE_TOP * bot.body.geometry_scale, -slab, slab)
	var drive_z := h.z * MvpBot.ZONE_DRIVE_LENGTH
	var weapon_x := h.x * MvpBot.ZONE_WEAPON_WIDTH
	var lines := PackedVector3Array()
	var corners := [Vector2(-h.x, -h.z), Vector2(h.x, -h.z), Vector2(h.x, h.z), Vector2(-h.x, h.z)]
	for index: int in 4:
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % 4]
		# Box edges, and the top and underside slab lines around the sides.
		for y: float in [-h.y, h.y, -slab, slab]:
			lines.append_array([Vector3(a.x, y, a.y), Vector3(b.x, y, b.y)])
		lines.append_array([Vector3(a.x, -h.y, a.y), Vector3(a.x, h.y, a.y)])
		# Inside, sides and ends meet on the diagonals from the centre to the corners.
		for y: float in [-slab, slab]:
			lines.append_array([Vector3(0, y, 0), Vector3(a.x, y, a.y)])
	for x: float in [-h.x, h.x]:
		# Drive pod: the low middle of each side.
		lines.append_array([Vector3(x, drive_top, -drive_z), Vector3(x, drive_top, drive_z),
			Vector3(x, -slab, -drive_z), Vector3(x, drive_top, -drive_z),
			Vector3(x, -slab, drive_z), Vector3(x, drive_top, drive_z)])
	for x: float in [-weapon_x, weapon_x]:
		# Weapon: the middle strip of the front.
		lines.append_array([Vector3(x, -slab, -h.z), Vector3(x, slab, -h.z)])
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _zone_material)
	for point: Vector3 in lines:
		mesh.surface_add_vertex(c + point)
	mesh.surface_end()
	var zones := MeshInstance3D.new()
	zones.mesh = mesh
	zones.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(zones)
	var labels: Dictionary = {}
	var side_y := (drive_top + slab) * 0.5
	var drive_y := (drive_top - slab) * 0.5
	for zone: String in ZONE_LABELS:
		if not bot.combat.zones.has(zone) and not bot.combat.stats.plates.has(zone):
			continue
		var share: Vector3 = ZONE_LABELS[zone]
		var at := c + share * h
		if zone in ["left", "right"]: at.y = c.y + side_y
		elif zone in ["drive_left", "drive_right"]: at.y = c.y + drive_y
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = LABEL_PIXEL
		label.font_size = LABEL_FONT
		label.outline_size = 8
		label.modulate = ZONE_COLOR
		label.position = at
		rig.add_child(label)
		labels[zone] = label
	return {"rig":rig, "labels":labels}
