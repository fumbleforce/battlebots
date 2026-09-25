extends PanelContainer
## Settings hub GAME page (#85). Emits detached live drafts; cancel restores
## the saved preferences. No class_name (see game_preferences.gd).
const GAME_PREFERENCES := preload("res://scripts/ui/game_preferences.gd")
signal preview_changed(preferences: RefCounted)
signal applied(preferences: RefCounted)
signal finished(saved: bool)
var damage_numbers_toggle: CheckButton
var player_numbers_toggle: CheckButton
var speedometer_toggle: CheckButton
var speed_value_toggle: CheckButton
var save_button: Button
var cancel_button: Button
var message: Label
var _original: RefCounted
var _path := ""
var _opened := false

func _ready() -> void:
	var page := SettingsStyle.page(self,"Game","In-match feedback and HUD. Changes apply immediately and can be cancelled.")
	page.tabs.hide()
	SettingsStyle.section(page.content,"Combat feedback")
	damage_numbers_toggle = _toggle(page.content,"Damage numbers","Numbers spray out of other bots for each hit they take.")
	player_numbers_toggle = _toggle(page.content,"Damage numbers on your bot","Numbers spray out of your own bot for each hit you take.")
	SettingsStyle.section(page.content,"HUD")
	speedometer_toggle = _toggle(page.content,"Speedometer","A dial above Integrity shows your speed; nitro adds an outer ring.")
	speed_value_toggle = _toggle(page.content,"Speed in km/h","The dial also shows your actual speed above the share of top speed.")
	message = page.message
	SettingsStyle.button(page.footer,"Restore defaults",func() -> void:
		_set_toggles(GAME_PREFERENCES.create())
		_preview())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.footer.add_child(spacer)
	cancel_button = SettingsStyle.button(page.footer,"Cancel",cancel)
	save_button = SettingsStyle.button(page.footer,"Save changes",save_and_close,true)
	SettingsStyle.focus_cycle([damage_numbers_toggle,player_numbers_toggle,speedometer_toggle,speed_value_toggle,cancel_button,save_button])
	hide()

func open_for(preferences: RefCounted, path: String) -> void:
	if _opened:
		preview_changed.emit(_original.copy())
	_original = preferences.copy()
	_path = path
	_opened = true
	_set_toggles(preferences)
	message.text = "" if preferences.load_error == OK else "Settings could not be loaded. Defaults are shown; Save replaces the file."
	show()
	damage_numbers_toggle.grab_focus()

func _values() -> RefCounted:
	var result := GAME_PREFERENCES.create()
	result.show_damage_numbers = damage_numbers_toggle.button_pressed
	result.show_player_damage_numbers = player_numbers_toggle.button_pressed
	result.show_speedometer = speedometer_toggle.button_pressed
	result.show_speed_value = speed_value_toggle.button_pressed
	return result

func _preview() -> void:
	if not _opened:
		return
	message.text = "Unsaved game changes"
	preview_changed.emit(_values())

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)

func cancel() -> void:
	if not _opened:
		return
	_opened = false
	preview_changed.emit(_original.copy())
	hide()
	finished.emit(false)

func save_and_close() -> void:
	if not _opened:
		return
	var preferences := _values()
	var error: Error = preferences.save_file(_path)
	if error != OK:
		message.text = "Could not save game settings (%s). Try again or Cancel." % error_string(error)
		return
	_opened = false
	hide()
	preview_changed.emit(preferences.copy())
	applied.emit(preferences)
	finished.emit(true)

func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()

func _exit_tree() -> void:
	if _opened and _original != null:
		preview_changed.emit(_original.copy())

func _toggle(parent: Node, caption: String, description: String) -> CheckButton:
	var row := SettingsStyle.row(parent, caption, description)
	var toggle := CheckButton.new()
	toggle.custom_minimum_size = Vector2(390, 48)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(toggle)
	toggle.toggled.connect(func(_pressed: bool) -> void:
		_caption(toggle)
		_preview())
	_caption(toggle)
	return toggle

## The caption states the current value; it used to read "Enabled" either way.
func _caption(toggle: CheckButton) -> void:
	toggle.text = "On" if toggle.button_pressed else "Off"

func _set_toggles(preferences: RefCounted) -> void:
	damage_numbers_toggle.set_pressed_no_signal(preferences.show_damage_numbers)
	player_numbers_toggle.set_pressed_no_signal(preferences.show_player_damage_numbers)
	speedometer_toggle.set_pressed_no_signal(preferences.show_speedometer)
	speed_value_toggle.set_pressed_no_signal(preferences.show_speed_value)
	_caption(damage_numbers_toggle)
	_caption(player_numbers_toggle)
	_caption(speedometer_toggle)
	_caption(speed_value_toggle)
