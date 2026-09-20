class_name CombatHud
extends Control
## Read-only bot feedback. No local damage, eligibility or countdown simulation.
const AMBER := Color("f5b82e")
const RED := Color("ff8a80")
const TEXT := Color("e8ecf1")
const MUTED := Color("9aa6b5")
const ZONES := {"front":"FRONT", "rear":"REAR", "left":"LEFT", "right":"RIGHT", "drive_left":"L DRIVE", "drive_right":"R DRIVE", "weapon":"WEAPON"}
const PHASES := {"idle":"IDLE", "active":"ACTIVE", "disabled":"DISABLED", "overheated":"OVERHEATED", "launch":"LAUNCH", "windup":"WINDUP", "strike":"STRIKE", "cooldown":"COOLDOWN"}
var canvas: Control
var resources: Dictionary = {}
var components: Dictionary = {}
var weapon_label: Label
var cooldown_label: Label
var recovery_label: Label
var heading_label: Label
var warning_label: Label
var roster_label: Label
var roster_title: Label
var failure_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	canvas = Control.new()
	add_child(canvas)
	var resources_panel := _panel(Rect2(24, 490, 310, 206))
	var resource_col := _column(resources_panel)
	_label(resource_col, "YOUR BOT / RESOURCES", 20, &"Heading")
	for key: String in ["Core", "Battery", "Heat"]:
		resources[key] = _resource(resource_col, key.to_upper())
	var components_panel := _panel(Rect2(946, 448, 310, 248))
	var diagram := Control.new()
	diagram.custom_minimum_size = Vector2(282, 220)
	components_panel.add_child(diagram)
	var caption := _label(diagram, "COMPONENT INTEGRITY", 20, &"Heading")
	caption.position = Vector2(0, 0)
	var positions := {"front":Rect2(94, 30, 96, 42), "weapon":Rect2(94, 76, 96, 42), "left":Rect2(0, 70, 86, 52), "right":Rect2(198, 70, 86, 52), "drive_left":Rect2(32, 128, 100, 42), "drive_right":Rect2(152, 128, 100, 42), "rear":Rect2(94, 176, 96, 42)}
	for key: String in ZONES:
		var cell := PanelContainer.new()
		cell.theme_type_variation = &"PanelDark"
		diagram.add_child(cell)
		cell.position = positions[key].position
		cell.size = positions[key].size
		var value := _label(cell, "", 13)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		components[key] = value
	var weapon_panel := _panel(Rect2(356, 548, 568, 148))
	var weapon_col := _column(weapon_panel)
	var weapon_row := HBoxContainer.new()
	weapon_col.add_child(weapon_row)
	weapon_label = _label(weapon_row, "", 23, &"Heading")
	weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cooldown_label = _label(weapon_row, "", 18)
	resources["Charge"] = _resource(weapon_col, "CHARGE")
	recovery_label = _label(weapon_col, "", 18)
	failure_label = _label(weapon_col, "", 15)
	failure_label.modulate = AMBER
	heading_label = _label(canvas, "", 18, &"Heading")
	heading_label.position = Vector2(356, 512)
	heading_label.size = Vector2(568, 30)
	heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var roster := _panel(Rect2(24, 24, 310, 74))
	var roster_col := _column(roster)
	roster_title = _label(roster_col, "DUEL / BOT STATUS", 18, &"Heading")
	roster_label = _label(roster_col, "", 16)
	warning_label = _label(canvas, "", 27, &"Heading")
	warning_label.position = Vector2(350, 232)
	warning_label.size = Vector2(580, 76)
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.add_theme_color_override("font_outline_color", Color.BLACK)
	warning_label.add_theme_constant_override("outline_size", 6)
	_ignore_input(self)
	get_viewport().size_changed.connect(_resize)
	_resize()
	render(null)

func _panel(bounds: Rect2) -> PanelContainer:
	var item := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.08, 0.9)
	style.border_color = Color("36424f")
	style.set_border_width_all(1)
	style.border_width_top = 2
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	item.add_theme_stylebox_override("panel", style)
	canvas.add_child(item)
	item.position = bounds.position
	item.size = bounds.size
	return item

