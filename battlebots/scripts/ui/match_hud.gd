class_name MatchHud
extends Control
## Read-only authoritative MatchState snapshot. Never advances time or judges winners.

const PHASES := {"lobby":"LOBBY", "loading":"LOADING", "countdown":"GET READY", "active":"FIGHT", "overtime":"OVERTIME", "intermission":"INTERMISSION", "results":"MATCH COMPLETE"}
@onready var phase_label: Label = $Panel/Content/Phase
@onready var round_label: Label = $Panel/Content/Round
@onready var timer_label: Label = $Panel/Content/Timer
@onready var timer_caption: Label = $Panel/Content/TimerCaption
@onready var score_label: Label = $Panel/Content/Score
@onready var result_label: Label = $Panel/Content/Result

func _ready() -> void:
	$Panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	$Panel.minimum_size_changed.connect(_fit_content)
	get_viewport().size_changed.connect(_resize)
	_resize()
	render({})

func _fit_content() -> void:
	var panel: Control = $Panel
	panel.size = Vector2(416.0, panel.get_combined_minimum_size().y)

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1280.0, extent.y / 720.0)
	var panel: Control = $Panel
	panel.scale = Vector2.ONE * ratio
	panel.position = Vector2((extent.x - 416.0 * ratio) * 0.5, 24.0 * ratio)

func render(view: Dictionary, practice: bool = false, local_team: int = -1) -> void:
	phase_label.text = "PRACTICE" if practice else "MATCH UNAVAILABLE"
	round_label.text = "Round unavailable"
	timer_label.text = "Time unavailable"
	score_label.text = "Score unavailable"
	result_label.text = ""
	timer_caption.text = ""
	timer_caption.visible = false
	timer_label.add_theme_color_override("font_color", Color("e8ecf1"))
	round_label.visible = not practice
	timer_label.visible = not practice
	score_label.visible = not practice
	result_label.visible = false
	if practice:
		return
	var phase: Variant = view.get("phase")
	if not phase is String or not PHASES.has(phase):
		return
	phase_label.text = PHASES[phase]
	if phase == "lobby":
		round_label.visible = false
		timer_label.visible = false
		score_label.visible = false
		return
	var round_value: Variant = view.get("round")
	if _integer_in(round_value, 1, 999):
		round_label.text = "ROUND %d" % int(round_value)
	var remaining: Variant = view.get("remaining")
	if _number(remaining) and remaining >= 0 and remaining <= 86400:
		var seconds := ceili(float(remaining))
		var time := "%d:%02d" % [seconds / 60, seconds % 60]
		match phase:
			"loading": timer_caption.text = "LOADING TIMEOUT"
			"countdown": timer_caption.text = "STARTS IN"
			"intermission": timer_caption.text = "NEXT ROUND IN"
			"results": timer_caption.text = "LOBBY IN"
			_: timer_label.text = time
		timer_label.text = str(seconds) if phase == "countdown" else time
		timer_caption.visible = not timer_caption.text.is_empty()
		if phase == "countdown" or phase == "overtime":
			timer_label.add_theme_color_override("font_color", Color("f5b82e"))
	if view.get("mode") == "ffa":
		round_label.text = "FREE FOR ALL"
		score_label.visible = false
		if phase == "results":
			result_label.visible = true
			var winners: Variant = view.get("winners", [])
			var names := PackedStringArray()
			if winners is Array:
				for id: Variant in winners:
					if _integer_in(id, 1, 2147483647):
						names.append("Player %d" % int(id))
			result_label.text = "Result unavailable" if names.is_empty() else ", ".join(names) + (" wins" if names.size() == 1 else " share the win")
		return
	var scores: Variant = view.get("scores")
	if scores is Array and scores.size() == 2 and _integer_in(scores[0], 0, 999) and _integer_in(scores[1], 0, 999):
		score_label.text = "TEAM A  %d  :  %d  TEAM B" % [int(scores[0]), int(scores[1])]
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
