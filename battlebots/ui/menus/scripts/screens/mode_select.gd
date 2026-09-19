extends MenuScreen

const MODE_CARD := preload("res://ui/menus/components/mode_card.tscn")
const PLAYABLE := ["training", "duel", "team"]

func _ready() -> void:
	super()
	set_step(1)
	if MenuRouter.match_setup.mode not in PLAYABLE:
		MenuRouter.match_setup.mode = "team"
	var group := ButtonGroup.new()
	# Keep the supplied four-card layout. Future modes are grouped in the last card.
	for m: Dictionary in MenuData.MODES:
		if m.id not in PLAYABLE and m.id != "ranked":
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
	_select(MenuData.mode_by_id(MenuRouter.match_setup.mode))
	%Next.pressed.connect(MenuRouter.goto.bind("garage"))
	%Invite.disabled = true
	%Invite.text = "INVITES UNAVAILABLE"
	%CustomLobby.text = "LAN / DIRECT IP"
	%CustomLobby.pressed.connect(func() -> void:
		_select(MenuData.mode_by_id("team"))
		MenuRouter.goto("garage"))

func _select(m: Dictionary) -> void:
	if m.get("id", "") not in PLAYABLE or not m.get("enabled", false):
		return
	MenuRouter.match_setup.mode = m.id
	%Rules.text = str(m.rules) + "\nQuick play, ranked, 5v5 and FFA are not available in this build."
