extends Node
## Canonical local loadouts. No currency, unlock gates, or paid gameplay upgrades.
signal scrap_changed(value: int)
signal inventory_changed
var player_name := "LOCAL PLAYER"
var level := 0
var level_progress := 0.0
var scrap := 0
var active_bot := 0
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

func _ready() -> void:
	reload()

func reload() -> void:
	_undo_history.clear()
	_redo_history.clear()
	catalogue = MenuData.catalogue(registry)
	var loaded := LoadoutStore.new(save_path).load_saved()
	errors = loaded.errors
	_read_errors = not errors.is_empty()
	_saved = loaded.loadouts.duplicate(true)
	loadouts = [registry.starter(),registry.starter(true),registry.duelist()]
	_save_indices = [-1,-1,-1]
	for index: int in _saved.size():
		loadouts.append(_saved[index].duplicate(true) if _saved[index] is Dictionary else {})
		_save_indices.append(index)
	if loaded.restored_backup: errors.append("Recovered backup. Review builds before saving.")
	active_bot = clampi(active_bot,0,loadouts.size()-1)
	_refresh_bots()

func active_loadout() -> Dictionary:
	if active_bot < 0 or active_bot >= loadouts.size(): return {}
	var result := registry.validate(loadouts[active_bot])
	return result.loadout.duplicate(true) if result.valid else {}

func save_active(name: String) -> Error:
	errors.clear()
	if _read_errors:
		errors.append("Save file could not be read safely. Resolve the existing file before overwriting it.")
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
	# Invalid saved entries remain visible and prevent replacement until repaired.
	for saved: Variant in next:
		if not saved is Dictionary or not registry.validate(saved).valid:
			errors.append("Another saved build needs repair. Existing saved data was preserved.")
			return ERR_INVALID_DATA
	var result := LoadoutStore.new(save_path).save(next)
	if result != OK:
		errors.append("Could not save build: " + error_string(result) + ". Names must be unique; maximum 12 saved builds.")
		return result
	_saved = next
	if index < 0: _save_indices[active_bot] = next.size()-1
	_record_edit(validation.loadout)
	loadouts[active_bot] = validation.loadout.duplicate(true)
	_refresh_bots()
	inventory_changed.emit()
	return OK

func new_build() -> void:
	var draft := registry.starter()
	draft.name = "Custom %d" % (loadouts.size()-1)
	loadouts.append(draft)
	_save_indices.append(-1)
	active_bot = loadouts.size()-1
	_refresh_bots()
	inventory_changed.emit()

func equipped_name(tab: String, cat: Dictionary) -> String:
	var draft: Dictionary = loadouts[active_bot]
	var raw: Variant = draft.get("cosmetics") if tab == "paint" else draft.get("parts")
	var selected := ""
	if raw is Dictionary:
		selected = str(raw.get("paint" if tab == "paint" else cat.slot,""))
	for item: Dictionary in cat.items:
		if item.id == selected: return item.name
	return "Unavailable" if tab == "decals" else "Missing / invalid"

func item_state(tab: String, cat: Dictionary, item: Dictionary) -> String:
	if tab == "decals": return "lock"
	return "eq" if equipped_name(tab,cat) == item.name else "own"

func equip(tab: String, cat: Dictionary, item: Dictionary) -> void:
	if tab not in ["parts","paint"]: return
	var draft: Dictionary = loadouts[active_bot].duplicate(true)
	if tab == "parts":
		if not registry.parts.has(item.id) or registry.parts[item.id].category != cat.slot: return
		if not draft.get("parts") is Dictionary: draft.parts = {}
		draft.parts[cat.slot] = item.id
	else:
		if item.id not in ["cyan","orange","white","red"]: return
		draft.cosmetics = {"paint":item.id}
	# Preserve invalid combinations for repair; never silently replace selected parts.
	if not _record_edit(draft): return
	loadouts[active_bot] = draft
	errors = registry.validate(draft).reasons
	_refresh_bots()
	inventory_changed.emit()

func rename_draft(value: String) -> void:
	var draft: Dictionary = loadouts[active_bot].duplicate(true)
	draft.name = value.strip_edges()
	if not _record_edit(draft): return
	loadouts[active_bot] = draft
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
		bots.append({"id":str(index),"name":str(draft.get("name","Invalid saved build")).left(48),"cls":"VALID BUILD · CONCEPT ART" if validation.valid else "INVALID · REPAIR REQUIRED","image":preload("res://ui/menus/art/bot_chevron.jpg") if parts.get("weapon") != "lifter" else preload("res://ui/menus/art/bot_rivetrex.jpg"),"hp":int(stats.get("core",0)),"shields":0,"weapon":str(parts.get("weapon","Unavailable")).capitalize(),"ability":str(parts.get("utility","Unavailable")).capitalize(),"boost":"Brake · Space","valid":validation.valid,"reasons":validation.reasons,"stats":{"MASS kg":int(stats.get("mass",0)),"POWER":int(stats.get("power",0)),"SPEED m/s":int(stats.get("speed",0)),"ARMOR %":int(float(stats.get("reduction",0))*100)}})
