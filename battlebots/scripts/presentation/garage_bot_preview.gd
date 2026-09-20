class_name GarageBotPreview
extends Control
## Cosmetic workshop only. Never creates a bot, collision body or combat state.
const PAINTS := {"cyan":Color(0.1, 0.65, 0.85), "orange":Color(0.95, 0.4, 0.1),
	"white":Color(0.86, 0.89, 0.93), "red":Color(0.75, 0.1, 0.08)}
var viewport: SubViewport
var camera: Camera3D
var model: Node3D
var weapon_visual: MvpWeaponVisual
var status: Label
var yaw := 0.6
var pitch := 0.45
var distance := 5.4
var _stage: Node3D
var _registry := ContentRegistry.new()
var _draft: Dictionary = {}
var _status_next: Button
var _status_pages: Array[String] = []
var _status_page := 0
var _text_factor := 1.0

func apply_text_scale(factor: float) -> void:
	var value := clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	_text_factor = value
	MenuTextScale.apply(self, value)
	_layout_status()

func _layout_status() -> void:
	var value := _text_factor
	if is_instance_valid(status):
		status.offset_top = -minf(size.y, (140 if not _status_pages.is_empty() else 84) * value)
		status.offset_bottom = -36 * value if not _status_pages.is_empty() else 0.0
	if is_instance_valid(_status_next): _status_next.offset_top = -36 * value

func _show_status_page() -> void:
	if _status_pages.is_empty(): return
	status.text = "Invalid build · %d / %d\n%s" % [_status_page + 1, _status_pages.size(), _status_pages[_status_page]]
	_status_next.visible = _status_pages.size() > 1

func _invalid_status(message: String) -> void:
	_status_pages.clear()
	while not message.is_empty():
		var split := mini(64, message.length())
		if message.length() > 64:
			var space := message.rfind(" ", 64)
			if space > 0: split = space
		_status_pages.append(message.left(split))
		message = message.substr(split).strip_edges()
	_status_page = 0
	_show_status_page()
	_layout_status()

func _ready() -> void:
	resized.connect(_layout_status)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drag to rotate • Wheel to zoom • Arrow keys to rotate • + / − to zoom • Home to reset"
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	_stage = Node3D.new()
	viewport.add_child(_stage)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111b26")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b7c9e0")
	environment.ambient_light_energy = 0.55
	world_environment.environment = environment
	_stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -35, 0)
	key.light_energy = 1.7
	_stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-3, 3, 2)
	rim.omni_range = 12
	rim.light_energy = 3
	rim.light_color = Color("6ca7cc")
	_stage.add_child(rim)
	var plinth := CylinderMesh.new()
	plinth.top_radius = 2.8
	plinth.bottom_radius = 2.8
	plinth.height = 0.12
	_mesh(_stage, plinth, Vector3(0, -0.18, 0), Color("263544"))
	camera = Camera3D.new()
	camera.fov = 45
	camera.near = 0.05
	_stage.add_child(camera)
	camera.current = true
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -84
	status.offset_left = 12
	status.offset_right = -84
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 1)
	status.add_theme_constant_override("shadow_offset_y", 1)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	_status_next = Button.new()
	_status_next.text = "NEXT REASON"
	_status_next.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status_next.offset_top = -36
	_status_next.offset_left = 12
	_status_next.add_theme_font_size_override("font_size", 18)
	_status_next.pressed.connect(func():
		_status_page = wrapi(_status_page + 1, 0, _status_pages.size())
		_show_status_page())
	add_child(_status_next)
	_status_next.hide()
	reset_view()
	show_loadout(_draft)

func show_loadout(draft: Dictionary) -> void:
	if viewport == null:
		_draft = draft.duplicate(true)
		return
	if model != null and _draft == draft:
		return
	_draft = draft.duplicate(true)
	if is_instance_valid(model):
		_stage.remove_child(model)
		model.queue_free()
	model = null
	weapon_visual = null
	var validation := _registry.validate(draft)
	if not validation.valid:
		_invalid_status("; ".join(validation.reasons))
		return
	_status_pages.clear()
	_status_next.hide()
	_layout_status()
	model = Node3D.new()
	model.name = "BuildModel"
	model.position.y = 0.4
	_stage.add_child(model)
	var size: Vector3 = validation.stats.size
	var chassis := BoxMesh.new()
	chassis.size = size
	_mesh(model, chassis, Vector3.ZERO, PAINTS[draft.cosmetics.paint]).name = "Chassis"
	var stripe := BoxMesh.new()
	stripe.size = Vector3(size.x * 0.65, 0.025, 0.12)
	_mesh(model, stripe, Vector3(0, size.y * 0.5 + 0.015, -size.z * 0.38), Color("f4b82e"))
	weapon_visual = MvpWeaponVisual.new()
	weapon_visual.name = "Weapon"
	model.add_child(weapon_visual)
	weapon_visual.assemble(validation.stats.weapon, size)
	status.text = "Equipped draft · primitive geometry\nDrag to rotate · Wheel to zoom"

func _mesh(parent: Node3D, mesh: Mesh, position: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.45
	material.roughness = 0.45
	visual.material_override = material
	parent.add_child(visual)
	return visual

func reset_view() -> void:
	yaw = 0.6
	pitch = 0.45
	distance = 5.4
	_update_camera()

func rotate_view(delta: Vector2) -> void:
	yaw = wrapf(yaw + delta.x, -PI, PI)
	pitch = clampf(pitch + delta.y, -0.15, 1.1)
	_update_camera()

func zoom_view(amount: float) -> void:
	distance = clampf(distance + amount, 3.0, 9.0)
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(camera): return
	var target := Vector3(0, 0.4, -0.35)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			grab_focus()
			accept_event()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_view(-0.4 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.4)
			accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		rotate_view(Vector2(-event.relative.x, event.relative.y) * 0.008)
		accept_event()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: rotate_view(Vector2(-0.12, 0))
			KEY_RIGHT: rotate_view(Vector2(0.12, 0))
			KEY_UP: rotate_view(Vector2(0, 0.08))
			KEY_DOWN: rotate_view(Vector2(0, -0.08))
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD: zoom_view(-0.4)
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_view(0.4)
			KEY_HOME: reset_view()
			_: return
		accept_event()
