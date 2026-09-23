class_name BuildReadout
extends PanelContainer
## Selected-build panel shared by Garage and Customize: build status and name, the
## live 3D preview and an at-a-glance stat strip. show_change() marks how a part
## swap moves each stat; stats come from ContentRegistry summaries only.

## The live preview inside the panel: text overlays belong to the stat strip.
class Preview extends GarageBotPreview:
	func _ready() -> void:
		super()
		# Blend the stage into the panel; the model and plinth stay as authored.
		for node: Node in _stage.get_children():
			if node is WorldEnvironment: node.environment.background_color = PANEL

	func _layout_status() -> void:
		super()
		if is_instance_valid(status): status.hide()
		if is_instance_valid(_status_next): _status_next.hide()

	func _invalid_status(message: String) -> void:
		super(message)
		status.hide()
		_status_next.hide()

	func rotate_view(delta: Vector2) -> void:
		super(Vector2(-delta.x, delta.y))

const PANEL := Color("151920")
const AMBER := Color("f5b82e")
const GOOD := Color("8fbf8f")
const BAD := Color("f08375")
const MUTED := Color("6f7883")
const MASS_LIMIT := 120.0

var preview: GarageBotPreview
var _max_core := 1.0
## Stats of the build as displayed without a pending change.
var _current: Dictionary = {}


func _ready() -> void:
	for part: Dictionary in ContentRegistry.new().parts.values():
		if part.get("category") == "chassis": _max_core = maxf(_max_core, float(part.get("core", 0)))


## Places the live preview behind the panel's hint and reset control.
func attach_preview(value: GarageBotPreview) -> void:
	preview = value
	%ImageFrame.add_child(value)
	%ImageFrame.move_child(value, %BotImage.get_index() + 1)
	%Rotate.pressed.connect(value.reset_view)


## Adds a header action beside the build name, styled as a panel button.
func add_action(button: Button) -> void:
	var looks := {"normal": [Color("232932"), Color("353d48")], "hover": [Color("2b3240"), AMBER],
		"pressed": [Color("2b3240"), AMBER], "hover_pressed": [Color("2b3240"), AMBER]}
	for state: String in looks:
		var box := StyleBoxFlat.new()
		box.bg_color = looks[state][0]
		box.border_color = looks[state][1]
		box.set_border_width_all(1)
		box.set_corner_radius_all(6)
		box.content_margin_left = 22
		box.content_margin_right = 24
		button.add_theme_stylebox_override(state, box)
	button.theme_type_variation = &"GhostButton"
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 58)
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.add_theme_color_override("icon_normal_color", AMBER)
	button.add_theme_color_override("icon_hover_color", AMBER)
	button.add_theme_color_override("icon_focus_color", AMBER)
	button.add_theme_constant_override("icon_max_width", 20)
	button.add_theme_constant_override("h_separation", 12)
	if not button.has_theme_font_size_override("font_size"): button.add_theme_font_size_override("font_size", 24)
	%Actions.add_child(button)


## Swaps the 3D view for another control (for example a detailed stat table).
func show_detail(control: Control, visible_detail: bool) -> void:
	if control.get_parent() != $Col:
		if control.get_parent() != null: control.get_parent().remove_child(control)
		$Col.add_child(control)
		$Col.move_child(control, %ImageFrame.get_index() + 1)
	control.visible = visible_detail
	%ImageFrame.visible = not visible_detail
	%StatsPanel.visible = not visible_detail


## Displays one PlayerProfile build entry and its canonical stats.
func show_build(bot: Dictionary, draft: Dictionary) -> void:
	if is_instance_valid(preview): preview.show_loadout(draft)
	var retained: bool = bot.get("retained", false)
	var color := BAD if not bot.valid else (AMBER if retained else GOOD)
	%BotClass.text = bot.cls
	%BotClass.add_theme_color_override("font_color", color)
	%Check.visible = bot.valid and not retained
	%Check.self_modulate = color
	%BotName.text = bot.name
	%BotName.tooltip_text = bot.name
	%BotHp.text = "%s core HP" % _n(bot.hp) if bot.valid else "Stats unavailable · " + "; ".join(bot.reasons)
	# The summary line is only shown when the stat strip cannot be.
	%BotHp.visible = not bot.valid
	%Stats.visible = bot.valid
	_current = GarageComparison.current(ContentRegistry.new(), draft).stats if bot.valid else {}
	clear_change()


