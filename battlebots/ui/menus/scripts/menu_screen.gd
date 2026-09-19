class_name MenuScreen
extends Control
## Base for every menu screen: back navigation, header profile/scrap readouts.
## Nodes are looked up by unique name (%Name) and are all optional.

## Set false on screens where Esc must not navigate (main menu, loading).
@export var allow_back := true


func _ready() -> void:
	var back_btn := get_node_or_null("%Back") as Button
	if back_btn:
		back_btn.pressed.connect(MenuRouter.back)
	if has_node("%ProfileName"):
		(%ProfileName as Label).text = PlayerProfile.player_name
	_update_scrap(PlayerProfile.scrap)
	PlayerProfile.scrap_changed.connect(_update_scrap)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_W, KEY_S, KEY_A, KEY_D]:
		var focus := get_viewport().gui_get_focus_owner()
		if focus and not focus is LineEdit and not focus is TextEdit:
			var next := focus.find_prev_valid_focus() if event.physical_keycode in [KEY_W, KEY_A] else focus.find_next_valid_focus()
			if next:
				next.grab_focus()
				get_viewport().set_input_as_handled()
	if allow_back and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		MenuRouter.back()


func _update_scrap(value: int) -> void:
	if has_node("%ScrapAmount"):
		(%ScrapAmount as Label).text = "—"
	if has_node("%ProfileMeta"):
		(%ProfileMeta as Label).text = "LOCAL PILOT · ALL PARTS AVAILABLE"


## Sets which step of Mode/Bot/Arena/Lobby is current (1-4) in a header step tracker.
func set_step(step: int) -> void:
	if not has_node("%Steps"):
		return
	var i := 1
	for chip in %Steps.get_children():
		var lbl := chip.get_child(0) as Label
		if i < step:
			chip.theme_type_variation = &"StepDone"
			lbl.add_theme_color_override("font_color", MenuData.TEXT)
		elif i == step:
			chip.theme_type_variation = &"StepActive"
			lbl.add_theme_color_override("font_color", MenuData.INK)
		else:
			chip.theme_type_variation = &"StepTodo"
			lbl.add_theme_color_override("font_color", MenuData.MUTED)
		i += 1


func tab_input(event: InputEvent) -> int:
	## Returns -1 / +1 for the optional "menu_tab_prev" / "menu_tab_next" actions (Q / E).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			return -1
		if event.physical_keycode == KEY_E:
			return 1
	if InputMap.has_action("menu_tab_prev") and event.is_action_pressed("menu_tab_prev"):
		return -1
	if InputMap.has_action("menu_tab_next") and event.is_action_pressed("menu_tab_next"):
		return 1
	return 0


static func clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
