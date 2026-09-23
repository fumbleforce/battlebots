class_name GarageTestDriveEntry
extends Button
## Caller-owned navigation for a detached, unsaved workshop draft.

var _callback: Callable
var _registry := ContentRegistry.new()
var _draft: Dictionary = {}
var _has_draft := false
var _valid := false
var _allowed := false


static func install(screen: Control, callback: Callable) -> GarageTestDriveEntry:
	var entry := GarageTestDriveEntry.new()
	entry.name = "TestDrive"
	entry.text = "TEST DRIVE"
	entry.tooltip_text = "Drive the current unsaved build locally. This does not save the build."
	entry.add_theme_font_size_override("font_size", 20)
	entry.custom_minimum_size.y = 48
	entry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	entry.disabled = true
	entry._callback = callback
	entry.pressed.connect(entry._activate)
	# Screens may reserve a slot for the entry beside the loadout it drives.
	var slot: Container = screen.get_node_or_null("%TestDriveSlot") as Container
	if slot != null:
		entry.theme_type_variation = &"GhostButton"
		entry.icon = preload("res://ui/menus/icons/play.svg")
		entry.add_theme_constant_override("icon_max_width", 18)
		entry.add_theme_constant_override("h_separation", 12)
		entry.add_theme_font_size_override("font_size", 26)
		entry.custom_minimum_size.y = 68
		entry.size_flags_vertical = Control.SIZE_FILL
		slot.add_child(entry)
		return entry
	var footer: HBoxContainer = screen.get_node("Layout/Footer/Row")
	footer.add_theme_constant_override("separation", 12)
	footer.add_child(entry)
	var save_button: Button = screen.get_node_or_null("%Save") as Button
	if save_button != null:
		entry.theme_type_variation = &"GhostButton"
		entry.custom_minimum_size = Vector2(224, save_button.custom_minimum_size.y)
		entry.add_theme_font_size_override("font_size", 30)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("#202c39")
		normal.border_color = Color("#f5b82e")
		normal.set_border_width_all(2)
		normal.set_corner_radius_all(5)
		entry.add_theme_stylebox_override("normal", normal)
		footer.move_child(entry, save_button.get_index())
	return entry


func render(draft: Dictionary, allowed: bool) -> void:
	if not _has_draft or draft != _draft:
		_draft = draft.duplicate(true)
		_has_draft = true
		_valid = _registry.validate(_draft).valid
	_allowed = allowed
	disabled = not _allowed or not _valid


func apply_text_scale(factor: float) -> void:
	MenuTextScale.apply(self, factor)


func _activate() -> void:
	if disabled or not _allowed or not _valid or not is_visible_in_tree(): return
	if _callback.is_valid(): _callback.call()
