extends MenuScreen
## The public service owns membership, admission and cleanup; this panel shows its state.
var service_override: PublicServiceClient
var service: PublicServiceClient
var quick_button: Button
var create_button: Button
var join_button: Button
var cancel_button: Button
var back_button: Button
var copy_button: Button
var code_input: LineEdit
var status_label: Label
var region_label: Label
var code_label: Label
var actions: HBoxContainer
var state_heading: Label
var header_panel: PanelContainer

func apply_text_scale(factor: float) -> void:
	preload("res://scripts/ui/menu_text_scale.gd").apply(self, factor)
	if is_instance_valid(header_panel):
		header_panel.custom_minimum_size.y = 180 if factor > 1.0 else 130

func _ready() -> void:
	allow_back = false
	super()
	service = service_override if is_instance_valid(service_override) else MenuRouter.host.public_service
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var header := panel(layout, &"HeaderBar")
	header_panel = header
	header.custom_minimum_size.y = 130
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 32)
	header.add_child(header_row)
	back_button = button(header_row, "BACK", back)
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title := VBoxContainer.new()
	title.custom_minimum_size.x = 620
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_row.add_child(title)
	label(title, "MULTIPLAYER · 1V1 DUELS", 18, &"EyebrowAmber")
	label(title, "PLAY ONLINE", 53, &"Heading")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var badge := label(header_row, "1V1 / FIRST TO TWO", 24, &"Subheading")
	badge.custom_minimum_size.x = 300
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 90)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	layout.add_child(margin)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	margin.add_child(body)
	# Three parallel ways to join a duel, with every action visible together.
	actions = HBoxContainer.new()
	actions.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 18)
	body.add_child(actions)
	var quick_col := card(actions, "PUBLIC MATCH", "QUICK PLAY", "Find an opponent for a 1v1 duel. Choose your bot and ready up in the lobby.")
	quick_button = button(quick_col, "QUICK PLAY · 1V1", quick_play)
	quick_button.theme_type_variation = &"PrimaryButton"
	var host_col := card(actions, "PRIVATE MATCH", "CHALLENGE A FRIEND", "Create a private 1v1 game and share its code with your opponent.")
	create_button = button(host_col, "CREATE 1V1 GAME", create_room)
	create_button.theme_type_variation = &"GhostButton"
	var join_col := card(actions, "HAVE AN INVITE?", "JOIN A FRIEND", "Enter the eight-character code your friend shared.")
	var join_row := VBoxContainer.new()
	join_row.add_theme_constant_override("separation", 16)
	join_col.add_child(join_row)
	code_input = LineEdit.new()
	code_input.placeholder_text = "GAME CODE"
	code_input.tooltip_text = "Eight-character game code"
	code_input.max_length = 8
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_input.custom_minimum_size.x = 220
	code_input.text_submitted.connect(func(_text: String) -> void: join_room())
	join_row.add_child(code_input)
	join_button = button(join_row, "JOIN GAME", join_room)
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status_panel := panel(body, &"PanelGlass")
	body.move_child(status_panel, actions.get_index())
	status_panel.size_flags_vertical = Control.SIZE_FILL
	var status_col := VBoxContainer.new()
	status_col.add_theme_constant_override("separation", 15)
	status_panel.add_child(status_col)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 32)
	status_col.add_child(status_row)
	var state_col := VBoxContainer.new()
	state_col.custom_minimum_size.x = 460
	state_col.add_theme_constant_override("separation", 10)
	status_row.add_child(state_col)
	state_heading = label(state_col, "", 24, &"EyebrowAmber")
	region_label = label(state_col, "", 22, &"Muted")
	status_label = label(status_row, "", 29)
	status_label.focus_mode = Control.FOCUS_ALL
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 24)
	status_col.add_child(code_row)
	code_label = label(code_row, "", 40, &"Heading")
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button = button(code_row, "COPY CODE", func() -> void: DisplayServer.clipboard_set(str(service.membership.get("code", ""))))
	copy_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var footer := panel(layout, &"FooterBar")
	footer.custom_minimum_size.y = 108
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 24)
	footer.add_child(footer_row)
	var hint := label(footer_row, "Choose your bot and ready up in the lobby.", 24, &"Muted")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel_button = button(footer_row, "CANCEL", cancel_online)
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	cancel_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	service.changed.connect(refresh)
	refresh()
	(quick_button if not quick_button.disabled else back_button).grab_focus()

