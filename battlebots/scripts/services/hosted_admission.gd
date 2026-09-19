class_name HostedAdmission
extends RefCounted
## Server-local allocation policy. Raw admission tickets never enter public views.
var config: Dictionary = {}

func configure(value: Variant, now: float, content_hash: String) -> Error:
	if not value is Dictionary or value.get("schema") != 1 or value.get("revoked", false) != false:
		return ERR_INVALID_DATA
	for field: String in ["allocation_id", "build", "content_hash", "bind_address", "mode"]:
		if not value.get(field) is String or value[field].is_empty() or value[field].length() > 256:
			return ERR_INVALID_DATA
	if value.build != WireCodec.BUILD or value.get("protocol") != WireCodec.PROTOCOL or value.content_hash != content_hash:
		return ERR_INVALID_DATA
	if not integer_between(value.get("port"), 1, 65535) or not integer_between(value.get("capacity"), 2, 10):
		return ERR_INVALID_DATA
	if (value.mode == "teams" and int(value.capacity) not in [2, 4, 10]) \
		or (value.mode == "ffa" and (value.capacity < 4 or value.capacity > 8)) or value.mode not in ["teams", "ffa"]:
		return ERR_INVALID_DATA
	if not timestamp(value.get("lease_expires_at")) or float(value.lease_expires_at) <= now:
		return ERR_INVALID_DATA
	if not value.get("slots") is Array or value.slots.size() > int(value.capacity):
		return ERR_INVALID_DATA
	var slots := {}
	var identities := {}
	var hashes := {}
	var reservations := {}
	for entry: Variant in value.slots:
		if not entry is Dictionary or not integer_between(entry.get("slot"), 0, int(value.capacity) - 1):
			return ERR_INVALID_DATA
		if not entry.get("player_id") is String or entry.player_id.is_empty() or entry.player_id.length() > 128:
			return ERR_INVALID_DATA
		if not hex_token(entry.get("ticket_hash")) or not timestamp(entry.get("expires_at")):
			return ERR_INVALID_DATA
		if not hex_token(entry.get("reservation_id"), 32):
			return ERR_INVALID_DATA
		if slots.has(int(entry.slot)) or identities.has(entry.player_id) or hashes.has(entry.ticket_hash) or reservations.has(entry.reservation_id):
			return ERR_INVALID_DATA
		slots[int(entry.slot)] = true
		identities[entry.player_id] = true
		hashes[entry.ticket_hash] = true
		reservations[entry.reservation_id] = true
	if not config.is_empty():
		for field: String in ["allocation_id", "build", "protocol", "content_hash", "port", "bind_address", "mode", "capacity"]:
			if value[field] != config[field]:
				return ERR_INVALID_DATA
	config = value.duplicate(true)
	return OK

func admit(ticket: Variant, players: Dictionary, now: float) -> Dictionary:
	if not live(now) or not hex_token(ticket):
		return {}
	var hashed: String = ticket.sha256_text()
	for entry: Dictionary in config.slots:
		if entry.ticket_hash != hashed or float(entry.expires_at) <= now:
			continue
		for player: Dictionary in players.values():
			if player.get("service_player_id") == entry.player_id or player.get("allocation_slot") == int(entry.slot):
				return {}
		return {"service_player_id":entry.player_id, "allocation_slot":int(entry.slot), "reservation_id":entry.reservation_id}
	return {}

func retains(player: Dictionary, now: float) -> bool:
	if not live(now):
		return false
	# Ticket expiry limits initial admission. A retained identity may reconnect
	# with its separately issued short-lived session token after ticket expiry.
	for entry: Dictionary in config.slots:
		if entry.player_id == player.get("service_player_id") and int(entry.slot) == player.get("allocation_slot") \
			and entry.reservation_id == player.get("reservation_id"):
			return true
	return false

func live(now: float) -> bool:
	return not config.is_empty() and float(config.lease_expires_at) > now

static func integer_between(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= low and value <= high

static func timestamp(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0

static func hex_token(value: Variant, length := 64) -> bool:
	if not value is String or value.length() != length:
		return false
	for character: String in value:
		if character not in "0123456789abcdef":
			return false
	return true
