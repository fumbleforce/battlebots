extends Button
## Mode select card. Toggle button; the SELECTED badge follows button_pressed.

var data: Dictionary


func _ready() -> void:
	toggled.connect(_on_toggled)
	_on_toggled(button_pressed)


func setup(m: Dictionary) -> void:
	data = m
	%Tint.color = m.tint
	%Big.text = m.big
	%Tag.text = m.tag
	%Title.text = m.title
	%Desc.text = m.desc
	%Meta1.text = m.meta1
	%Meta2.text = m.meta2


func _on_toggled(on: bool) -> void:
	%Selected.visible = on
