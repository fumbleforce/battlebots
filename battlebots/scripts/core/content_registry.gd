class_name ContentRegistry
extends RefCounted
## Only this server-owned catalogue supplies gameplay stats and assembly dimensions.
const SLOTS := ["chassis", "drive", "weapon", "utility", "nitro", "suspension"]
const SCHEMA := 3
var parts: Dictionary = {}
## Body faces an armour piece can cover, and the pieces per armour section
## (keyed like SawbladeConfig.OPTIONS; the index is the saved module choice).
var armor_faces: Array = []
var armor_pieces: Dictionary = {}
var content_hash: String = ""
## Match pickups are a bonus above the construction budget. Only the authority
## world sets this, on its own instance; lobby builds always use a strict registry.
var enforce_budget := true

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://data/mvp_parts.json")
	# Exported Linux servers and Windows clients identify the same catalogue.
	content_hash = source.replace("\r\n", "\n").sha256_text()
	var data: Dictionary = JSON.parse_string(source)
	for part: Dictionary in data.parts:
		parts[part.id] = part
	armor_faces = data.armor_faces
	armor_pieces = data.armor_pieces

## Armour HP per face for a draft's selected pieces; 0 means the face is bare
## and hits there go straight to the core.
func armor_plates(draft: Dictionary) -> Dictionary:
	var plates := {}
	for face: String in armor_faces: plates[face] = 0.0
	for piece: Dictionary in _armor_selection(draft):
		for face: String in piece.covers: plates[face] += float(piece.integrity)
	return plates

func armor_mass(draft: Dictionary) -> float:
	var total := 0.0
	for piece: Dictionary in _armor_selection(draft): total += float(piece.mass)
	return total

func _armor_selection(draft: Dictionary) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	var cosmetics: Variant = draft.get("cosmetics")
	var config: Variant = cosmetics.get("sawblade") if cosmetics is Dictionary else null
	if not SawbladeConfig.valid(config): return selected
	for section: String in armor_pieces:
		var choices: Array = armor_pieces[section]
		var index := int(config.get(section, 0))
		if index >= 0 and index < choices.size(): selected.append(choices[index])
	return selected

func starter(controller := false) -> Dictionary:
	return {"schema_version": SCHEMA, "name": "Controller" if controller else "Striker",
		"parts": {"chassis": "wide" if controller else "balanced",
		"drive": "traction" if controller else "standard_wheels",
		"weapon": "lifter" if controller else "vertical_spinner",
		"utility": "recovery_assist",
		"nitro": "nitro_boost", "suspension": "charged_jump"},
		"cosmetics": {"paint": "cyan"}, "content_hash": content_hash}

func duelist() -> Dictionary:
	var draft := starter()
	draft.name = "Duelist"
	draft.parts = {"chassis":"balanced", "drive":"agile", "weapon":"hammer",
		"utility":"cooling_pack",
		"nitro":"nitro_boost", "suspension":"charged_jump"}
	return draft

func scorpion() -> Dictionary:
	var draft := starter()
	draft.name = "SCORPION • HX-6"
	draft.parts = {"chassis":"scorpion_hex", "drive":"walker", "weapon":"hammer",
		"utility":"minigun_pod",
		"nitro":"nitro_boost", "suspension":"charged_jump"}
	draft.cosmetics = {"paint":"orange", "sawblade":SawbladeConfig.defaults()}
	return draft

func atlas() -> Dictionary:
	var draft := starter()
	draft.name = "ATLAS MX"
	draft.parts = {"chassis":"atlas_mx", "drive":"traction", "weapon":"lifter",
		"utility":"recovery_assist",
		"nitro":"nitro_boost", "suspension":"charged_jump"}
	draft.cosmetics = {"paint":"orange", "sawblade":AtlasGeometry.paint_defaults()}
	return draft

## Seeded Atlas with the roof turret: cannon main gun over the default lifter.
func atlas_turret() -> Dictionary:
	var draft := atlas()
	draft.name = "ATLAS MX • TURRET"
	draft.parts.utility = "turret_cannon"
	return draft

