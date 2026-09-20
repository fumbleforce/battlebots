extends MenuScreen

const MODE_CARD := preload("res://ui/menus/components/mode_card.tscn")
const PLAYABLE := ["duel", "team", "5v5", "ffa"]
var capacity_choice: OptionButton

func apply_text_scale(factor: float) -> void:
	preload("res://scripts/ui/menu_text_scale.gd").apply(self, factor)
	%Cards.columns = 2 if factor > 1.0 else 4
	%Rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for card: Control in %Cards.get_children():
		card.custom_minimum_size.y = 660 if factor > 1.0 else 542
		card.get_node("Inner/Col/Body/Col/Title").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.get_node("Selected").offset_left = -240 if factor > 1.0 else -180

func _ready() -> void:
	var body_style := StyleBoxEmpty.new()
	for side: String in ["left", "right", "top", "bottom"]:
		body_style.set("content_margin_" + side, $Layout/Body.get_theme_constant("margin_" + side))
	$Layout/Body.add_theme_stylebox_override("panel", body_style)
	super()
	%Steps.hide()
	$Layout/Header/Row/TitleBox/Eyebrow.text = "HOST GAME"
	$Layout/Header/Row/TitleBox/Title.text = "CHOOSE GAME MODE"
	if MenuRouter.match_setup.mode not in PLAYABLE:
		MenuRouter.match_setup.mode = "duel"
	var group := ButtonGroup.new()
	# Only host decisions belong here. Join and Practice have direct main routes.
	for m: Dictionary in MenuData.MODES:
		if m.id not in PLAYABLE:
			continue
		var card := MODE_CARD.instantiate()
		%Cards.add_child(card)
		card.setup(m)
		card.button_group = group
		card.disabled = m.id not in PLAYABLE or not m.get("enabled", false)
		card.tooltip_text = "Not available in this build" if card.disabled else ""
		card.pressed.connect(_select.bind(m))
		if m.id == MenuRouter.match_setup.mode:
			card.button_pressed = true
			card.grab_focus.call_deferred()
	capacity_choice = OptionButton.new()
	capacity_choice.name = "FfaCapacity"
	capacity_choice.custom_minimum_size = Vector2(250, 54)
	capacity_choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	capacity_choice.tooltip_text = "Maximum players; FFA can start with four when everyone present is ready"
	for count: int in range(4, 9):
		capacity_choice.add_item("UP TO %d PLAYERS" % count, count)
	capacity_choice.select(clampi(int(MenuRouter.match_setup.capacity), 4, 8) - 4)
	capacity_choice.item_selected.connect(func(index: int) -> void: MenuRouter.match_setup.capacity = capacity_choice.get_item_id(index))
	%Next.get_parent().add_child(capacity_choice)
	%Next.get_parent().move_child(capacity_choice, %Next.get_index())
	_select(MenuData.mode_by_id(MenuRouter.match_setup.mode))
	%Next.text = "CONTINUE"
	%Next.pressed.connect(MenuRouter.goto.bind("lobby"))
	%Invite.get_parent().get_parent().hide()

func _select(m: Dictionary) -> void:
	if m.get("id", "") not in PLAYABLE or not m.get("enabled", false):
		return
	MenuRouter.match_setup.mode = m.id
	capacity_choice.visible = m.id == "ffa"
	%Rules.text = str(m.rules) + "\nThe Foundry · Selected bot: " + str(PlayerProfile.bots[PlayerProfile.active_bot].name) + "\nYou can change your bot in the lobby."
