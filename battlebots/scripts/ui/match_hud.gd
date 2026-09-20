class_name MatchHud
extends Control
## Read-only authoritative MatchState snapshot. Never advances time or judges winners.

const PHASES := {"lobby":"LOBBY", "loading":"LOADING", "countdown":"GET READY", "active":"", "overtime":"OVERTIME", "intermission":"INTERMISSION", "results":"MATCH COMPLETE"}
var text_scale := 1.0
var palette := "standard"
var high_contrast := false
var accent := Color("f5b82e")
var panel_width := 380.0
var _compact := true
var _highlight_timer := false

@onready var phase_label: Label = $Panel/Content/Caption/Phase
@onready var round_label: Label = $Panel/Content/Caption/Round
@onready var timer_label: Label = $Panel/Content/Scores/Timer
@onready var timer_caption: Label = $Panel/Content/Caption/TimerCaption
@onready var score_label: Label = $Panel/Content/Scores/Local/Score
@onready var opponent_score_label: Label = $Panel/Content/Scores/Opponent/Score
@onready var local_name_label: Label = $Panel/Content/Scores/Local/Name
@onready var opponent_name_label: Label = $Panel/Content/Scores/Opponent/Name
@onready var result_label: Label = $Panel/Content/Result

func _ready() -> void:
	$Panel.minimum_size_changed.connect(_fit_content)
	get_viewport().size_changed.connect(_resize)
	apply_accessibility(text_scale, palette, high_contrast)
	render({})

func apply_accessibility(value: float, colors: String, contrast: bool) -> void:
	text_scale = clampf(value, 1.0, 1.5) if is_finite(value) else 1.0
	palette = colors if colors in ["standard", "deuteranopia", "protanopia", "tritanopia"] else "standard"
	high_contrast = contrast
	accent = {"standard":Color("f5b82e"), "deuteranopia":Color("82cfff"), "protanopia":Color("82cfff"), "tritanopia":Color("ffcc91")}[palette]
	if not is_node_ready():
		return
	var sizes := {phase_label:11, round_label:11, timer_caption:11, timer_label:34, score_label:26, opponent_score_label:26, local_name_label:11, opponent_name_label:11, result_label:14}
	for label: Label in sizes:
		label.add_theme_font_size_override("font_size", roundi(sizes[label] * text_scale))
		label.add_theme_color_override("font_color", Color.WHITE if high_contrast else Color("f1f0eb"))
	for label: Label in [round_label, opponent_name_label]:
		label.add_theme_color_override("font_color", Color.WHITE if high_contrast else Color("aeb6bc"))
	for label: Label in [phase_label, timer_caption, local_name_label, result_label]:
		label.add_theme_color_override("font_color", accent)
	_update_timer_color()
	timer_label.custom_minimum_size.x = 104.0 * text_scale
	$Panel/Content/Scores/Local.custom_minimum_size.x = 90.0 * text_scale
	$Panel/Content/Scores/Opponent.custom_minimum_size.x = 90.0 * text_scale
	_fit_content()

func _update_timer_color() -> void:
	timer_label.add_theme_color_override("font_color", accent if _highlight_timer else (Color.WHITE if high_contrast else Color("f1f0eb")))

func _fit_content() -> void:
	var panel: Control = $Panel
	panel_width = (108.0 if _compact else 380.0) * text_scale
	var minimum := panel.get_combined_minimum_size()
	panel.size = Vector2(maxf(panel_width, minimum.x), minimum.y)
	panel.configure(text_scale, _compact, high_contrast, accent, palette)
	_resize()

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
	var panel: Control = $Panel
	panel.scale = Vector2.ONE * ratio
	panel.position = Vector2((extent.x - panel.size.x * ratio) * 0.5, 24.0 * ratio)

