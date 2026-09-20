class_name MatchResults
extends PanelContainer
## Detached, server-published records only. No local scoring or vote acknowledgement.
signal rematch_requested
signal leave_requested

var heading: Label
var timer: Label
var status: Label
var scope: OptionButton
var table: GridContainer
var rematch: Button
var leave: Button
var record: Dictionary = {}
var _view: Dictionary = {}
var _local_id := 0
var _requested := false

var overview: VBoxContainer
var scores_page: VBoxContainer
var score: Label
var outcome: Label
var round_summary: Label
var overview_tab: Button
var scores_tab: Button
var _local_team := -1
var _text_scale := 1.0
var _margin: MarginContainer
var _column: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	var background := StyleBoxFlat.new()
	background.bg_color = Color("0e1217")
	add_theme_stylebox_override("panel", background)
	var backdrop := TextureRect.new()
	backdrop.texture = preload("res://ui/menus/art/bg_arena_blur.jpg")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate.a = 0.22
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	_margin = margin
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_label("THE FOUNDRY  /  MATCH RESULTS", column).theme_type_variation = &"EyebrowAmber"
	heading = _label("MATCH COMPLETE", column)
	heading.theme_type_variation = &"Heading"
	heading.add_theme_font_size_override("font_size", 36)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	overview_tab = _button("OVERVIEW", tabs, &"Tab")
	scores_tab = _button("SCORE DETAILS", tabs, &"Tab")
	overview_tab.pressed.connect(func() -> void: show_scores(false))
	scores_tab.pressed.connect(func() -> void: show_scores(true))
	var body := PanelContainer.new()
	body.theme_type_variation = &"PanelGlass"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	overview = VBoxContainer.new()
	overview.add_theme_constant_override("separation", 12)
	body.add_child(overview)
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 24)
	overview.add_child(hero)
	outcome = _label("MATCH COMPLETE", hero)
	outcome.theme_type_variation = &"HeadingItalic"
	outcome.add_theme_font_size_override("font_size", 48)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outcome.custom_minimum_size.x = 250
	score = _label("", hero)
	score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score.theme_type_variation = &"HeadingWide"
	score.add_theme_font_size_override("font_size", 50)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var score_caption := _label("FINAL RESULT", overview)
	score_caption.theme_type_variation = &"Eyebrow"
	score_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var round_scroll := ScrollContainer.new()
	round_scroll.custom_minimum_size.y = 80
	round_scroll.focus_mode = Control.FOCUS_ALL
	round_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	round_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overview.add_child(round_scroll)
	round_summary = _label("", round_scroll)
	round_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scores_page = VBoxContainer.new()
	scores_page.add_theme_constant_override("separation", 12)
	body.add_child(scores_page)
	scope = OptionButton.new()
	scope.add_item("Match totals")
	scope.custom_minimum_size.y = 44
	scores_page.add_child(scope)
	scope.item_selected.connect(func(_index: int) -> void: _render_table())
	var scroll := ScrollContainer.new()
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scores_page.add_child(scroll)
	table = GridContainer.new()
	table.columns = 6
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 36)
	table.add_theme_constant_override("v_separation", 16)
	scroll.add_child(table)
	timer = _label("", column)
	timer.theme_type_variation = &"Strong"
	status = _label("Waiting for the final match record.", column)
	status.theme_type_variation = &"Muted"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 16)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	rematch = _button("Request rematch", actions, &"PrimaryButton")
	rematch.pressed.connect(func() -> void: rematch_requested.emit())
	leave = _button("Leave to main menu", actions, &"GhostButton")
	leave.pressed.connect(func() -> void: leave_requested.emit())
	show_scores(false)
	hide()

func apply_text_scale(factor: float) -> void:
	_text_scale = factor
	MenuTextScale.apply(self, factor)
	for edge: String in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + edge, 20 if factor > 1.0 else 28)
	_column.add_theme_constant_override("separation", 10 if factor > 1.0 else 14)
	# Fixed column shares let enlarged headings wrap instead of widening the page.
	table.add_theme_constant_override("h_separation", 12 if factor > 1.0 else 36)
	for child: Node in table.get_children():
		if child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			child.custom_minimum_size.x = 160 if child.get_index() % 6 == 0 else 140
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _button(value: String, parent: Node, variation: StringName) -> Button:
	var button := Button.new()
	button.text = value
	button.theme_type_variation = variation
	button.custom_minimum_size = Vector2(210, 48)
	parent.add_child(button)
	return button

func show_scores(enabled: bool) -> void:
	overview.visible = not enabled
	scores_page.visible = enabled
	overview_tab.toggle_mode = true
	scores_tab.toggle_mode = true
	overview_tab.set_pressed_no_signal(not enabled)
	scores_tab.set_pressed_no_signal(enabled)

func _label(value: String, parent: Node) -> Label:
	var label := Label.new()
	label.text = value
	parent.add_child(label)
	return label

func accept_record(details: Dictionary, current_match: String) -> void:
	var match_data: Variant = details.get("match")
	if not match_data is Dictionary or current_match.is_empty() \
		or match_data.get("match_id") != current_match or match_data.get("phase") != "results":
		return
	if record.get("match", {}).get("match_id") == current_match:
		return
	record = details.duplicate(true)
	scope.clear()
	scope.add_item("Match totals")
	var rounds: Variant = match_data.get("rounds", [])
	if rounds is Array:
		for round_data: Variant in rounds.slice(0, 5):
			if round_data is Dictionary and _integer(round_data.get("round"), 1, 5):
				scope.add_item("Round %d" % int(round_data.round))
				scope.set_item_metadata(scope.item_count - 1, round_data)
	scope.select(0)
	_render_table()
	_render_overview(_view)

