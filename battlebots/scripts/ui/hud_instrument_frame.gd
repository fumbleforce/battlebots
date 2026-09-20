extends PanelContainer
## Original vector instrument housing; cut steel silhouette and luminous rails.
var accent := Color("f5b82e")
var high_contrast := false
var mirrored := false

func _ready() -> void:
	resized.connect(queue_redraw)

func configure(color: Color, contrast: bool) -> void:
	accent = color
	high_contrast = contrast
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 32 or h < 20: return
	var points := PackedVector2Array([Vector2(0, 8), Vector2(8, 0), Vector2(w - 22, 0), Vector2(w, 16), Vector2(w, h - 8), Vector2(w - 8, h), Vector2(18, h), Vector2(0, h - 16)])
	var top := Color(0.10, 0.19, 0.24, 0.94)
	var bottom := Color(0.025, 0.065, 0.085, 0.72)
	if high_contrast:
		top = Color("101f28")
		bottom = Color("071015")
	draw_polygon(points, PackedColorArray([top, top, top, top, bottom, bottom, bottom, bottom]))
	var edge := Color.WHITE if high_contrast else Color(0.40, 0.64, 0.73, 0.65)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, edge, 1.0, true)
	var rail_start := Vector2(w - 18, h - 1) if mirrored else Vector2(9, 1)
	var rail_end := rail_start + Vector2(-w * 0.34, 0) if mirrored else rail_start + Vector2(w * 0.34, 0)
	draw_line(rail_start, rail_end, Color(accent, 0.12), 7, true)
	draw_line(rail_start, rail_end, accent, 2, true)
	draw_line(Vector2(20, h - 5), Vector2(w - 26, h - 5), Color(edge, 0.20), 1, true)
	# Sparse machined index marks; these never imply a gameplay measurement.
	for index: int in 4:
		var x := w - 56 + index * 7
		draw_line(Vector2(x, 3), Vector2(x + 4, 7), Color(edge, 0.45), 1, true)
	draw_circle(Vector2(6, h - 19), 1.5, edge)
	draw_circle(Vector2(w - 6, 20), 1.5, edge)