func render(view: Dictionary, practice: bool = false, local_team: int = -1) -> void:
	phase_label.text = "PRACTICE" if practice else "MATCH UNAVAILABLE"
	phase_label.visible = true
	round_label.text = "ROUND —"
	timer_label.text = "--:--"
	score_label.text = "—"
	opponent_score_label.text = "—"
	local_name_label.text = "YOU" if local_team in [0, 1] else "TEAM A"
	opponent_name_label.text = "RIVAL" if local_team in [0, 1] else "TEAM B"
	result_label.text = ""
	timer_caption.text = ""
	timer_caption.visible = false
	_highlight_timer = false
	_update_timer_color()
	round_label.visible = false
	_set_score_visibility(false)
	timer_label.visible = false
	result_label.visible = false
	_compact = true
	if practice:
		_fit_content.call_deferred()
		return
	var phase: Variant = view.get("phase")
	if not phase is String or not PHASES.has(phase):
		_fit_content.call_deferred()
		return
	phase_label.text = PHASES[phase]
	if phase == "lobby":
		_fit_content.call_deferred()
		return
	_compact = false
	round_label.visible = true
	timer_label.visible = true
	_set_score_visibility(view.get("mode") != "ffa")
	phase_label.visible = phase == "overtime"
	var round_value: Variant = view.get("round")
	if _integer_in(round_value, 1, 999):
		round_label.text = "ROUND %d" % int(round_value)
	match phase:
		"loading": timer_caption.text = "LOADING"
		"countdown": timer_caption.text = "STARTS IN"
		"intermission": timer_caption.text = "NEXT ROUND IN"
		"results": timer_caption.text = "LOBBY IN"
	timer_caption.visible = not timer_caption.text.is_empty()
	var remaining: Variant = view.get("remaining")
	if _number(remaining) and remaining >= 0 and remaining <= 86400:
		var seconds := ceili(float(remaining))
		timer_label.text = str(seconds) if phase == "countdown" else "%d:%02d" % [seconds / 60, seconds % 60]
		_highlight_timer = phase in ["countdown", "overtime"]
		_update_timer_color()
	if view.get("mode") == "ffa":
		round_label.text = "FREE FOR ALL"
		if phase == "results":
			result_label.visible = true
			var winners: Variant = view.get("winners", [])
			var names := PackedStringArray()
			if winners is Array:
				for id: Variant in winners:
					if _integer_in(id, 1, 2147483647):
						names.append("Player %d" % int(id))
			result_label.text = "Result unavailable" if names.is_empty() else ", ".join(names) + (" wins" if names.size() == 1 else " share the win")
		_fit_content.call_deferred()
		return
	var scores: Variant = view.get("scores")
	if scores is Array and scores.size() == 2 and _integer_in(scores[0], 0, 999) and _integer_in(scores[1], 0, 999):
		var left_team := local_team if local_team in [0, 1] else 0
		score_label.text = str(int(scores[left_team]))
		opponent_score_label.text = str(int(scores[1 - left_team]))
	if phase == "results":
		result_label.visible = true
		result_label.text = _winner_text(view.get("winner"), true, local_team)
	elif phase == "intermission":
		result_label.visible = true
		result_label.text = "Round result unavailable"
		var rounds: Variant = view.get("rounds")
		if rounds is Array and not rounds.is_empty() and rounds.back() is Dictionary:
			var last: Dictionary = rounds.back()
			if _integer_in(round_value, 1, 999) and _integer_in(last.get("round"), 1, 999) and last.round == round_value:
				result_label.text = _winner_text(last.get("winner"), false, local_team)
	_fit_content.call_deferred()

func _set_score_visibility(shown: bool) -> void:
	# Set labels as well as their containers: existing consumers inspect visibility.
	for node: Control in [score_label, opponent_score_label, local_name_label, opponent_name_label, $Panel/Content/Scores/Local, $Panel/Content/Scores/Opponent, $Panel/Content/Scores/LeftDivider, $Panel/Content/Scores/RightDivider]:
		node.visible = shown
	$Panel/Content/Scores.alignment = BoxContainer.ALIGNMENT_BEGIN if shown else BoxContainer.ALIGNMENT_CENTER

func _winner_text(winner: Variant, match_result: bool, local_team: int = -1) -> String:
	var scope := "Match" if match_result else "Round"
	if not _integer_in(winner, -1, 1):
		return scope + " result unavailable"
	if winner == -1:
		return scope + " drawn"
	if local_team in [0, 1]:
		return scope + (" won" if winner == local_team else " lost")
	return "Team %s wins %s" % ["A" if winner == 0 else "B", "the match" if match_result else "the round"]

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and value >= minimum and value <= maximum and float(value) == floorf(float(value))
