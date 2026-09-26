extends Node3D
const TUNING = preload("res://scripts/simulation/practice_tuning.gd")
## Practice Duel debug views (#93): draws the marks the offline authority
## records on the player's PracticeTuning (scripts/simulation/practice_tuning.gd)
## while the Esc menu's Debug toggles are on. Shot paths are lines; impacts are
## see-through spheres the size of the area of effect (red when they did
## damage), or small solid cubes for weapons without one. Each mark stays for the tuning's debug_linger seconds
## of unpaused play; turning a toggle off clears its marks.
##
## With hitboxes on, every other bot (and, with Player hitboxes on, the
## player's own, #94) shows its core in red: its real collision
## shapes. Over it, a see-through box per intact armour plate (blue) and per
## working component, the weapon strip and drive pods (amber), each covering
## the area of the collision bounds MvpBot.zone_at() assigns to it. Armour sits
## a little out from the core and components a little further, so the part a
## hit reaches first is in front. Components take most of a hit on them (the
## blue part of its damage numbers, #85). Presentation only.
const PATH_COLOR := Color(1.0, 0.85, 0.2, 0.9)
## Area-of-effect spheres are see-through: red when the blast damaged
## something, white when it did not.
const AREA_COLOR := Color(1.0, 1.0, 1.0, 0.15)
const AREA_DAMAGE_COLOR := Color(1.0, 0.1, 0.1, 0.18)
## Point impacts are solid cubes: white when they hit nothing, else the colour
## of what they hit on a bot (its hitbox layer) this much brighter.
const IMPACT_MISS_COLOR := Color.WHITE
const IMPACT_HIT_BRIGHTEN := 0.35
## Edge of the cube marking an impact without an area of effect (m).
const IMPACT_CUBE_SIZE := 0.35
## Sphere tessellation.
const SPHERE_SEGMENTS := 24
const SPHERE_RINGS := 12
## Hitboxes, depth tested so the arena and bot models hide them as usual.
const CORE_COLOR := Color(1.0, 0.15, 0.15, 0.6)
const ARMOUR_COLOR := Color(0.2, 0.4, 1.0, 0.35)
const COMPONENT_COLOR := Color(1.0, 0.6, 0.05, 0.4)
const LABEL_COLOR := Color(0.55, 0.7, 1.0)
const COMPONENT_LABEL_COLOR := Color(1.0, 0.78, 0.4)
## The core's health: a billboard at the centre of its hitbox, larger than the
## zone labels, drawn over the bot it belongs to.
const CORE_LABEL_COLOR := Color(1.0, 0.3, 0.3)
const CORE_LABEL_PIXEL := 0.03
## Box thickness and how far (m) armour boxes stand out from the core;
## component boxes stand twice as far, in front of the armour around them.
const LAYER_THICKNESS := 0.02
const LAYER_OFFSET := 0.03
## Zone labels lie flat on the outer face of their box, facing out; world size
## (m per font pixel).
const LABEL_FONT := 20
const LABEL_PIXEL := 0.022
## A thick black outline keeps the small text readable over any backdrop.
const LABEL_OUTLINE := 10
## Labels stand this far (m) off their box's face, so the box never hides them.
const LABEL_LIFT := 0.05
## Armour and weapon labels stand this much (m) further out.
const OUTER_LABEL_LIFT := 0.15
## Armour face -> its outward direction in the bot's frame.
const ARMOUR_FACES := {"top":Vector3.UP, "underside":Vector3.DOWN, "front":Vector3.FORWARD,
	"rear":Vector3.BACK, "left":Vector3.LEFT, "right":Vector3.RIGHT}
## Component zone -> its outward direction.
const COMPONENT_FACES := {"weapon":Vector3.FORWARD, "drive_left":Vector3.LEFT, "drive_right":Vector3.RIGHT}
## [MeshInstance3D, type, age] per mark on screen.
var _shown: Array = []
var _path_material := StandardMaterial3D.new()
var _area_material := StandardMaterial3D.new()
var _area_damage_material := StandardMaterial3D.new()
## Hitbox layer ("armour", "component", "core", "" for a miss) -> its solid
## point-impact material.
var _impact_hit_materials: Dictionary = {}
var _core_material := StandardMaterial3D.new()
var _armour_material := StandardMaterial3D.new()
var _component_material := StandardMaterial3D.new()
## Bot instance id -> {rig:Node3D, signature, labels:{zone:Label3D}}.
var _hitboxes: Dictionary = {}