func clear_record() -> void:
	record.clear()
	show_scores(false)
	_requested = false
	scope.clear()
	scope.add_item("Match totals")
	_render_table()

func render(view: Dictionary, local_id: int, local_team: int = -1) -> void:
	_local_team = local_team
	if not _view.is_empty() and _view.get("match_id") != view.get("match_id"):
		clear_record()
	_view = view.duplicate(true)
	if not record.is_empty() and record.get("match", {}).get("match_id") != view.get("match_id"):
		clear_record()
	if _local_id != local_id:
		_local_id = local_id
		_render_table()
	var active: bool = view.get("phase") == "results"
	rematch.disabled = not active or _requested
	rematch.text = "Rematch requested" if _requested else "Request rematch"
	_render_overview(view)
	heading.text = "MATCH COMPLETE — " + _outcome(view)
	var remaining: Variant = view.get("remaining")
	timer.text = "Waiting for server" if not _number(remaining) or remaining < 0 else "Return to lobby in %d s" % ceili(remaining)
	status.text = "Waiting for the final match record." if record.is_empty() else "Final server record • Damage is effective damage dealt."
	if _requested:
		status.text += " Rematch request sent; waiting for the server and other players."

func mark_requested() -> void:
	_requested = true
	render(_view, _local_id, _local_team)
	leave.grab_focus()

func _render_overview(view: Dictionary) -> void:
	outcome.text = "MATCH COMPLETE"
	var winner: Variant = view.get("winner")
	if view.get("mode") == "ffa":
		var winners: Variant = view.get("winners", [])
		if winners is Array and _local_id in winners:
			outcome.text = "VICTORY" if winners.size() == 1 else "SHARED VICTORY"
		score.text = "FREE FOR ALL"
	else:
		if _integer(winner, -1, 1):
			if winner == -1:
				outcome.text = "DRAW"
			elif _local_team in [0, 1]:
				outcome.text = "VICTORY" if winner == _local_team else "DEFEAT"
		var scores: Variant = view.get("scores")
		score.text = "Score unavailable"
		if scores is Array and scores.size() == 2 and _integer(scores[0], 0, 5) and _integer(scores[1], 0, 5):
			if view.get("mode") == "1v1" and _local_team in [0, 1]:
				score.text = "YOU   %d  :  %d   OPPONENT" % [int(scores[_local_team]), int(scores[1 - _local_team])]
			else:
				score.text = "TEAM A   %d  :  %d   TEAM B" % [int(scores[0]), int(scores[1])]
	var lines := PackedStringArray()
	var rounds: Variant = view.get("rounds", [])
	if rounds is Array:
		for round_data: Variant in rounds.slice(0, 5):
			if round_data is Dictionary and _integer(round_data.get("round"), 1, 5):
				lines.append("ROUND %d  ·  %s" % [int(round_data.round), _outcome(round_data)])
	if view.get("mode") == "ffa":
		lines = PackedStringArray([_outcome(view), "Open score details for placements and combat statistics."])
	round_summary.text = "\n".join(lines) if not lines.is_empty() else "Round breakdown unavailable."

func _outcome(view: Dictionary) -> String:
	if view.get("mode") == "ffa":
		var winners: Variant = view.get("winners")
		if not winners is Array or winners.is_empty():
			return "Result unavailable"
		var names := PackedStringArray()
		for id: Variant in winners:
			if not _integer(id, 1, 2147483647):
				return "Result unavailable"
			names.append("Player %d" % int(id))
		return ", ".join(names) + (" wins" if names.size() == 1 else " share the win")
	var winner: Variant = view.get("winner")
	if not _integer(winner, -1, 1):
		return "Result unavailable"
	if _view.get("mode") == "1v1" and _local_team in [0, 1] and winner != -1:
		return "You won" if winner == _local_team else "You lost"
	return "Draw" if winner == -1 else "Team %s wins" % ("A" if winner == 0 else "B")

func _render_table() -> void:
	for child: Node in table.get_children():
		table.remove_child(child)
		child.queue_free()
	for title: String in ["Player / place", "Damage", "Eliminations", "Assists", "Parts disabled", "Recoveries"]:
		_label(title, table).modulate = Color("e6b65b")
	var data: Dictionary = record
	if scope.selected > 0:
		data = scope.get_item_metadata(scope.selected)
	var participants: Variant = data.get("participants")
	if not participants is Dictionary:
		_label("Statistics unavailable", table)
		apply_text_scale(_text_scale)
		return
	var ids: Array[int] = []
	for key: Variant in participants:
		if _integer(key, 1, 2147483647):
			ids.append(int(key))
	ids.sort()
	for id: int in ids.slice(0, 10):
		var stats: Variant = participants[id]
		var name_text := "Player %d%s" % [id, " (you)" if id == _local_id else ""]
		var placements: Variant = record.get("match", {}).get("placements", [])
		if placements is Array:
			for placement: Variant in placements:
				if placement is Dictionary and placement.get("entity_id") == id and _integer(placement.get("place"), 1, 10):
					name_text += " · #%d" % int(placement.place)
		_label(name_text, table).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for field: String in ["damage", "eliminations", "assists", "component_disables", "recoveries"]:
			var value: Variant = stats.get(field) if stats is Dictionary else null
			_label(str(int(value)) if _integer(value, 0, 2147483647) else "—", table)
	apply_text_scale(_text_scale)

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and value >= minimum and value <= maximum and float(value) == floorf(float(value))
