extends Control
## F6 workshop fixture. Local disposable draft; no profile or session dependencies.
var preview: GarageBotPreview
var _registry := ContentRegistry.new()
var _draft: Dictionary

func _ready() -> void:
	_draft = _registry.duelist()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "GARAGE PREVIEW · INDEPENDENT DEVELOPMENT SCENE"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var instructions := Label.new()
	instructions.text = "Select a chassis, weapon and paint. Drag to rotate; wheel or + / − to zoom.\nFocus the preview for arrow-key rotation and Home to reset. Changes stay in this scene."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(instructions)
	var selectors := HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 16)
	column.add_child(selectors)
	for category: String in ["chassis", "weapon"]:
		var choices: Array[String] = []
		for id: String in _registry.parts:
			if _registry.parts[id].category == category: choices.append(id)
		_add_selector(selectors, category, choices, _draft.parts[category])
	_add_selector(selectors, "paint", ["cyan", "orange", "white", "red"], _draft.cosmetics.paint)
	var reset := Button.new()
	reset.text = "Reset view"
	selectors.add_child(reset)
	reset.pressed.connect(func() -> void: preview.reset_view())
	var frame := Control.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(frame)
	preview = GarageBotPreview.new()
	preview.show_loadout(_draft)
	frame.add_child(preview)

func _add_selector(parent: HBoxContainer, category: String, ids: Array[String], selected: String) -> void:
	var label := Label.new()
	label.text = category.capitalize()
	parent.add_child(label)
	var picker := OptionButton.new()
	picker.name = category.capitalize() + "Selector"
	picker.custom_minimum_size.x = 170
	for id: String in ids: picker.add_item(id.replace("_", " ").capitalize())
	picker.select(ids.find(selected))
	parent.add_child(picker)
	picker.item_selected.connect(func(index: int) -> void:
		if category == "paint": _draft.cosmetics.paint = ids[index]
		else: _draft.parts[category] = ids[index]
		preview.show_loadout(_draft))
