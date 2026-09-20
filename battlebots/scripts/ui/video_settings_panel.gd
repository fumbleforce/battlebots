class_name VideoSettingsPanel
extends PanelContainer
signal applied(preferences: VideoPreferences)
signal finished(saved: bool)
var mode_choice: OptionButton
var resolution_choice: OptionButton
var vsync_button: CheckButton
var message: Label
var apply_button: Button
var keep_button: Button
var revert_button: Button
var defaults_button: Button
var cancel_button: Button
var apply_display: Callable
var capture_display: Callable
var capture_state: Callable
var restore_state: Callable
var _display_state: Dictionary = {}
var _original: VideoPreferences
var _actual: VideoPreferences
var _pending: VideoPreferences
var _path := ""
var _opened := false
var deadline_ms := 0
const MODES := ["windowed", "borderless", "fullscreen"]

func _ready() -> void:
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	theme_type_variation = &"PanelDark"
	custom_minimum_size = Vector2(560, 0)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var title := Label.new()
	title.text = "VIDEO SETTINGS"
	title.theme_type_variation = &"Heading"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	mode_choice = _choice(column, "Display mode", ["Windowed", "Borderless fullscreen", "Fullscreen"])
	resolution_choice = _choice(column, "Window resolution", [])
	for size: Vector2i in [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160)]:
		_add_resolution(size)
	mode_choice.item_selected.connect(func(_index: int) -> void: resolution_choice.disabled = mode_choice.selected != 0)
	vsync_button = CheckButton.new()
	vsync_button.text = "V-Sync"
	column.add_child(vsync_button)
	message = Label.new()
	message.custom_minimum_size = Vector2(500, 64)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var row := HBoxContainer.new()
	column.add_child(row)
	defaults_button = _button(row, "Defaults", reset_defaults)
	cancel_button = _button(row, "Cancel", cancel)
	apply_button = _button(row, "Apply", preview_changes)
	keep_button = _button(row, "Keep", confirm)
	revert_button = _button(row, "Revert", revert)
	_confirming(false)
	hide()

func _choice(parent: Node, caption: String, options: Array) -> OptionButton:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	var choice := OptionButton.new()
	choice.custom_minimum_size.y = 42
	for text: String in options:
		choice.add_item(text)
	parent.add_child(choice)
	return choice

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(92, 42)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _add_resolution(size: Vector2i) -> void:
	resolution_choice.add_item("%d × %d" % [size.x, size.y])
	resolution_choice.set_item_metadata(resolution_choice.item_count - 1, size)

func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)

func open_for(preferences: VideoPreferences, path: String = VideoPreferences.DEFAULT_PATH) -> void:
	if deadline_ms > 0:
		revert()
	_original = preferences.copy()
	_actual = capture_display.call() if capture_display.is_valid() else VideoPreferences.capture()
	_display_state = capture_state.call() if capture_state.is_valid() else VideoPreferences.capture_display_state()
	_path = path
	_opened = true
	_fill(_original)
	message.text = "Fullscreen uses your display’s native size. Apply previews changes for 15 seconds. V-Sync availability depends on the renderer."
	show()
	mode_choice.grab_focus()

func _fill(preferences: VideoPreferences) -> void:
	mode_choice.select(MODES.find(preferences.mode))
	var index := -1
	for item in range(resolution_choice.item_count):
		if resolution_choice.get_item_metadata(item) == preferences.resolution:
			index = item
	if index < 0:
		_add_resolution(preferences.resolution)
		index = resolution_choice.item_count - 1
	resolution_choice.select(index)
	resolution_choice.disabled = preferences.mode != "windowed"
	vsync_button.set_pressed_no_signal(preferences.vsync)

func _apply(preferences: VideoPreferences, vsync_only := false) -> Error:
	return apply_display.call(preferences) if apply_display.is_valid() else preferences.apply(vsync_only)

func preview_changes() -> void:
	if not _opened or deadline_ms > 0:
		return
	_pending = VideoPreferences.new()
	_pending.mode = MODES[mode_choice.selected]
	_pending.resolution = resolution_choice.get_item_metadata(resolution_choice.selected)
	_pending.vsync = vsync_button.button_pressed
	var vsync_only := _pending.mode == _original.mode and _pending.resolution == _original.resolution
	var error := _apply(_pending, vsync_only)
	if error != OK:
		message.text = "Display settings could not be applied: " + error_string(error)
		return
	deadline_ms = Time.get_ticks_msec() + 15000
	_confirming(true)
	keep_button.grab_focus()

func _confirming(active: bool) -> void:
	keep_button.visible = active
	revert_button.visible = active
	apply_button.visible = not active
	defaults_button.visible = not active
	cancel_button.visible = not active
	mode_choice.disabled = active
	resolution_choice.disabled = active or mode_choice.selected != 0
	vsync_button.disabled = active

func _process(_delta: float) -> void:
	if deadline_ms <= 0:
		return
	if Time.get_ticks_msec() >= deadline_ms:
		revert()
	else:
		message.text = "Keep these display settings? Reverting in %d seconds." % ceili((deadline_ms - Time.get_ticks_msec()) / 1000.0)

func confirm() -> void:
	if deadline_ms <= 0:
		return
	if Time.get_ticks_msec() >= deadline_ms:
		revert()
		return
	var error := _pending.save_file(_path)
	if error != OK:
		revert()
		message.text = "Could not save video settings. Previous display restored."
		return
	deadline_ms = 0
	_confirming(false)
	_opened = false
	applied.emit(_pending.copy())
	hide()
	finished.emit(true)

func revert() -> void:
	if deadline_ms <= 0:
		return
	_restore_display()
	deadline_ms = 0
	_confirming(false)
	_fill(_original)
	message.text = "Previous display settings restored."
	apply_button.grab_focus()

func reset_defaults() -> void:
	if deadline_ms == 0:
		_fill(VideoPreferences.new())

func cancel() -> void:
	revert()
	_opened = false
	hide()
	finished.emit(false)

func _input(event: InputEvent) -> void:
	if _opened and visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if deadline_ms > 0:
			revert()
		else:
			cancel()

func _exit_tree() -> void:
	if deadline_ms > 0 and _actual != null:
		_restore_display()

func _restore_display() -> void:
	if restore_state.is_valid():
		restore_state.call(_display_state.duplicate(true))
	elif not _display_state.is_empty():
		VideoPreferences.restore_display_state(_display_state)
	else:
		_apply(_actual)
