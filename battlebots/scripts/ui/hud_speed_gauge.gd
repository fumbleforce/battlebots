class_name HudSpeedGauge
extends Control
## Speedometer dial driven only by the published BotView speed fields. The inner
## arc spans 0-100% of the drive's normal top speed; with nitro fitted, an outer
## nitro-blue ring is always shown as a dim track and fills with the extra share
## nitro adds, up to the nitro top speed.
## Inside, the actual speed in km/h sits small above the share of top speed.
const FONT := preload("res://ui/menus/fonts/Barlow-SemiBold.ttf")
const TEXT := Color("e8ecf1")
const MUTED := Color("9aa6b5")
const TRACK := Color("384553")
const FILL := Color("80aab9")
const TICK := Color("102730")
## Nitro blue, after the exhaust flame (nitro_flame.gdshader body colour),
## lightened to read on the dark instrument panels.
const NITRO := Color("4da3ff")
## Dial sweep (radians, clockwise from lower left through the top). The open
## bottom lets the circle overhang the dial's height, so the rings reach from
## the top edge to the bottom edge.
const SWEEP_START := PI * 0.75
const SWEEP := PI * 1.5
## Ring geometry in canvas px, and the default height before the HUD fits it.
const DIAL_HEIGHT := 60.0
const RING_WIDTH := 6.0
const NITRO_WIDTH := 4.0
const RING_GAP := 2.0
## Reading font sizes as shares of the outer radius.
const VALUE_FONT := 0.5
const SPEED_FONT := 0.3
const KMH_PER_MPS := 3.6
## Exponential rate (1/s) for the needle.
const NEEDLE_RATE := 14.0
var speed := NAN
var nitro_top := 1.0
var nitro_active := false
## Normal top speed (m/s) for the km/h reading; 0 when unknown.
var top_speed := 0.0
## Game settings toggle for the km/h line; the share of top speed always shows.
var show_speed_value := true:
	set(value):
		show_speed_value = value
		queue_redraw()
## Displayed speed.
var shown := 0.0
var high_contrast := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if custom_minimum_size == Vector2.ZERO: fit_height(DIAL_HEIGHT)

func apply_accessibility(contrast: bool) -> void:
	high_contrast = contrast
	queue_redraw()

## Sizes the dial to a given height; the width follows from the open bottom.
func fit_height(height: float) -> void:
	custom_minimum_size = Vector2(ceilf(2.0 * _radius(height)), height)

func _radius(height: float) -> float:
	return height / (1.0 + sin(PI * 0.25))

func render(view: BotView) -> void:
	var value := view.speed_fraction if view != null else NAN
	speed = maxf(0.0, value) if is_finite(value) else NAN
	var top := view.nitro_speed_fraction if view != null else 1.0
	nitro_top = maxf(1.0, top) if is_finite(top) else 1.0
	nitro_active = view != null and view.nitro_active and nitro_top > 1.0
	top_speed = view.top_speed if view != null and is_finite(view.top_speed) and view.top_speed > 0.0 else 0.0
	if not is_finite(speed): shown = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	if not visible or not is_finite(speed): return
	shown = lerpf(shown, speed, 1.0 - exp(-delta * NEEDLE_RATE))
	queue_redraw()

## Extra share of normal top speed nitro is currently adding (0 when none).
func overdrive() -> float:
	return clampf(shown - 1.0, 0.0, nitro_top - 1.0) if is_finite(speed) else 0.0

## The displayed actual speed, or "--" when speed or top speed is unknown.
func speed_text() -> String:
	return "%d km/h" % roundi(shown * top_speed * KMH_PER_MPS) if is_finite(speed) and top_speed > 0.0 else "-- km/h"

func _draw() -> void:
	var known := is_finite(speed)
	var boosting := known and (nitro_active or overdrive() > 0.0)
	var outer_radius := _radius(size.y)
	var center := Vector2(size.x * 0.5, outer_radius)
	var outer := outer_radius - NITRO_WIDTH * 0.5
	var radius := outer_radius - NITRO_WIDTH - RING_GAP - RING_WIDTH * 0.5
	var outline := Color(0.015, 0.02, 0.03, 0.95)
	# Normal range: 0-100% of top speed on the inner ring, tenths ticked.
	draw_arc(center, radius, SWEEP_START, SWEEP_START + SWEEP, 48, TRACK, RING_WIDTH, true)
	if known and shown > 0.0:
		draw_arc(center, radius, SWEEP_START, SWEEP_START + SWEEP * minf(shown, 1.0), 48,
			Color.WHITE if high_contrast else FILL, RING_WIDTH, true)
	for tick: int in range(1, 10):
		var direction := Vector2.from_angle(SWEEP_START + SWEEP * tick / 10.0)
		draw_line(center + direction * (radius - RING_WIDTH * 0.5), center + direction * (radius + RING_WIDTH * 0.5), TICK, 1)
	# Overdrive: with nitro fitted the outer track always shows and fills with nitro's extra share.
	if nitro_top > 1.0:
		draw_arc(center, outer, SWEEP_START, SWEEP_START + SWEEP, 48, Color(NITRO, 0.28), NITRO_WIDTH, true)
		var extra := overdrive() / (nitro_top - 1.0)
		if extra > 0.0:
			draw_arc(center, outer, SWEEP_START, SWEEP_START + SWEEP * extra, 48, NITRO, NITRO_WIDTH, true)
	# Readings: km/h small above the share of top speed.
	var value_size := roundi(outer_radius * VALUE_FONT)
	var speed_size := roundi(outer_radius * SPEED_FONT)
	var value := "%d%%" % roundi(shown * 100.0) if known else "--"
	# Alone, the share sits centred on the hub.
	var value_base := center.y + FONT.get_ascent(value_size) * (0.75 if show_speed_value else 0.5)
	var speed_base := value_base - FONT.get_ascent(value_size) - 2.0
	if show_speed_value:
		_reading(speed_text(), speed_base, speed_size, Color.WHITE if high_contrast else MUTED, outline)
	_reading(value, value_base, value_size, NITRO if boosting else (Color.WHITE if high_contrast else TEXT), outline)

func _reading(text: String, baseline: float, font_size: int, color: Color, outline: Color) -> void:
	draw_string_outline(FONT, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 3, outline)
	draw_string(FONT, Vector2(0, baseline), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)
