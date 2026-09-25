extends PanelContainer
## Settings hub GAME page (#85). Emits detached live drafts; cancel restores
## the saved preferences. No class_name (see game_preferences.gd).
const GAME_PREFERENCES := preload("res://scripts/ui/game_preferences.gd")
signal preview_changed(preferences: RefCounted)
signal applied(preferences: RefCounted)
signal finished(saved: bool)
var damage_numbers_toggle: CheckButton
var save_button: Button
var cancel_button: Button
var message: Label
var _original: RefCounted
var _path := ""
var _opened := false

func _ready() -> void:
	var page := SettingsStyle.page(self,"Game","In-match feedback. Changes apply immediately and can be cancelled.")
	page.tabs.hide()
	SettingsStyle.section(page.content,"Combat feedback")
	var row := SettingsStyle.row(page.content,"Damage numbers","Show the damage of each hit as numbers spraying out of the struck bot.")
	damage_numbers_toggle = CheckButton.new()
	damage_numbers_toggle.text = "Enabled"
	damage_numbers_toggle.custom_minimum_size = Vector2(390,48)
	damage_numbers_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(damage_numbers_toggle)
	damage_numbers_toggle.toggled.connect(func(_pressed: bool) -> void: _preview())
	message = page.message
	SettingsStyle.button(page.footer,"Restore defaults",func() -> void:
		damage_numbers_toggle.set_pressed_no_signal(GAME_PREFERENCES.create().show_damage_numbers)
		_preview())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.footer.add_child(spacer)
	cancel_button = SettingsStyle.button(page.footer,"Cancel",cancel)
	save_button = SettingsStyle.button(page.footer,"Save changes",save_and_close,true)
	SettingsStyle.focus_cycle([damage_numbers_toggle,cancel_button,save_button])
	hide()

func open_for(preferences: RefCounted, path: String) -> void:
	if _opened:
		preview_changed.emit(_original.copy())
	_original = preferences.copy()
	_path = path
	_opened = true
	damage_numbers_toggle.set_pressed_no_signal(preferences.show_damage_numbers)
	message.text = "" if preferences.load_error == OK else "Settings could not be loaded. Defaults are shown; Save replaces the file."
	show()
	damage_numbers_toggle.grab_focus()

func _values() -> RefCounted:
	var result := GAME_PREFERENCES.create()
	result.show_damage_numbers = damage_numbers_toggle.button_pressed
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
