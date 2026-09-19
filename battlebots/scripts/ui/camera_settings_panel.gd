class_name CameraSettingsPanel
extends Control

signal closed(saved: bool)
signal input_applied(preferences: InputPreferences)
@onready var form: VBoxContainer = $Center/Panel/Margin/Form
@onready var sensitivity: HSlider = $Center/Panel/Margin/Form/Sensitivity/Slider
@onready var sensitivity_y: HSlider = $Center/Panel/Margin/Form/SensitivityY/Slider
@onready var invert: CheckButton = $Center/Panel/Margin/Form/Invert
@onready var automatic: CheckButton = $Center/Panel/Margin/Form/Automatic
@onready var strength: HSlider = $Center/Panel/Margin/Form/Strength/Slider
@onready var message: Label = $Center/Panel/Margin/Form/Message
var _rig: BotOrbitCamera
var _path: String
var _original: CameraPreferences
var _display_values: CameraPreferences
var _display_axes: Vector2
var input_panel: InputSettingsPanel
var controls_button: Button
var _input_preferences: InputPreferences
var _input_path: String
var _input_notice: String

func _ready() -> void:
	sensitivity.value_changed.connect(_on_value_changed)
	sensitivity_y.value_changed.connect(_on_value_changed)
	strength.value_changed.connect(_on_value_changed)
	invert.toggled.connect(_on_toggled)
	automatic.toggled.connect(_on_toggled)
	form.get_node("Buttons/Defaults").pressed.connect(reset_defaults)
	form.get_node("Buttons/Cancel").pressed.connect(cancel)
	form.get_node("Buttons/Save").pressed.connect(save_and_close)
	controls_button = Button.new()
	controls_button.text = "Controls…"
	controls_button.custom_minimum_size.y = 36
	controls_button.pressed.connect(open_controls)
	form.add_child(controls_button)
	input_panel = InputSettingsPanel.new()
	$Center/Panel/Margin.add_child(input_panel)
	input_panel.finished.connect(_close_controls)
	input_panel.applied.connect(_apply_inputs)

func configure_inputs(preferences: InputPreferences, path: String, notice: String = "") -> void:
	_input_preferences = preferences
	_input_path = path
	_input_notice = notice

func open_controls() -> void:
	if _input_preferences == null:
		return
	form.hide()
	input_panel.open_for(_input_preferences, _input_path, _input_notice)

func _close_controls() -> void:
	form.show()
	controls_button.grab_focus()

func _apply_inputs(preferences: InputPreferences) -> void:
	_input_preferences = preferences
	_input_notice = ""
	input_applied.emit(preferences)

func open_for(rig: BotOrbitCamera, path: String, notice: String = "") -> void:
	_rig = rig
	_path = path
	_original = CameraPreferences.from_rig(rig)
	input_panel.hide()
	form.show()
	_fill(_original)
	message.text = notice
	show()
	sensitivity.grab_focus()

func _fill(values: CameraPreferences) -> void:
	_display_values = values
	sensitivity.set_value_no_signal(values.sensitivity_x / 0.003)
	sensitivity_y.set_value_no_signal(values.sensitivity_y / 0.003)
	_display_axes = Vector2(sensitivity.value, sensitivity_y.value)
	strength.set_value_no_signal(values.recenter_speed)
	invert.set_pressed_no_signal(values.invert_y)
	automatic.set_pressed_no_signal(values.auto_recenter)
	_refresh_labels()

func _values() -> CameraPreferences:
	var result := CameraPreferences.new()
	result.sensitivity_x = sensitivity.value * 0.003
	result.sensitivity_y = sensitivity_y.value * 0.003
	# An unrelated setting must not round a loaded custom axis to the slider step.
	if is_equal_approx(sensitivity.value, _display_axes.x):
		result.sensitivity_x = _display_values.sensitivity_x
	if is_equal_approx(sensitivity_y.value, _display_axes.y):
		result.sensitivity_y = _display_values.sensitivity_y
	result.invert_y = invert.button_pressed
	result.auto_recenter = automatic.button_pressed
	result.recenter_speed = strength.value
	return result

func _refresh_labels() -> void:
	form.get_node("Sensitivity/Value").text = "%.2fx" % sensitivity.value
	form.get_node("SensitivityY/Value").text = "%.2fx" % sensitivity_y.value
	form.get_node("Strength/Value").text = "%.1f" % strength.value
	strength.editable = automatic.button_pressed
	form.get_node("Strength").modulate.a = 1.0 if automatic.button_pressed else 0.5
	strength.focus_mode = Control.FOCUS_ALL if automatic.button_pressed else Control.FOCUS_NONE
	var navigation: Array[Control] = [sensitivity, sensitivity_y, invert, automatic]
	if automatic.button_pressed:
		navigation.append(strength)
	navigation.append_array([form.get_node("Buttons/Defaults"),
		form.get_node("Buttons/Cancel"), form.get_node("Buttons/Save"), controls_button])
	for index: int in range(navigation.size()):
		var control := navigation[index]
		var previous := navigation[posmod(index - 1, navigation.size())]
		var next := navigation[(index + 1) % navigation.size()]
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)

func _on_value_changed(_value: float) -> void:
	_preview()

func _on_toggled(_value: bool) -> void:
	_preview()

func _preview() -> void:
	_refresh_labels()
	if is_instance_valid(_rig):
		_values().apply_to(_rig)
	message.text = "Unsaved changes"

func reset_defaults() -> void:
	_fill(CameraPreferences.new())
	_preview()

func cancel() -> void:
	if not visible:
		return
	if input_panel.visible:
		input_panel.cancel()
		return
	if is_instance_valid(_rig):
		_original.apply_to(_rig)
	hide()
	closed.emit(false)

func save_and_close() -> void:
	var values := _values()
	var error := values.save_file(_path)
	if error != OK:
		message.text = "Could not save. Changes are temporary; retry or cancel."
		return
	if is_instance_valid(_rig):
		values.apply_to(_rig)
	hide()
	closed.emit(true)
