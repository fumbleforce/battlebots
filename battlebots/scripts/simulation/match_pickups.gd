class_name MatchPickups
extends RefCounted
## Authoritative in-match item pickups. Parts and perks change only the picker's
## match loadout until the match ends; nothing unlocks for the account. Credits
## are tallied here and paid into the account wallet with the match reward.
## See docs/coordination/MATCH_PICKUPS.md.
const RESPAWN_SECONDS := 20.0
const CREDIT_CHANCE := 0.3
const CREDIT_AMOUNTS := [25, 50, 100]
## Customize offers these bodies (MenuData.catalogue); legacy chassis never drop.
const OFFERED_CHASSIS := ["balanced", "scorpion_hex", "atlas_mx"]
## Removing a perk is not a reward.
const EXCLUDED_PARTS := ["nitro_off", "jump_off"]
const PERK_SLOTS := ["nitro", "suspension"]
const REQUIRED_DRIVE := {"scorpion_hex":"walker", "atlas_mx":"traction"}
const FALLBACK_UTILITY := "recovery_assist"
## Vertical pickup column in metres from the point; REACH_UP is also the height of
## the marker's light beam, so a bot collects anywhere it visibly overlaps.
const REACH_UP := 9.0
const REACH_DOWN := 1.5
const REWARD_PARTICIPATION := 50
const REWARD_VICTORY := 150
const REWARD_PER_ELIMINATION := 50
const REWARD_PER_ASSIST := 20
const REWARD_DAMAGE_DIVISOR := 10

## Budget-exempt catalogue: pickups are a bonus above the construction limits,
## but physical compatibility (required drives, gun sockets) still applies.
var registry := ContentRegistry.new()
var items: Array[Dictionary] = []
## Entity id -> credits collected from pickups during this match.
var credits: Dictionary = {}
## Collections resolved during the latest tick.
var events: Array[Dictionary] = []
## Pickups refused during the latest tick: {entity, item, kind, part, reason}.
## Reported once per contact, not every tick a bot stands on the item. Reason is
## "equipped" (same part or perk already fitted) or "incompatible".
var refusals: Array[Dictionary] = []
var _contacts: Dictionary = {}
var _previous_contacts: Dictionary = {}
var revision := 0
var pool: Array[String] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	registry.enforce_budget = false
	for id: String in registry.parts:
		var slot: String = registry.parts[id].category
		if id in EXCLUDED_PARTS or (slot == "chassis" and id not in OFFERED_CHASSIS):
			continue
		pool.append(id)
	pool.sort()

func begin(points: Array[Vector3], seed: int) -> void:
	_rng.seed = seed
	items.clear()
	credits.clear()
	events.clear()
	for index: int in points.size():
		items.append(_roll({"id":index, "point":points[index]}))
	_clear_contacts()
	revision += 1

## A new round restocks every point. Tallies and match loadouts persist.
func reset_round() -> void:
	events.clear()
	_clear_contacts()
	for item: Dictionary in items:
		if not item.available:
			_roll(item)
	revision += 1

func clear() -> void:
	items.clear()
	credits.clear()
	events.clear()
	_clear_contacts()
	revision += 1

func tick(delta: float) -> void:
	events.clear()
	refusals.clear()
	_previous_contacts = _contacts
	_contacts = {}
	for item: Dictionary in items:
		if item.available:
			continue
		item.respawn = maxf(0.0, item.respawn - delta)
		if item.respawn <= 0.0:
			_roll(item)
			revision += 1

func _roll(item: Dictionary) -> Dictionary:
	item.available = true
	item.respawn = 0.0
	if pool.is_empty() or _rng.randf() < CREDIT_CHANCE:
		item.kind = "credits"
		item.part = ""
		item.amount = CREDIT_AMOUNTS[_rng.randi_range(0, CREDIT_AMOUNTS.size() - 1)]
	else:
		item.part = pool[_rng.randi_range(0, pool.size() - 1)]
		item.kind = "perk" if registry.parts[item.part].category in PERK_SLOTS else "part"
		item.amount = 0
	return item

