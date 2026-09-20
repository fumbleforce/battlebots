class_name InputSettingsPanel
extends VBoxContainer
## Draft edits remain local until Save. The enclosing camera modal owns navigation.
signal finished
signal applied(preferences: InputPreferences)
var draft: InputPreferences
var capture_action: StringName = &""
var binding_buttons: Dictionary = {}
var mode: CheckButton
var message: Label
var save_button: Button
var _path: String
var _scroll: ScrollContainer
var _text_scale: float = 1.0

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 26)
	add_child(title)
	var help := Label.new()
	help.text = "Select a binding, then press a key or mouse button.\nEscape cancels capture. Duplicate bindings are rejected."
	help.add_theme_font_size_override("font_size", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(484, 300)
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(rows)
	for action: StringName in InputPreferences.ACTIONS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label := Label.new()
		label.text = InputPreferences.LABELS[action]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(180, 34)
		button.pressed.connect(begin_capture.bind(action))
		row.add_child(button)
		binding_buttons[action] = button
	mode = CheckButton.new()
	mode.text = "Toggle primary weapon (otherwise hold)"
	mode.toggled.connect(func(value: bool) -> void: draft.toggle_primary = value)
	add_child(mode)
	var explanation := Label.new()
	explanation.text = "Toggle: press to activate, press again to release/fire.\nSecondary, menus and focus loss cancel activation."
	explanation.add_theme_font_size_override("font_size", 14)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(explanation)
	message = Label.new()
	message.custom_minimum_size = Vector2(0, 42)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_color_override("font_color", Color(1, 0.73, 0.28))
	add_child(message)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	var defaults := Button.new()
	defaults.text = "Reset defaults"
	defaults.pressed.connect(reset_defaults)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel & back"
	cancel_button.pressed.connect(cancel)
	save_button = Button.new()
	save_button.text = "Save & back"
	save_button.pressed.connect(save)
	for button: Button in [defaults, cancel_button, save_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40
		buttons.add_child(button)
	var navigation: Array[Control] = []
	for action: StringName in InputPreferences.ACTIONS:
		navigation.append(binding_buttons[action])
	navigation.append_array([mode, defaults, cancel_button, save_button])
	for index: int in range(navigation.size()):
		var control := navigation[index]
		control.focus_next = control.get_path_to(navigation[(index + 1) % navigation.size()])
		control.focus_previous = control.get_path_to(navigation[posmod(index - 1, navigation.size())])
	get_window().focus_exited.connect(cancel_capture)
	apply_text_scale(_text_scale)
	hide()

func apply_text_scale(factor: float) -> void:
	_text_scale = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	if not is_node_ready():
		return
	MenuTextScale.apply(self, _text_scale)
	_scroll.custom_minimum_size = Vector2(0, 240.0)
	for button: Button in binding_buttons.values():
		button.custom_minimum_size = Vector2(200.0 * _text_scale, 34.0 * _text_scale)

func open_for(preferences: InputPreferences, path: String, notice: String = "") -> void:
	draft = preferences.clone()
	_path = path
	capture_action = &""
	_refresh()
	message.text = notice
	show()
	binding_buttons[InputPreferences.ACTIONS[0]].grab_focus()
	_scroll.scroll_vertical = 0

func _refresh() -> void:
	for action: StringName in InputPreferences.ACTIONS:
		binding_buttons[action].text = draft.label_for(action)
	mode.set_pressed_no_signal(draft.toggle_primary)

func begin_capture(action: StringName) -> void:
	if not capture_action.is_empty():
		cancel_capture()
	capture_action = action
	binding_buttons[action].text = "Press a control…"
	message.text = "Binding %s. Escape cancels." % InputPreferences.LABELS[action]

func cancel_capture() -> void:
	if capture_action.is_empty():
		return
	var action := capture_action
	capture_action = &""
	_refresh()
	message.text = "Binding unchanged."
	if is_visible_in_tree() and get_window().has_focus():
		binding_buttons[action].grab_focus()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or capture_action.is_empty():
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	get_viewport().set_input_as_handled()
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		cancel_capture()
		return
	var error := draft.try_bind(capture_action, event)
	if not error.is_empty():
		message.text = error
		return
	var action := capture_action
	capture_action = &""
	_refresh()
	message.text = "Unsaved binding. Save to apply."
	binding_buttons[action].grab_focus()

func reset_defaults() -> void:
	capture_action = &""
	draft = InputPreferences.new()
	_refresh()
	message.text = "Defaults are a draft until saved."

func cancel() -> void:
	if not capture_action.is_empty():
		cancel_capture()
		return
	hide()
	finished.emit()

func save() -> void:
	if not capture_action.is_empty():
		return
	var error := draft.save_file(_path)
	if error != OK:
		message.text = "Could not save controls. Retry or cancel."
		return
	applied.emit(draft.clone())
	hide()
	finished.emit()
