class_name AudioSettingsPanel
extends PanelContainer
## Live bus preview; only a successful Save publishes a new preferences object.
signal finished(saved: bool)
signal applied(preferences: AudioPreferences)
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var mute_button: CheckButton
var message: Label
var save_button: Button
var cancel_button: Button
var defaults_button: Button
var _original: AudioPreferences
var _path := ""
var _opened := false

func _ready() -> void:
	custom_minimum_size.x = 480
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var heading := Label.new()
	heading.text = "Audio"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	var navigation: Array[Control] = []
	for key: String in AudioPreferences.DEFAULTS:
		var row := VBoxContainer.new()
		column.add_child(row)
		var title := Label.new()
		title.text = key.capitalize()
		row.add_child(title)
		var line := HBoxContainer.new()
		row.add_child(line)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.custom_minimum_size = Vector2(300, 30)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = title.text + " volume"
		line.add_child(slider)
		var amount := Label.new()
		amount.custom_minimum_size.x = 56
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(amount)
		sliders[key] = slider
		value_labels[key] = amount
		slider.value_changed.connect(func(_value: float) -> void: _preview())
		navigation.append(slider)
	mute_button = CheckButton.new()
	mute_button.text = "Mute all audio"
	mute_button.toggled.connect(func(_value: bool) -> void: _preview())
	column.add_child(mute_button)
	message = Label.new()
	message.custom_minimum_size.y = 48
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 15)
	column.add_child(message)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	defaults_button = _button(buttons, "Defaults", reset_defaults)
	cancel_button = _button(buttons, "Cancel", cancel)
	save_button = _button(buttons, "Save", save_and_close)
	navigation.append_array([mute_button, defaults_button, cancel_button, save_button])
	for index: int in range(navigation.size()):
		var control := navigation[index]
		control.focus_next = control.get_path_to(navigation[(index + 1) % navigation.size()])
		control.focus_previous = control.get_path_to(navigation[posmod(index - 1, navigation.size())])
	hide()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = 40
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(callback)
	parent.add_child(result)
	return result

func open_for(preferences: AudioPreferences, path: String) -> void:
	if _opened:
		_original.apply()
	_original = preferences.copy()
	_path = path
	_opened = true
	_fill(_original)
	message.text = "Adjust volume to preview. Save keeps these settings." if preferences.load_error == OK else "Audio settings could not be loaded. Defaults are shown; Save replaces the file."
	show()
	sliders.master.grab_focus()

func _fill(preferences: AudioPreferences) -> void:
	for key: String in sliders:
		var value: float = preferences.get(key)
		sliders[key].set_value_no_signal(clampf(value, 0, 1) if is_finite(value) else AudioPreferences.DEFAULTS[key])
	mute_button.set_pressed_no_signal(preferences.muted)
	_refresh_labels()

func _values() -> AudioPreferences:
	var result := AudioPreferences.new()
	for key: String in sliders:
		result.set(key, sliders[key].value)
	result.muted = mute_button.button_pressed
	return result

func _refresh_labels() -> void:
	for key: String in value_labels:
		value_labels[key].text = "%d%%" % roundi(sliders[key].value * 100)

func _preview() -> void:
	if not _opened:
		return
	_refresh_labels()
	_values().apply()
	message.text = "Unsaved audio changes"

func reset_defaults() -> void:
	_fill(AudioPreferences.new())
	_preview()

func cancel() -> void:
	if not _opened:
		return
	_original.apply()
	_opened = false
	hide()
	finished.emit(false)

func save_and_close() -> void:
	if not _opened:
		return
	var preferences := _values()
	var error := preferences.save_file(_path)
	if error != OK:
		message.text = "Could not save audio settings (%s). Try again or Cancel." % error_string(error)
		return
	preferences.apply()
	_opened = false
	hide()
	applied.emit(preferences)
	finished.emit(true)

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()

func _exit_tree() -> void:
	if _opened and _original != null:
		_original.apply()