## Resolves one entity touching an available item. Returns {} when the pickup
## would change nothing (same part, perk already equipped, incompatible body);
## the item then stays in the world. Otherwise returns the collection event, with
## "loadout" holding the new match loadout for part and perk pickups.
func collect(item: Dictionary, entity_id: int, loadout: Dictionary) -> Dictionary:
	if not item.get("available", false):
		return {}
	var event := {"entity":entity_id, "item":item.id, "kind":item.kind, "part":item.part, "amount":item.amount}
	if item.kind == "credits":
		credits[entity_id] = int(credits.get(entity_id, 0)) + int(item.amount)
		event.credits = credits[entity_id]
	else:
		var next := swapped(loadout, item.part)
		if next.is_empty():
			_refuse(item, entity_id, loadout)
			return {}
		event.slot = registry.parts[item.part].category
		event.loadout = next
	item.available = false
	item.respawn = RESPAWN_SECONDS
	events.append(event)
	revision += 1
	return event

func _clear_contacts() -> void:
	refusals.clear()
	_contacts = {}
	_previous_contacts = {}

func _refuse(item: Dictionary, entity_id: int, loadout: Dictionary) -> void:
	# Key on contents too: a respawn under a parked bot is a new attempt.
	var key := "%d:%d:%s" % [entity_id, item.id, item.part]
	_contacts[key] = true
	if _previous_contacts.has(key):
		return
	var slot: String = registry.parts[item.part].category if registry.parts.has(item.part) else ""
	var equipped: bool = loadout.get("parts") is Dictionary and loadout.parts.get(slot) == item.part
	refusals.append({"entity":entity_id, "item":item.id, "kind":item.kind, "part":item.part,
		"reason":"equipped" if equipped else "incompatible"})

## The picked part replaces the one in its slot. A new body brings the drive it
## requires and drops a utility it has no socket for; any other conflict
## (for example a wheeled drive on a Scorpion) leaves the pickup unused.
func swapped(loadout: Dictionary, part: String) -> Dictionary:
	if not registry.parts.has(part) or not loadout.get("parts") is Dictionary:
		return {}
	var slot: String = registry.parts[part].category
	if loadout.parts.get(slot) == part:
		return {}
	var next: Dictionary = loadout.duplicate(true)
	next.parts[slot] = part
	if slot == "chassis":
		if REQUIRED_DRIVE.has(part):
			next.parts.drive = REQUIRED_DRIVE[part]
		# Match Customize's body change: every offered body renders from the
		# modular appearance record, so keep or supply one.
		if next.get("cosmetics") is Dictionary and not SawbladeConfig.enabled(next):
			next.cosmetics["sawblade"] = SawbladeConfig.defaults()
		# Socket-bound utilities (the auxiliary minigun, or any later body-only
		# module) cannot move to a body without that socket: fit the fallback.
		if not registry.validate(next).valid and next.parts.get("utility") != FALLBACK_UTILITY:
			next.parts.utility = FALLBACK_UTILITY
	return next if registry.validate(next).valid else {}

## Post-match account reward. `participant` is a results participant record.
static func reward(participant: Dictionary, won: bool, picked_up: int) -> Dictionary:
	var performance := REWARD_PARTICIPATION + (REWARD_VICTORY if won else 0) \
		+ int(participant.get("eliminations", 0)) * REWARD_PER_ELIMINATION \
		+ int(participant.get("assists", 0)) * REWARD_PER_ASSIST \
		+ floori(float(participant.get("damage", 0)) / REWARD_DAMAGE_DIVISOR)
	return {"pickups":picked_up, "performance":performance, "total":picked_up + performance}

## Compact public state for clients: no respawn timers or RNG.
func snapshot() -> Dictionary:
	var public: Array = []
	for item: Dictionary in items:
		public.append({"id":item.id, "point":item.point, "kind":item.kind, "part":item.part,
			"amount":item.amount, "available":item.available})
	return {"revision":revision, "items":public, "credits":credits.duplicate()}
