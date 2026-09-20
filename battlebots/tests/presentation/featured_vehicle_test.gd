extends Node
var failures: Array[String] = []
var requests: Array = []

func _ready() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func settle() -> void:
	for frame: int in 5: await get_tree().process_frame

func run() -> void:
	get_window().size = Vector2i(1280, 720)
	var registry := ContentRegistry.new()
	var choices := [registry.starter(), registry.starter(true), registry.duelist()]
	var original := choices.duplicate(true)
	var featured := FeaturedVehicle.new()
	featured.position = Vector2(40, 40)
	featured.size = Vector2(560, 620)
	featured.render(choices, 0)
	add_child(featured)
	featured.selection_requested.connect(func(index: int, draft: Dictionary): requests.append([index, draft]))
	await settle()
	check(featured.preview.model != null, "Initial canonical vehicle assembles")
	var model := featured.preview.model
	featured.render(choices, 0)
	check(featured.preview.model == model, "Repeated render keeps model identity")
	featured.next_button.pressed.emit()
	check(requests.size() == 1 and requests[-1][0] == 1, "Next emits selection intent")
	check(featured.name_label.text == choices[0].name, "Intent does not invent caller acceptance")
	requests[-1][1].name = "Mutated outgoing request"
	check(choices == original, "Signals do not mutate caller records")
	featured.render(choices, 1)
	check(featured.preview.weapon_visual.kind == "lifter", "Accepted selection changes canonical weapon")
	featured.render(choices, 0, false, "Waiting for host")
	var count := requests.size()
	featured.next_button.pressed.emit()
	featured.previous_button.pressed.emit()
	check(requests.size() == count, "Programmatic signal cannot bypass lock")
	check(featured.next_button.disabled and featured.previous_button.disabled, "Locked choices are disabled")
	featured.render(choices, 0)
	featured.previous_button.pressed.emit()
	check(requests[-1][0] == 2, "Previous wraps through all choices")
	choices[2].parts.weapon = "unavailable"
	featured.render(choices, 2)
	check(featured.preview.model == null, "Invalid build removes previous model")
	check(featured.preview.status.text.contains("Invalid"), "Invalid reason remains visible")
	featured.render([], -1)
	check(featured.next_button.disabled and featured.preview.model == null, "Empty profile has no selectable or fabricated bot")
	check(not featured.preview.visible, "No selection is a neutral empty state")
	featured.render(original, -1)
	featured.previous_button.pressed.emit()
	check(requests[-1][0] == 2, "Previous from no selection chooses last vehicle")
	featured.next_button.pressed.emit()
	check(requests[-1][0] == 0, "Next from no selection chooses first vehicle")
	choices = original.duplicate(true)
	choices[0].name = "An unusually long experimental vehicle name 12345"
	featured.render(choices, 0)
	for factor: float in [1.0, 1.25, 1.5, 1.5, 1.0]:
		featured.apply_text_scale(factor)
		await settle()
		check(featured.name_label.get_theme_font_size("font_size") == roundi(28 * factor), "Exact noncompounding name scale")
		check(featured.next_button.get_global_rect().end.x <= featured.get_global_rect().end.x + 1, "Selection actions fit width")
		check(featured.get_combined_minimum_size().y <= 620, "Full text and preview fit independent panel")
	featured.next_button.grab_focus()
	check(featured.next_button.has_focus(), "Selection supports keyboard focus")
	count = requests.size()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	Input.parse_input_event(key)
	await settle()
	key = InputEventKey.new()
	key.keycode = KEY_ENTER
	Input.parse_input_event(key)
	await settle()
	check(requests.size() == count + 1, "Enter activates the focused selection button")
	count = requests.size()
	var click := InputEventMouseButton.new()
	click.position = featured.previous_button.get_global_rect().get_center()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await settle()
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await settle()
	check(requests.size() == count + 1, "Mouse click activates vehicle selection")
	featured.queue_free()
	await settle()
	if failures.is_empty(): print("FEATURED VEHICLE PASS")
	else:
		for failure: String in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
