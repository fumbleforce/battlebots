extends RefCounted
## Saved arena choice for practice and LAN hosting. Joining follows the server.
const PATH := "user://arena_scenery.cfg"
const IDS := ["foundry", "moon", "woodland"]

static func load_choice(path: String = PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return "foundry"
	var choice: Variant = config.get_value("arena", "environment", "foundry")
	return choice if choice is String and choice in IDS else "foundry"

static func save_choice(choice: String, path: String = PATH) -> Error:
	if choice not in IDS:
		return ERR_INVALID_PARAMETER
	var config := ConfigFile.new()
	config.set_value("arena", "environment", choice)
	var error := config.save(path + ".tmp")
	if error != OK:
		return error
	return DirAccess.rename_absolute(path + ".tmp", path)
