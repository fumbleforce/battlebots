extends MenuScreen
## Browse available functional parts. Gameplay power is never sold.
const TABS := ["upgrades", "parts", "cosmetics"]
var _tab := "upgrades"
func _ready() -> void:
	super()
	var group := ButtonGroup.new()
	var buttons := [%TabUpgrades,%TabParts,%TabCosmetics]
	for index: int in TABS.size():
		buttons[index].button_group = group
		buttons[index].pressed.connect(_set_tab.bind(TABS[index]))
	%TabUpgrades.text = "BUILD RULES"
	%TabUpgrades.button_pressed = true
	%CustomizeLink.pressed.connect(MenuRouter.goto.bind("customize"))
	%Play.pressed.connect(MenuRouter.goto.bind("mode_select"))
	%BotChips.hide()
	%Deals.get_parent().get_parent().hide()
	var items: GridContainer = %ItemsView
	var parent := items.get_parent()
	parent.remove_child(items)
	var scroll := ScrollContainer.new()
	scroll.name = "CatalogueScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	scroll.add_child(items)
	items.owner = self
	items.unique_name_in_owner = true
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_tab("upgrades")
func _unhandled_input(event: InputEvent) -> void:
	super(event)
	var direction := tab_input(event)
	if direction != 0:
		var index := wrapi(TABS.find(_tab)+direction,0,TABS.size())
		[%TabUpgrades,%TabParts,%TabCosmetics][index].button_pressed = true
		_set_tab(TABS[index])
func _set_tab(tab: String) -> void:
	_tab = tab
	for index: int in TABS.size():
		[%TabUpgrades,%TabParts,%TabCosmetics][index].button_pressed = TABS[index] == tab
	%UpgradesView.visible = tab == "upgrades"
	%ItemsView.visible = tab != "upgrades"
	%ItemsView.get_parent().visible = tab != "upgrades"
	clear_children(%UpgradeGrid)
	clear_children(%ItemsView)
	if tab == "upgrades":
		var bot: Dictionary = PlayerProfile.bots[PlayerProfile.active_bot]
		var validation := PlayerProfile.registry.validate(PlayerProfile.loadouts[PlayerProfile.active_bot])
		_entry(%UpgradeGrid,bot.name.to_upper(),bot.cls,bot.image)
		if validation.valid:
			var stats: Dictionary = validation.stats
			_entry(%UpgradeGrid,"BUILD BUDGET","MASS   %.0f / 120 kg\nINSTALLED POWER   %.0f / 100\n\nAll functional parts are available. No currency or paid power upgrades." % [stats.mass,stats.power])
			_entry(%UpgradeGrid,"DURABILITY","CORE   %.0f HP\nARMOR PLATE   %.0f integrity\nDAMAGE REDUCTION   %.0f%%" % [stats.core,stats.plate_integrity,float(stats.reduction)*100])
			_entry(%UpgradeGrid,"DRIVE & RESOURCES","TOP SPEED   %.0f m/s\nBATTERY   %.0f\nCOOLING   %.0f / s\nRECOVERY   %.1f s" % [stats.speed,stats.battery,stats.cooling,stats.recovery_seconds])
		else:
			_entry(%UpgradeGrid,"BUILD NEEDS REPAIR","; ".join(validation.reasons))
	else:
		for category: Dictionary in PlayerProfile.catalogue["parts" if tab == "parts" else "paint"]:
			for item: Dictionary in category.items:
				var card := preload("res://ui/menus/components/shop_item_card.tscn").instantiate()
				%ItemsView.add_child(card)
				var data: Dictionary = {"name":item.name,"kind":category.label,"info":item.desc,"price":0}
				if item.has("swatch"): data.swatch = item.swatch
				card.setup(data,true,false)
				card.get_node("%Buy").text = "AVAILABLE IN CUSTOMIZE"

func _entry(parent: Node, title: String, description: String, art: Texture2D = null) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"PanelBox"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"Heading"
	heading.add_theme_font_size_override("font_size",30)
	box.add_child(heading)
	if art:
		var image := TextureRect.new()
		image.texture = art
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.custom_minimum_size.y = 140
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(image)
	var body := Label.new()
	body.text = description
	body.theme_type_variation = &"Body"
	body.add_theme_font_size_override("font_size",22)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 220
	box.add_child(body)
