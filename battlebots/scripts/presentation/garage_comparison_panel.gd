class_name GarageComparisonPanel
extends VBoxContainer
## Displays canonical comparisons without assigning a universal good/bad direction.
const FIELDS := [
	["Core integrity", "core", 1.0], ["Speed (m/s)", "speed", 1.0],
	["Armor reduction (%)", "reduction", 100.0], ["Grip (m/s²)", "grip", 1.0],
	["Battery capacity", "battery", 1.0], ["Cooling (heat/s)", "cooling", 1.0],
	["Recovery time (s)", "recovery_seconds", 1.0],
	["Plate integrity", "plate_integrity", 1.0]]
var title: Label
var budgets: GridContainer
var details: GridContainer

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)
	budgets = _grid(self)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 125
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	details = _grid(scroll)

func _grid(parent: Node) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 5)
	parent.add_child(grid)
	return grid

func render(comparison: Dictionary, candidate: String, proposed := true) -> void:
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

func _clear(grid: GridContainer) -> void:
	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

func _cell(grid: GridContainer, value: String, name_cell := false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 21)
	label.custom_minimum_size.x = 280 if name_cell else 115
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
