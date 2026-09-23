class_name GarageComparisonPanel
extends VBoxContainer
## Displays canonical comparisons without assigning a universal good/bad direction.
const FIELDS := [
	["Core integrity", "core", 1.0], ["Speed (m/s)", "speed", 1.0],
	["Armor reduction (%)", "reduction", 100.0], ["Grip (m/s²)", "grip", 1.0],
	["Cooling (heat/s)", "cooling", 1.0],
	["Recovery time (s)", "recovery_seconds", 1.0],
	["Plate integrity", "plate_integrity", 1.0]]
var title: Label
var budgets: GridContainer
var details: GridContainer
var _text_scale := 1.0
var page := 0
var page_label: Label
var _current_only := false

func apply_text_scale(factor: float) -> void:
	_text_scale = clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	MenuTextScale.apply(self, _text_scale)
	for grid: GridContainer in [budgets, details]:
		if not is_instance_valid(grid): continue
		for index: int in grid.get_child_count():
			if _current_only:
				grid.get_child(index).custom_minimum_size.x = (250 if _text_scale > 1.0 else 280) if index % 2 == 0 else 140
			else:
				grid.get_child(index).custom_minimum_size.x = (250 if _text_scale > 1.0 else 280) if index % 4 == 0 else (160 if _text_scale > 1.0 else 115)

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title)
	budgets = _grid(self)
	details = _grid(self)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pages := HBoxContainer.new()
	add_child(pages)
	var previous := Button.new()
	previous.text = "PREVIOUS"
	previous.pressed.connect(func(): page = 1 - page; _show_page())
	pages.add_child(previous)
	page_label = Label.new()
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.add_child(page_label)
	var next := Button.new()
	next.text = "NEXT"
	next.pressed.connect(func(): page = 1 - page; _show_page())
	pages.add_child(next)

func _show_page() -> void:
	var page_size := 8 if _current_only else 16
	for index: int in details.get_child_count():
		details.get_child(index).visible = index / page_size == page
	page_label.text = "STATS %d / 2" % (page + 1) if _current_only else "DETAILS %d / 2" % (page + 1)

func _grid(parent: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	parent.add_child(grid)
	return grid

func render(comparison: Dictionary, candidate: String, proposed := true) -> void:
	_current_only = false
	budgets.columns = 4
	details.columns = 4
	title.text = "EQUIPPED → " + candidate.to_upper() if proposed else "EQUIPPED BUILD · COSMETICS DO NOT CHANGE STATS"
	_clear(budgets)
	_clear(details)
	for heading: String in ["Statistic", "Equipped", "Proposed" if proposed else "Same", "Change"]:
		_cell(budgets, heading, budgets.get_child_count() % 4 == 0).modulate = Color("f5b82e")
	var before: Dictionary = comparison.current.stats
	var after: Dictionary = comparison.proposed.stats if proposed else before
	_row(budgets, "Mass (kg / 120)", before.get("mass"), after.get("mass"), 1, 120)
	_row(budgets, "Power ( / 100)", before.get("power"), after.get("power"), 1, 100)
	for field: Array in FIELDS:
		_row(details, field[0], before.get(field[1]), after.get(field[1]), field[2])
	_show_page()
	apply_text_scale(_text_scale)


func render_current(summary: Dictionary) -> void:
	_current_only = true
	budgets.columns = 2
	details.columns = 2
	title.text = "CURRENT BUILD"
	_clear(budgets)
	_clear(details)
	_cell(budgets, "STAT", true).modulate = Color("f5b82e")
	_cell(budgets, "VALUE").modulate = Color("f5b82e")
	var stats: Dictionary = summary.stats
	_current_row(budgets, "Mass (kg / 120)", stats.get("mass"))
	_current_row(budgets, "Power ( / 100)", stats.get("power"))
	for field: Array in FIELDS:
		_current_row(details, field[0], stats.get(field[1]), field[2])
	_show_page()
	apply_text_scale(_text_scale)


func _current_row(grid: GridContainer, label: String, value: Variant, scale_value := 1.0) -> void:
	_cell(grid, label, true)
	_cell(grid, _format(value, scale_value))

func _clear(grid: GridContainer) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

func _cell(grid: GridContainer, value: String, name_cell := false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 21)
	label.custom_minimum_size.x = 280 if name_cell else 115
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if name_cell: label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	return label

func _row(grid: GridContainer, label: String, before: Variant, after: Variant, scale_value := 1.0, limit := INF) -> void:
	_cell(grid, label, true)
	var prior := _cell(grid, _format(before, scale_value))
	var next := _cell(grid, _format(after, scale_value))
	if _number(before) and float(before) > limit: prior.modulate = Color("e5534b")
	if _number(after) and float(after) > limit: next.modulate = Color("e5534b")
	var delta := "—"
	if _number(before) and _number(after):
		var change := (float(after) - float(before)) * scale_value
		delta = "0" if is_zero_approx(change) else ("+" if change > 0 else "") + _format(change)
	_cell(grid, delta)

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _format(value: Variant, multiplier := 1.0) -> String:
	if not _number(value): return "—"
	var scaled := float(value) * multiplier
	return str(roundi(scaled)) if is_equal_approx(scaled, roundf(scaled)) else "%.1f" % scaled
