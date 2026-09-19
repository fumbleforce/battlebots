extends MenuScreen

const MODE_CARD := preload("res://ui/menus/components/mode_card.tscn")
const PLAYABLE := ["duel", "team", "5v5", "ffa"]
var capacity_choice: OptionButton

func _ready() -> void:
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
