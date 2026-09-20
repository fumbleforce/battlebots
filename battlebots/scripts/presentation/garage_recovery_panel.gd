class_name GarageRecoveryPanel
extends Control
## Explicit local file management; never discards drafts or writes on opening.
var reload_button: Button
var review_button: Button
var restore_button: Button
var close_button: Button
var details: RichTextLabel
var _profile: Node
var _review: Dictionary = {}
var _return_focus: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.04, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 220)
	for edge: String in ["top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 160)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "SAVED BUILDS · FILE RECOVERY"
	heading.add_theme_font_size_override("font_size", 32)
	box.add_child(heading)
	details = RichTextLabel.new()
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_font_size_override("normal_font_size", 24)
	details.focus_mode = Control.FOCUS_ALL
	box.add_child(details)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	box.add_child(actions)
	reload_button = _button(actions, "RELOAD FILE", _reload)
	review_button = _button(actions, "REVIEW BACKUP", _show_review)
	restore_button = _button(actions, "RESTORE BACKUP", _restore)
	close_button = _button(actions, "CLOSE", dismiss)
	hide()

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 64
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 22)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func open(profile: Node) -> void:
	_profile = profile
	_return_focus = get_viewport().gui_get_focus_owner()
	_review.clear()
	show()
	_show_status()
	close_button.grab_focus()

func _show_status(message := "") -> void:
	var recovery := LoadoutStore.new(_profile.save_path).inspect_recovery()
	details.text = message + ("\n\n" if not message.is_empty() else "") + \
		"Reload reads the latest saved builds from this computer. Edited and new drafts stay in the garage as unsaved copies, with Undo/Redo retained. Rename a retained copy before saving if its name already exists.\n\n" + \
		"A backup can be restored only when the main file is missing or unreadable. Review it before confirming; the existing file will be preserved separately.\n\n" + \
		("Backup available for review." if recovery.available else "No restorable backup: " + "; ".join(recovery.errors))
	review_button.disabled = not recovery.available
	review_button.show()
	reload_button.show()
	restore_button.hide()
	close_button.text = "CLOSE"
	_focus_loop()

func _reload() -> void:
	var count: int = _profile.reload_retaining_drafts()
	_review.clear()
	var message := "Reloaded disk builds; retained %d unsaved draft(s). No files were changed." % count
	if not _profile.errors.is_empty(): message += "\n" + "; ".join(_profile.errors)
	_show_status(message)
	close_button.grab_focus()

func _show_review() -> void:
	_review = LoadoutStore.new(_profile.save_path).inspect_recovery()
	if not _review.available:
		_show_status("The backup is no longer available. No files were changed.")
		return
	details.text = "RESTORE THIS BACKUP?\n\nThis replaces the missing or unreadable main file with the reviewed backup. The backup is kept unchanged; an existing main file is preserved separately. Local edited drafts and Undo/Redo are retained.\n\nBackup contains %d saved build(s):\n" % _review.loadouts.size()
	for draft: Variant in _review.loadouts:
		var title := str(draft.get("name", "Unnamed build")).left(48) if draft is Dictionary else "Malformed entry"
		var valid: bool = draft is Dictionary and _profile.registry.validate(draft).valid
		details.text += "• %s — %s\n" % [title, "valid" if valid else "needs repair (preserved)"]
	details.text += "\nCancel leaves both files unchanged."
	reload_button.hide()
	review_button.hide()
	restore_button.show()
	close_button.text = "CANCEL"
	_focus_loop()
	close_button.grab_focus()

func _focus_loop() -> void:
	var controls: Array[Control] = [details]
	for button: Button in [reload_button, review_button, restore_button, close_button]:
		if button.visible and not button.disabled: controls.append(button)
	for index: int in controls.size():
		controls[index].focus_next = controls[index].get_path_to(controls[(index + 1) % controls.size()])
		controls[index].focus_previous = controls[index].get_path_to(controls[(index - 1 + controls.size()) % controls.size()])
		controls[index].focus_neighbor_bottom = controls[index].focus_next
		controls[index].focus_neighbor_right = controls[index].focus_next
		controls[index].focus_neighbor_top = controls[index].focus_previous
		controls[index].focus_neighbor_left = controls[index].focus_previous

func _restore() -> void:
	if _review.is_empty(): return
	var result: Dictionary = _profile.restore_reviewed_backup(_review.token)
	_review.clear()
	if result.error != OK:
		var message := "Restore refused: %s. Review the current files again; your drafts remain in the garage." % error_string(result.error)
		if not result.preserved_path.is_empty(): message += "\nPrevious main file preserved at: " + ProjectSettings.globalize_path(result.preserved_path)
		_show_status(message)
	else:
		var message := "Backup restored. Retained %d unsaved draft(s)." % result.retained
		if not result.preserved_path.is_empty(): message += "\nPrevious main file preserved at: " + ProjectSettings.globalize_path(result.preserved_path)
		_show_status(message)
	close_button.grab_focus()

func dismiss() -> void:
	_review.clear()
	hide()
	if is_instance_valid(_return_focus) and _return_focus.is_inside_tree() and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()
