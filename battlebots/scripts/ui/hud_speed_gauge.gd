class_name HudSpeedGauge
extends Control
## Speedometer bar driven only by the published BotView speed fields. The track
## spans 0-100% of the drive's normal top speed; with nitro fitted, an overdrive
## section slides in on top of it while nitro burns (or the bot is still above
## normal top speed), rescaling the track up to the nitro top speed.
const FONT := preload("res://ui/menus/fonts/Barlow-SemiBold.ttf")
const TEXT := Color("e8ecf1")
const MUTED := Color("9aa6b5")
const TRACK := Color("384553")
const FILL := Color("80aab9")
const TICK := Color("102730")
const BAR_HEIGHT := 8.0
## Exponential rates (1/s) for the needle and for the overdrive section growing
## in and settling out.
const NEEDLE_RATE := 14.0
const EXTEND_RATE := 9.0
const RETRACT_RATE := 4.0
var speed := NAN
var nitro_top := 1.0
var nitro_active := false
## Displayed speed and how far the overdrive section is shown (0-1).
var shown := 0.0
var extension := 0.0
var accent := Color("f5b82e")
var text_scale := 1.0
var high_contrast := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	apply_accessibility(text_scale, accent, high_contrast)

func apply_accessibility(font_scale: float, color: Color, contrast: bool) -> void:
	text_scale = clampf(font_scale, 1.0, 1.5) if is_finite(font_scale) else 1.0
	accent = color
	high_contrast = contrast
	custom_minimum_size.y = roundi(20 * text_scale) + 6 + BAR_HEIGHT
	size.y = custom_minimum_size.y
	queue_redraw()

func render(view: BotView) -> void:
	var value := view.speed_fraction if view != null else NAN
	speed = maxf(0.0, value) if is_finite(value) else NAN
	var top := view.nitro_speed_fraction if view != null else 1.0
	nitro_top = maxf(1.0, top) if is_finite(top) else 1.0
	nitro_active = view != null and view.nitro_active and nitro_top > 1.0
	if not is_finite(speed):
		shown = 0.0
		extension = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not visible or not is_finite(speed): return
	shown = lerpf(shown, speed, 1.0 - exp(-delta * NEEDLE_RATE))
	# Past nitro, the section stays while the bot is still over normal top speed.
	var target := 1.0 if nitro_active else (clampf((shown - 1.0) / (nitro_top - 1.0), 0.0, 1.0) if nitro_top > 1.0 else 0.0)
	extension = lerpf(extension, target, 1.0 - exp(-delta * (EXTEND_RATE if target > extension else RETRACT_RATE)))
	if extension < 0.001: extension = 0.0
	queue_redraw()

## Share of the bar width taken by 0-100%, given how far overdrive is shown.
func normal_width() -> float:
	return 1.0 / (1.0 + (nitro_top - 1.0) * extension)

func _draw() -> void:
	var title_size := roundi(13 * text_scale)
	var value_size := roundi(20 * text_scale)
	var ascent := FONT.get_ascent(value_size)
	var known := is_finite(speed)
	var boosting := known and (nitro_active or (nitro_top > 1.0 and shown > 1.0))
	var title := "SPEED  /  NITRO" if nitro_active else "SPEED"
	var value := "%d%%" % roundi(shown * 100.0) if known else "--"
	draw_string(FONT, Vector2(0, ascent), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size,
		accent if nitro_active else (Color.WHITE if high_contrast else MUTED))
	draw_string(FONT, Vector2(0, ascent), value, HORIZONTAL_ALIGNMENT_RIGHT, size.x, value_size,
		accent if boosting else (Color.WHITE if high_contrast else TEXT))
	var top := size.y - BAR_HEIGHT
	var normal := size.x * normal_width()
	var span := 1.0 / normal_width()
	draw_rect(Rect2(0, top, size.x, BAR_HEIGHT), TRACK)
	if normal < size.x:
		draw_rect(Rect2(normal, top, size.x - normal, BAR_HEIGHT), Color(accent, 0.28))
	if known:
		var fill := size.x * clampf(shown, 0.0, span) / span
		draw_rect(Rect2(0, top, minf(fill, normal), BAR_HEIGHT), Color.WHITE if high_contrast else FILL)
		if fill > normal:
			draw_rect(Rect2(normal, top, fill - normal, BAR_HEIGHT), accent)
	# Tenths of normal top speed across the whole track, overdrive included.
	for tick: int in range(1, ceili(span * 10.0)):
		var x := normal * tick / 10.0
		if tick % 10 != 0: draw_line(Vector2(x, top), Vector2(x, size.y), TICK, 1)
	# The 100% mark stands proud of the bar once overdrive is showing.
	if normal < size.x:
		draw_rect(Rect2(normal - 1, top - 3, 2, BAR_HEIGHT + 3), Color.WHITE if high_contrast else TEXT)
