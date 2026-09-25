class_name HudSpeedGauge
extends Control
## Speedometer dial driven only by the published BotView speed fields. The inner
## arc spans 0-100% of the drive's normal top speed; with nitro fitted, an outer
## overdrive ring sweeps in while nitro burns (or the bot is still above normal
## top speed) and fills with the extra share nitro adds, up to the nitro top speed.
const FONT := preload("res://ui/menus/fonts/Barlow-SemiBold.ttf")
const TEXT := Color("e8ecf1")
const TRACK := Color("384553")
const FILL := Color("80aab9")
const TICK := Color("102730")
## Dial sweep (radians, clockwise from lower left through the top) and ring
## geometry in unscaled canvas px.
const SWEEP_START := PI * 0.75
const SWEEP := PI * 1.5
const DIAL_SIZE := 76.0
const RING_WIDTH := 7.0
const NITRO_WIDTH := 4.0
const RING_GAP := 3.0
## Exponential rates (1/s) for the needle and for the overdrive ring sweeping
## in and settling out.
const NEEDLE_RATE := 14.0
const EXTEND_RATE := 9.0
const RETRACT_RATE := 4.0
var speed := NAN
var nitro_top := 1.0
var nitro_active := false
## Displayed speed and how far the overdrive ring is shown (0-1).
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
	# The dial grows with text so the reading keeps fitting inside it.
	custom_minimum_size = Vector2.ONE * DIAL_SIZE * text_scale
	size = custom_minimum_size
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
	# Past nitro, the ring stays while the bot is still over normal top speed.
	var target := 1.0 if nitro_active else (clampf((shown - 1.0) / (nitro_top - 1.0), 0.0, 1.0) if nitro_top > 1.0 else 0.0)
	extension = lerpf(extension, target, 1.0 - exp(-delta * (EXTEND_RATE if target > extension else RETRACT_RATE)))
	if extension < 0.001: extension = 0.0
	queue_redraw()

## Extra share of normal top speed nitro is currently adding (0 when none).
func overdrive() -> float:
	return clampf(shown - 1.0, 0.0, nitro_top - 1.0) if is_finite(speed) else 0.0

func _draw() -> void:
	var known := is_finite(speed)
	var boosting := known and extension > 0.0
	var dial := DIAL_SIZE * text_scale
	var center := Vector2(dial, dial) * 0.5
	var radius := dial * 0.5 - NITRO_WIDTH - RING_GAP - RING_WIDTH * 0.5
	var outline := Color(0.015, 0.02, 0.03, 0.95)
	# Normal range: 0-100% of top speed on the inner ring, tenths ticked.
	draw_arc(center, radius, SWEEP_START, SWEEP_START + SWEEP, 48, TRACK, RING_WIDTH, true)
	if known and shown > 0.0:
		draw_arc(center, radius, SWEEP_START, SWEEP_START + SWEEP * minf(shown, 1.0), 48,
			Color.WHITE if high_contrast else FILL, RING_WIDTH, true)
	for tick: int in range(1, 10):
		var angle := SWEEP_START + SWEEP * tick / 10.0
		var direction := Vector2.from_angle(angle)
		draw_line(center + direction * (radius - RING_WIDTH * 0.5), center + direction * (radius + RING_WIDTH * 0.5), TICK, 1)
	# Overdrive: the outer ring sweeps in from 0% and fills with nitro's extra share.
	if extension > 0.0 and nitro_top > 1.0:
		var outer := radius + RING_WIDTH * 0.5 + RING_GAP + NITRO_WIDTH * 0.5
		draw_arc(center, outer, SWEEP_START, SWEEP_START + SWEEP * extension, 48, Color(accent, 0.28), NITRO_WIDTH, true)
		var extra := overdrive() / (nitro_top - 1.0)
		if extra > 0.0:
			draw_arc(center, outer, SWEEP_START, SWEEP_START + SWEEP * minf(extra, extension), 48, accent, NITRO_WIDTH, true)
	# Reading in the dial's heart.
	var value_size := roundi(20 * text_scale)
	var value := "%d%%" % roundi(shown * 100.0) if known else "--"
	var baseline := center.y + FONT.get_ascent(value_size) * 0.5 - 1.0
	draw_string_outline(FONT, Vector2(0, baseline), value, HORIZONTAL_ALIGNMENT_CENTER, dial, value_size, 3, outline)
	draw_string(FONT, Vector2(0, baseline), value, HORIZONTAL_ALIGNMENT_CENTER, dial, value_size,
		accent if boosting else (Color.WHITE if high_contrast else TEXT))
