class_name CameraSettingsPanel
extends Control

signal closed(saved: bool)
@onready var form: VBoxContainer = $Center/Panel/Margin/Form
@onready var sensitivity: HSlider = $Center/Panel/Margin/Form/Sensitivity/Slider
@onready var invert: CheckButton = $Center/Panel/Margin/Form/Invert
@onready var automatic: CheckButton = $Center/Panel/Margin/Form/Automatic
@onready var strength: HSlider = $Center/Panel/Margin/Form/Strength/Slider
@onready var message: Label = $Center/Panel/Margin/Form/Message
var _rig: BotOrbitCamera
var _path: String
var _original: CameraPreferences

func _ready() -> void:
	sensitivity.value_changed.connect(_on_value_changed)
	strength.value_changed.connect(_on_value_changed)
	invert.toggled.connect(_on_toggled)
	automatic.toggled.connect(_on_toggled)
	form.get_node("Buttons/Defaults").pressed.connect(reset_defaults)
	form.get_node("Buttons/Cancel").pressed.connect(cancel)
	form.get_node("Buttons/Save").pressed.connect(save_and_close)

func open_for(rig: BotOrbitCamera, path: String, notice: String = "") -> void:
	_rig = rig
	_path = path
	_original = CameraPreferences.from_rig(rig)
	_fill(_original)
	message.text = notice
	show()
	sensitivity.grab_focus()

func _fill(values: CameraPreferences) -> void:
	sensitivity.set_value_no_signal(values.sensitivity / 0.003)
	strength.set_value_no_signal(values.recenter_speed)
	invert.set_pressed_no_signal(values.invert_y)
	automatic.set_pressed_no_signal(values.auto_recenter)
	_refresh_labels()

func _values() -> CameraPreferences:
	var result := CameraPreferences.new()
	result.sensitivity = sensitivity.value * 0.003
	result.invert_y = invert.button_pressed
	result.auto_recenter = automatic.button_pressed
	result.recenter_speed = strength.value
	return result

func _refresh_labels() -> void:
	form.get_node("Sensitivity/Value").text = "%.2fx" % sensitivity.value
	form.get_node("Strength/Value").text = "%.1f" % strength.value
	strength.editable = automatic.button_pressed
	form.get_node("Strength").modulate.a = 1.0 if automatic.button_pressed else 0.5

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
