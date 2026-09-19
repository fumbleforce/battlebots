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


func _ready() -> void:
	super()
	$Layout/Footer/Row/Hint1.hide()
	var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
	var name_edit := LineEdit.new()
	name_edit.name = "BuildName"
	name_edit.text = bot.name
	name_edit.placeholder_text = "Build name (1–48 characters)"
	name_edit.max_length = 48
	%Save.get_parent().add_child(name_edit)
	name_edit.custom_minimum_size.x = 240
	name_edit.tooltip_text = "Saved build name"
	name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_edit.custom_minimum_size.y = 48
	for control: Node in find_children("Rotate","Button",true,false):
		control.disabled = true
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
	%Eyebrow.text = current.name + " · " + current.cls
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
	var state := PlayerProfile.item_state(_tab, cat, cur)
	%SelName.text = cur.name
	%PreviewName.text = cur.name
	var fallback := ("Applies to the %s layer." if _tab == "paint" else "Decal for the %s.") % cat.label.to_lower()
	%SelDesc.text = cur.get("desc", fallback)
	if not current.valid: %SelDesc.text += "\nBuild invalid: " + "; ".join(current.reasons)
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

	var is_parts := _tab == "parts"
	%Stats.visible = is_parts and current.valid
	%CosmeticNote.visible = not is_parts
	if is_parts:
		var base: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot].stats
		var d: Dictionary = cur.get("d", {})
		var bars := %Stats.get_children()
		for k in MenuData.STAT_KEYS.size():
			var s: String = MenuData.STAT_KEYS[k]
			bars[k].set_stat(s, base[s], int(d.get(s, 0)))


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
	var result: Error = PlayerProfile.save_active(%Save.get_parent().get_node("BuildName").text)
	if result == OK:
		%SelDesc.text = "Build saved to this computer."
	else:
		%SelDesc.text = "; ".join(PlayerProfile.errors)