func _init() -> void:
	name = "PracticeDebugDraw"
	top_level = true
	for material: StandardMaterial3D in [_path_material, _area_material, _area_damage_material, _core_material,
			_armour_material, _component_material]:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.disable_receive_shadows = true
	_path_material.albedo_color = PATH_COLOR
	_area_material.albedo_color = AREA_COLOR
	_area_damage_material.albedo_color = AREA_DAMAGE_COLOR
	var layers := {"armour":ARMOUR_COLOR, "component":COMPONENT_COLOR, "core":CORE_COLOR, "":IMPACT_MISS_COLOR}
	for layer: String in layers:
		var colour: Color = layers[layer]
		var solid := StandardMaterial3D.new()
		solid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		solid.albedo_color = Color(colour.lightened(IMPACT_HIT_BRIGHTEN) if not layer.is_empty() else colour, 1.0)
		_impact_hit_materials[layer] = solid
	_core_material.albedo_color = CORE_COLOR
	_armour_material.albedo_color = ARMOUR_COLOR
	_component_material.albedo_color = COMPONENT_COLOR

## Called every frame with the local player's tuning (null outside Practice),
## the other bots (MvpBot) whose hitboxes may show and the player's own bot,
## shown with Player hitboxes on (#94).
func render(tuning: RefCounted, delta: float, others: Array = [], player: MvpBot = null) -> void:
	if tuning == null:
		clear()
		return
	var bots: Array = others.duplicate() if tuning.debug_hitboxes else []
	if tuning.debug_player_hitboxes and player != null:
		bots.append(player)
	_render_hitboxes(bots)
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
		var layer: String = mark.get("layer", "")
		if radius > 0.0:
			item.material_override = _area_material if layer.is_empty() else _area_damage_material
		else:
			item.material_override = _impact_hit_materials[layer]
		item.position = mark.position
	add_child(item)
	_shown.append([item, mark.type, 0.0])

func _render_hitboxes(others: Array) -> void:
	var seen: Dictionary = {}
	for bot: MvpBot in others:
		if not is_instance_valid(bot) or not is_instance_valid(bot.body) or not bot.body.is_inside_tree() \
				or bot.combat.eliminated:
			# A dead bot's hitboxes go with it, as a broken plate's do.
			continue
		var key := bot.get_instance_id()
		seen[key] = true
		var bounds := bot.collision_bounds()
		var zones := _hit_zones(bot)
		var signature := "%s|%d|%s|%s" % [bounds, bot.body.get_child_count(), bot.loadout.parts, zones]
		var entry: Dictionary = _hitboxes.get(key, {})
		if entry.get("signature") != signature:
			if entry.has("rig"): entry.rig.queue_free()
			entry = _build_hitbox(bot, bounds, zones)
			entry.signature = signature
			_hitboxes[key] = entry
		entry.rig.global_transform = bot.body.global_transform
		for zone: String in entry.labels:
			entry.labels[zone].text = "%s  %.0f" % [zone.to_upper(), float(bot.combat.zones.get(zone, 0.0))]
		entry.core_label.text = "CORE  %.0f" % bot.combat.core
	for key: int in _hitboxes.keys():
		if not seen.has(key):
			_hitboxes[key].rig.queue_free()
			_hitboxes.erase(key)

## Zones layered over the core: armour plates fitted and not yet broken, and
## components still working.
func _hit_zones(bot: MvpBot) -> Array[String]:
	var zones: Array[String] = []
	for zone: String in ARMOUR_FACES.keys() + COMPONENT_FACES.keys():
		if TUNING.hit_layer(bot.combat, zone) != "core":
			zones.append(zone)
	return zones

