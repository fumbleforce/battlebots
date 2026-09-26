extends RefCounted
## Practice HUD cards (#97): drag a card by its background (anywhere its
## buttons, switches and boxes do not take the press) to move its whole
## overlay. The offset, in viewport pixels from where the overlay's own layout
## puts it, lasts for the session; the card is kept on screen.
var overlay: Control
var card: Control
var offset := Vector2.ZERO
var _dragging := false
var _from := Vector2.ZERO
var _start := Vector2.ZERO

func _init(owner: Control, handle: Control) -> void:
	overlay = owner
	card = handle
	card.gui_input.connect(_on_card_input)

func _on_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_from = event.global_position
		_start = offset
		card.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		offset = _start + event.global_position - _from
		overlay.call("_resize")
		card.accept_event()

## Places the overlay at base (its layout position) plus the offset, pulling
## the offset back so the card stays inside the viewport.
func place(base: Vector2) -> void:
	overlay.position = base + offset
	var bounds := overlay.get_viewport_rect()
	var rect := card.get_global_rect()
	if rect.size == Vector2.ZERO:
		return
	var shift := Vector2(
		clampf(rect.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - rect.size.x)) - rect.position.x,
		clampf(rect.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - rect.size.y)) - rect.position.y)
	if not shift.is_zero_approx():
		offset += shift
		overlay.position += shift
