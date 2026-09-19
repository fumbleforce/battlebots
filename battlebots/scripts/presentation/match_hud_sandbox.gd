extends Control
## Development-only fixture; these snapshots never enter a real session.
var _index := 0
var _views: Array[Dictionary] = [
	{"phase":"loading", "round":1, "remaining":30, "scores":[0, 0]},
	{"phase":"countdown", "round":1, "remaining":5, "scores":[0, 0]},
	{"phase":"active", "round":1, "remaining":128, "scores":[0, 0]},
	{"phase":"overtime", "round":1, "remaining":22, "scores":[0, 0]},
	{"phase":"intermission", "round":1, "remaining":15, "scores":[1, 0], "rounds":[{"round":1, "winner":0}]},
	{"phase":"results", "round":2, "remaining":20, "scores":[2, 0], "winner":0},
	{"phase":"results", "round":5, "remaining":20, "scores":[1, 1], "winner":-1},
	{},
	{"phase":"active", "round":1, "remaining":0, "scores":[0, 0]},
]

func _ready() -> void:
	_show()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_SPACE, KEY_RIGHT, KEY_LEFT]:
			_index = posmod(_index + (-1 if event.keycode == KEY_LEFT else 1), _views.size())
			_show()
			get_viewport().set_input_as_handled()

func _show() -> void:
	$MatchHud.render(_views[_index], _index == _views.size() - 1)
	$Instructions.text = "MOCK MATCH HUD FIXTURE — no simulation or network\nLeft / Right / Space: cycle snapshots (%d / %d)\nSnapshots remain frozen until you advance." % [_index + 1, _views.size()]