func _column(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	parent.add_child(column)
	return column

func _label(parent: Node, text: String, font_size: int, variation: StringName = &"Body") -> Label:
	var item := Label.new()
	item.text = text
	item.theme_type_variation = variation
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", TEXT)
	parent.add_child(item)
	return item

func _resource(parent: Node, title: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size.y = 34
	parent.add_child(row)
	var name_label := _label(row, title, 17, &"Heading")
	name_label.custom_minimum_size.x = 64
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(60, 10)
	bar.show_percentage = false
	row.add_child(bar)
	var value := _label(row, "--", 18)
	value.custom_minimum_size.x = 47
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return {"bar":bar, "value":value}

func _ignore_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if node is BaseButton:
			node.focus_mode = Control.FOCUS_NONE
	for child: Node in node.get_children():
		_ignore_input(child)

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
	canvas.size = Vector2(1280, 720)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (extent - canvas.size * ratio) * 0.5

func render(view: BotView, recovery_binding: String = "", opponent: BotView = null, practice := false, duel := true, combat_active := true) -> void:
	if not is_node_ready():
		return
	var values := [view.core_fraction, view.battery_fraction, view.heat_fraction, view.weapon_charge_fraction] if view != null else [NAN, NAN, NAN, NAN]
	var index := 0
	for key: String in ["Core", "Battery", "Heat", "Charge"]:
		var value: float = values[index]
		var valid := is_finite(value) and value >= 0.0 and value <= 1.0
		resources[key].bar.value = value * 100.0 if valid else 0.0
		resources[key].value.text = "%d%%" % roundi(value * 100.0) if valid else "--"
		resources[key].value.modulate = AMBER if valid and ((key == "Core" and value <= 0.25) or (key == "Heat" and value >= 0.9)) else TEXT
		index += 1
	for key: String in ZONES:
		var integrity: Variant = view.zones.get(key) if view != null else null
		var valid: bool = _number(integrity) and integrity >= 0
		var detail := "--"
		if valid:
			detail = str(ceili(float(integrity))) if integrity > 0 else ("BREACHED" if key in ["front", "rear", "left", "right"] else "DISABLED")
		components[key].text = ZONES[key] + "\n" + detail
		components[key].modulate = RED if valid and integrity == 0 else (TEXT if valid else MUTED)
	weapon_label.text = "WEAPON / " + (PHASES.get(str(view.weapon_state), "UNKNOWN") if view != null else "UNAVAILABLE")
	cooldown_label.text = ""
	if view != null and _number(view.weapon_cooldown) and view.weapon_cooldown >= 0:
		cooldown_label.text = "%.1f s cooldown" % view.weapon_cooldown if view.weapon_cooldown > 0 else ""
	elif view != null:
		cooldown_label.text = "Cooldown --"
	var recovery := "UNAVAILABLE"
	if view != null and not view.eliminated:
		if not combat_active:
			recovery = "ROUND LOCKED"
		elif view.recovery_available:
			recovery = "READY" + (" / " + recovery_binding if not recovery_binding.is_empty() else "")
		elif _number(view.recovery_cooldown) and view.recovery_cooldown > 0:
			recovery = "%.1f s COOLDOWN" % view.recovery_cooldown
	recovery_label.text = "SELF-RIGHT / " + recovery
	recovery_label.modulate = AMBER if view != null and view.recovery_available and not view.eliminated and combat_active else TEXT
	var failures := {"battery_empty":"Not enough battery", "recovery_unavailable":"Self-right unavailable", "disabled":"Weapon disabled", "overheated":"Weapon overheated", "cooldown":"Weapon cooling down"}
	failure_label.text = failures.get(view.failure_reason, "") if view != null else "Bot data unavailable"
	if view != null and not view.eliminated and not combat_active:
		failure_label.text = "Weapons and self-right unlock during the round."
	heading_label.text = "CHASSIS / " + _heading(view)
	roster_label.text = "PRACTICE / UNSCORED" if practice else "YOU: %s   /   RIVAL: %s" % [_alive(view), _alive(opponent)]
	roster_title.text = "PRACTICE / BOT STATUS" if practice else ("DUEL / BOT STATUS" if duel else "BOT STATUS")
	if not practice and not duel:
		roster_label.text = "YOUR BOT: " + _alive(view)
	warning_label.text = ""
	warning_label.modulate = AMBER
	if view != null:
		if view.eliminated:
			warning_label.text = "BOT ELIMINATED"
			warning_label.modulate = RED
		elif _number(view.immobilized_remaining) and view.immobilized_remaining > 0:
			warning_label.text = "IMMOBILIZED / %.1f s\nRegain wheel contact and drive to recover" % view.immobilized_remaining
			warning_label.modulate = RED
		elif view.weapon_state == &"overheated":
			warning_label.text = "WEAPON OVERHEATED"
		elif is_finite(view.core_fraction) and view.core_fraction >= 0 and view.core_fraction <= 0.25:
			warning_label.text = "CORE CRITICAL"
	warning_label.visible = not warning_label.text.is_empty()

func _alive(view: BotView) -> String:
	return "--" if view == null else ("OUT" if view.eliminated else "IN")

func _heading(view: BotView) -> String:
	if view == null:
		return "--"
	var forward := -view.pose.basis.z
	if not forward.is_finite() or Vector2(forward.x, forward.z).length_squared() < 0.0001:
		return "--"
	var degrees := fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)
	var compass: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][int(round(degrees / 45.0)) % 8]
	return "%s %03d°" % [compass, roundi(degrees) % 360]

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
