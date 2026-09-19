extends MenuScreen
## Online intent selection; no fabricated roster or local readiness decisions.
var service: PublicServiceClient
var quick_button: Button
var create_button: Button
var join_button: Button
var cancel_button: Button
var back_button: Button
var copy_button: Button
var mode_choice: OptionButton
var code_input: LineEdit
var status_label: Label
var region_label: Label
var code_label: Label
var actions: VBoxContainer

func _ready() -> void:
	allow_back = false
	super()
	service = MenuRouter.host.public_service
	var background := ColorRect.new()
	background.color = Color("111824")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margins.add_theme_constant_override("margin_" + side, 80)
	add_child(margins)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 22)
	margins.add_child(col)
	label(col, "PLAY ONLINE", 56)
	label(col, "Hosted games — no router setup or tunnel needed.", 28)
	region_label = label(col, "", 24)
	actions = VBoxContainer.new()
	actions.add_theme_constant_override("separation", 18)
	col.add_child(actions)
	quick_button = button(actions, "QUICK PLAY · 2V2 · 4 PLAYERS", service.quick_play)
	label(actions, "OR CREATE A PRIVATE GAME", 25)
	var private_row := HBoxContainer.new()
	private_row.add_theme_constant_override("separation", 20)
	actions.add_child(private_row)
	mode_choice = OptionButton.new()
	mode_choice.custom_minimum_size = Vector2(580, 64)
	mode_choice.add_item("1v1 · 2 players", 2)
	mode_choice.add_item("2v2 · 4 players", 4)
	mode_choice.add_item("5v5 · 10 players", 10)
	for count: int in range(4, 9):
		mode_choice.add_item("Free for all · up to %d players" % count, 100 + count)
	private_row.add_child(mode_choice)
	create_button = button(private_row, "CREATE PRIVATE GAME", create_room)
	label(actions, "OR JOIN A FRIEND", 25)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 20)
	actions.add_child(join_row)
	code_input = LineEdit.new()
	code_input.placeholder_text = "8-character game code"
	code_input.max_length = 8
	code_input.custom_minimum_size = Vector2(580, 64)
	code_input.text_submitted.connect(func(_text: String) -> void: join_room())
	join_row.add_child(code_input)
	join_button = button(join_row, "JOIN GAME", join_room)
	status_label = label(col, "", 30)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var code_row := HBoxContainer.new()
	col.add_child(code_row)
	code_label = label(code_row, "", 40)
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_button = button(code_row, "COPY CODE", func() -> void: DisplayServer.clipboard_set(str(service.membership.get("code", ""))))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	col.add_child(footer)
	cancel_button = button(footer, "CANCEL", cancel_online)
	back_button = button(footer, "BACK", back)
	service.changed.connect(refresh)
	refresh()
	quick_button.grab_focus()

func label(parent: Node, text: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", font_size)
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

func create_room() -> void:
	var id := mode_choice.get_selected_id()
	service.create_private("ffa" if id >= 100 else "teams", id - 100 if id >= 100 else id)

func join_room() -> void:
	service.join_code(code_input.text)

func refresh() -> void:
	status_label.text = service.message
	region_label.text = "Region: " + (service.region if not service.region.is_empty() else "Shown when the service responds")
	var available := service.can_start()
	quick_button.disabled = not available
	create_button.disabled = not available
	join_button.disabled = not available
	mode_choice.disabled = not available
	code_input.editable = available
	actions.visible = service.state in ["idle", "failed"] and not service.can_cancel()
	var code := str(service.membership.get("code", ""))
	code_label.text = "FRIEND CODE: " + code if not code.is_empty() else ""
	copy_button.visible = not code.is_empty()
	cancel_button.visible = service.can_cancel() or service.state == "canceling"
	cancel_button.disabled = service.state == "canceling"
	back_button.text = "BACK TO MAIN MENU"

func cancel_online() -> void:
	MenuRouter.host.cancel_online()

func back() -> void:
	MenuRouter.host.cancel_online()
	MenuRouter.goto("main", false)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back()
