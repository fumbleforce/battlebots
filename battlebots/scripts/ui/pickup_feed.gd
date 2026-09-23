class_name PickupFeed
extends VBoxContainer
## Local pickup notifications and this match's collected credits. Reads only the
## session's public pickup state and events; the server decides every pickup.
const PART := Color("f5b82e")
const PERK := Color("29cce5")
const CREDITS := Color("3fcb4a")
const COOLANT := Color("bdf1ff")
const TEXT := Color("e8ecf1")
const MUTED := Color("9aa6b5")
const TOAST_SECONDS := 4.0
const MAX_TOASTS := 3
var text_scale := 1.0
var credits_panel: PanelContainer
var credits_value: Label
var credits_caption: Label
var practice_note: Label
var toasts: VBoxContainer
var _names: Dictionary = {}
var _ages: Dictionary = {}

static func names_from(registry: ContentRegistry) -> Dictionary:
	var names := {}
	for category: Dictionary in MenuData.catalogue(registry).parts:
		for item: Dictionary in category.items:
			names[item.id] = str(item.name)
	return names

static func color_for(kind: String) -> Color:
	if kind == "coolant": return COOLANT
	return CREDITS if kind == "credits" else (PERK if kind == "perk" else PART)

## Short world/HUD label for an item or collection event.
static func describe(record: Dictionary, names: Dictionary) -> String:
	if record.get("kind") == "credits":
		return "+%d CREDITS" % int(record.get("amount", 0))
	if record.get("kind") == "coolant":
		return "COOLANT  −%d HEAT" % int(record.get("amount", 0))
	var part := str(record.get("part", ""))
	return str(names.get(part, part.capitalize())).to_upper()

## One-line chips keep the feed out of the battlefield's way.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_theme_constant_override("separation", 3)
	credits_panel = _chip()
	add_child(credits_panel)
	var row := _row(credits_panel)
	credits_caption = _label(row, "CR", 10, MUTED)
	credits_value = _label(row, "+0", 13, CREDITS)
	practice_note = _label(row, "practice · not banked", 10, MUTED)
	toasts = VBoxContainer.new()
	toasts.add_theme_constant_override("separation", 3)
	add_child(toasts)
	hide()

func bind_names(names: Dictionary) -> void:
	_names = names

func apply_text_scale(value: float) -> void:
	text_scale = clampf(value, 1.0, 1.5) if is_finite(value) else 1.0
	for label: Label in find_children("*", "Label", true, false):
		label.add_theme_font_size_override("font_size", roundi(float(label.get_meta(&"base_size", 14)) * text_scale))

## `view` is MvpSession.pickup_view; hidden when the match has no pickups.
func render(view: Dictionary, local_entity: int, practice: bool) -> void:
	var items: Variant = view.get("items", [])
	visible = items is Array and not items.is_empty()
	var credits: Variant = view.get("credits", {})
	var amount := 0
	if credits is Dictionary and credits.get(local_entity) is int:
		amount = maxi(0, credits[local_entity])
	credits_value.text = "+%s" % MenuData.fmt_int(amount)
	practice_note.visible = practice

func notify(event: Dictionary, local_entity: int) -> void:
	if event.get("entity") != local_entity:
		return
	var kind := str(event.get("kind", "part"))
	var panel := _chip()
	var row := _row(panel)
	if kind not in ["credits", "coolant"]:
		_label(row, "PERK" if kind == "perk" else "PART", 10, MUTED)
	_label(row, describe(event, _names), 12, color_for(kind))
	toasts.add_child(panel)
	toasts.move_child(panel, 0)
	_ages[panel] = 0.0
	while toasts.get_child_count() > MAX_TOASTS:
		var oldest := toasts.get_child(toasts.get_child_count() - 1)
		_ages.erase(oldest)
		oldest.queue_free()
		toasts.remove_child(oldest)
	apply_text_scale(text_scale)

func clear_toasts() -> void:
	for child: Node in toasts.get_children():
		toasts.remove_child(child)
		child.queue_free()
	_ages.clear()

func _process(delta: float) -> void:
	for panel: Control in _ages.keys():
		_ages[panel] += delta
		panel.modulate.a = clampf((TOAST_SECONDS - float(_ages[panel])) / 0.6, 0.0, 1.0)
		if _ages[panel] >= TOAST_SECONDS:
			_ages.erase(panel)
			toasts.remove_child(panel)
			panel.queue_free()

func _chip() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.08, 0.72)
	style.set_corner_radius_all(3)
	style.content_margin_left = 7
	style.content_margin_right = 7
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _row(parent: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	return row

func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.set_meta(&"base_size", font_size)
	label.add_theme_font_size_override("font_size", roundi(font_size * text_scale))
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
