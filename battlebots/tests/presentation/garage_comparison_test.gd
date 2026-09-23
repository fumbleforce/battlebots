extends Node
## F6/headless pure comparison acceptance; no profile mutation or session access.
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var registry := ContentRegistry.new()
	var catalogue_before := registry.parts.duplicate(true)
	var draft := registry.starter()
	draft.cosmetics.sawblade = SawbladeConfig.defaults()
	var original := draft.duplicate(true)
	var cases := [
		["chassis", "compact", "core", 220.0],
		["drive", "agile", "speed", 12.0],
		["utility", "cooling_pack", "cooling", 15.0],
		["utility", "cooling_pack", "recovery_seconds", 2.0],
		["weapon", "hammer", "weapon", "hammer"]]
	for entry: Array in cases:
		var result := GarageComparison.compare(registry, draft, entry[0], entry[1])
		check(result.current.valid and result.proposed.valid and result.changed, "Legal replacement: " + entry[1])
		check(result.proposed.stats.get(entry[2]) == entry[3], "Canonical tradeoff: " + entry[2])
		check(result.current.stats == registry.validate(original).stats, "Current stats stay canonical")
		check(result.draft.parts[entry[0]] == entry[1], "Candidate contains requested part")
		check(draft == original, "Comparison never equips the candidate")
		result.draft.parts.chassis = "wide"
		result.draft.cosmetics.paint = "red"
		result.current.stats.mass = -1
		result.proposed.stats.clear()
		check(draft == original, "Returned nested records are detached")
	# Armour pieces are module choices: each covers faces with its own HP and mass.
	for entry: Array in [["armor_front", 1, "front", 90.0, 97.0], ["armor_side", 2, "left", 110.0, 97.0], ["armor_side", 0, "right", 0.0, 85.0]]:
		var result := GarageComparison.compare_armor(registry, draft, entry[0], entry[1])
		check(result.current.valid and result.proposed.valid and result.changed, "Legal armour swap: %s %d" % [entry[0], entry[1]])
		check(result.proposed.stats.plates[entry[2]] == entry[3] and result.proposed.stats.mass == entry[4], "Canonical armour tradeoff: " + entry[0])
		check(result.current.stats.plates.left == 60.0 and result.current.stats.armor_total == 120.0, "Current armour stays canonical")
		check(result.draft.cosmetics.sawblade[entry[0]] == entry[1] and draft == original, "Armour comparison never equips the candidate")
	check(not GarageComparison.compare_armor(registry, draft, "armor_side", 1).changed, "Fitted armour piece is a no-op")
	for bad: Array in [["armor_side", 3], ["exhaust", 1], ["paint", 0]]:
		var result := GarageComparison.compare_armor(registry, draft, bad[0], bad[1])
		check(not result.proposed.valid and not result.changed and draft == original, "Invalid armour request rejects: " + bad[0])
	check(not GarageComparison.compare_armor(registry, registry.starter(), "armor_front", 1).proposed.valid, "Armour needs a modular body")
	var noop := GarageComparison.compare(registry, draft, "chassis", "balanced")
	check(not noop.changed and noop.proposed.valid and noop.current.stats == noop.proposed.stats, "Equipped part is a legal no-op")
	noop.proposed.stats.mass = -1
	check(noop.current.stats.mass == 91.0, "Current and proposed do not share dictionaries")
	var heavy := registry.starter()
	heavy.parts.merge({"chassis": "wide", "drive": "traction", "weapon": "horizontal_spinner", "utility": "cooling_pack"}, true)
	heavy.cosmetics.sawblade = SawbladeConfig.defaults()
	heavy.cosmetics.sawblade.merge({"armor_side": 2, "armor_top": 1, "armor_front": 1, "armor_rear": 1}, true)
	var repair := GarageComparison.compare_armor(registry, heavy, "armor_side", 0)
	check(not repair.current.valid and repair.current.reasons.has("Mass exceeds 120 kg"), "Overweight build retains concrete validation error")
	check(repair.current.stats == {"mass": 128.0, "power": 80.0}, "Invalid build exposes only verified canonical budgets")
	check(repair.proposed.valid and repair.proposed.stats.mass == 116.0, "Proposed swap repairs overweight build")
	var over := GarageComparison.compare_armor(registry, repair.draft, "armor_side", 2)
	check(not over.proposed.valid and over.proposed.stats.mass == 128.0 and not over.proposed.stats.has("core"), "Invalid candidate budget remains visible without invented derived values")
	for bad: Array in [["paint", "compact"], ["chassis", "missing"], ["chassis", "agile"]]:
		var result := GarageComparison.compare(registry, draft, bad[0], bad[1])
		check(not result.proposed.valid and not result.changed and not result.proposed.reasons.is_empty(), "Invalid request rejects with reason")
		check(result.draft == original and draft == original, "Rejected request never changes draft")
	for malformed: Variant in [null, [], {"chassis": "compact"}, {"chassis": 12, "drive": "agile", "weapon": "saw", "utility": "cooling_pack"}, {"chassis": "agile", "drive": "agile", "weapon": "saw", "utility": "cooling_pack"}]:
		var broken := original.duplicate(true)
		broken.parts = malformed
		var before := broken.duplicate(true)
		var result := GarageComparison.compare(registry, broken, "weapon", "hammer")
		check(not result.current.valid and result.current.stats.is_empty(), "Malformed parts do not produce partial budget totals")
		check(not result.proposed.valid and broken == before, "Malformed draft stays invalid and untouched")
	var unknown := original.duplicate(true)
	unknown.parts.weapon = "retired_weapon"
	var fixed := GarageComparison.compare(registry, unknown, "weapon", "saw")
	check(not fixed.current.valid and fixed.current.stats.is_empty() and fixed.proposed.valid, "Unknown saved part can be repaired by canonical replacement")
	var forged := original.duplicate(true)
	forged.stats = {"mass": 1.0, "core": 9999.0}
	var rejected := GarageComparison.compare(registry, forged, "weapon", "saw")
	check(not rejected.proposed.valid and rejected.proposed.stats == {"mass": 83.0, "power": 65.0}, "Client-supplied stats never influence comparison")
	check(registry.parts == catalogue_before, "Catalogue remains unchanged")
	if failures.is_empty(): print("GARAGE COMPARISON PASS")
	else:
		for message: String in failures: push_error(message)
	get_tree().quit(0 if failures.is_empty() else 1)
