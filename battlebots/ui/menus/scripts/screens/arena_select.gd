extends MenuScreen

const ARENA_TILE := preload("res://ui/menus/components/arena_tile.tscn")
const HAZARD_TEX := preload("res://ui/menus/art/hazard_stripe.png")


func _ready() -> void:
	super()
	set_step(3)
	var bot: Dictionary = PlayerProfile.bots[MenuRouter.match_setup.bot]
	%Eyebrow.text = "STEP 3 OF 4 · %s · %s" % [MenuData.mode_by_id(MenuRouter.match_setup.mode).title, bot.name]
	var group := ButtonGroup.new()
	for i in MenuData.ARENAS.size():
		var tile := ARENA_TILE.instantiate()
		%Tiles.add_child(tile)
		tile.setup(MenuData.ARENAS[i])
		tile.button_group = group
		tile.pressed.connect(_select.bind(i))
		if i == MenuRouter.match_setup.arena:
			tile.button_pressed = true
			tile.grab_focus.call_deferred()
	_select(MenuRouter.match_setup.arena)
	%Next.text = "START PRACTICE" if MenuRouter.match_setup.mode == "training" else "CONTINUE TO LOBBY"
	%Next.pressed.connect(_next)


func _select(i: int) -> void:
	MenuRouter.match_setup.arena = i
	var a: Dictionary = MenuData.ARENAS[i]
	var img: Texture2D = a.get("image")
	%DetailImage.texture = img
	%DetailImage.visible = img != null
	%DetailPlaceholder.visible = img == null
	%DetailPlaceholderLabel.text = a.get("art", "ARENA ART")
	%DetailSize.text = a.size
	%DetailName.text = a.name
	clear_children(%Hazards)
	for h in a.hazards:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var sw := TextureRect.new()
		sw.texture = HAZARD_TEX
		sw.stretch_mode = TextureRect.STRETCH_TILE
		sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sw.custom_minimum_size = Vector2(22, 22)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lbl := Label.new()
		lbl.text = h
		lbl.theme_type_variation = &"Body"
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", MenuData.TEXT)
		row.add_child(sw)
		row.add_child(lbl)
		%Hazards.add_child(row)

func _next() -> void:
	if MenuRouter.match_setup.mode == "training":
		MenuRouter.start_practice()
	else:
		MenuRouter.goto("lobby")
