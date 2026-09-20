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
@onready var network_diagnostics: NetworkDiagnosticsPanel = $DiagnosticsLayer/NetworkDiagnostics
var sequence: int = 0
var controls_enabled: bool = false
var input_gate := GameplayInputGate.new()
var _load_notice: String = ""
var _control_generation: int = 0
var _leaving: bool = false
var input_preferences: InputPreferences
var _input_map_before: Dictionary = {}
var _diagnostics_epoch := ""
var _diagnostics_initial_samples := 0.0
var _diagnostics_fresh := false

func _ready() -> void:
	hud.set_context(fixture_title)
	rig.bind_source(source)
	var preferences := CameraPreferences.load_file(settings_path)
	preferences.apply_to(rig)
	if preferences.load_error != OK:
		_load_notice = "Saved settings could not be loaded. Using defaults."
	_input_map_before = InputPreferences.snapshot_input_map()
	var input_path := "" if settings_path.is_empty() else settings_path + ".input"
	if settings_path == CameraPreferences.DEFAULT_PATH:
		input_path = InputPreferences.DEFAULT_PATH
	input_preferences = InputPreferences.load_file(input_path)
	_apply_input_preferences(input_preferences)
	settings_panel.configure_inputs(input_preferences, input_path,
		"Saved controls could not be loaded. Using defaults." if input_preferences.load_error != OK else "")
	settings_panel.input_applied.connect(_apply_input_preferences)
	network_diagnostics.interaction_started.connect(_on_diagnostics_interaction)
	refresh_diagnostics()
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

func _apply_input_preferences(preferences: InputPreferences) -> void:
	input_preferences = preferences
	input_preferences.apply_to_input_map()
	input_gate.toggle_primary = preferences.toggle_primary
	input_gate.require_release()

func _on_diagnostics_interaction() -> void:
	release_controls(false)
	# Losing focus even briefly cancels a keyboard button's pending activation.
	network_diagnostics.details_button.grab_focus()

func release_controls(focus_menu: bool = true) -> void:
	_control_generation += 1
	controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	rig.driving = false
	pause_menu.visible = not settings_panel.visible and not _leaving
	resume_button.disabled = not is_instance_valid(source)
	_submit_neutral()
	if focus_menu:
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
	if not _input_map_before.is_empty():
		InputPreferences.restore_input_map(_input_map_before)
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
		strengths[action] = _action_strength(action)
	var edges := {
		&"primary": Input.is_action_just_pressed("primary"),
		&"recover": Input.is_action_just_pressed("recover"),
	}
	var enabled := controls_enabled and not settings_panel.visible \
		and not _leaving and get_window().has_focus()
	# Clear toggle intent during A's countdown/elimination/lifecycle suppression too.
	if source is SessionBotSource and source.input_allowed.is_valid():
		enabled = enabled and bool(source.input_allowed.call())
	input_gate.auxiliary_weapon = source.read_view().has_auxiliary_weapon
	var command := input_gate.sample(strengths, edges, enabled)
	command.sequence = sequence
	sequence += 1
	rig.driving = absf(command.throttle) > 0.05 or absf(command.steering) > 0.05
	source.submit_command(command)

func _action_strength(action: StringName) -> float:
	var strength := Input.get_action_strength(action)
	# Rebinding releases action state, but a physical key may still be held.
	# Keep it blocked until real release rather than rearming on an artificial zero.
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and Input.is_physical_key_pressed(event.physical_keycode):
			strength = 1.0
		elif event is InputEventMouseButton and Input.is_mouse_button_pressed(event.button_index):
			strength = 1.0
	return strength

func _process(_delta: float) -> void:
	hud.show_view(source.read_view() if is_instance_valid(source) else null)
	refresh_diagnostics()
	hint.text = "Mouse  Orbit  |  %s / %s  Zoom  |  %s  Recenter  |  Esc  Menu" % [
		input_preferences.label_for(&"camera_zoom_in"), input_preferences.label_for(&"camera_zoom_out"),
		input_preferences.label_for(&"camera_recenter")] \
		if controls_enabled else "Tab / arrows  Select   |   Enter  Confirm   |   Esc  Resume"
	if controls_enabled and is_instance_valid(source) and source.read_view().has_auxiliary_weapon:
		hint.text = "%s  Primary weapon  |  %s  Minigun  |  Mouse  Orbit  |  Esc  Menu" % [
			input_preferences.label_for(&"primary"), input_preferences.label_for(&"secondary")]

func refresh_diagnostics() -> void:
	if not is_instance_valid(source) or not source is SessionBotSource \
		or not is_instance_valid(source.session):
		network_diagnostics.hide()
		_diagnostics_epoch = ""
		return
	var session: MvpSession = source.session
	var state: String = session.connection_state
	var phase: String = str(session.match_view.get("phase", "lobby"))
	var epoch := "%d/%s/%s/%s" % [session.get_instance_id(), state,
		str(session.match_view.get("match_id", "")), phase]
	var samples: Variant = session.diagnostics.get("snapshots_received")
	var count := float(samples) if (samples is int or samples is float) and is_finite(float(samples)) else 0.0
	if epoch != _diagnostics_epoch:
		_diagnostics_epoch = epoch
		_diagnostics_initial_samples = count
		_diagnostics_fresh = false
	elif count > _diagnostics_initial_samples:
		_diagnostics_fresh = true
	var data := session.diagnostics.duplicate(true)
	if state == "connected" and not _diagnostics_fresh:
		data.clear()
	network_diagnostics.show_diagnostics(state, data, {
		"build": WireCodec.BUILD,
		"mode": "Practice" if state == "practice" else str(session.lobby_view.get("mode", "--")),
		"phase": phase,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
	})
	# A's centered session menu occupies 720px. Use its side gutter when paused.
	var inset := 24.0 if controls_enabled else clampf(
		(get_viewport().get_visible_rect().size.x - 720.0) * 0.5 - 280.0, 0.0, 24.0)
	network_diagnostics.offset_left = -280.0 - inset
	network_diagnostics.offset_right = -inset
	network_diagnostics.visible = not settings_panel.visible

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
		# Captured mouse sensitivity uses screen pixels, independent of viewport stretch.
		rig.orbit(event.screen_relative)
	elif event.is_action_pressed("camera_zoom_in"):
		rig.zoom(-1.0)
	elif event.is_action_pressed("camera_zoom_out"):
		rig.zoom(1.0)
	elif event.is_action_pressed("camera_recenter"):
		rig.recenter()
