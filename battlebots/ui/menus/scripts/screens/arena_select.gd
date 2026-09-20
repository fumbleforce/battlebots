extends MenuScreen

const ARENA_TILE := preload("res://ui/menus/components/arena_tile.tscn")
const HAZARD_TEX := preload("res://ui/menus/art/hazard_stripe.png")
var _text_scale := 1.0
const CHOICE = preload("res://scripts/arena/arena_scenery.gd")

func apply_text_scale(factor: float) -> void:
	_text_scale = factor
	preload("res://scripts/ui/menu_text_scale.gd").apply(self, factor)
	%Tiles.columns = 2
	%DetailName.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%Eyebrow.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	$Layout/Header/Row/TitleBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Layout/Body/Row/Details/Col/ArtBox.custom_minimum_size.y = 180 if factor > 1.0 else 300
	for tile: Control in %Tiles.get_children():
		if not tile.has_meta("base_tile_height"):
			tile.set_meta("base_tile_height", tile.custom_minimum_size.y)
		tile.custom_minimum_size.y = maxf(float(tile.get_meta("base_tile_height")), 340 * factor)


func _ready() -> void:
	var body_style := StyleBoxEmpty.new()
	for side: String in ["left", "right", "top", "bottom"]:
		body_style.set("content_margin_" + side, $Layout/Body.get_theme_constant("margin_" + side))
	$Layout/Body.add_theme_stylebox_override("panel", body_style)
	super()
	%Steps.hide()
	$Layout/Footer/Row/Note2.hide()
	$Layout/Body/Row/Details/Col/Text/Col/HazardsBlock/Label.text = "ENVIRONMENT"
	$Layout/Header/Row/Sep.hide()
	$Layout/Header/Row/TitleBox/Title.text = "PRACTICE" if MenuRouter.arena_intent == "practice" else "CHOOSE ARENA"
	%Eyebrow.text = "CHOOSE YOUR ARENA" if MenuRouter.arena_intent == "practice" else "LOCAL ARENA"
	$Layout/Header/Row/Profile.hide()
	MenuRouter.match_setup.arena = CHOICE.IDS.find(CHOICE.load_choice())
	%Tiles.columns = 2
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
	%Next.text = "START PRACTICE" if MenuRouter.arena_intent == "practice" else "USE ARENA"
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
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preload("res://scripts/ui/menu_text_scale.gd").apply(%Hazards, _text_scale)

func _next() -> void:
	var error := CHOICE.save_choice(CHOICE.IDS[MenuRouter.match_setup.arena])
	if error != OK:
		%Eyebrow.text = "Could not save arena: " + error_string(error)
		return
	if MenuRouter.arena_intent == "practice":
		MenuRouter.start_practice()
	else:
		MenuRouter.back()
