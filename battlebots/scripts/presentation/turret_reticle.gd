class_name TurretReticle
extends Control
## B control presentation for mouse-aimed turrets. The centre crosshair is the
## player's aim; the ring marks where the authoritative barrel currently points,
## so the traverse lag stays visible. Drawing never feeds back into input.
var crosshair_visible := false
var barrel_visible := false
var barrel_point := Vector2.ZERO
var readiness := 1.0
var ready_color := Color(1.0, 0.78, 0.25)

func _init() -> void:
	name = "TurretReticle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func render(show_crosshair: bool, barrel_on_screen: bool, at: Vector2, fraction: float) -> void:
	var changed := show_crosshair != crosshair_visible or barrel_on_screen != barrel_visible \
		or at.distance_to(barrel_point) > 0.5 or absf(fraction - readiness) > 0.01
	crosshair_visible = show_crosshair
	barrel_visible = barrel_on_screen and show_crosshair
	barrel_point = at
	readiness = clampf(fraction, 0.0, 1.0)
	visible = crosshair_visible
	if changed:
		queue_redraw()

func _draw() -> void:
	if not crosshair_visible:
		return
	var centre := size * 0.5
	var unit := clampf(size.y / 1080.0, 0.6, 2.0)
	var shadow := Color(0, 0, 0, 0.55)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var a := centre + direction * 7.0 * unit
		var b := centre + direction * 17.0 * unit
		draw_line(a, b, shadow, 4.0 * unit)
		draw_line(a, b, Color(1, 1, 1, 0.92), 2.0 * unit)
	draw_circle(centre, 2.2 * unit, Color(1, 1, 1, 0.92))
	if not barrel_visible:
		return
	var radius := 22.0 * unit
	var ready := readiness >= 0.999
	var color := ready_color if ready else Color(0.75, 0.78, 0.8, 0.85)
	draw_arc(barrel_point, radius, 0.0, TAU, 48, shadow, 4.0 * unit)
	draw_arc(barrel_point, radius, 0.0, TAU, 48, Color(color, 0.35), 2.0 * unit)
	# Reload/charge progress sweeps clockwise from the top.
	if readiness > 0.0:
		draw_arc(barrel_point, radius, -PI * 0.5, -PI * 0.5 + TAU * readiness, 48, color, 2.5 * unit)
	for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(barrel_point + direction * (radius - 5.0 * unit), barrel_point + direction * (radius + 5.0 * unit), color, 2.0 * unit)
