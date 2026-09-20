extends MenuScreen

var _text_factor := 1.0
var featured_vehicle: FeaturedVehicle

func _ready() -> void:
	allow_back = false
	super()
	%ProfileName.tooltip_text = PlayerProfile.player_name
	%PlayOnline.pressed.connect(MenuRouter.open_online)
	%Play.pressed.connect(MenuRouter.open_host)
	%JoinGame.pressed.connect(MenuRouter.open_join)
	%Practice.pressed.connect(MenuRouter.open_practice)
	%Garage.pressed.connect(MenuRouter.goto.bind("garage"))
	%Settings.pressed.connect(MenuRouter.open_settings)
	%Quit.pressed.connect(get_tree().quit)
	%CustomizeLink.pressed.connect(MenuRouter.goto.bind("customize"))
	for button: Button in [%Play, %JoinGame, %Practice, %Garage, %Settings, %Quit]:
		_soft_hover(button)
	featured_vehicle = FeaturedVehicle.new()
	featured_vehicle.name = "FeaturedVehicle"
	featured_vehicle.set_compact(true)
	featured_vehicle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	%ShowcaseContent.add_child(featured_vehicle)
	featured_vehicle.selection_requested.connect(_select_vehicle)
	PlayerProfile.inventory_changed.connect(_refresh_vehicle)
	_refresh_vehicle()
	resized.connect(_layout_navigation)
	_layout_navigation()
	%PlayOnline.grab_focus()

func apply_text_scale(factor: float) -> void:
	_text_factor = clampf(factor, 1.0, 1.5)
	MenuTextScale.apply(self, _text_factor)
	if is_instance_valid(featured_vehicle):
		featured_vehicle.apply_text_scale(_text_factor)
	_layout_navigation()

func _layout_navigation() -> void:
	if not is_node_ready():
		return
	%Navigation.custom_minimum_size.x = 660 if _text_factor > 1.0 else 590
	%PlayOnline.custom_minimum_size.y = 100 if _text_factor > 1.0 else 90
	for button: Button in [%Practice, %Garage, %Play, %JoinGame]:
		button.custom_minimum_size.y = 82 if _text_factor > 1.0 else 72
	# Keep the showcase close to the actions even on wide/tall windows.
	%Showcase.custom_minimum_size = Vector2(820, 660 if _text_factor > 1.0 else 610)

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
	if index < 0 or index >= PlayerProfile.loadouts.size():
		return
	PlayerProfile.active_bot = index
	_refresh_vehicle()

func _refresh_vehicle() -> void:
	if is_instance_valid(featured_vehicle):
		featured_vehicle.render(PlayerProfile.loadouts, PlayerProfile.active_bot)
