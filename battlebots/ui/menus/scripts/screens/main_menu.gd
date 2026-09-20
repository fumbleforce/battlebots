extends MenuScreen

var _text_factor := 1.0
var featured_vehicle: FeaturedVehicle

func apply_text_scale(factor: float) -> void:
	_text_factor = clampf(factor, 1.0, 1.5)
	preload("res://scripts/ui/menu_text_scale.gd").apply(self, _text_factor)
	if is_instance_valid(featured_vehicle): featured_vehicle.apply_text_scale(_text_factor)
	_layout_navigation()

func _layout_navigation() -> void:
	if not is_node_ready():
		return
	# Reserve space for every action; wider windows add breathing room, not larger type.
	$Layout/Columns/Left.custom_minimum_size.x = 850
	$Layout/Columns/Left.add_theme_constant_override("separation", 20)
	$Layout/Columns/Left/Logo.add_theme_constant_override("separation", 0)
	%Play.custom_minimum_size.y = 78 if _text_factor > 1.0 else 66
	for item: Button in [%PlayOnline, %JoinGame, %Practice, %Garage, %Settings, %Quit]:
		item.custom_minimum_size.y = 78 if _text_factor > 1.0 else 66


func _ready() -> void:
	allow_back = false
	super()
	%Play.pressed.connect(MenuRouter.open_host)
	%JoinGame.pressed.connect(MenuRouter.open_join)
	%Practice.pressed.connect(MenuRouter.start_practice)
	%Garage.pressed.connect(MenuRouter.goto.bind("garage"))
	%Settings.pressed.connect(MenuRouter.open_settings)
	%Quit.pressed.connect(get_tree().quit)
	%CustomizeLink.pressed.connect(MenuRouter.goto.bind("customize"))
	var nav := %Play.get_parent()
	nav.move_child(%JoinGame, 1)
	nav.move_child(%Practice, 2)
	var online := Button.new()
	online.name = "PlayOnline"
	online.text = "PLAY ONLINE"
	online.theme_type_variation = &"MenuItemPrimary"
	online.custom_minimum_size.y = 82
	online.pressed.connect(MenuRouter.open_online)
	nav.add_child(online)
	online.owner = self
	online.unique_name_in_owner = true
	nav.move_child(online, 0)
	%Play.get_node("Pad/Row/Text/Label").text = "HOST LAN GAME"
	%Play.get_node("Pad/Row/Text/Label").add_theme_font_size_override("font_size", 36)
	%Play.get_node("Pad/Row/Text/Caption").text = "Local network · Direct IP"
	%JoinGame.text = "JOIN LAN GAME"
	# Preserve compact action rows at the default text size.
	%Play.custom_minimum_size.y = 94
	for item: Button in [%JoinGame, %Practice, %Garage, %Settings, %Quit]:
		item.custom_minimum_size.y = 64

	%ProfileLevel.text = "LOCAL PILOT"
	%XpBar.hide()
	%GarageCaption.text = "%d bots · Customize" % PlayerProfile.bots.size()
	featured_vehicle = FeaturedVehicle.new()
	featured_vehicle.name = "FeaturedVehicle"
	$Layout/Columns/Right/BotRow/ActiveBot/Col.add_child(featured_vehicle)
	featured_vehicle.selection_requested.connect(_select_vehicle)
	PlayerProfile.inventory_changed.connect(_refresh_vehicle)
	_refresh_vehicle()
	# The main menu is a fixed composition: all actions remain visible at 150%.
	$Layout.add_theme_constant_override("margin_top", 48)
	$Layout.add_theme_constant_override("margin_bottom", 32)
	$Layout/Columns/Left/Logo/Row/Wordmark.text = "BATTLEBOTS"
	$Layout/Columns/Left/Logo/Row/Wordmark.add_theme_font_size_override("font_size", 82)
	$Layout/Columns/Left/Logo/Row/Wordmark.add_theme_constant_override("line_spacing", 0)
	$Layout/Columns/Left/Logo/Row/Gear.custom_minimum_size = Vector2(50, 50)
	$Layout/Columns/Left/Logo/TaglinePad.add_theme_constant_override("margin_left", 69)
	$Layout/Columns/Left/Logo/TaglinePad/Tagline.add_theme_font_size_override("font_size", 20)
	%Play.theme_type_variation = &"MenuItem"
	%Play.get_node("Pad/Row/Text/Label").add_theme_font_size_override("font_size", 34)
	%Play.get_node("Pad/Row/Text/Caption").add_theme_font_size_override("font_size", 16)
	%Play.get_node("Pad/Row/Text/Label").add_theme_color_override("font_color", MenuData.TEXT)
	%Play.get_node("Pad/Row/Text/Caption").add_theme_color_override("font_color", MenuData.TEXT2)
	%Play.get_node("Pad/Row/PlayIcon").self_modulate = MenuData.TEXT
	%Play.get_node("Pad/Row/Enter").hide()
	for item: Button in [%JoinGame, %Practice, %Garage, %Settings, %Quit]:
		item.add_theme_font_size_override("font_size", 34)
		if item.has_node("CaptionPad"):
			item.get_node("CaptionPad").get_child(0).add_theme_font_size_override("font_size", 16)
		_soft_hover(item)
	_soft_hover(%Play)
	online.add_theme_font_size_override("font_size", 40)
	resized.connect(_layout_navigation)
	_layout_navigation()
	online.grab_focus()
	var arenas := Button.new()
	arenas.name = "ArenaChoice"
	arenas.text = "ARENA  /  " + ("LUNAR OUTPOST" if preload("res://scripts/arena/arena_scenery.gd").load_choice() == "moon" else "THE FOUNDRY")
	arenas.theme_type_variation = &"GhostButton"
	arenas.custom_minimum_size.y = 54
	arenas.add_theme_font_size_override("font_size",24)
	arenas.pressed.connect(MenuRouter.goto.bind("arena_select"))
	$Layout/Columns/Right.add_child(arenas)
	arenas.owner = self
	arenas.unique_name_in_owner = true

func _soft_hover(button: Button) -> void:
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	hover.content_margin_left = 34
	hover.content_margin_right = 34
	hover.content_margin_top = 8
	hover.content_margin_bottom = 8
	for state: String in ["hover", "pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, hover)

func _select_vehicle(index: int, _draft: Dictionary) -> void:
	if index < 0 or index >= PlayerProfile.loadouts.size(): return
	PlayerProfile.active_bot = index
	_refresh_vehicle()

func _refresh_vehicle() -> void:
	if not is_instance_valid(featured_vehicle): return
	featured_vehicle.render(PlayerProfile.loadouts, PlayerProfile.active_bot, true, "Selected for your next game")
	%GarageCaption.text = "%d bots · Customize" % PlayerProfile.bots.size()
