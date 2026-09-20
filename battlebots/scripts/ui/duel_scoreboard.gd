class_name DuelScoreboard
extends Control
## Read-only held overlay. All values come from accepted match/lobby/bot views.
const PHASES := {"countdown":"GET READY", "active":"FIGHT", "overtime":"OVERTIME", "intermission":"INTERMISSION"}
var canvas: Control
var panel: PanelContainer
var heading: Label
var context: Label
var hint: Label
var cards: Array[Dictionary] = []
var _fonts: Dictionary = {}
var _blocked_until_release := false
var _fit_pending := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = preload("res://ui/menus/theme/menu_theme.tres")
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	panel = PanelContainer.new()
	panel.theme_type_variation = &"PanelDark"
	canvas.add_child(panel)
	panel.position = Vector2(70, 54)
	panel.custom_minimum_size = Vector2(1140, 0)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	heading = _label(column, "1V1 SCOREBOARD", 28, &"HeadingItalic")
	context = _label(column, "", 20, &"Muted")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	for title: String in ["YOU", "OPPONENT"]:
		var card := PanelContainer.new()
		card.theme_type_variation = &"PanelGlass"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var inset := MarginContainer.new()
		for edge: String in ["left", "right", "top", "bottom"]:
			inset.add_theme_constant_override("margin_" + edge, 8)
		card.add_child(inset)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 10)
		inset.add_child(content)
		var title_label := _label(content, title, 20, &"EyebrowAmber")
		var name_label := _label(content, "Waiting for player", 22, &"Heading")
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 24)
		content.add_child(stats)
		var score := VBoxContainer.new()
		score.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.add_child(score)
		var condition := VBoxContainer.new()
		condition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		condition.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats.add_child(condition)
		cards.append({"panel":card, "title":title_label, "name":name_label,
			"wins":_label(score, "—", 52, &"HeadingWide"),
			"caption":_label(score, "ROUNDS WON", 16, &"Eyebrow"),
			"status":_label(condition, "STATE UNAVAILABLE", 18, &"Strong"),
			"core":_label(condition, "CORE —", 18, &"Muted")})
	hint = _label(column, "", 18, &"Muted")
	panel.minimum_size_changed.connect(_queue_fit)
	_ignore_input(self)
	get_viewport().size_changed.connect(_resize)
	apply_accessibility(1.0, "standard", false)
	_resize()
	hide()

func _label(parent: Node, text: String, font_size: int, variation: StringName) -> Label:
	var item := Label.new()
	item.text = text
	item.theme_type_variation = variation
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(item)
	_fonts[item] = font_size
	item.add_theme_font_size_override("font_size", font_size)
	return item

func _ignore_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.focus_mode = Control.FOCUS_NONE
	for child: Node in node.get_children():
		_ignore_input(child)

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
	canvas.size = Vector2(1280, 720)
	canvas.scale = Vector2.ONE * ratio
	canvas.position = (extent - canvas.size * ratio) * 0.5

func apply_accessibility(factor: float, palette: String, contrast: bool) -> void:
	var scale_value := clampf(factor, 1.0, 1.5) if is_finite(factor) else 1.0
	var accent: Color = {"standard":Color("f5b82e"), "deuteranopia":Color("82cfff"), "protanopia":Color("82cfff"), "tritanopia":Color("ffcc91")}.get(palette, Color("f5b82e"))
	for label: Label in _fonts:
		label.add_theme_font_size_override("font_size", roundi(_fonts[label] * scale_value))
		label.add_theme_color_override("font_color", Color.WHITE if contrast else Color("e8ecf1"))
	for card: Dictionary in cards:
		card.title.add_theme_color_override("font_color", Color.WHITE if contrast else accent)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.BLACK if contrast else Color(0.035, 0.047, 0.06, 0.97)
	style.border_color = Color.WHITE if contrast else accent
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.size.x = 1140
	_queue_fit()

func _queue_fit() -> void:
	if not _fit_pending:
		_fit_pending = true
		_fit_height.call_deferred()

