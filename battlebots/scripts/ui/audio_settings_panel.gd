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
	var page := SettingsStyle.page(self,"Audio","Set your mix. Volume changes preview immediately; Cancel restores your saved levels.")
	page.tabs.hide()
	SettingsStyle.section(page.content,"Volume mix")
	var descriptions := {"master":"Overall game volume.","music":"Menu and arena music.","effects":"Motors, weapons and impacts.","ui":"Menu feedback and interface sounds.","announcements":"Arena announcements and match calls.","ambience":"Crowd and arena background sound."}
	for key: String in AudioPreferences.DEFAULTS:
		var row := SettingsStyle.row(page.content,key.capitalize(),descriptions.get(key,"Adjust this audio channel."))
		var line := HBoxContainer.new()
		line.custom_minimum_size.x = 480
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(line)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.custom_minimum_size = Vector2(320,42)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = key.capitalize() + " volume"
		line.add_child(slider)
		var amount := SettingsStyle.label(line,"100%",22,SettingsStyle.ACCENT)
		amount.custom_minimum_size.x = 80
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sliders[key] = slider
		value_labels[key] = amount
		slider.value_changed.connect(func(_value: float) -> void: _preview())
	var mute_row := SettingsStyle.row(page.content,"Mute all audio","Silence every channel without changing your volume mix.")
	mute_button = CheckButton.new()
	mute_button.text = "Enabled"
	mute_button.toggled.connect(func(_value: bool) -> void: _preview())
	mute_row.add_child(mute_button)
	message = page.message
	defaults_button = SettingsStyle.button(page.footer,"Restore defaults",reset_defaults)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.footer.add_child(spacer)
	cancel_button = SettingsStyle.button(page.footer,"Cancel",cancel)
	save_button = SettingsStyle.button(page.footer,"Save changes",save_and_close,true)
	SettingsStyle.focus_cycle(sliders.values() + [mute_button,defaults_button,cancel_button,save_button])
	hide()

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self,factor)

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
