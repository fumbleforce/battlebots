class_name GarageComparison
extends RefCounted
## Detached, read-only catalogue comparisons. Never equips, saves or joins a session.

static func current(registry: ContentRegistry, draft: Dictionary) -> Dictionary:
	return _summary(registry, draft)


static func compare(registry: ContentRegistry, draft: Dictionary, slot: String, part_id: String) -> Dictionary:
	var candidate := draft.duplicate(true)
	var current := _summary(registry, draft)
	var error := ""
	if slot not in ContentRegistry.SLOTS:
		error = "Unknown part slot: " + slot
	elif not registry.parts.has(part_id):
		error = "Unknown proposed part: " + part_id
	elif registry.parts[part_id].category != slot:
		error = "Proposed part is incompatible with " + slot
	elif not candidate.get("parts") is Dictionary:
		error = "Select one part for every chassis, drive, weapon, armor, utility, Nitro and suspension slot"
	if not error.is_empty():
		return {"current": current, "proposed": {"valid": false,
			"reasons": PackedStringArray([error]), "stats": {}}, "draft": candidate, "changed": false}
	var changed: bool = candidate.parts.get(slot) != part_id
	candidate.parts[slot] = part_id
	return {"current": current, "proposed": _summary(registry, candidate),
		"draft": candidate, "changed": changed}

## Proposed armour piece for one section (index into ContentRegistry.armor_pieces).
static func compare_armor(registry: ContentRegistry, draft: Dictionary, section: String, index: int) -> Dictionary:
	var candidate := draft.duplicate(true)
	var current := _summary(registry, draft)
	var cosmetics: Variant = candidate.get("cosmetics")
	if not registry.armor_pieces.has(section) or index < 0 or index >= registry.armor_pieces[section].size() \
			or not cosmetics is Dictionary or not cosmetics.get("sawblade") is Dictionary:
		return {"current": current, "proposed": {"valid": false,
			"reasons": PackedStringArray(["Unknown armour piece"]), "stats": {}}, "draft": candidate, "changed": false}
	var changed: bool = int(cosmetics.sawblade.get(section, 0)) != index
	cosmetics.sawblade[section] = index
	return {"current": current, "proposed": _summary(registry, candidate), "draft": candidate, "changed": changed}

static func _summary(registry: ContentRegistry, draft: Dictionary) -> Dictionary:
	var validation := registry.validate(draft)
	var stats := validation.stats.duplicate(true)
	# Validation deliberately withholds derived stats from invalid builds. Only
	# known canonical part totals remain meaningful while repairing such a draft.
	if not validation.valid:
		var selected: Variant = draft.get("parts")
		if selected is Dictionary and selected.size() == ContentRegistry.SLOTS.size():
			var complete := true
			var mass := 0.0
			var power := 0.0
			for slot: String in ContentRegistry.SLOTS:
				var id: Variant = selected.get(slot)
				if not id is String or not registry.parts.has(id) or registry.parts[id].category != slot:
					complete = false
					break
				mass += float(registry.parts[id].mass)
				power += float(registry.parts[id].power)
			if complete:
				mass += registry.armor_mass(draft)
				stats = {"mass": mass, "power": power}
	return {"valid": validation.valid, "reasons": validation.reasons.duplicate(), "stats": stats}