func _fit_height() -> void:
	# Wrapped labels need their final column widths before reporting their height.
	await get_tree().process_frame
	await get_tree().process_frame
	panel.size.y = panel.get_combined_minimum_size().y
	_fit_pending = false

func update_hold(held: bool, allowed: bool) -> void:
	if not held:
		_blocked_until_release = false
	elif not allowed:
		_blocked_until_release = true
	visible = held and allowed and not _blocked_until_release

func suppress(held: bool) -> void:
	update_hold(held, false)

func render(view: Dictionary, lobby: Dictionary, bots: Array[BotView], local_id: int, binding: String, stale := false) -> void:
	var phase: String = str(view.get("phase", ""))
	var round_value: Variant = view.get("round")
	var remaining: Variant = view.get("remaining")
	context.text = "ROUND %d" % int(round_value) if _integer(round_value, 1, 999) else "ROUND —"
	context.text += "  ·  " + str(PHASES.get(phase, "MATCH STATE UNAVAILABLE"))
	if _number(remaining) and remaining >= 0 and remaining <= 86400:
		var seconds := ceili(remaining)
		context.text += "  ·  %d:%02d" % [seconds / 60, seconds % 60]
	else:
		context.text += "  ·  TIME —"
	hint.text = "HOLD %s · RELEASE TO RETURN. The match continues." % binding.to_upper()
	if stale:
		hint.text = "CONNECTION DELAY · Showing last received state. Release %s to return." % binding.to_upper()
	var slots: Array = lobby.get("slots", []) if lobby.get("slots") is Array else []
	var by_id := {}
	for slot: Variant in slots:
		if slot is Dictionary and _integer(slot.get("entity_id"), 1, 2147483647):
			var id := int(slot.entity_id)
			by_id[id] = {} if by_id.has(id) else slot
	var local: Dictionary = by_id.get(local_id, {})
	var local_team: Variant = local.get("team")
	var rival: Dictionary = {}
	if _integer(local_team, 0, 1) and by_id.size() == 2:
		for id: int in by_id:
			var candidate: Dictionary = by_id[id]
			if id != local_id and _integer(candidate.get("team"), 0, 1) and candidate.team != local_team:
				rival = candidate
	_render_card(cards[0], local, view.get("scores"), bots)
	_render_card(cards[1], rival, view.get("scores"), bots)

func _render_card(card: Dictionary, slot: Dictionary, scores: Variant, bots: Array[BotView]) -> void:
	card.name.text = "Waiting for player"
	card.wins.text = "—"
	card.status.text = "STATE UNAVAILABLE"
	card.core.text = "CORE —"
	if slot.is_empty():
		return
	var id := int(slot.entity_id)
	var loadout: Variant = slot.get("loadout")
	if loadout is Dictionary and loadout.get("name") is String:
		var clean := str(loadout.name).replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(48)
		card.name.text = clean if not clean.is_empty() else "Player %d" % id
	else:
		card.name.text = "Player %d" % id
	var team: Variant = slot.get("team")
	if _integer(team, 0, 1) and scores is Array and scores.size() == 2 and _integer(scores[0], 0, 5) and _integer(scores[1], 0, 5):
		card.wins.text = str(int(scores[int(team)]))
	var accepted: BotView
	var count := 0
	for bot: BotView in bots:
		if bot != null and bot.entity_id == id:
			accepted = bot
			count += 1
	if slot.get("connected") == false:
		card.status.text = "DISCONNECTED"
	if count != 1 or accepted == null or accepted.server_tick < 0 or accepted.team != team:
		return
	if slot.get("connected") == true:
		card.status.text = "OUT" if accepted.eliminated else "IN THE ARENA"
	if is_finite(accepted.core_fraction) and accepted.core_fraction >= 0 and accepted.core_fraction <= 1:
		card.core.text = "CORE %d%%" % roundi(accepted.core_fraction * 100)

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and value >= minimum and value <= maximum and floorf(float(value)) == value