## One bot's hitbox rig in its body frame: the core's collision shapes, then a
## box and label per layered zone, and the core's health at its centre.
func _build_hitbox(bot: MvpBot, bounds: AABB, zones: Array[String]) -> Dictionary:
	var rig := Node3D.new()
	rig.name = "Hitboxes_%d" % bot.entity_id
	add_child(rig)
	for child: Node in bot.body.get_children():
		var collider := child as CollisionShape3D
		if collider == null or collider.shape == null or collider.disabled:
			continue
		var core := MeshInstance3D.new()
		core.name = "CoreShape"
		core.mesh = collider.shape.get_debug_mesh()
		core.transform = collider.transform
		core.material_override = _core_material
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rig.add_child(core)
	var c := bounds.get_center()
	var h := bounds.size * 0.5
	var slab := h.y * MvpBot.ZONE_SLAB
	var drive_top := clampf(MvpBot.ZONE_DRIVE_TOP * bot.body.geometry_scale, -slab, slab)
	var drive_z := h.z * MvpBot.ZONE_DRIVE_LENGTH
	var weapon_x := h.x * MvpBot.ZONE_WEAPON_WIDTH
	var labels: Dictionary = {}
	for zone: String in zones:
		var component := COMPONENT_FACES.has(zone)
		var normal: Vector3 = COMPONENT_FACES[zone] if component else ARMOUR_FACES[zone]
		# The area it covers, [low corner, high corner], bounds-centred. Side and
		# front plates span their whole face; the drive pods and the weapon strip
		# stand in front of them.
		var area: Array = []
		match zone:
			"top":
				area = [Vector3(-h.x, slab, -h.z), Vector3(h.x, h.y, h.z)]
			"underside":
				area = [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -slab, h.z)]
			"left", "right", "front", "rear":
				area = [Vector3(-h.x, -slab, -h.z), Vector3(h.x, slab, h.z)]
			"weapon":
				area = [Vector3(-weapon_x, -slab, -h.z), Vector3(weapon_x, slab, h.z)]
			"drive_left", "drive_right":
				area = [Vector3(-h.x, -slab, -drive_z), Vector3(h.x, drive_top, drive_z)]
		var box := _layer_box(zone, normal, area, h, LAYER_OFFSET * (2.0 if component else 1.0),
			_component_material if component else _armour_material)
		box.position += c
		rig.add_child(box)
		var label := Label3D.new()
		label.double_sided = false
		label.pixel_size = LABEL_PIXEL
		label.font_size = LABEL_FONT
		label.outline_size = LABEL_OUTLINE
		label.modulate = COMPONENT_LABEL_COLOR if component else LABEL_COLOR
		label.outline_modulate = Color.BLACK
		# Label3D reads from its +Z side: turn that to face out of the box.
		var up := Vector3.FORWARD if absf(normal.y) > 0.5 else Vector3.UP
		label.basis = Basis.looking_at(-normal, up)
		var depth: float = (box.mesh as BoxMesh).size[normal.abs().max_axis_index()]
		label.position = box.position + normal * (depth * 0.5 + LABEL_LIFT)
		# Armour and weapon labels stand further out, in front of the drive pods'.
		if not component or zone == "weapon":
			label.position += normal * OUTER_LABEL_LIFT
		# The front label stays centred and clears the weapon's label by standing
		# as far ahead of it as the side labels stand out past the drive pods'
		# (OUTER_LABEL_LIFT - LAYER_OFFSET): the weapon label's own lift again.
		if zone == "front":
			label.position.x = c.x
			label.position += normal * OUTER_LABEL_LIFT
		# Text and its outline both draw after the see-through boxes (the outline
		# just before the text), so no box tints over either. Those priorities
		# order every label's outline before every label's text, so the labels
		# also write depth (#96): a near label's outline then hides a label
		# behind it instead of that label's text painting over the outline.
		label.render_priority = 2
		label.outline_render_priority = 1
		label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		rig.add_child(label)
		labels[zone] = label
	var core_label := Label3D.new()
	core_label.name = "CoreLabel"
	core_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	core_label.no_depth_test = true
	core_label.pixel_size = CORE_LABEL_PIXEL
	core_label.font_size = LABEL_FONT
	core_label.outline_size = LABEL_OUTLINE
	core_label.modulate = CORE_LABEL_COLOR
	core_label.outline_modulate = Color.BLACK
	core_label.render_priority = 2
	core_label.outline_render_priority = 1
	core_label.position = c
	rig.add_child(core_label)
	return {"rig":rig, "labels":labels, "core_label":core_label}

## A thin see-through box over the area, standing offset out from its face;
## the top and underside plates are their whole slab, grown by offset.
func _layer_box(zone: String, normal: Vector3, area: Array, h: Vector3, offset: float, material: Material) -> MeshInstance3D:
	var low: Vector3 = area[0]
	var high: Vector3 = area[1]
	if zone in ["top", "underside"]:
		low -= Vector3.ONE * offset
		high += Vector3.ONE * offset
	else:
		# Flatten onto its face: the face plane plus offset, LAYER_THICKNESS deep.
		var axis := normal.abs().max_axis_index()
		var face := (h[axis] + offset) * normal[axis]
		low[axis] = face - LAYER_THICKNESS * 0.5
		high[axis] = face + LAYER_THICKNESS * 0.5
	var mesh := BoxMesh.new()
	mesh.size = high - low
	var item := MeshInstance3D.new()
	item.name = "Layer_" + zone
	item.mesh = mesh
	item.position = (low + high) * 0.5
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return item
