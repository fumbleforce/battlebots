class_name CombatHud
extends Control
## Snapshot-only combat instruments. The battlefield stays clear in normal play.
const AMBER := Color("f5b82e")
const RED := Color("ff8a80")
const TEXT := Color("e8ecf1")
const MUTED := Color("9aa6b5")
const ZONES := {"front":"FRONT", "rear":"REAR", "left":"LEFT", "right":"RIGHT", "drive_left":"L DRIVE", "drive_right":"R DRIVE", "weapon":"WEAPON"}
const PHASES := {"idle":"IDLE", "active":"ACTIVE", "disabled":"DISABLED", "overheated":"OVERHEATED", "launch":"LAUNCH", "windup":"WINDUP", "strike":"STRIKE", "cooldown":"COOLDOWN"}
var text_scale := 1.0
var palette := "standard"
var high_contrast := false
var accent := AMBER
var danger := RED
var panels: Array[PanelContainer] = []
var base_fonts: Dictionary = {}
var muted_labels: Array[Label] = []
var resources_panel: PanelContainer
var components_panel: PanelContainer
var weapon_panel: PanelContainer
var canvas: Control
var resources: Dictionary = {}
var components: Dictionary = {}
var weapon_label: Label
var cooldown_label: Label
var recovery_label: Label
var warning_label: Label
var failure_label: Label
var connection_label: Label
var _component_grid: GridContainer
var _weapon_name: Label
var charge_gauge: Control
var status_stack: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	canvas = Control.new()
	add_child(canvas)
	resources_panel = _panel()
	var health_col := _column(resources_panel)
	var health_row := HBoxContainer.new()
	health_col.add_child(health_row)
	var title := _label(health_row, "INTEGRITY", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.modulate = MUTED
	muted_labels.append(title)
	var health_value := _label(health_row, "--", 28)
	var health_bar := _bar(health_col, 6)
	resources["Core"] = {"bar":health_bar, "value":health_value}
	var support := HBoxContainer.new()
	support.add_theme_constant_override("separation", 18)
	health_col.add_child(support)
	resources["Heat"] = _resource(support, "HEAT")
	components_panel = _panel()
	_component_grid = GridContainer.new()
	_component_grid.columns = 4
	_component_grid.add_theme_constant_override("h_separation", 12)
	_component_grid.add_theme_constant_override("v_separation", 5)
	components_panel.add_child(_component_grid)
	for key: String in ZONES:
		var label := _label(_component_grid, "", 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		components[key] = label
	weapon_panel = _panel()
	weapon_panel.set("mirrored", true)
	var weapon_body := HBoxContainer.new()
	weapon_body.add_theme_constant_override("separation", 14)
	weapon_panel.add_child(weapon_body)
	charge_gauge = preload("res://scripts/ui/hud_charge_gauge.gd").new()
	charge_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	weapon_body.add_child(charge_gauge)
	var weapon_col := _column(weapon_body)
	weapon_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var weapon_row := VBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 0)
	weapon_col.add_child(weapon_row)
	_weapon_name = _label(weapon_row, "WEAPON", 13)
	_weapon_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_name.modulate = MUTED
	muted_labels.append(_weapon_name)
	_weapon_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_label = _label(weapon_row, "", 18)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	resources["Charge"] = {"bar":_bar(weapon_col, 5), "value":_label(weapon_col, "", 12)}
	resources.Charge.value.hide()
	resources.Charge.bar.hide()
	cooldown_label = _label(weapon_col, "", 13)
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	failure_label = _label(weapon_col, "", 13)
	failure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recovery_label = _label(canvas, "", 14)
	recovery_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	recovery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	recovery_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	warning_label = _label(canvas, "", 20)
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_stack = VBoxContainer.new()
	status_stack.add_theme_constant_override("separation", 6)
	status_stack.size = Vector2(480, 0)
	canvas.add_child(status_stack)
	warning_label.reparent(status_stack, false)
	recovery_label.reparent(status_stack, false)
	components_panel.reparent(status_stack, false)
	components_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for label: Label in [warning_label, recovery_label]:
		label.custom_minimum_size.x = 480
		label.size.x = 480
	status_stack.minimum_size_changed.connect(_resize)
	connection_label = _label(canvas, "CONNECTION UNSTABLE", 13)
	connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	connection_label.hide()
	for label: Label in [recovery_label, warning_label, connection_label]:
		label.add_theme_color_override("font_outline_color", Color(0.015, 0.02, 0.03, 0.95))
		label.add_theme_constant_override("outline_size", 2)
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_y", 2)
	_ignore_input(self)
	get_viewport().size_changed.connect(_resize)
	apply_accessibility(text_scale, palette, high_contrast)
	render(null)

func apply_accessibility(value: float, colors: String, contrast: bool) -> void:
	var previous_accent := accent
	var previous_danger := danger
	text_scale = clampf(value, 1.0, 1.5) if is_finite(value) else 1.0
	palette = colors if colors in ["standard", "deuteranopia", "protanopia", "tritanopia"] else "standard"
	high_contrast = contrast
	accent = {"standard":AMBER, "deuteranopia":Color("82cfff"), "protanopia":Color("82cfff"), "tritanopia":Color("ffcc91")}[palette]
	danger = {"standard":RED, "deuteranopia":Color("ffce75"), "protanopia":Color("ffe083"), "tritanopia":Color("ffa7cd")}[palette]
	if not is_node_ready(): return
	for label: Label in base_fonts:
		if label in muted_labels: label.modulate = Color.WHITE if high_contrast else MUTED
		elif label.modulate == previous_accent: label.modulate = accent
		elif label.modulate == previous_danger: label.modulate = danger
		elif label.modulate == TEXT or label.modulate == Color.WHITE: label.modulate = _text_color()
		label.add_theme_font_size_override("font_size", roundi(base_fonts[label] * text_scale))
		label.add_theme_color_override("font_color", _text_color())
	for panel: PanelContainer in panels:
		panel.call("configure", danger if panel == components_panel else accent, high_contrast)
	for key: String in resources:
		var fill := StyleBoxFlat.new()
		fill.bg_color = accent if key == "Charge" else (Color("9ed8e5") if key == "Core" else Color("80aab9"))
		resources[key].bar.add_theme_stylebox_override("fill", fill)
		var background := StyleBoxFlat.new()
		background.bg_color = Color("384553")
		resources[key].bar.add_theme_stylebox_override("background", background)
	_layout()
	_resize()

func caption_bounds() -> Rect2:
	return Rect2(Vector2((canvas.size.x - 480) * 0.5, status_stack.position.y - 122), Vector2(480, 112))

func _layout() -> void:
	if not is_node_ready(): return
	var large := text_scale > 1.0
	var health_width := 340.0 if large else 284.0
	var weapon_width := 324.0 if large else 252.0
	# Recompute after visibility/text changes; containers can shrink after a warning.
	resources_panel.size = Vector2(health_width, 0)
	resources_panel.position = Vector2(28, 692 - resources_panel.size.y)
	weapon_panel.size = Vector2(weapon_width, 0)
	weapon_panel.position = Vector2(1252 - weapon_width, 692 - weapon_panel.size.y)
	status_stack.size = Vector2(480, 0)
	status_stack.position = Vector2((canvas.size.x - 480) * 0.5, canvas.size.y - 28 - status_stack.size.y)
	connection_label.position = Vector2(910, 28)
	connection_label.size = Vector2(342, 32)

func _panel() -> PanelContainer:
	var item: PanelContainer = preload("res://scripts/ui/hud_instrument_frame.gd").new()
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 10
	item.add_theme_stylebox_override("panel", style)
	panels.append(item)
	canvas.add_child(item)
	item.minimum_size_changed.connect(_resize)
	return item

func _column(parent: Node) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	parent.add_child(column)
	return column

func _label(parent: Node, text: String, font_size: int) -> Label:
	var item := Label.new()
	base_fonts[item] = font_size
	item.text = text
	item.add_theme_font_override("font", preload("res://ui/menus/fonts/Barlow-SemiBold.ttf"))
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", TEXT)
	parent.add_child(item)
	return item

func _bar(parent: Node, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(40, height)
	bar.show_percentage = false
	parent.add_child(bar)
	bar.draw.connect(func() -> void:
		for tick: int in range(1, 10):
			var x := bar.size.x * tick / 10.0
			bar.draw_line(Vector2(x, 0), Vector2(x, bar.size.y), Color("102730"), 1))
	return bar

func _resource(parent: Node, title: String) -> Dictionary:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	parent.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var name_label := _label(row, title, 11)
	name_label.modulate = MUTED
	muted_labels.append(name_label)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := _label(row, "--", 12)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return {"bar":_bar(column, 3), "value":value}

func _ignore_input(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children(): _ignore_input(child)

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
	# Edge instruments use the full aspect ratio, including ultrawide screens.
	canvas.size = extent / ratio
	canvas.scale = Vector2.ONE * ratio
	canvas.position = Vector2.ZERO
	_layout()
	var extra := canvas.size.x - 1280.0
	weapon_panel.position.x += extra
	connection_label.position.x += extra
	var extra_height := canvas.size.y - 720.0
	for control: Control in [resources_panel, weapon_panel]:
		control.position.y += extra_height
func render(view: BotView, recovery_binding: String = "", opponent: BotView = null, practice := false, duel := true, combat_active := true) -> void:
	if not is_node_ready():
		return
	var values := [view.core_fraction, view.heat_fraction, view.weapon_charge_fraction] if view != null else [NAN, NAN, NAN]
	var index := 0
	for key: String in ["Core", "Heat", "Charge"]:
		var value: float = values[index]
		var valid := is_finite(value) and value >= 0.0 and value <= 1.0
		resources[key].bar.value = value * 100.0 if valid else 0.0
		resources[key].value.text = "%d%%" % roundi(value * 100.0) if valid else "--"
		resources[key].value.modulate = accent if valid and ((key == "Core" and value <= 0.25) or (key == "Heat" and value >= 0.9)) else _text_color()
		index += 1
	for key: String in ZONES:
		var integrity: Variant = view.zones.get(key) if view != null else null
		var valid: bool = _number(integrity) and integrity >= 0
		var detail := "--"
		if valid:
			detail = str(ceili(float(integrity))) if integrity > 0 else ("BREACHED" if key in ["front", "rear", "left", "right"] else "DISABLED")
		components[key].text = ZONES[key] + "\n" + detail
		components[key].modulate = danger if valid and integrity == 0 else (_text_color() if valid else (Color.WHITE if high_contrast else MUTED))
		components[key].visible = valid and integrity == 0
	components_panel.visible = view != null and not view.eliminated and components.values().any(func(label: Label) -> bool: return label.visible)
	weapon_label.text = PHASES.get(str(view.weapon_state), "UNKNOWN") if view != null else "UNAVAILABLE"
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
	recovery_label.modulate = accent if view != null and view.recovery_available and not view.eliminated and combat_active else _text_color()
	recovery_label.visible = view != null and not view.eliminated and combat_active and (view.recovery_available or (_number(view.recovery_cooldown) and view.recovery_cooldown > 0))
	var failures := {"recovery_unavailable":"Self-right unavailable", "disabled":"Weapon disabled", "overheated":"Overheated", "cooldown":"Weapon cooling down"}
	failure_label.text = failures.get(view.failure_reason, "") if view != null else "Bot data unavailable"
	if view != null and not combat_active:
		weapon_label.text = "LOCKED"
		failure_label.text = ""
	# The weapon state already explains these failures; do not repeat it below.
	if view != null and view.failure_reason in ["disabled", "overheated", "cooldown"]:
		failure_label.text = ""
	failure_label.visible = not failure_label.text.is_empty()
	cooldown_label.visible = not cooldown_label.text.is_empty()
	warning_label.text = ""
	warning_label.modulate = accent
	if view != null:
		if view.eliminated:
			warning_label.text = "BOT ELIMINATED"
			warning_label.modulate = danger
		elif _number(view.immobilized_remaining) and view.immobilized_remaining > 0:
			warning_label.text = ("IMMOBILIZED %.1f s\nWheels down; drive" if text_scale > 1.0 else "IMMOBILIZED / %.1f s\nRegain wheel contact and drive to recover") % view.immobilized_remaining
			warning_label.modulate = danger
		elif view.overheated:
			warning_label.text = "OVERHEATED / COOL TO 50%"
		elif is_finite(view.core_fraction) and view.core_fraction >= 0 and view.core_fraction <= 0.25:
			warning_label.text = "CORE CRITICAL"
	warning_label.visible = not warning_label.text.is_empty()
	charge_gauge.call("render", view.weapon_charge_fraction if view != null else NAN, danger if view != null and (view.overheated or view.weapon_state == &"disabled") else accent, text_scale, high_contrast)
	for key: String in ["Core", "Heat"]:
		var fill := resources[key].bar.get_theme_stylebox("fill") as StyleBoxFlat
		var urgent: bool = view != null and ((key == "Core" and is_finite(view.core_fraction) and view.core_fraction >= 0 and view.core_fraction <= 0.25) or (key == "Heat" and (view.overheated or (is_finite(view.heat_fraction) and view.heat_fraction >= 0.9 and view.heat_fraction <= 1))))
		fill.bg_color = danger if urgent else (Color("9ed8e5") if key == "Core" else Color("80aab9"))
	_resize()

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _text_color() -> Color:
	return Color.WHITE if high_contrast else TEXT