## Shows target stats with each difference from base marked. Both are
## GarageComparison summaries; caption names the swap.
func show_change(base: Dictionary, target: Dictionary, caption: String) -> void:
	%ChangeBanner.visible = true
	if not target.valid:
		%ChangeCaption.text = caption + "  ·  " + "; ".join(target.reasons)
		%ChangeCaption.add_theme_color_override("font_color", BAD)
	else:
		%ChangeCaption.text = caption
		%ChangeCaption.remove_theme_color_override("font_color")
	if _current.is_empty(): return
	var before: Dictionary = base.stats
	var after: Dictionary = target.stats
	# Invalid targets only carry mass and power; other stats keep current values.
	_show_values(_merged(after))
	_mark(%CoreDelta, before, after, "core", false)
	_mark(%MassDelta, before, after, "mass", true)
	_mark(%SpeedDelta, before, after, "speed", false)
	_mark(%CoolingDelta, before, after, "cooling", false)
	_mark(%ArmorDelta, before, after, "armor_total", false)
	if after.has("plates"): _show_armor(after.plates, before.get("plates", {}))


## Returns the strip to the displayed build without change marks.
func clear_change() -> void:
	%ChangeBanner.hide()
	for label: Label in [%CoreDelta, %MassDelta, %SpeedDelta, %CoolingDelta, %ArmorDelta]: label.hide()
	if not _current.is_empty(): _show_values(_current)


func _merged(stats: Dictionary) -> Dictionary:
	var result := _current.duplicate()
	for key: String in stats: result[key] = stats[key]
	return result


func _show_values(stats: Dictionary) -> void:
	var core := float(stats.get("core", 0))
	var mass := float(stats.get("mass", 0))
	%CoreValue.text = _n(core)
	%MassValue.text = "%s / 120 kg" % _n(mass)
	%MassValue.add_theme_color_override("font_color", BAD if mass > MASS_LIMIT else Color("e9ebee"))
	%SpeedValue.text = "%s m/s" % _n(stats.get("speed", 0))
	%CoolingValue.text = "%s heat/s" % _n(stats.get("cooling", 0))
	_show_armor(stats.get("plates", {}), {})
	_tween_bar(%CoreBar, clampf(core / _max_core, 0.0, 1.0))
	_tween_bar(%MassBar, minf(mass, MASS_LIMIT))


## Armour HP per area; a bare area reads "—". Areas that differ from `before`
## (a previewed or last swap) are tinted by whether they gained or lost armour.
func _show_armor(plates: Dictionary, before: Dictionary) -> void:
	var labels := {"front": [%FrontArmor, "Front  %s"], "rear": [%RearArmor, "Rear  %s"],
		"left": [%LeftArmor, "Left\n%s"], "right": [%RightArmor, "Right\n%s"],
		"top": [%TopArmor, "Top  %s"], "underside": [%BottomArmor, "Bottom  %s"]}
	for face: String in labels:
		var label: Label = labels[face][0]
		var value := float(plates.get(face, 0.0))
		label.text = labels[face][1] % (_n(value) if value > 0.0 else "—")
		var color := Color("e9ebee") if value > 0.0 else MUTED
		if before.has(face) and absf(value - float(before[face])) >= 0.5:
			color = GOOD if value > float(before[face]) else BAD
		label.add_theme_color_override("font_color", color)


func _tween_bar(bar: ProgressBar, value: float) -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		bar.value = value
		return
	var tween := bar.create_tween()
	tween.tween_property(bar, "value", value, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _mark(label: Label, before: Dictionary, after: Dictionary, key: String, cost: bool) -> void:
	var difference := float(after.get(key, 0)) - float(before.get(key, 0))
	label.visible = before.has(key) and after.has(key) and absf(difference) >= 0.5
	if not label.visible: return
	label.text = ("+" if difference > 0 else "−") + _n(absf(difference))
	# Mass is a budget: gaining it costs headroom, shedding it frees some.
	var better := difference < 0 if cost else difference > 0
	label.add_theme_color_override("font_color", GOOD if better else (AMBER if cost else BAD))


func _n(value: Variant) -> String:
	return MenuData.fmt_int(roundi(float(value)))
