class_name CreditWallet
extends RefCounted
## Account credit balance. A finished match pays its server-computed reward once
## per match id (results can arrive again on reconnect or a repeated baseline).
## Credits are meant to unlock Customize parts later; they never change a match.
## This local file is not tamper-proof: server-held identity (#16) must own the
## balance before credits gate anything shared between players.
const DEFAULT_PATH := "user://wallet.cfg"
const REMEMBERED_MATCHES := 64
const MAX_BALANCE := 2000000000
var path: String
var balance := 0
var banked: PackedStringArray = []

func _init(save_path := DEFAULT_PATH) -> void:
	path = save_path
	reload()

func reload() -> void:
	var file := ConfigFile.new()
	balance = 0
	banked = PackedStringArray()
	if file.load(path) != OK:
		return
	var stored: Variant = file.get_value("wallet", "balance", 0)
	if stored is int:
		balance = clampi(stored, 0, MAX_BALANCE)
	var matches: Variant = file.get_value("wallet", "banked_matches", PackedStringArray())
	if matches is PackedStringArray:
		banked = matches

## The server's total reward for one participant of a results record, or 0.
static func reward_for(results: Dictionary, entity_id: int) -> int:
	var participants: Variant = results.get("participants")
	if not participants is Dictionary or not participants.get(entity_id) is Dictionary:
		return 0
	var credits: Variant = participants[entity_id].get("credits")
	if not credits is Dictionary or not credits.get("total") is int:
		return 0
	return clampi(credits.total, 0, MAX_BALANCE)

## Returns true when the reward was added; false for a repeat, empty or invalid reward.
func bank(match_id: String, amount: int) -> bool:
	if match_id.is_empty() or banked.has(match_id) or amount <= 0:
		return false
	balance = mini(MAX_BALANCE, balance + amount)
	banked.append(match_id)
	if banked.size() > REMEMBERED_MATCHES:
		banked = banked.slice(banked.size() - REMEMBERED_MATCHES)
	save()
	return true

func save() -> Error:
	var file := ConfigFile.new()
	file.set_value("wallet", "balance", balance)
	file.set_value("wallet", "banked_matches", banked)
	# Write beside the wallet first so an interrupted save keeps the old balance.
	var staging := path + ".tmp"
	var error := file.save(staging)
	if error == OK:
		error = DirAccess.rename_absolute(staging, path)
	return error
