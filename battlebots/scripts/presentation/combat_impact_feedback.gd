class_name CombatImpactFeedback
extends Node3D
## Confirms event context before creating cosmetic effects; never predicts a hit.
const PHASES := ["lobby", "loading", "countdown", "active", "overtime", "intermission", "results"]
const KINDS := ["hammer", "saw", "lifter", "vertical_spinner", "horizontal_spinner", "ram", "crush", "ram_punch", "spear", "grinder"]
const CONTEXT_LIMIT := 16
## BotPartLoss (scripts/presentation/bot_part_loss.gd) group.
const PART_LOSS_GROUP := &"bot_part_loss"
## A Tesla discharge reports its first target, then (same attacker, tick and
## attack_id) the bot it chains to. That second event draws the chain arc on
## the shooter's turret (TurretSpecialEffects.CHAIN_GROUP); Tesla hits make no
## generic impact sparks here.
const CHAIN_KIND := "tesla"
const DAMAGE_NUMBERS := preload("res://scripts/presentation/damage_numbers.gd")
var visual: CombatImpactVisual
## Floating damage numbers for every accepted damaging hit (#85).
var damage_numbers: DAMAGE_NUMBERS
## Game settings toggles (game_preferences.gd): numbers on other bots, and on
## the local player's own bot.
var show_damage_numbers := true
var show_player_damage_numbers := true
## Bot-on-bot rams report the attacker's centre; their numbers start where the
## hulls met (see _collision_point).
const COLLISION_KINDS := ["ram"]
var session: MvpSession
var _bound := false
var _match := ""
var _round := 0
var _phase := ""
var _phase_event := -1
var _practice := false
var _watermarks: Dictionary = {}
var _contexts: Dictionary = {}
var _network_match := ""
var _retired: Array[String] = []
## Attacker entity -> its latest accepted Tesla hit {tick, attack_id, target, position}.
var _discharges: Dictionary = {}

func _ready() -> void:
	visual = CombatImpactVisual.new()
	add_child(visual)
	damage_numbers = DAMAGE_NUMBERS.new()
	damage_numbers.name = "DamageNumbers"
	add_child(damage_numbers)

func set_damage_numbers(others: bool, own: bool) -> void:
	if (show_damage_numbers and not others) or (show_player_damage_numbers and not own):
		if damage_numbers != null: damage_numbers.clear()
	show_damage_numbers = others
	show_player_damage_numbers = own

func bind_session(value: MvpSession) -> void:
	if is_instance_valid(session):
		session.combat_event.disconnect(_session_impact)
		session.session_event.disconnect(_session_changed)
	reset()
	session = value
	_bound = is_instance_valid(session)
	if is_instance_valid(session):
		session.combat_event.connect(_session_impact)
		session.session_event.connect(_session_changed)

func _process(_delta: float) -> void:
	if not is_instance_valid(session):
		if _bound:
			reset()
			_bound = false
		return
	if session.connection_state not in ["hosting", "connected", "practice"]:
		if not _match.is_empty(): reset()
		return
	observe_match(session.match_view, session.connection_state == "practice")

func _session_changed(kind: String, _details: Dictionary) -> void:
	if kind in ["practice", "practice_restarted", "left"]: reset()

func _session_impact(event: Dictionary) -> void:
	if not is_instance_valid(session) or session.connection_state not in ["hosting", "connected", "practice"]:
		reset()
		return
	observe_match(session.match_view, session.connection_state == "practice")
	combat_event(event)

func reset() -> void:
	if _practice:
		_contexts.erase(_match)
		for key: String in _watermarks.keys():
			if key.begins_with(_match + "/"): _watermarks.erase(key)
	_match = ""
	_round = 0
	_phase = ""
	_phase_event = -1
	_practice = false
	_discharges.clear()
	_clear_effects()

func observe_match(view: Dictionary, practice := false) -> void:
	if not view.get("match_id") is String or view.match_id.is_empty() or view.match_id.length() > 128 \
		or not view.get("phase") is String or view.phase not in PHASES \
		or not _integer(view.get("round"), 0 if view.phase == "lobby" else 1) \
		or not _integer(view.get("event_id"), 0):
		_phase = ""
		_clear_effects()
		return
	if not practice and view.match_id in _retired: return
	var saved: Dictionary = _contexts.get(view.match_id, {})
	if not saved.is_empty() and (view.round < saved.round or view.event_id < saved.event \
		or (view.event_id == saved.event and (view.phase != saved.phase or view.round != saved.round))): return
	if not practice and view.match_id != _network_match:
		if not _network_match.is_empty(): _retired.append(_network_match)
		if _retired.size() > CONTEXT_LIMIT: _retired.pop_front()
		_network_match = view.match_id
	if _match != view.match_id or _round != view.round or _phase != view.phase:
		_discharges.clear()
		_clear_effects()
	_match = view.match_id
	_round = view.round
	_phase = view.phase
	_phase_event = view.event_id
	_practice = practice
	_contexts[_match] = {"round": _round, "phase": _phase, "event": _phase_event}
	_trim(_contexts)

