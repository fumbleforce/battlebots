class_name PickupVisuals
extends Node3D
## World markers for the session's public pickup state: a floor ring, a light
## column and a floating, rotating item labelled with its contents. Parts with
## real art show that model (PickupModels); perks, credits and parts without a
## dedicated mesh show a token. Colour identifies the kind (amber part, cyan
## perk, green credits). Presentation only.
const TOKEN_HEIGHT := 2.6
const BEAM_HEIGHT := MatchPickups.REACH_UP
var session: MvpSession
var names: Dictionary = {}
var registry: ContentRegistry
var markers: Dictionary = {}
var _time := 0.0

func bind_session(value: MvpSession) -> void:
	session = value
	registry = session.registry
	names = PickupFeed.names_from(registry)

func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless" or not is_instance_valid(session):
		return
	_time += delta
	var items: Variant = session.pickup_view.get("items", [])
	var seen := {}
	if items is Array:
		for item: Variant in items:
			if not item is Dictionary or not item.get("id") is int or not item.get("point") is Vector3:
				continue
			seen[item.id] = true
			var marker: Node3D = markers.get(item.id)
			if marker == null:
				marker = _marker()
				add_child(marker)
				markers[item.id] = marker
			_show(marker, item)
	for id: Variant in markers.keys():
		if not seen.has(id):
			markers[id].queue_free()
			markers.erase(id)

func _show(marker: Node3D, item: Dictionary) -> void:
	marker.visible = bool(item.get("available", false))
	marker.position = item.point
	var key := "%s:%s:%s" % [item.get("kind"), item.get("part"), item.get("amount")]
	if marker.get_meta(&"key", "") != key:
		marker.set_meta(&"key", key)
		var color := PickupFeed.color_for(str(item.get("kind", "part")))
		for path: String in ["Ring", "Beam", "Token/Core", "Token/Frame"]:
			var material: StandardMaterial3D = (marker.get_node(path) as MeshInstance3D).material_override
			material.albedo_color = Color(color, material.albedo_color.a)
			material.emission = color
		var label: Label3D = marker.get_node("Label")
		label.text = PickupFeed.describe(item, names)
		label.modulate = color.lightened(0.35)
		var core: MeshInstance3D = marker.get_node("Token/Core")
		core.mesh = _token_mesh(str(item.get("kind", "part")))
		# Stand coins on edge so their spin reads from the chase camera.
		core.rotation.x = PI * 0.5 if item.get("kind") == "credits" else 0.0
		var token: Node3D = marker.get_node("Token")
		var previous := token.get_node_or_null("Model")
		if previous != null:
			token.remove_child(previous)
			previous.queue_free()
		var model: Node3D = null
		if registry != null and item.get("kind") == "part":
			model = PickupModels.build(str(item.get("part", "")), registry, token)
		core.visible = model == null
		(marker.get_node("Token/Frame") as Node3D).visible = model == null
	if not marker.visible:
		return
	var phase := float(int(item.id)) * 1.7
	var token: Node3D = marker.get_node("Token")
	token.position.y = TOKEN_HEIGHT + sin(_time * 2.0 + phase) * 0.25
	token.rotation.y = _time * 1.4 + phase
	var pulse := 0.75 + 0.25 * sin(_time * 3.0 + phase)
	(marker.get_node("Ring") as MeshInstance3D).scale = Vector3.ONE * (0.95 + 0.08 * pulse)

func _marker() -> Node3D:
	var marker := Node3D.new()
	marker.name = "Pickup"
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.9
	torus.outer_radius = 2.2
	ring.mesh = torus
	ring.position.y = 0.06
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.material_override = _glow(1.0, 2.5)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var column := CylinderMesh.new()
	column.top_radius = 0.55
	column.bottom_radius = 0.9
	column.height = BEAM_HEIGHT
	column.cap_top = false
	column.cap_bottom = false
	beam.mesh = column
	beam.position.y = BEAM_HEIGHT * 0.5
	beam.material_override = _glow(0.12, 1.2, true)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(beam)
	var token := Node3D.new()
	token.name = "Token"
	token.position.y = TOKEN_HEIGHT
	marker.add_child(token)
	var core := MeshInstance3D.new()
	core.name = "Core"
	core.mesh = _token_mesh("part")
	core.material_override = _glow(1.0, 1.6)
	token.add_child(core)
	var frame := MeshInstance3D.new()
	frame.name = "Frame"
	var cage := BoxMesh.new()
	cage.size = Vector3.ONE * 1.9
	frame.mesh = cage
	frame.material_override = _glow(0.18, 0.8, true)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	token.add_child(frame)
	var label := Label3D.new()
	label.name = "Label"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.fixed_size = false
	label.pixel_size = 0.012
	label.font_size = 72
	label.outline_size = 14
	label.outline_modulate = Color(0.04, 0.05, 0.06, 0.9)
	label.position.y = TOKEN_HEIGHT + 2.0
	marker.add_child(label)
	return marker

static func _token_mesh(kind: String) -> Mesh:
	if kind == "credits":
		var coin := CylinderMesh.new()
		coin.top_radius = 0.75
		coin.bottom_radius = 0.75
		coin.height = 0.22
		coin.radial_segments = 24
		return coin
	if kind == "perk":
		var gem := SphereMesh.new()
		gem.radius = 0.7
		gem.height = 1.4
		gem.radial_segments = 6
		gem.rings = 2
		return gem
	var crate := BoxMesh.new()
	crate.size = Vector3.ONE * 1.2
	return crate

static func _glow(alpha: float, energy: float, transparent := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 1, alpha)
	material.emission_enabled = true
	material.emission_energy_multiplier = energy
	material.metallic = 0.3
	material.roughness = 0.35
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
