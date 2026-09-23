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
const GROUPS := [[&"drive_forward", &"drive_reverse", &"steer_left", &"steer_right", &"brake"], [&"nitro", &"jump"], [&"primary", &"secondary", &"recover", &"ping"], [&"camera_recenter", &"camera_zoom_in", &"camera_zoom_out", &"camera_toggle", &"scoreboard"], [&"dev_weapon", &"dev_body", &"dev_drive"], []]
var page_buttons: Array[Button] = []
var controller_guide: GridContainer
var help_text: Label
var page_index := 0
var _footer: Array[Control] = []
var _text_scale: float = 1.0

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 26)
	add_child(title)
	var help := Label.new()
	help_text = help
	help.text = "Select a keyboard/mouse binding, then press an input.\nEscape / B cancels capture. See Controller for gamepad bindings."
	help.add_theme_font_size_override("font_size", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var pages := HFlowContainer.new()
	add_child(pages)
	for title_text: String in ["Driving", "Perks", "Weapons", "Camera & HUD", "Local dev", "Controller"]:
		var page := Button.new()
		page.text = title_text
		page.toggle_mode = true
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.pressed.connect(show_page.bind(page_buttons.size()))
		pages.add_child(page)
		page_buttons.append(page)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(rows)
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
	controller_guide = GridContainer.new()
	controller_guide.columns = 2
	controller_guide.add_theme_constant_override("h_separation", 24)
	controller_guide.add_theme_constant_override("v_separation", 8)
	rows.add_child(controller_guide)
	for entry: String in GamepadInput.GUIDE:
		var label := Label.new()
		label.text = entry
		label.add_theme_font_size_override("font_size", 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controller_guide.add_child(label)
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
	_footer.assign([mode, defaults, cancel_button, save_button])
	show_page(0)
	get_window().focus_exited.connect(cancel_capture)
	apply_text_scale(_text_scale)
	hide()

func apply_text_scale(factor: float) -> void:
	_text_scale = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	if not is_node_ready():
		return
	MenuTextScale.apply(self, _text_scale)
	for button: Button in binding_buttons.values():
		button.custom_minimum_size = Vector2(200.0 * _text_scale, 30.0 * _text_scale)

func show_page(index: int) -> void:
	cancel_capture()
	page_index = clampi(index, 0, GROUPS.size() - 1)
	controller_guide.visible = page_index == GROUPS.size() - 1
	help_text.text = "Standard gamepad layout. Bindings are fixed.\nCamera sensitivity and inversion apply to mouse and right stick." if controller_guide.visible else "Select a keyboard/mouse binding, then press an input.\nEscape / B cancels capture. See Controller for gamepad bindings."
	var navigation: Array[Control] = []
	navigation.append_array(page_buttons)
	for action: StringName in InputPreferences.ACTIONS:
		var button: Button = binding_buttons[action]
		button.get_parent().visible = action in GROUPS[page_index]
		if button.get_parent().visible:
			navigation.append(button)
	for index_value: int in range(page_buttons.size()):
		page_buttons[index_value].set_pressed_no_signal(index_value == page_index)
	navigation.append_array(_footer)
	for index_value: int in range(navigation.size()):
		var control := navigation[index_value]
		control.focus_next = control.get_path_to(navigation[(index_value + 1) % navigation.size()])
		control.focus_previous = control.get_path_to(navigation[posmod(index_value - 1, navigation.size())])
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and is_ancestor_of(focus) and not focus.is_visible_in_tree():
		page_buttons[page_index].grab_focus()

func open_for(preferences: InputPreferences, path: String, notice: String = "") -> void:
	draft = preferences.clone()
	_path = path
	capture_action = &""
	_refresh()
	message.text = notice
	show()
	binding_buttons[InputPreferences.ACTIONS[0]].grab_focus()
	show_page(0)

func _refresh() -> void:
	for action: StringName in InputPreferences.ACTIONS:
		binding_buttons[action].text = draft.label_for(action)
	mode.set_pressed_no_signal(draft.toggle_primary)

func begin_capture(action: StringName) -> void:
	if not capture_action.is_empty():
		cancel_capture()
	for index: int in range(GROUPS.size()):
		if action in GROUPS[index] and index != page_index:
			show_page(index)
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
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_capture()
		return
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
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
