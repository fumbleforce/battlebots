extends Node
## Canonical local loadouts and the account credit wallet. Every part is still
## available; match rewards accumulate credits for future Customize unlocks.
signal credits_changed(value: int)
signal inventory_changed
var player_name := "LOCAL PLAYER"
var level := 0
var level_progress := 0.0
var wallet := CreditWallet.new()
var credits: int:
	get: return wallet.balance
var active_bot := 0
const PRESET_COUNT := 9
var bots: Array = []
var registry := ContentRegistry.new()
var save_path := "user://loadouts.json"
var loadouts: Array = []
var errors: PackedStringArray = []
var catalogue: Dictionary = {}
var _saved: Array = []
var _save_indices: Array[int] = []
var _read_errors := false
const HISTORY_LIMIT := 100
var _undo_history: Dictionary = {}
var _redo_history: Dictionary = {}
var _draft_baseline: Array = []
var _retained_drafts: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	_retained_drafts.clear()
	_undo_history.clear()
	_redo_history.clear()
	catalogue = MenuData.catalogue(registry)
	var loaded := LoadoutStore.new(save_path).load_saved()
	errors = loaded.errors
	_read_errors = not errors.is_empty() or loaded.restored_backup
	_saved = loaded.loadouts.duplicate(true)
	loadouts = [SawbladeConfig.starter(registry),registry.starter(true),registry.duelist()]
	for preset: Dictionary in loadouts:
		preset.parts.chassis = "balanced"
		_ensure_body(preset)
	loadouts.append(registry.scorpion())
	loadouts.append(registry.atlas())
	loadouts.append(registry.atlas_turret())
	loadouts.append_array(registry.atlas_showcase())
	_save_indices = [-1,-1,-1,-1,-1,-1,-1,-1,-1]
	for index: int in _saved.size():
		loadouts.append(_saved[index].duplicate(true) if _saved[index] is Dictionary else {})
		_save_indices.append(index)
	# Retained legacy part IDs remain readable; only the offered body appearance changes.
	for draft: Dictionary in loadouts:
		if registry.validate(draft).valid: _ensure_body(draft)
	if loaded.restored_backup: errors.append("Backup loaded for review. Open Saved File to restore it before saving.")
	active_bot = clampi(active_bot,0,loadouts.size()-1)
	_draft_baseline = loadouts.duplicate(true)
	_refresh_bots()

## Pays a finished match's reward into the wallet once per match id.
func bank_match_credits(match_id: String, amount: int) -> bool:
	if not wallet.bank(match_id, amount):
		return false
	credits_changed.emit(wallet.balance)
	return true

## Refresh disk slots without losing local work or linking old drafts to new slots.
func reload_retaining_drafts() -> int:
	var retained: Array = []
	var previous_active := active_bot
	var previous_draft: Dictionary = loadouts[active_bot].duplicate(true)
	for index: int in loadouts.size():
		var changed: bool = index >= _draft_baseline.size() or \
			not _same_draft(loadouts[index], _draft_baseline[index])
		var needs_copy: bool = changed or (index >= PRESET_COUNT and _save_indices[index] < 0)
		if needs_copy or not _undo_history.get(index, []).is_empty() or not _redo_history.get(index, []).is_empty():
			retained.append({"draft":loadouts[index].duplicate(true), "index":index,
				"copy":needs_copy, "saved":_save_indices[index] >= 0,
				"undo":_undo_history.get(index, []).duplicate(true),
				"redo":_redo_history.get(index, []).duplicate(true)})
	reload()
	# Prefer the exact unchanged build if disk order changed.
	active_bot = 0
	for index: int in loadouts.size():
		if _same_draft(loadouts[index], previous_draft):
			active_bot = index
			break
	var retained_count := 0
	for entry: Dictionary in retained:
		var history_target := -1
		if not entry.copy:
			# Keep history on an unchanged disk build, including redo at baseline.
			for candidate: int in loadouts.size():
				if (_save_indices[candidate] >= 0) != entry.saved: continue
				if _undo_history.has(candidate) or _redo_history.has(candidate): continue
				if _same_draft(loadouts[candidate], entry.draft):
					history_target = candidate
					break
		if history_target >= 0:
			_undo_history[history_target] = entry.undo
			_redo_history[history_target] = entry.redo
			if entry.index == previous_active: active_bot = history_target
			continue
		var index := loadouts.size()
		loadouts.append(entry.draft)
		_save_indices.append(-1)
		_draft_baseline.append(entry.draft.duplicate(true))
		_undo_history[index] = entry.undo
		_redo_history[index] = entry.redo
		_retained_drafts[index] = true
		if entry.index == previous_active: active_bot = index
		retained_count += 1
	_refresh_bots()
	inventory_changed.emit()
	return retained_count

