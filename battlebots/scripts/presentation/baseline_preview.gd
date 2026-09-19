extends Node3D
## B-owned input/presentation adapter; never writes authoritative bot transforms.

@export var source_path: NodePath
@export var fixture_title: String = "Development fixture"
@onready var source: BotSource = get_node_or_null(source_path) as BotSource
@onready var rig: BotOrbitCamera = $OrbitCamera
@onready var hud: BotStatusHud = $CanvasLayer/BotStatusHud
@onready var hint: Label = $CanvasLayer/Hint
var sequence: int = 0
var controls_enabled: bool = false
var _suppress_primary_until_release: bool = false

func _ready() -> void:
	hud.set_context(fixture_title)
	rig.bind_source(source)
	get_window().focus_exited.connect(release_controls)
	if DisplayServer.get_name() != "headless":
		capture_controls()

func capture_controls() -> void:
	controls_enabled = true
	_suppress_primary_until_release = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_controls() -> void:
	controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rig.driving = false
	_submit_neutral()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _submit_neutral() -> void:
	if not is_instance_valid(source):
		return
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	source.submit_command(command)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(source):
		if controls_enabled:
			release_controls()
		return
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	if controls_enabled and get_window().has_focus():
		if not Input.is_action_pressed("primary"):
			_suppress_primary_until_release = false
		command.throttle = Input.get_axis("drive_reverse", "drive_forward")
		command.steering = Input.get_axis("steer_left", "steer_right")
		command.brake = Input.is_action_pressed("brake")
		command.primary_held = Input.is_action_pressed("primary") \
			and not _suppress_primary_until_release
		command.primary_pressed = Input.is_action_just_pressed("primary") \
			and not _suppress_primary_until_release
		command.secondary_held = Input.is_action_pressed("secondary")
		command.recovery_pressed = Input.is_action_just_pressed("recover")
	rig.driving = absf(command.throttle) > 0.05 or absf(command.steering) > 0.05
	source.submit_command(command)

func _process(_delta: float) -> void:
	if not is_instance_valid(source):
		hud.show_view(null)
		return
	hud.show_view(source.read_view())
	hint.text = "Mouse  Orbit   |   Wheel  Zoom   |   MMB  Recenter   |   Esc  Release cursor" \
		if controls_enabled else "Click the arena to resume   |   Esc  Return to launcher"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if controls_enabled:
			release_controls()
		else:
			get_tree().change_scene_to_file("res://scenes/app/main.tscn")
		get_viewport().set_input_as_handled()
		return
	if not controls_enabled:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed and get_window().has_focus():
			capture_controls()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		rig.orbit(event.relative)
	elif event.is_action_pressed("camera_zoom_in"):
		rig.zoom(-1.0)
	elif event.is_action_pressed("camera_zoom_out"):
		rig.zoom(1.0)
	elif event.is_action_pressed("camera_recenter"):
		rig.recenter()
