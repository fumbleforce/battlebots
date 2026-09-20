class_name CombatAudioStatus
extends RefCounted
## Edges in accepted local state; this does not claim an attack is affordable.
const PANELS := ["front", "rear", "left", "right"]
const FAMILIES := ["vertical_spinner", "horizontal_spinner", "lifter", "saw", "hammer"]
const STATES := [&"idle", &"active", &"launch", &"cooldown", &"disabled", &"overheated", &"strike", &"windup"]
var _entity := 0
var _family := ""
var _tick := -1
var _panels: Dictionary = {}
var _weapon_valid := false
var _armed := false
var _cooldown := 0.0

func reset() -> void:
	_entity = 0
	_family = ""
	_tick = -1
	_clear_baseline()

func _clear_baseline() -> void:
	_panels.clear()
	_weapon_valid = false
	_armed = false
	_cooldown = 0.0

func observe(view: BotView, weapon: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if view == null or view.entity_id <= 0 or view.server_tick < 0:
		reset()
		return events
	if view.entity_id == _entity and view.server_tick <= _tick:
		return events
	if view.entity_id != _entity or weapon != _family:
		_clear_baseline()
	_entity = view.entity_id
	_family = weapon
	_tick = view.server_tick
	if view.eliminated:
		_clear_baseline()
		return events
	var broken: Array[String] = []
	for panel in PANELS:
		var integrity: Variant = view.zones.get(panel)
		if not _number(integrity) or float(integrity) < 0.0:
			_panels.erase(panel)
			continue
		if _panels.has(panel) and float(_panels[panel]) > 0.0 and float(integrity) == 0.0:
			broken.append(panel)
		_panels[panel] = float(integrity)
	if not broken.is_empty():
		events.append({"cue": "armor_break", "caption": "Armor breached: " + ", ".join(broken)})
	if weapon not in FAMILIES or view.weapon_state not in STATES:
		_weapon_valid = false
		return events
	if weapon == "hammer":
		if not is_finite(view.weapon_cooldown) or view.weapon_cooldown < 0.0:
			_weapon_valid = false
			return events
		if _weapon_valid and _cooldown > 0.0 and view.weapon_cooldown == 0.0 and view.weapon_state == &"idle":
			events.append({"cue": "weapon_ready", "caption": "Hammer cooldown complete"})
		_cooldown = view.weapon_cooldown
		_weapon_valid = true
		return events
	var charge := view.weapon_charge_fraction
	if not is_finite(charge) or charge < 0.0 or charge > 1.0:
		_weapon_valid = false
		return events
	var rearm := charge == 0.0 if weapon == "saw" else charge < 0.9
	if not _weapon_valid:
		_armed = charge < 1.0
		_weapon_valid = true
		return events
	if rearm:
		_armed = true
	if _armed and charge == 1.0 and view.weapon_state == &"active":
		_armed = false
		var caption := "Spinner at full speed"
		if weapon == "lifter":
			caption = "Lift charged"
		elif weapon == "saw":
			caption = "Saw running"
		events.append({"cue": "weapon_ready", "caption": caption})
	return events

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
