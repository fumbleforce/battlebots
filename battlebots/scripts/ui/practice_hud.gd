class_name PracticeHud
extends PanelContainer
## Detached BotView data only; the practice session owns resets and damage.
const COMPONENTS := {"drive_left":"Left drive", "drive_right":"Right drive", "weapon":"Weapon"}
var target_label: Label
var components_label: Label
var local_status: Label
var hint_label: Label

func _ready() -> void:
	custom_minimum_size.x = 310
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.06, 0.94)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.border_width_top = 2
	style.border_color = Color(0.3, 0.65, 0.8)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	_label(column, "PRACTICE TARGET", 17)
	target_label = _label(column, "Target unavailable", 16)
	components_label = _label(column, "Components unavailable", 14)
	local_status = _label(column, "Your bot unavailable", 14)
	local_status.modulate = Color(1, 0.73, 0.35)
	hint_label = _label(column, "Pause → Restart practice repairs and repositions both bots.", 13)
	render(null, null)

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	# A hidden CanvasLayer child can be measured before its container is sorted.
	# Supply the fixed panel's inner width before shaping wrapped text; otherwise
	# a zero-width paragraph can latch a several-thousand-pixel minimum height.
	label.custom_minimum_size.x = 286
	label.size.x = 286
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func render(local_view: BotView, target_view: BotView) -> void:
	if not is_node_ready():
		return
	local_status.text = "Your bot unavailable" if local_view == null else ("Your bot is knocked out" if local_view.eliminated else "")
	local_status.visible = not local_status.text.is_empty()
	if target_view == null:
		target_label.text = "Target unavailable"
		components_label.text = "Components unavailable"
		return
	var fraction := target_view.core_fraction
	var core := "Core: %d%%" % roundi(fraction * 100) if is_finite(fraction) and fraction >= 0 and fraction <= 1 else "Core unavailable"
	target_label.text = core + (" · TARGET DEFEATED" if target_view.eliminated else "")
	var disabled := PackedStringArray()
	var unknown := false
	for key: String in COMPONENTS:
		var value: Variant = target_view.zones.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0:
			unknown = true
		elif value == 0:
			disabled.append(COMPONENTS[key])
	components_label.text = "Disabled: " + ", ".join(disabled) if not disabled.is_empty() else ("Components unavailable" if unknown else "Disabled: none")
	if unknown and not disabled.is_empty():
		components_label.text += "\nOther components unavailable"
