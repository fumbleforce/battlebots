extends Control
## Segmented rotor instrument driven only by the published charge fraction.
const FONT := preload("res://ui/menus/fonts/BarlowCondensed-SemiBold.ttf")
var fraction := NAN
var accent := Color("f5b82e")
var text_scale := 1.0
var high_contrast := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func render(value: float, color: Color, font_scale: float, contrast: bool) -> void:
	fraction = value
	accent = color
	text_scale = font_scale
	high_contrast = contrast
	custom_minimum_size = Vector2.ONE * (58 if font_scale == 1.0 else 72)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4
	var valid := is_finite(fraction) and fraction >= 0 and fraction <= 1
	draw_arc(center, radius - 7, 0, TAU, 48, Color(0.37, 0.64, 0.73, 0.25), 1, true)
	for index: int in 20:
		var start := -PI * 0.5 + index * TAU / 20.0
		var color := accent if valid and float(index) < fraction * 20 else (Color("718c99") if high_contrast else Color("365561"))
		draw_arc(center, radius, start + 0.04, start + TAU / 20 - 0.04, 5, color, 3, true)
	var value := "%d%%" % roundi(fraction * 100) if valid else "--"
	var font_size := roundi(16 * text_scale)
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(FONT, Vector2(center.x - width * 0.5, center.y + FONT.get_ascent(font_size) * 0.35), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("edf6f8"))