func restore_reviewed_backup(token: Dictionary) -> Dictionary:
	var result := LoadoutStore.new(save_path).restore_backup(token)
	if result.error == OK:
		result["retained"] = reload_retaining_drafts()
	return result

func active_loadout() -> Dictionary:
	if active_bot < 0 or active_bot >= loadouts.size(): return {}
	var result := registry.validate(loadouts[active_bot])
	return result.loadout.duplicate(true) if result.valid else {}

func save_active(name: String) -> Error:
	errors.clear()
	if _read_errors:
		errors.append("Save file could not be read safely. Open Saved File to review a backup or reload; your draft is retained.")
		return ERR_FILE_CORRUPT
	var draft: Dictionary = loadouts[active_bot].duplicate(true)
	draft.name = name.strip_edges()
	var validation := registry.validate(draft)
	if not validation.valid:
		errors = validation.reasons
		return ERR_INVALID_DATA
	var next := _saved.duplicate(true)
	var index := _save_indices[active_bot]
	if index < 0: next.append(validation.loadout)
	else: next[index] = validation.loadout
	var result := LoadoutStore.new(save_path).save_build(validation.loadout, index, _saved)
	if result != OK:
		if result == ERR_BUSY:
			errors.append("The saved file changed outside this garage. Your draft was retained; reload the profile before saving again.")
		elif result == ERR_FILE_CORRUPT:
			errors.append("The saved file cannot be read safely. Your draft and existing file were preserved.")
		else:
			errors.append("Could not save build: " + error_string(result) + ". Names must be unique; maximum 12 saved builds.")
		return result
	_saved = next
	if index < 0: _save_indices[active_bot] = next.size()-1
	_record_edit(validation.loadout)
	loadouts[active_bot] = validation.loadout.duplicate(true)
	while _draft_baseline.size() < loadouts.size(): _draft_baseline.append({})
	_draft_baseline[active_bot] = validation.loadout.duplicate(true)
	_retained_drafts.erase(active_bot)
	_refresh_bots()
	inventory_changed.emit()
	return OK

func new_build() -> void:
	var draft := SawbladeConfig.starter(registry)
	draft.name = "Custom %d" % (loadouts.size()-1)
	loadouts.append(draft)
	_save_indices.append(-1)
	active_bot = loadouts.size()-1
	_refresh_bots()
	inventory_changed.emit()

func equipped_name(tab: String, cat: Dictionary) -> String:
	var draft: Dictionary = loadouts[active_bot]
	if tab == "decals" or (tab == "paint" and cat.slot != "paint"):
		if cat.slot == "model": return "Sawblade Tank" if SawbladeConfig.enabled(draft) else "Classic bot"
		if not SawbladeConfig.enabled(draft): return "Choose Sawblade Tank"
		var config: Dictionary = draft.cosmetics.sawblade
		if tab == "paint": return "Custom color"
		return SawbladeConfig.OPTIONS[cat.slot][int(config[cat.slot])]
	var raw: Variant = draft.get("cosmetics") if tab == "paint" else draft.get("parts")
	var selected := ""
	if raw is Dictionary:
		selected = str(raw.get("paint" if tab == "paint" else cat.slot,""))
	for item: Dictionary in cat.items:
		if item.id == selected: return item.name
	if tab == "parts" and cat.slot == "chassis" and registry.parts.has(selected) and registry.parts[selected].category == "chassis":
		return "Legacy body"
	return "Unavailable" if tab == "decals" else "Missing / invalid"

func item_state(tab: String, cat: Dictionary, item: Dictionary) -> String:
	return "eq" if equipped_name(tab, cat) == item.name else "own"

func resolved_item(tab: String, cat: Dictionary, item: Dictionary) -> Dictionary:
	if tab != "paint" or cat.slot not in SawbladeConfig.COLORS or item.id != "original": return item
	if not AtlasGeometry.enabled(loadouts[active_bot]): return item
	var choice := item.duplicate(true)
	choice.rgba = AtlasGeometry.paint_defaults()[cat.slot]
	var rgba: Array = choice.rgba
	choice.swatch = Color(rgba[0], rgba[1], rgba[2]).linear_to_srgb().to_html()
	return choice

