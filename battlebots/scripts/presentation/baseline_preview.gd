extends Node3D
## B-owned input/presentation adapter; never writes authoritative bot transforms.

@export var source_path: NodePath
@export var fixture_title: String = "Development fixture"
@export var settings_path: String = CameraPreferences.DEFAULT_PATH
@onready var source: BotSource = get_node_or_null(source_path) as BotSource
@onready var rig: BotOrbitCamera = $OrbitCamera
@onready var hud: BotStatusHud = $CanvasLayer/BotStatusHud
@onready var hint: Label = $CanvasLayer/Hint
@onready var pause_menu: PanelContainer = $CanvasLayer/PauseMenu
@onready var resume_button: Button = $CanvasLayer/PauseMenu/Margin/Content/Resume
@onready var settings_button: Button = $CanvasLayer/PauseMenu/Margin/Content/Settings
@onready var return_button: Button = $CanvasLayer/PauseMenu/Margin/Content/Return
@onready var settings_panel: CameraSettingsPanel = $ModalLayer/CameraSettings
var sequence: int = 0
var controls_enabled: bool = false
var input_gate := GameplayInputGate.new()
var _load_notice: String = ""
var _control_generation: int = 0
var _leaving: bool = false

func _ready() -> void:
	hud.set_context(fixture_title)
	rig.bind_source(source)
	var preferences := CameraPreferences.load_file(settings_path)
	preferences.apply_to(rig)
	if preferences.load_error != OK:
		_load_notice = "Saved settings could not be loaded. Using defaults."
	resume_button.pressed.connect(capture_controls)
	settings_button.pressed.connect(open_settings)
	return_button.pressed.connect(return_to_launcher)
	settings_panel.closed.connect(_on_settings_closed)
	get_window().focus_exited.connect(release_controls)
	if DisplayServer.get_name() != "headless":
		capture_controls()
	else:
		release_controls()

func capture_controls() -> void:
	if _leaving or settings_panel.visible or not is_instance_valid(source):
		return
	_control_generation += 1
	controls_enabled = true
	pause_menu.hide()
	input_gate.require_release()
	get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func release_controls() -> void:
	_control_generation += 1
	controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rig.driving = false
	pause_menu.visible = not settings_panel.visible and not _leaving
	resume_button.disabled = not is_instance_valid(source)
	_submit_neutral()
	_focus_menu()

func _focus_menu() -> void:
	if not pause_menu.is_visible_in_tree() or _leaving:
		return
	if not resume_button.disabled:
		resume_button.grab_focus()
	else:
		return_button.grab_focus()

func open_settings() -> void:
	if _leaving:
		return
	release_controls()
	pause_menu.hide()
	settings_panel.open_for(rig, settings_path, _load_notice)

func _on_settings_closed(saved: bool) -> void:
	if saved:
		_load_notice = ""
	pause_menu.visible = not _leaving
	_focus_menu()
	if get_window().has_focus():
		_resume_after_settings.call_deferred(_control_generation)

func _resume_after_settings(generation: int) -> void:
	# Focus loss or another modal after close invalidates this pending resume.
	if generation == _control_generation and get_window().has_focus():
		capture_controls()

func _input(event: InputEvent) -> void:
	if settings_panel.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		settings_panel.cancel()

func return_to_launcher() -> void:
	if _leaving:
		return
	_leaving = true
	get_viewport().set_input_as_handled()
	release_controls()
	_finish_return.call_deferred()

func _finish_return() -> void:
	if is_inside_tree():
		get_tree().change_scene_to_file("res://scenes/app/main.tscn")

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _submit_neutral() -> void:
	if not is_instance_valid(source):
		return
	var command := input_gate.sample({}, {}, false)
	command.sequence = sequence
	sequence += 1
	source.submit_command(command)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(source):
		if controls_enabled:
			release_controls()
		resume_button.disabled = true
		return
	var strengths: Dictionary = {}
	for action: StringName in GameplayInputGate.ACTIONS:
		strengths[action] = Input.get_action_strength(action)
	var edges := {
		&"primary": Input.is_action_just_pressed("primary"),
		&"recover": Input.is_action_just_pressed("recover"),
	}
	var enabled := controls_enabled and not settings_panel.visible \
		and not _leaving and get_window().has_focus()
	var command := input_gate.sample(strengths, edges, enabled)
	command.sequence = sequence
	sequence += 1
	rig.driving = absf(command.throttle) > 0.05 or absf(command.steering) > 0.05
	source.submit_command(command)

func _process(_delta: float) -> void:
	hud.show_view(source.read_view() if is_instance_valid(source) else null)
	hint.text = "Mouse  Orbit   |   Wheel  Zoom   |   MMB  Recenter   |   Esc  Menu" \
		if controls_enabled else "Tab / arrows  Select   |   Enter  Confirm   |   Esc  Resume"

func _unhandled_input(event: InputEvent) -> void:
	if settings_panel.visible or _leaving:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if controls_enabled:
			release_controls()
		else:
			capture_controls()
		return
	# Resume is explicit; clicks outside buttons must not fire a weapon or close menus.
	if not controls_enabled:
		return
	if event is InputEventMouseMotion:
		rig.orbit(event.relative)
	elif event.is_action_pressed("camera_zoom_in"):
		rig.zoom(-1.0)
	elif event.is_action_pressed("camera_zoom_out"):
		rig.zoom(1.0)
	elif event.is_action_pressed("camera_recenter"):
		rig.recenter()
