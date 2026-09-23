class_name HudJumpGauge
extends Control
## Charged-jump force bar driven only by the published BotView jump fields.
## Fills while Jump is held, then drains with the post-jump cooldown.
const FONT := preload("res://ui/menus/fonts/Barlow-SemiBold.ttf")
const COOLDOWN := 4.0
const TEXT := Color("e8ecf1")
const MUTED := Color("9aa6b5")
var charge := 0.0
var cooldown := 0.0
var accent := Color("f5b82e")
var text_scale := 1.0
var high_contrast := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	apply_accessibility(text_scale, accent, high_contrast)
	hide()

func apply_accessibility(font_scale: float, color: Color, contrast: bool) -> void:
	text_scale = clampf(font_scale, 1.0, 1.5) if is_finite(font_scale) else 1.0
	accent = color
	high_contrast = contrast
	custom_minimum_size.y = roundi(12 * text_scale) + 14
	size.y = custom_minimum_size.y
	queue_redraw()

func render(view: BotView, combat_active: bool) -> void:
	var value := view.jump_charge_fraction if view != null else 0.0
	var remaining := view.jump_cooldown if view != null else 0.0
	charge = clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
	cooldown = maxf(0.0, remaining) if is_finite(remaining) else 0.0
	visible = view != null and not view.eliminated and combat_active and (charge > 0.0 or cooldown > 0.0)
	queue_redraw()

func _draw() -> void:
	var font_size := roundi(12 * text_scale)
	var bar_top := size.y - 6.0
	var charging := charge > 0.0
	var fill := charge if charging else clampf(cooldown / COOLDOWN, 0.0, 1.0)
	var fill_color := accent if charging else (Color("9aa6b5") if high_contrast else Color("5d7280"))
	var title := "JUMP FORCE" if charging else "JUMP COOLDOWN"
	var ascent := FONT.get_ascent(font_size)
	var value := ("MAX" if charge >= 1.0 else "%d%%" % roundi(charge * 100.0)) if charging else "%.1f s" % cooldown
	# Outlined like the other free-floating HUD text so it reads over bright terrain.
	var outline := Color(0.015, 0.02, 0.03, 0.95)
	draw_string_outline(FONT, Vector2(0, ascent), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, outline)
	draw_string_outline(FONT, Vector2(0, ascent), value, HORIZONTAL_ALIGNMENT_RIGHT, size.x, font_size, 3, outline)
	draw_string(FONT, Vector2(0, ascent), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE if high_contrast else MUTED)
	draw_string(FONT, Vector2(0, ascent), value, HORIZONTAL_ALIGNMENT_RIGHT, size.x, font_size, accent if charge >= 1.0 else (Color.WHITE if high_contrast else TEXT))
	draw_rect(Rect2(-1, bar_top - 1, size.x + 2, 8), outline)
	draw_rect(Rect2(0, bar_top, size.x, 6), Color("384553"))
	draw_rect(Rect2(0, bar_top, size.x * fill, 6), fill_color)
	for tick: int in range(1, 10):
		var x := size.x * tick / 10.0
		draw_line(Vector2(x, bar_top), Vector2(x, size.y), Color("102730"), 1)
