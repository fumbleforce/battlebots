class_name SpreeBanner
extends Label
const HEAT_RELIEF = preload("res://scripts/core/heat_relief.gd")
## Kill-spree banner (#67): when the local bot's replicated spree combo rises,
## announce the kill, the combo and the heat it vented (data/heat_relief.json).
const SECONDS := 2.2
const FADE := 0.6
const NAMES := ["ELIMINATED", "DOUBLE KILL", "TRIPLE KILL", "QUAD KILL", "RAMPAGE"]
const COLOR := Color("ffd24a")
var session: MvpSession
var text_scale := 1.0
var _seen := 0
var _age := SECONDS

func bind_session(value: MvpSession) -> void:
	session = value

static func message(combo: int) -> String:
	var title: String = NAMES[clampi(combo, 1, NAMES.size()) - 1]
	var vented := roundi(HEAT_RELIEF.settings().kill_vent(combo))
	return ("%s   HEAT −%d" % [title, vented]) if combo <= 1 else ("%s  ×%d   HEAT −%d" % [title, combo, vented])

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_color_override("font_color", COLOR)
	add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02, 0.95))
	add_theme_constant_override("outline_size", 10)
	apply_text_scale(text_scale)
	hide()

func apply_text_scale(value: float) -> void:
	text_scale = clampf(value, 1.0, 1.5) if is_finite(value) else 1.0
	add_theme_font_size_override("font_size", roundi(40 * text_scale))

func _process(delta: float) -> void:
	var spree := 0
	if is_instance_valid(session) and session.local_source() != null:
		spree = session.local_source().read_view().spree
	if spree > _seen:
		text = message(spree)
		_age = 0.0
		scale = Vector2.ONE * 1.25
		show()
	_seen = spree
	if not visible:
		return
	_age += delta
	scale = scale.lerp(Vector2.ONE, 1.0 - exp(-delta * 12.0))
	modulate.a = clampf((SECONDS - _age) / FADE, 0.0, 1.0)
	if _age >= SECONDS:
		hide()
