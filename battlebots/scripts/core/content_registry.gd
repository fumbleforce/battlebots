class_name ContentRegistry
extends RefCounted
## Only this server-owned catalogue supplies gameplay stats and assembly dimensions.
const SLOTS := ["chassis", "drive", "weapon", "armor", "utility", "nitro", "suspension"]
const SCHEMA := 2
var parts: Dictionary = {}
var content_hash: String = ""

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://data/mvp_parts.json")
	# Exported Linux servers and Windows clients identify the same catalogue.
	content_hash = source.replace("\r\n", "\n").sha256_text()
	var data: Dictionary = JSON.parse_string(source)
	for part: Dictionary in data.parts:
		parts[part.id] = part

func starter(controller := false) -> Dictionary:
	return {"schema_version": SCHEMA, "name": "Controller" if controller else "Striker",
		"parts": {"chassis": "wide" if controller else "balanced",
		"drive": "traction" if controller else "standard_wheels",
		"weapon": "lifter" if controller else "vertical_spinner",
		"armor": "standard_armor", "utility": "recovery_assist",
		"nitro": "nitro_boost", "suspension": "charged_jump"},
		"cosmetics": {"paint": "cyan"}, "content_hash": content_hash}

func duelist() -> Dictionary:
	var draft := starter()
	draft.name = "Duelist"
	draft.parts = {"chassis":"balanced", "drive":"agile", "weapon":"hammer",
		"armor":"standard_armor", "utility":"cooling_pack",
		"nitro":"nitro_boost", "suspension":"charged_jump"}
	return draft

func scorpion() -> Dictionary:
	var draft := starter()
	draft.name = "SCORPION • HX-6"
	draft.parts = {"chassis":"scorpion_hex", "drive":"walker", "weapon":"hammer",
		"armor":"standard_armor", "utility":"minigun_pod",
		"nitro":"nitro_boost", "suspension":"charged_jump"}
	draft.cosmetics = {"paint":"orange", "sawblade":SawbladeConfig.defaults()}
	return draft

func validate(draft: Dictionary) -> LoadoutValidation:
	var result := LoadoutValidation.new()
	if draft.size() != 5 or draft.get("schema_version") != SCHEMA:
		result.reasons.append("Unsupported loadout schema or fields")
	if draft.get("content_hash") != content_hash:
		result.reasons.append("Content version differs; repair/revalidate the saved build")
	if not draft.get("name") is String or str(draft.get("name", "")).strip_edges().length() not in range(1, 49):
		result.reasons.append("Name must contain 1–48 characters")
	var selected: Variant = draft.get("parts")
	if not selected is Dictionary or selected.size() != SLOTS.size():
		result.reasons.append("Select one part for every chassis, drive, weapon, armor, utility, Nitro and suspension slot")
		return result
	var seen: Array = []
	var mass := 0.0
	var power := 0.0
	for slot: String in SLOTS:
		var id: Variant = selected.get(slot)
		if not id is String or not parts.has(id):
			result.reasons.append("Unknown or missing part in " + slot)
			continue
		var part: Dictionary = parts[id]
		if part.category != slot or seen.has(id):
			result.reasons.append("Duplicate/incompatible part in " + slot)
		seen.append(id)
		mass += float(part.mass)
		power += float(part.power)
	if mass > 120.0:
		result.reasons.append("Mass exceeds 120 kg")
	if power > 100.0:
		result.reasons.append("Installed power exceeds 100")
	if selected.get("chassis") == "scorpion_hex" and selected.get("drive") != "walker":
		result.reasons.append("Scorpion hex body requires the articulated walking drive")
	if selected.get("weapon") == "minigun" or selected.get("utility") == "minigun_pod":
		if selected.get("utility") == "minigun_pod" and selected.get("chassis") != "scorpion_hex":
			result.reasons.append("Auxiliary minigun requires the Scorpion hex body's gun socket")
		if selected.get("weapon") == "minigun" and selected.get("utility") == "minigun_pod":
			result.reasons.append("One minigun fits the gun socket; select another auxiliary part")
	var cosmetics: Variant = draft.get("cosmetics")
	if not cosmetics is Dictionary or cosmetics.size() not in [1, 2] or cosmetics.get("paint") not in ["cyan", "orange", "white", "red"]:
		result.reasons.append("Unknown cosmetic selection")
	elif cosmetics.size() == 2:
		if not SawbladeConfig.valid(cosmetics.get("sawblade")):
			result.reasons.append("Invalid Sawblade Tank appearance")
	if not result.reasons.is_empty():
		return result
	var chassis: Dictionary = parts[selected.chassis]
	var drive: Dictionary = parts[selected.drive]
	var armor: Dictionary = parts[selected.armor]
	result.stats = {"mass": mass, "power": power, "core": float(chassis.core),
		"size": Vector3(chassis.size[0], chassis.size[1], chassis.size[2]),
		"speed": float(drive.speed), "grip": float(drive.grip),
		"plate_integrity": float(armor.integrity), "reduction": float(armor.reduction),
		"weapon": selected.weapon, "secondary_weapon": "minigun" if selected.utility == "minigun_pod" else "",
		"battery": 125.0 if selected.utility == "battery_pack" else 100.0,
		"cooling": 15.0 if selected.utility == "cooling_pack" else 12.0,
		"recovery_seconds": 1.0 if selected.utility == "recovery_assist" else 2.0,
		"nitro": selected.nitro == "nitro_boost", "charged_jump": selected.suspension == "charged_jump"}
	result.loadout = draft.duplicate(true)
	result.valid = true
	return result