func _ensure_body(draft: Dictionary) -> void:
	if not draft.get("cosmetics") is Dictionary: draft.cosmetics = {"paint":"cyan"}
	if not SawbladeConfig.enabled(draft): draft.cosmetics["sawblade"] = SawbladeConfig.defaults()

## True when this part works with the rest of the active draft: choosing it leaves
## only validation reasons that every choice for the slot would leave. Customize
## lists just these parts. The equipped part always fits, keeping saved or
## body-changed invalid builds repairable.
func part_fits(slot: String, id: String) -> bool:
	var draft: Dictionary = loadouts[active_bot]
	if draft.get("parts") is Dictionary and draft.parts.get(slot) == id: return true
	var trial := _with_part(draft, slot, id)
	if trial.is_empty(): return false
	var unavoidable: Variant = null
	for cat: Dictionary in catalogue.get("parts", []):
		if cat.slot != slot: continue
		for item: Dictionary in cat.items:
			var choice := _with_part(draft, slot, item.id)
			if choice.is_empty(): continue
			var reasons := registry.validate(choice).reasons
			if unavoidable == null: unavoidable = reasons
			else: unavoidable = Array(unavoidable).filter(func(reason: String) -> bool: return reasons.has(reason))
	for reason: String in registry.validate(trial).reasons:
		if unavoidable == null or not Array(unavoidable).has(reason): return false
	return true

func _with_part(source: Dictionary, slot: String, id: String) -> Dictionary:
	if not registry.parts.has(id) or registry.parts[id].category != slot: return {}
	var draft := source.duplicate(true)
	if not draft.get("parts") is Dictionary: draft.parts = {}
	draft.parts[slot] = id
	if slot == "chassis": _ensure_body(draft)
	return draft

func equip(tab: String, cat: Dictionary, item: Dictionary) -> void:
	if tab not in ["parts","paint","decals"]: return
	var draft: Dictionary = loadouts[active_bot].duplicate(true)
	if tab == "parts":
		draft = _with_part(draft, cat.slot, item.id)
		if draft.is_empty(): return
	elif tab == "decals":
		if cat.slot == "model":
			if item.id != "sawblade": return
			_ensure_body(draft)
		elif cat.slot in SawbladeConfig.OPTIONS:
			_ensure_body(draft)
			draft.cosmetics.sawblade[cat.slot] = int(item.id)
	elif cat.slot != "paint":
		if cat.slot not in SawbladeConfig.COLORS: return
		_ensure_body(draft)
		draft.cosmetics.sawblade[cat.slot] = resolved_item(tab, cat, item).rgba.duplicate()
	else:
		if item.id not in ["cyan","orange","white","red"]: return
		_ensure_body(draft)
		draft.cosmetics.paint = item.id
		var colors := {"cyan":"#29cce5","orange":"#ef922a","white":"#eeeeee","red":"#d93c39"}
		var color := Color(colors[item.id]).srgb_to_linear()
		for channel: String in ["paint_primary", "paint_secondary"]:
			draft.cosmetics.sawblade[channel] = [color.r, color.g, color.b, 1.0]

	# Preserve invalid combinations for repair; never silently replace selected parts.
	if not _record_edit(draft): return
	loadouts[active_bot] = draft
	errors = registry.validate(draft).reasons
	_refresh_bots()
	inventory_changed.emit()

func set_sawblade_color(channel: String, color: Color) -> void:
	if channel not in SawbladeConfig.COLORS: return
	var draft: Dictionary = loadouts[active_bot].duplicate(true)
	_ensure_body(draft)
	var linear := color.srgb_to_linear()
	draft.cosmetics.sawblade[channel] = [linear.r, linear.g, linear.b, 1.0]
	if not _record_edit(draft): return
	loadouts[active_bot] = draft
	_draft_changed()

func rename_draft(value: String) -> void:
	var draft: Dictionary = loadouts[active_bot].duplicate(true)
	draft.name = value.strip_edges()
	if not _record_edit(draft): return
	loadouts[active_bot] = draft
	_draft_changed()

