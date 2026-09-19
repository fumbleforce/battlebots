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

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("111923")
	background.content_margin_left = 32
	background.content_margin_right = 32
	background.content_margin_top = 24
	background.content_margin_bottom = 24
	add_theme_stylebox_override("panel", background)
	add_theme_font_size_override("font_size", 20)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	heading = _label("MATCH COMPLETE", column)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 30)
	timer = _label("", column)
	scope = OptionButton.new()
	scope.add_item("Match totals")
	column.add_child(scope)
	scope.item_selected.connect(func(_index: int) -> void: _render_table())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	table = GridContainer.new()
	table.columns = 6
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 24)
	table.add_theme_constant_override("v_separation", 12)
	scroll.add_child(table)
	status = _label("Waiting for the final match record.", column)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	column.add_child(actions)
	rematch = Button.new()
	rematch.text = "Request rematch"
	rematch.custom_minimum_size = Vector2(220, 48)
	actions.add_child(rematch)
	rematch.pressed.connect(func() -> void: rematch_requested.emit())
	leave = Button.new()
	leave.text = "Leave to main menu"
	leave.custom_minimum_size = Vector2(240, 48)
	actions.add_child(leave)
	leave.pressed.connect(func() -> void: leave_requested.emit())
	hide()

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

func clear_record() -> void:
	record.clear()
	_requested = false
	scope.clear()
	scope.add_item("Match totals")
	_render_table()

func render(view: Dictionary, local_id: int) -> void:
	_view = view.duplicate(true)
	if not record.is_empty() and record.get("match", {}).get("match_id") != view.get("match_id"):
		clear_record()
	if _local_id != local_id:
		_local_id = local_id
		_render_table()
	var active: bool = view.get("phase") == "results"
	rematch.disabled = not active or _requested
	rematch.text = "Rematch requested" if _requested else "Request rematch"
	heading.text = "MATCH COMPLETE — " + _outcome(view)
	var remaining: Variant = view.get("remaining")
	timer.text = "Waiting for server" if not _number(remaining) or remaining < 0 else "Return to lobby in %d s" % ceili(remaining)
	status.text = "Waiting for the final match record." if record.is_empty() else "Final server record • Damage is effective damage dealt."
	if _requested:
		status.text += " Rematch request sent; waiting for the server and other players."

func mark_requested() -> void:
	_requested = true
	render(_view, _local_id)
	leave.grab_focus()

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

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and value >= minimum and value <= maximum and float(value) == floorf(float(value))