func panel(parent: Node, variation: StringName) -> PanelContainer:
	var item := PanelContainer.new()
	item.theme_type_variation = variation
	parent.add_child(item)
	return item

func card(parent: Node, eyebrow: String, heading: String, description: String) -> VBoxContainer:
	var item := panel(parent, &"PanelBox")
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	item.add_child(col)
	label(col, eyebrow, 18, &"EyebrowAmber")
	label(col, heading, 38, &"Heading")
	var detail := label(col, description, 25, &"Muted")
	detail.custom_minimum_size.y = 74
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return col

func label(parent: Node, text: String, font_size: int, variation: StringName = &"Body") -> Label:
	var item := Label.new()
	item.text = text
	item.theme_type_variation = variation
	item.add_theme_font_size_override("font_size", font_size)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item)
	return item

func button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	item.custom_minimum_size.y = 64
	item.theme_type_variation = &"GhostButton"
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.pressed.connect(action)
	parent.add_child(item)
	return item

func quick_play() -> void:
	if service.can_start():
		service.quick_play()

func create_room() -> void:
	service.create_private("teams", 2)

func join_room() -> void:
	if service.can_start():
		service.join_code(code_input.text)

func refresh() -> void:
	status_label.text = service.message
	if service.state == "idle" and service.available():
		status_label.text = "Find an opponent or play a private duel with a friend."
	state_heading.text = {"idle": "READY TO PLAY" if service.available() else "ONLINE UNAVAILABLE", "failed": "CONNECTION NEEDS ATTENTION", "requesting": "CONTACTING ONLINE SERVICE", "waiting": "WAITING FOR YOUR OPPONENT", "starting": "PREPARING THE ARENA", "ready": "CONNECTING TO YOUR GAME", "connected": "GAME CONNECTED", "canceling": "LEAVING GAME"}.get(service.state, "ONLINE STATUS")
	region_label.text = "REGION · " + (service.region if not service.region.is_empty() else "Assigned by the online service")
	var available := service.can_start()
	quick_button.disabled = not available
	create_button.disabled = not available
	join_button.disabled = not available
	code_input.editable = available
	var actions_were_visible := actions.visible
	actions.visible = service.state in ["idle", "failed"] and not service.can_cancel()
	var code := str(service.membership.get("code", ""))
	if service.state == "waiting" and code.is_empty():
		state_heading.text = "FINDING YOUR OPPONENT"
	code_label.text = "FRIEND CODE: " + code if not code.is_empty() else ""
	code_label.visible = not code.is_empty()
	copy_button.visible = not code.is_empty()
	cancel_button.visible = service.can_cancel() or service.state == "canceling"
	cancel_button.disabled = service.state == "canceling"
	var focused := get_viewport().gui_get_focus_owner()
	if service.state == "failed":
		status_label.grab_focus()
	elif actions.visible and not actions_were_visible and available:
		quick_button.grab_focus()
	elif focused == null or not focused.is_visible_in_tree() or (focused is BaseButton and focused.disabled):
		(cancel_button if cancel_button.visible and not cancel_button.disabled else back_button).grab_focus()

func cancel_online() -> void:
	if is_instance_valid(service_override):
		service.cancel()
	else:
		MenuRouter.host.cancel_online()

func back() -> void:
	cancel_online()
	MenuRouter.goto("main", false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()
	else:
		super(event)
