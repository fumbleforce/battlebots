extends PanelContainer
## Match-only instrument chrome. Geometry remains behind the read-only labels.

var text_factor := 1.0
var compact := true
var contrast := false
var accent := Color("f5b82e")
var cool := Color("6ecfe3")

func _ready() -> void:
	resized.connect(queue_redraw)

func configure(factor: float, is_compact: bool, high_contrast: bool, highlight: Color, colors: String) -> void:
	text_factor = factor
	compact = is_compact
	contrast = high_contrast
	accent = highlight
	cool = Color("ffcb94") if colors in ["deuteranopia", "protanopia"] else (Color("a7b7ff") if colors == "tritanopia" else Color("6ecfe3"))
	queue_redraw()

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var s := text_factor
	var edge := Color.WHITE if contrast else Color("526c7c")
	if compact:
		var badge := _chamfered(Rect2(Vector2.ZERO, size), 7 * s)
		_plate(badge, Color("263e4b"), Color("0d1820"), edge)
		_light(Vector2(9 * s, 1), Vector2(size.x - 20 * s, 1), accent)
		draw_line(Vector2(4 * s, 10 * s), Vector2(4 * s, size.y - 8 * s), accent, 2)
		_etch(Vector2(size.x - 17 * s, size.y - 6 * s), -1, cool)
		return
	var content: Control = $Content
	var result: Label = $Content/Result
	var caption: Control = $Content/Caption
	var body_end := size.y
	if result.visible:
		body_end = content.position.y + result.position.y - 1
	var center := size.x * 0.5
	var shield_half := maxf(71 * s, caption.get_combined_minimum_size().x * 0.5 + 12 * s)
	var neck := 60 * s
	var wing_top := 22 * s
	var wing_end := body_end - 5 * s
	if $Content/Scores/Local.visible:
		var left := PackedVector2Array([
			Vector2(0, wing_top + 9 * s), Vector2(9 * s, wing_top),
			Vector2(center - neck - 1, wing_top), Vector2(center - neck - 1, wing_end - 7 * s),
			Vector2(center - neck - 10 * s, wing_end), Vector2(11 * s, wing_end),
			Vector2(0, wing_end - 11 * s),
		])
		_plate(left, Color("28424d"), Color("111f29"), edge)
		var right := PackedVector2Array()
		for point: Vector2 in left:
			right.append(Vector2(size.x - point.x, point.y))
		_plate(right, Color("233b50"), Color("111b28"), edge)
		_light(Vector2(10 * s, wing_top), Vector2(center - shield_half - 6 * s, wing_top), accent)
		_light(Vector2(center + shield_half + 6 * s, wing_top), Vector2(size.x - 10 * s, wing_top), cool)
		_etch(Vector2(16 * s, wing_end - 4 * s), 1, accent)
		_etch(Vector2(size.x - 16 * s, wing_end - 4 * s), -1, cool)
		# Small clipped end caps and datum lines give the score wings a machined edge.
		draw_line(Vector2(0.5, wing_top + 11 * s), Vector2(0.5, wing_end - 12 * s), accent, 2)
		draw_line(Vector2(size.x - 0.5, wing_top + 11 * s), Vector2(size.x - 0.5, wing_end - 12 * s), cool, 2)
	var shield := PackedVector2Array([
		Vector2(center - shield_half + 9 * s, 0), Vector2(center + shield_half - 9 * s, 0),
		Vector2(center + shield_half, 9 * s), Vector2(center + neck, body_end - 11 * s),
		Vector2(center + neck - 11 * s, body_end), Vector2(center - neck + 11 * s, body_end),
		Vector2(center - neck, body_end - 11 * s), Vector2(center - shield_half, 9 * s),
	])
	_plate(shield, Color("304959"), Color("101c26"), edge)
	# Broad upper bevel catches the light; the center ticks are etched into it.
	var bevel := PackedVector2Array([
		shield[0], shield[1], Vector2(center + shield_half - 14 * s, 4 * s),
		Vector2(center - shield_half + 14 * s, 4 * s),
	])
	draw_colored_polygon(bevel, Color(0.48, 0.65, 0.72, 0.24))
	_light(Vector2(center - 23 * s, 0.5), Vector2(center + 23 * s, 0.5), accent)
	draw_line(Vector2(center - neck + 12 * s, body_end - 1), Vector2(center + neck - 12 * s, body_end - 1), Color(cool, 0.65), 1, true)
	for side: float in [-1.0, 1.0]:
		var x := center + side * (neck - 5 * s)
		draw_line(Vector2(x, body_end - 16 * s), Vector2(x - side * 6 * s, body_end - 9 * s), Color(accent, 0.85), 1, true)
	if result.visible:
		var result_top := body_end + 1
		var result_left := content.position.x + result.position.x - 6
		var result_plate := _chamfered(Rect2(Vector2(result_left, result_top), Vector2(result.size.x + 12, size.y - result_top)), 6 * s)
		_plate(result_plate, Color("1d303b"), Color("101b24"), edge)
		draw_line(Vector2(center - 22 * s, size.y - 0.5), Vector2(center + 22 * s, size.y - 0.5), accent, 1, true)

func _chamfered(rect: Rect2, cut: float) -> PackedVector2Array:
	cut = minf(cut, rect.size.y * 0.4)
	var p := rect.position
	var e := rect.end
	return PackedVector2Array([Vector2(p.x + cut, p.y), Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), Vector2(e.x, e.y - cut), Vector2(e.x - cut, e.y), Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut), Vector2(p.x, p.y + cut)])

func _plate(points: PackedVector2Array, upper: Color, lower: Color, edge: Color) -> void:
	var top := INF
	var bottom := -INF
	for point: Vector2 in points:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	var colors := PackedColorArray()
	for point: Vector2 in points:
		var color := upper.lerp(lower, (point.y - top) / maxf(1.0, bottom - top))
		colors.append(Color("071017") if contrast else Color(color, 0.94))
	draw_polygon(points, colors)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(edge, 1.0 if contrast else 0.8), 1, true)

func _light(from: Vector2, to: Vector2, color: Color) -> void:
	# Static layered lines give restrained luminous bloom without animation or textures.
	draw_line(from + Vector2(0, 2), to + Vector2(0, 2), Color(color, 0.08), 5, true)
	draw_line(from + Vector2(0, 1), to + Vector2(0, 1), Color(color, 0.22), 2, true)
	draw_line(from, to, Color(color, 1.0 if contrast else 0.85), 1, true)

func _etch(origin: Vector2, direction: float, color: Color) -> void:
	for i: int in 3:
		var start := origin + Vector2(direction * i * 5 * text_factor, 0)
		draw_line(start, start + Vector2(direction * 3 * text_factor, -3 * text_factor), Color(color, 0.5), 1, true)
