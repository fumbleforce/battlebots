extends MenuScreen
## Parts / Paint / Decals customization. Selection is local; equip/buy goes through PlayerProfile.

const CATEGORY_ROW := preload("res://ui/menus/components/category_row.tscn")
const ITEM_TILE := preload("res://ui/menus/components/item_tile.tscn")
const TABS := ["parts", "paint", "decals"]
const SLOT_HEADINGS := {"parts": "PART SLOTS", "paint": "PAINT LAYERS", "decals": "DECAL SPOTS"}

var _tab := "parts"
var _cat := {"parts": 0, "paint": 0, "decals": 0}
var _item := {}
var _refocus := ""
var name_edit: LineEdit
var undo_button: Button
var redo_button: Button
var build_preview: GarageBotPreview
var comparison_panel: GarageComparisonPanel


func _ready() -> void:
	super()
	build_preview = GarageBotPreview.new()
	var frame := %BotImage.get_parent()
	%BotImage.hide()
	frame.add_child(build_preview)
	frame.move_child(build_preview, 1)
	frame.get_node("PreviewChip").hide()
	frame.custom_minimum_size.y = 300
	comparison_panel = GarageComparisonPanel.new()
	comparison_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var preview_column := frame.get_parent()
	preview_column.add_child(comparison_panel)
	preview_column.move_child(comparison_panel, %Stats.get_index())
	$Layout/Footer/Row/Hint1.hide()
	var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	name_edit = LineEdit.new()
	name_edit.name = "BuildName"
	name_edit.text = bot.name
	name_edit.placeholder_text = "Build name (1–48 characters)"
	name_edit.max_length = 48
	%Save.get_parent().add_child(name_edit)
	name_edit.custom_minimum_size.x = 240
	name_edit.tooltip_text = "Saved build name"
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.custom_minimum_size.y = 48
	name_edit.tooltip_text = "Enter a name, then press Enter or leave this field to apply it to the draft. Save writes it to this computer."
	name_edit.text_submitted.connect(func(_value: String) -> void: _commit_name())
	name_edit.focus_exited.connect(_commit_name)
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 12)
	$Layout/Body/Row/Preview/Col.add_child(history)
	undo_button = Button.new()
	undo_button.text = "UNDO"
	undo_button.tooltip_text = "Undo build edit (Ctrl+Z). Saved files change only when you Save."
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_child(undo_button)
	undo_button.pressed.connect(PlayerProfile.undo_edit)
	redo_button = Button.new()
	redo_button.text = "REDO"
	redo_button.tooltip_text = "Redo build edit (Ctrl+Y or Ctrl+Shift+Z)."
	redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history.add_child(redo_button)
	redo_button.pressed.connect(PlayerProfile.redo_edit)
	for control: Node in find_children("Rotate","Button",true,false):
		control.tooltip_text = "Reset build preview view"
		control.pressed.connect(build_preview.reset_view)
	%Eyebrow.text = "%s · %s" % [bot.name, bot.cls]
	%BotImage.texture = bot.image
	var group := ButtonGroup.new()
	var tab_buttons := [%TabParts, %TabPaint, %TabDecals]
	for i in TABS.size():
		tab_buttons[i].button_group = group
		tab_buttons[i].pressed.connect(_set_tab.bind(TABS[i]))
	%TabParts.button_pressed = true
	%Action.pressed.connect(_on_action)
	%Save.pressed.connect(_save_build)
	%ShopLink.pressed.connect(MenuRouter.goto.bind("shop"))
	PlayerProfile.inventory_changed.connect(_refresh)
	_refocus = "item"
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed \
		and not event.alt_pressed and not event.meta_pressed:
		var focus := get_viewport().gui_get_focus_owner()
		if not focus is LineEdit and not focus is TextEdit:
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if code in [KEY_Z, KEY_Y]:
				if code == KEY_Y or event.shift_pressed:
					PlayerProfile.redo_edit()
				else:
					PlayerProfile.undo_edit()
				get_viewport().set_input_as_handled()
				return
	super(event)
	var dir := tab_input(event)
	if dir != 0:
		var i := wrapi(TABS.find(_tab) + dir, 0, TABS.size())
		[%TabParts, %TabPaint, %TabDecals][i].button_pressed = true
		_set_tab(TABS[i])


func _set_tab(t: String) -> void:
	_tab = t
	_refresh()