## Showcase turret presets: quad-cannon fortress, close-quarters flamethrower
## brawler with a saw, a long-range railgun, a harpoon whaler that drags
## enemies onto its lifter, a mortar artillery piece, and the front tools: a
## battering-ram breaker, a harpoon-and-spear impaler and a grinder shredder.
func atlas_showcase() -> Array[Dictionary]:
	var fortress := atlas()
	fortress.name = "ATLAS MX • FORTRESS"
	fortress.parts.utility = "turret_cannon_quad"
	var inferno := atlas()
	inferno.name = "ATLAS MX • INFERNO"
	inferno.parts.utility = "turret_flamer"
	inferno.parts.weapon = "saw"
	var rail := atlas()
	rail.name = "ATLAS MX • RAIL"
	rail.parts.utility = "turret_railgun"
	var whaler := atlas()
	whaler.name = "ATLAS MX • WHALER"
	whaler.parts.utility = "turret_harpoon"
	var artillery := atlas()
	artillery.name = "ATLAS MX • ARTILLERY"
	artillery.parts.utility = "turret_mortar"
	var breaker := atlas()
	breaker.name = "ATLAS MX • BREAKER"
	breaker.parts.weapon = "battering_ram"
	breaker.parts.utility = "turret_cannon"
	var impaler := atlas()
	impaler.name = "ATLAS MX • IMPALER"
	impaler.parts.weapon = "spear_fork"
	impaler.parts.utility = "turret_harpoon"
	var shredder := atlas()
	shredder.name = "ATLAS MX • SHREDDER"
	shredder.parts.weapon = "grinder_drum"
	return [fortress, inferno, rail, whaler, artillery, breaker, impaler, shredder]

## Showcase quick bots with their own gaits: biped, monowheel, pogo, skater.
func nimble() -> Array[Dictionary]:
	return NimbleBots.presets(self)

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
		result.reasons.append("Select one part for every chassis, drive, weapon, utility, Nitro and suspension slot")
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
	mass += armor_mass(draft)
	if enforce_budget and power > 100.0:
		result.reasons.append("Installed power exceeds 100")
	if selected.get("chassis") == "scorpion_hex" and selected.get("drive") != "walker":
		result.reasons.append("Scorpion hex body requires the articulated walking drive")
	if selected.get("chassis") == "atlas_mx" and not AtlasGeometry.DRIVE_GEAR.has(selected.get("drive")):
		result.reasons.append("Atlas MX drives on tracks, large wheels or hydraulic legs")
	# The four nimble bots (#61) are sealed factory builds for now.
	result.reasons.append_array(NimbleBots.reasons(draft))
	if selected.get("weapon") in AtlasGeometry.TOOL_PARTS and selected.get("chassis") != "atlas_mx":
		result.reasons.append("Ram, spear and grinder tools mount on the Atlas MX front coupler")
	if selected.get("utility") in AtlasGeometry.TURRET_PARTS:
		if selected.get("chassis") != "atlas_mx":
			result.reasons.append("Turret modules require the Atlas MX roof traverse race")
		elif selected.get("weapon") == "minigun":
			result.reasons.append("The turret occupies the Atlas roof gun mount; select another primary weapon")
	if selected.get("weapon") == "minigun" or selected.get("utility") == "minigun_pod":
		if selected.get("utility") == "minigun_pod" and selected.get("chassis") not in ["scorpion_hex", "atlas_mx"]:
			result.reasons.append("Auxiliary minigun requires a Scorpion or Atlas MX gun socket")
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
	var plates := armor_plates(draft)
	var armor_total := 0.0
	for face: String in plates: armor_total += float(plates[face])
	result.stats = {"mass": mass, "power": power, "core": float(chassis.core),
		"size": Vector3(chassis.size[0], chassis.size[1], chassis.size[2]),
		# Heavier builds lose top speed; the drive supplies the reference value.
		"speed": float(drive.speed) * BotPhysics.settings().top_speed_factor(mass), "drive_speed": float(drive.speed),
		"grip": float(drive.grip),
		"plates": plates, "armor_total": armor_total,
		"weapon": selected.weapon, "secondary_weapon": AtlasGeometry.family(AtlasGeometry.TURRET_PARTS.get(selected.utility,
			"minigun" if selected.utility == "minigun_pod" else "")),
		"turret_model": AtlasGeometry.TURRET_PARTS.get(selected.utility, ""),
		"turret_barrels": AtlasGeometry.TURRET_BARRELS.get(AtlasGeometry.TURRET_PARTS.get(selected.utility, ""), []).size(),
		"cooling": 15.0 if selected.utility == "cooling_pack" else 12.0,
		"recovery_seconds": 1.0 if selected.utility == "recovery_assist" else 2.0,
		"nitro": selected.nitro == "nitro_boost", "charged_jump": selected.suspension == "charged_jump"}
	result.loadout = draft.duplicate(true)
	result.valid = true
	return result