func combat_event(event: Dictionary) -> void:
	if visual == null or _match.is_empty() or _phase not in ["active", "overtime"] \
		or not _integer(event.get("event_id"), 1) or not _integer(event.get("round"), 1) \
		or event.round != _round or not _integer(event.get("tick"), 0) \
		or not _integer(event.get("attacker"), 1) or not _integer(event.get("target"), 1) \
		or event.attacker == event.target or not event.get("kind") is String \
		or not (event.get("damage") is float or event.get("damage") is int) \
		or not is_finite(float(event.damage)) or event.damage < 0 \
		or not event.get("position") is Vector3 or not event.position.is_finite() \
		or not event.get("normal") is Vector3 or not event.normal.is_finite(): return
	if event.get("match_id", _match if _practice else "") != _match: return
	var context := "%s/%d" % [_match, _round]
	if event.event_id <= int(_watermarks.get(context, 0)): return
	_watermarks[context] = event.event_id
	_trim(_watermarks)
	# Every accepted hit tells the struck bot where parts should come off (#72).
	get_tree().call_group(PART_LOSS_GROUP, &"note_hit", event)
	if damage_numbers != null and event.damage > 0:
		var local := session.local_entity if is_instance_valid(session) else 0
		var own: bool = local > 0 and event.target == local
		if show_player_damage_numbers if own else show_damage_numbers:
			var at: Vector3 = _collision_point(event) if event.kind in COLLISION_KINDS else event.position
			for part: Array in damage_parts(event):
				damage_numbers.spawn(at, part[1], part[0])
	if event.kind not in KINDS and event.kind != CHAIN_KIND: return
	if event.kind == CHAIN_KIND:
		_tesla_hit(event)
		return
	visual.spawn_impact(event.position, event.normal, event.kind, float(event.damage), event.attacker)

func _tesla_hit(event: Dictionary) -> void:
	if not _integer(event.get("attack_id"), 0): return
	var first: Dictionary = _discharges.get(event.attacker, {})
	if not first.is_empty() and first.tick == event.tick and first.attack_id == event.attack_id and first.target != event.target:
		_discharges.erase(event.attacker)
		if is_inside_tree():
			get_tree().call_group(TurretSpecialEffects.CHAIN_GROUP, &"show_chain", event.attacker, first.position, event.position)
		return
	_discharges[event.attacker] = {"tick":event.tick, "attack_id":event.attack_id, "target":event.target, "position":event.position}
	_trim(_discharges)

## [[part, amount], ...] for the damage numbers: armour, core and piercing
## from the event's split (#85). An event without a valid split (an older
## server) shows its total as core damage.
static func damage_parts(event: Dictionary) -> Array:
	var parts := []
	for part: String in ["armour", "core", "pierce"]:
		var amount: Variant = event.get(part)
		if not (amount is float or amount is int) or not is_finite(float(amount)) or amount < 0:
			return [["core", float(event.damage)]]
		if amount > 0: parts.append([part, float(amount)])
	return parts if not parts.is_empty() else [["core", float(event.damage)]]

## Where two rammed hulls met. The event carries the attacker's centre, so ray
## from it toward the victim's centre and take where the victim's hull is
## crossed; fall back to the midpoint of the two centres.
func _collision_point(event: Dictionary) -> Vector3:
	var world: AuthorityWorld = session.world if is_instance_valid(session) else null
	if world == null or not world.bots.has(event.target): return event.position
	var victim: MvpBot = world.bots[event.target]
	if not is_instance_valid(victim) or not is_instance_valid(victim.body): return event.position
	var from: Vector3 = event.position
	var to := victim.body.global_position
	var midpoint := from.lerp(to, 0.5)
	if not is_inside_tree() or from.distance_squared_to(to) < 0.0001: return midpoint
	var space := get_world_3d().direct_space_state
	if space == null: return midpoint
	var ray := PhysicsRayQueryParameters3D.create(from, to, BaselineConfig.BOT_LAYER)
	if world.bots.has(event.attacker) and is_instance_valid(world.bots[event.attacker].body):
		ray.exclude = [world.bots[event.attacker].body.get_rid()]
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.collider != victim.body: return midpoint
	return hit.position

func _clear_effects() -> void:
	if visual != null: visual.clear_effects()
	if damage_numbers != null: damage_numbers.clear()

func _integer(value: Variant, minimum: int) -> bool:
	return value is int and value >= minimum

func _trim(values: Dictionary) -> void:
	while values.size() > CONTEXT_LIMIT: values.erase(values.keys()[0])
