class_name PickupNotice
extends Label
## Centred, briefly shown explanation when the server refuses a pickup the local
## player touched (perk or part already fitted, or it cannot fit this build).
const SECONDS := 2.5
const FADE := 0.5
const COLOR := Color("ffb45e")
var text_scale := 1.0
var _age := SECONDS

static func message(event: Dictionary, names: Dictionary) -> String:
	var name := PickupFeed.describe(event, names)
	if event.get("reason") == "equipped":
		return name + (" ALREADY EQUIPPED" if event.get("kind") == "perk" else " ALREADY FITTED")
	return name + " DOESN'T FIT YOUR BUILD"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A snug dark backing keeps amber text readable over bright hulls and floors.
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.03, 0.04, 0.05, 0.78)
	backing.set_corner_radius_all(4)
	backing.content_margin_left = 12
	backing.content_margin_right = 12
	backing.content_margin_top = 3
	backing.content_margin_bottom = 3
	add_theme_stylebox_override("normal", backing)
	add_theme_color_override("font_color", COLOR)
	add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.05, 0.9))
	add_theme_constant_override("outline_size", 6)
	apply_text_scale(text_scale)
	hide()

func apply_text_scale(value: float) -> void:
	text_scale = clampf(value, 1.0, 1.5) if is_finite(value) else 1.0
	add_theme_font_size_override("font_size", roundi(18 * text_scale))

func notify(event: Dictionary, names: Dictionary) -> void:
	text = message(event, names)
	_age = 0.0
	modulate.a = 1.0
	show()

func clear() -> void:
	_age = SECONDS
	hide()

func _process(delta: float) -> void:
	if not visible:
		return
	_age += delta
	modulate.a = clampf((SECONDS - _age) / FADE, 0.0, 1.0)
	if _age >= SECONDS:
		hide()
