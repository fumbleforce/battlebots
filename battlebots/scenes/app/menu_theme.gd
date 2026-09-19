class_name GameMenuTheme
extends RefCounted

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	var normal := _box(Color(0.105, 0.15, 0.19), Color(0.22, 0.31, 0.36))
	var hover := _box(Color(0.15, 0.25, 0.3), Color(0.22, 0.75, 0.85))
	var pressed := _box(Color(0.07, 0.32, 0.38), Color(0.22, 0.75, 0.85))
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(1, 0.74, 0.2)))
	theme.set_stylebox("panel", "PanelContainer", _box(Color(0.035, 0.055, 0.075, 0.98), Color(0.16, 0.29, 0.35)))
	theme.set_color("font_color", "Label", Color(0.87, 0.92, 0.94))
	theme.set_color("font_color", "Button", Color(0.92, 0.97, 1))
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme

static func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