func needs_revalidation() -> bool:
	var draft: Dictionary = loadouts[active_bot]
	return draft.size() != 5 or draft.get("schema_version") != ContentRegistry.SCHEMA \
		or draft.get("content_hash") != registry.content_hash

func revalidate_active() -> void:
	var current: Dictionary = loadouts[active_bot]
	# Explicit repair changes only the local envelope; no part/paint substitutions.
	var repaired := {"schema_version":ContentRegistry.SCHEMA,
		"content_hash":registry.content_hash, "name":current.get("name", ""),
		"parts":current.get("parts", {}), "cosmetics":current.get("cosmetics", {})}
	if repaired.parts is Dictionary and repaired.parts.size() == 5 and current.get("schema_version") == 1:
		repaired.parts = repaired.parts.duplicate(true)
		repaired.parts["nitro"] = "nitro_off"
		repaired.parts["suspension"] = "jump_off"
	if not _record_edit(repaired): return
	loadouts[active_bot] = repaired.duplicate(true)
	_draft_changed()

func can_undo() -> bool:
	return not _undo_history.get(active_bot, []).is_empty()

func can_redo() -> bool:
	return not _redo_history.get(active_bot, []).is_empty()

func undo_edit() -> void:
	_restore_history(_undo_history, _redo_history)

func redo_edit() -> void:
	_restore_history(_redo_history, _undo_history)

func _record_edit(next: Dictionary) -> bool:
	if loadouts[active_bot] == next: return false
	_push_history(_undo_history, loadouts[active_bot])
	_redo_history.erase(active_bot)
	return true

func _push_history(history: Dictionary, draft: Dictionary) -> void:
	if not history.has(active_bot): history[active_bot] = []
	history[active_bot].append(draft.duplicate(true))
	if history[active_bot].size() > HISTORY_LIMIT:
		history[active_bot].pop_front()

func _restore_history(source: Dictionary, destination: Dictionary) -> void:
	if source.get(active_bot, []).is_empty(): return
	_push_history(destination, loadouts[active_bot])
	loadouts[active_bot] = source[active_bot].pop_back().duplicate(true)
	_draft_changed()

func _draft_changed() -> void:
	errors = registry.validate(loadouts[active_bot]).reasons
	_refresh_bots()
	inventory_changed.emit()

func _refresh_bots() -> void:
	bots.clear()
	for index: int in loadouts.size():
		var draft: Dictionary = loadouts[index]
		var validation := registry.validate(draft)
		var parts: Dictionary = draft.get("parts",{}) if draft.get("parts") is Dictionary else {}
		var stats: Dictionary = validation.stats
		var perk_labels: PackedStringArray = []
		if parts.get("nitro") == "nitro_boost": perk_labels.append("Nitro · Shift")
		if parts.get("suspension") == "charged_jump": perk_labels.append("Jump · Space")
		bots.append({"id":str(index),"name":str(draft.get("name","Invalid saved build")).left(48),"cls":"VALID BUILD" if validation.valid else "INVALID · REPAIR REQUIRED","image":preload("res://ui/menus/art/bot_scorpion.png") if parts.get("chassis") == "scorpion_hex" else (preload("res://ui/menus/art/bot_chevron.jpg") if parts.get("weapon") != "lifter" else preload("res://ui/menus/art/bot_rivetrex.jpg")),"hp":int(stats.get("core",0)),"shields":0,"weapon":str(parts.get("weapon","Unavailable")).capitalize(),"ability":str(parts.get("utility","Unavailable")).capitalize(),"boost":" / ".join(perk_labels) if not perk_labels.is_empty() else "No perks equipped","valid":validation.valid,"reasons":validation.reasons,"stats":{"MASS kg":int(stats.get("mass",0)),"POWER":int(stats.get("power",0)),"SPEED m/s":int(stats.get("speed",0)),"ARMOR %":int(float(stats.get("reduction",0))*100)}})
		bots[-1]["retained"] = _retained_drafts.has(index)
		if _retained_drafts.has(index): bots[-1].cls = "UNSAVED COPY" + (" · REPAIR REQUIRED" if not validation.valid else "")

func _same_draft(a: Dictionary, b: Dictionary) -> bool:
	# JSON disk reads turn integer module choices into floats. Compare the persisted
	# representation so a saved build does not become another retained draft.
	return JSON.stringify(JSON.parse_string(JSON.stringify(a))) == JSON.stringify(JSON.parse_string(JSON.stringify(b)))
