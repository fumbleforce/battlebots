class_name SettingsCategoryFrame
extends CenterContainer
## A fixed reference page keeps every category action visible without scrolling.
func _ready() -> void:
	get_viewport().size_changed.connect(_resize)
	_resize()

func _resize() -> void:
	var extent := get_viewport_rect().size
	var ratio := minf(extent.x / 1600.0, extent.y / 900.0)
	size = Vector2(1600, 900)
	scale = Vector2.ONE * ratio
	position = (extent - size * ratio) * 0.5
