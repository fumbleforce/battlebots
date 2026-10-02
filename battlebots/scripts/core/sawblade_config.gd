class_name SawbladeConfig
extends RefCounted
## Optional appearance record. Weapon/drive choices remain canonical gameplay parts.
const OPTIONS := {
	"armor_side": ["None", "Reference Covers", "Heavy Skirts & Fenders"],
	"armor_top": ["None", "Machinery Guard"],
	"armor_front": ["None", "Chin Plate"],
	"armor_rear": ["None", "Rear Pack Armor"],
	"exhaust": ["None", "Small", "Medium Dual", "Large Dual"]}
## Paint channels in Customize order. paint_armor is optional in saved records
## (older saves lack it) and falls back to paint_primary; see armor_color().
const COLORS := ["paint_primary", "paint_secondary", "paint_armor", "paint_metal", "paint_rubber"]
## Weapon part -> authored weapon module of the Sawblade body.
const WEAPONS := {"saw": "saw", "hammer": "hammer", "ramp": "ramp"}

static func defaults() -> Dictionary:
	return {"armor_side": 1, "armor_top": 0, "armor_front": 0, "armor_rear": 0,
		"exhaust": 0, "paint_primary": [0.66, 0.32, 0.018, 1.0],
		"paint_secondary": [0.035, 0.041, 0.044, 1.0], "paint_armor": [0.66, 0.32, 0.018, 1.0],
		"paint_metal": [0.58, 0.6, 0.62, 1.0], "paint_rubber": [0.025, 0.029, 0.031, 1.0]}

static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != (10 if value.has("paint_armor") else 9): return false
	for key: String in OPTIONS:
		var selected: Variant = value.get(key)
		if not (selected is int or selected is float): return false
		if not is_finite(float(selected)) or selected != int(selected): return false
		if selected < 0 or selected >= OPTIONS[key].size(): return false
	for key: String in COLORS:
		if key == "paint_armor" and not value.has(key): continue
		var rgba: Variant = value.get(key)
		if not rgba is Array or rgba.size() != 4: return false
		for component: Variant in rgba:
			if not (component is int or component is float): return false
			if not is_finite(float(component)) or component < 0 or component > 1: return false
		if rgba[3] != 1: return false
	return true

## Paint of the armour modules' enamel. Primary/secondary never tint armour.
static func armor_color(config: Dictionary) -> Array:
	return config.get("paint_armor", config.paint_primary)

static func enabled(draft: Dictionary) -> bool:
	var cosmetics: Variant = draft.get("cosmetics")
	return cosmetics is Dictionary and valid(cosmetics.get("sawblade"))

## True when the draft renders as the Sawblade body itself: the appearance
## record on a chassis that has no authored body of its own.
static func body(draft: Dictionary) -> bool:
	return enabled(draft) and not ScorpionGeometry.enabled(draft) and not AtlasGeometry.enabled(draft)

static func starter(registry: ContentRegistry) -> Dictionary:
	var draft := registry.starter()
	draft.name = "Sawblade Tank"
	draft.parts.weapon = "saw"
	draft.parts.drive = "traction"
	draft.cosmetics["sawblade"] = defaults()
	return draft