func _refresh() -> void:
	var current: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	build_preview.show_loadout(PlayerProfile.loadouts[PlayerProfile.active_bot])
	if not name_edit.has_focus(): name_edit.text = current.name
	undo_button.disabled = not PlayerProfile.can_undo()
	redo_button.disabled = not PlayerProfile.can_redo()
	%Eyebrow.text = current.name + " · " + ("EQUIPPED DRAFT" if current.valid else "REPAIR REQUIRED")
	%Save.disabled = not current.valid
	var cats: Array = PlayerProfile.catalogue[_tab]
	var ci: int = _cat[_tab]
	var cat: Dictionary = cats[ci]
	var key := "%s:%d" % [_tab, ci]
	var ii: int = _item.get(key, 0)
	%SlotHeading.text = SLOT_HEADINGS[_tab]

	clear_children(%Categories)
	var cg := ButtonGroup.new()
	for i in cats.size():
		var row := CATEGORY_ROW.instantiate()
		%Categories.add_child(row)
		row.setup(cats[i].label, PlayerProfile.equipped_name(_tab, cats[i]))
		row.button_group = cg
		row.button_pressed = i == ci
		row.pressed.connect(func():
			_cat[_tab] = i
			_refocus = "cat"
			_refresh())
		if _refocus == "cat" and i == ci:
			row.grab_focus.call_deferred()

	clear_children(%Items)
	var ig := ButtonGroup.new()
	var owned_count := 0
	for i in cat.items.size():
		var it: Dictionary = cat.items[i]
		var st := PlayerProfile.item_state(_tab, cat, it)
		if st == "eq" or st == "own":
			owned_count += 1
		var tile := ITEM_TILE.instantiate()
		%Items.add_child(tile)
		tile.setup(it, st)
		tile.button_group = ig
		tile.button_pressed = i == ii
		tile.pressed.connect(func():
			_item[key] = i
			_refocus = "item"
			_refresh())
		if _refocus == "item" and i == ii:
			tile.grab_focus.call_deferred()
	_refocus = ""

	%CatLabel.text = cat.label
	%Count.text = "%d / %d available" % [owned_count, cat.items.size()]
	var cur: Dictionary = cat.items[ii]
	var comparison_slot: String = cat.slot if _tab == "parts" else "chassis"
	var selected_parts: Variant = PlayerProfile.loadouts[PlayerProfile.active_bot].get("parts", {})
	var candidate_id := ""
	if _tab == "parts": candidate_id = str(cur.id)
	elif selected_parts is Dictionary: candidate_id = str(selected_parts.get("chassis", ""))
	var comparison := GarageComparison.compare(PlayerProfile.registry, PlayerProfile.loadouts[PlayerProfile.active_bot], comparison_slot, candidate_id)
	comparison_panel.render(comparison, str(cur.name), _tab == "parts")
	var state := PlayerProfile.item_state(_tab, cat, cur)
	%SelName.text = cur.name
	%PreviewName.text = cur.name
	var fallback := ("Applies to the %s layer." if _tab == "paint" else "Decal for the %s.") % cat.label.to_lower()
	%SelDesc.text = cur.get("desc", fallback)
	if not current.valid: %SelDesc.text += "\nBuild invalid: " + "; ".join(current.reasons)
	if _tab == "parts" and not comparison.proposed.valid:
		%SelDesc.text += "\nProposed build: " + "; ".join(comparison.proposed.reasons)
	match state:
		"eq":
			%Action.text = "EQUIPPED"
			%Action.disabled = true
		"lock":
			%Action.text = "UNAVAILABLE"
			%Action.disabled = true
		"own":
			%Action.text = "EQUIP"
			%Action.disabled = false
		_:
			%Action.text = "UNAVAILABLE"
			%Action.disabled = true

	%Stats.hide()
	%CosmeticNote.hide()


func _on_action() -> void:
	var cat: Dictionary = PlayerProfile.catalogue[_tab][_cat[_tab]]
	var cur: Dictionary = cat.items[_item.get("%s:%d" % [_tab, _cat[_tab]], 0)]
	_refocus = "item"
	match PlayerProfile.item_state(_tab, cat, cur):
		"own":
			PlayerProfile.equip(_tab, cat, cur)
		"buy":
			PlayerProfile.equip(_tab, cat, cur)


func _save_build() -> void:
	_commit_name()
	var result: Error = PlayerProfile.save_active(%Save.get_parent().get_node("BuildName").text)
	if result == OK:
		%SelDesc.text = "Build saved to this computer."
	else:
		%SelDesc.text = "; ".join(PlayerProfile.errors)

func _commit_name() -> void:
	if is_inside_tree():
		PlayerProfile.rename_draft(name_edit.text)
