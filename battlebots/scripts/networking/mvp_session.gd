class_name MvpSession
extends Node
## B-facing session API. Keep this node at the same relative path on all peers.
signal session_event(kind: String, details: Dictionary)
signal lobby_changed(view: Dictionary)
signal match_changed(view: Dictionary)
signal bot_updated(entity_id: int, view: BotView)
signal combat_event(event: Dictionary)
## Public pickup state changed (items, per-entity match credits).
signal pickups_changed(view: Dictionary)
## One entity collected an item: {entity, kind, part, amount, slot?, credits?}.
signal pickup_collected(event: Dictionary)
## This player touched an item it cannot take: {entity, item, kind, part, reason}.
## Reason is "equipped" or "incompatible". Only the owning player receives it.
signal pickup_refused(event: Dictionary)
const MAX_CONTROL_STATE_BYTES := 131072 # Ten players, up to five detailed round results.
# Arena content this client understands. Older clients cannot build newer arenas,
# so a host rejects them with a visible update message rather than a bad world.
# 1 = Moon, 2 = Woodland.
const ARENA_RULES := 2
const ARENA_MIN_RULES := {"moon":1, "woodland":2}

var registry := ContentRegistry.new()
var match_state := MatchState.new()
var world: AuthorityWorld
var players: Dictionary = {}
var peer_entities: Dictionary = {}
var local_entity := 0
var reconnect_token := ""
var connection_state := "offline"
var lobby_view: Dictionary = {}
var match_view: Dictionary = {}
## Public pickup state for presentation: {match_id, revision, items, credits}.
var pickup_view: Dictionary = {}
var diagnostics := {"rtt_ms":0.0, "correction_m":0.0, "rejected_inputs":0, "snapshot_bytes":0, "snapshots_received":0}
var _server := false
var _time := 0.0
var _last_event := -1
var _next_entity := 1
var _hello_data: Dictionary = {}
var _pending_peers: Dictionary = {}
var _control_budget: Dictionary = {}
var _input_queue: Dictionary = {}
var _input_highwater: Dictionary = {}
var _input_budget: Dictionary = {}
var _last_input_time: Dictionary = {}
var _loaded: Dictionary = {}
var _rematch: Dictionary = {}
var _forfeit: Dictionary = {}
var _local_commands: Array = []
var _client_sequence := 0
var _client_tick := 0
var _remote_buffers: Dictionary = {}
var _last_snapshot_tick: Dictionary = {}
var _last_ping := 0.0
var _ping_ticks: Dictionary = {}
var _server_tick_offset := 0.0
var _clock_ready := false
var _clock_samples: Array[Vector2] = []
var _results: Dictionary = {}
var interpolation_delay := 0.1
var _last_arrival := 0.0
var _effect_ids: Dictionary = {}
var network_simulation := NetworkSimulator.new()
var player_capacity := 4
var match_mode := "teams"
var arena_id := "foundry"
var hosted_admission: HostedAdmission
var hosted_config_refresh: Callable
var _join_address := ""
var _join_port := 0
var _reconnect_deadline := 0
var _reconnecting := false
var _tearing_down := false
var practice_director: PracticeBotDirector
## Offline Woodland practice only (#45): edge starts and the roaming giant.
var woodland_boss: WoodlandBoss
## Woodland LAN/online matches include the roaming giant as a neutral hazard (#79).
var woodland_boss_online := true
## Authority only: stock item pickups when a match or practice starts. Fixtures
## that hold MvpBot references across frames disable this, since a part pickup
## replaces the bot node.
var pickups_enabled := true
var _pickup_revision := -1
## Catalogue slots the local part shortcuts cycle.
const DEV_SLOTS := ["weapon", "chassis", "drive"]

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func() -> void: _transport_failed("Connection failed"))
	multiplayer.server_disconnected.connect(func() -> void: _transport_failed("Server disconnected"))
	multiplayer.allow_object_decoding = false

func host(port := 24567, listen := true, player_count := 4, mode := "teams", bind_address := "*", selected_arena := "foundry") -> Error:
	if connection_state != "offline":
		return ERR_ALREADY_IN_USE
	if selected_arena not in ArenaBounds.IDS:
		return ERR_INVALID_PARAMETER
	arena_id = selected_arena
	_clear_reconnect()
	if (mode == "teams" and player_count not in [2, 4, 10]) or (mode == "ffa" and (player_count < 4 or player_count > 8)) or mode not in ["teams", "ffa"]:
		session_event.emit("error", {"message":"Choose 2, 4 or 10 team players, or an FFA limit of 4–8"})
		return ERR_INVALID_PARAMETER
	if hosted_admission != null and (listen or not hosted_admission.live(Time.get_unix_time_from_system())):
		return ERR_UNAUTHORIZED
	if hosted_admission != null and (hosted_admission.config.port != port or hosted_admission.config.capacity != player_count
		or hosted_admission.config.mode != mode or hosted_admission.config.bind_address != bind_address):
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var bind_ip: String = bind_address
	if bind_ip != "*" and not bind_ip.is_valid_ip_address():
		bind_ip = IP.resolve_hostname(bind_ip, IP.TYPE_IPV4)
	if bind_ip.is_empty():
		return ERR_CANT_RESOLVE
	peer.set_bind_ip(bind_ip)
	# Keep a few handshake slots beyond the match capacity for version rejection
	# and reconnects; admitted players are still bounded by player_capacity.
	var error := peer.create_server(port, player_count + 4, 3)
	if error != OK:
		session_event.emit("error", {"message":"Cannot bind UDP port", "code":error})
		return error
	# Apply on both ends: compressed baselines avoid oversized public-route
	# datagrams and reduce snapshot bandwidth. Godot exposes no ENet MTU setter.
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	player_capacity = player_count
	match_mode = mode
	match_state.configure(player_capacity, match_mode)
	_server = true
	connection_state = "hosting"
	_make_world()
	if listen:
		local_entity = _admit(1, registry.starter())
		peer_entities[1] = local_entity
	_publish_lobby()
	session_event.emit("hosted", {"port":port, "capacity":player_capacity})
	return OK

func join(address: String, port := 24567, token := "", admission_ticket := "") -> Error:
	if connection_state != "offline":
		return ERR_ALREADY_IN_USE
	_clear_reconnect()
	return _join(address, port, token, admission_ticket)

func _join(address: String, port: int, token: String, admission_ticket: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port, 3)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	_join_address = address
	_join_port = port
	_hello_data = {"protocol":WireCodec.PROTOCOL, "build":WireCodec.BUILD, "content":registry.content_hash,
		"token":token, "admission_ticket":admission_ticket, "arena_rules":ARENA_RULES}
	_server = false
	connection_state = "connecting"
	arena_id = "foundry" # The server's validated baseline chooses the actual world.
	multiplayer.multiplayer_peer = peer
	_make_world()
	return OK

func can_reconnect() -> bool:
	return connection_state == "offline" and not reconnect_token.is_empty() and reconnect_seconds_remaining() > 0.0

func reconnect_seconds_remaining() -> float:
	return maxf(0.0, float(_reconnect_deadline - Time.get_ticks_msec()) / 1000.0) if _reconnect_deadline > 0 else 0.0

func is_reconnecting() -> bool:
	return _reconnecting

func reconnect() -> Error:
	if not can_reconnect():
		return ERR_UNAVAILABLE
	_reconnecting = true
	var error := _join(_join_address, _join_port, reconnect_token, "")
	if error != OK:
		_reconnecting = false
		session_event.emit("error", {"message":"Could not reconnect", "code":error, "reconnect_available":can_reconnect()})
	return error

func _clear_reconnect() -> void:
	reconnect_token = ""
	_join_address = ""
	_join_port = 0
	_reconnect_deadline = 0
	_reconnecting = false

func practice(draft: Dictionary = {}, selected_arena := "foundry") -> Error:
	if connection_state != "offline":
		return ERR_ALREADY_IN_USE
	_clear_reconnect()
	var build := registry.starter() if draft.is_empty() else draft
	if selected_arena not in ArenaBounds.IDS:
		return ERR_INVALID_PARAMETER
	if not registry.validate(build).valid:
		return ERR_INVALID_DATA
	_server = true
	connection_state = "practice"
	arena_id = selected_arena
	_make_world()
	local_entity = _admit(1, build)
	var bot := world.spawn(local_entity, 0, 0, build)
	bot.owner_id = 1
	practice_director = PracticeBotDirector.new()
	_next_entity = practice_director.configure(world, local_entity, _next_entity)
	if arena_id == "woodland":
		woodland_boss = WoodlandBoss.new()
		_next_entity = woodland_boss.configure(world, _next_entity)
	if pickups_enabled:
		world.begin_pickups(randi())
	match_state.match_id = "practice"
	match_state.round_index = 1
	match_state.transition("active", 0)
	match_view = match_state.snapshot()
	session_event.emit("practice", {})
	return OK

## Local development shortcut (#64): replace the local bot's weapon, body or
## drive with the next one that fits, mid-match. Honoured only where this
## process runs the match itself (practice or a self-hosted listen game),
## never on a hosted worker or as a joined client. The swap reuses the pickup
## path, so peers of a local host receive it like a picked-up part.
## Returns {"part": id} after a swap, else {"refused": reason} with reason
## "remote" (not this computer's game), "unavailable" or "no_fit".
func dev_cycle_part(slot: String) -> Dictionary:
	if slot not in DEV_SLOTS:
		return {"refused":"unavailable"}
	if not _server or hosted_admission != null or connection_state not in ["practice", "hosting"] or not is_instance_valid(world):
		return {"refused":"remote"}
	var bot: MvpBot = world.bots.get(local_entity)
	if bot == null or bot.combat.eliminated:
		return {"refused":"unavailable"}
	var pickups := world.pickups
	var options: Array[String] = []
	for id: String in pickups.registry.parts:
		if pickups.registry.parts[id].category == slot and (slot != "chassis" or id in MatchPickups.OFFERED_CHASSIS):
			options.append(id)
	var current: String = bot.loadout.parts.get(slot, "")
	var start := options.find(current)
	for step: int in range(1, options.size()):
		var part := options[(start + step) % options.size()]
		var next := pickups.swapped(bot.loadout, part)
		if next.is_empty() and slot == "chassis":
			# A body that cannot carry the fitted weapon takes the lifter.
			var fallback: Dictionary = bot.loadout.duplicate(true)
			fallback.parts.weapon = "lifter"
			next = pickups.swapped(fallback, part)
		if next.is_empty():
			continue
		world.apply_loadout(local_entity, next)
		# Publish like a pickup so a local host's guests rebuild the same bot.
		pickups.revision += 1
		return {"part":part}
	return {"refused":"no_fit"}

func practice_target() -> BotSource:
	if connection_state != "practice" or not is_instance_valid(world):
		return null
	if practice_director != null:
		return world.bots.get(practice_director.target_id)
	return null

func restart_practice() -> Error:
	# Local training is the only mode allowed to repair on demand. This is not an RPC.
	if connection_state != "practice" or not _server or not is_instance_valid(world):
		return ERR_UNAUTHORIZED
	_input_queue.clear()
	_local_commands.clear()
	_input_budget.clear()
	world.reset_round()
	if practice_director != null: practice_director.restart()
	if woodland_boss != null: woodland_boss.restart()
	# Keep command sequence high-water marks: bot identities survive this reset.
	var neutral := BotCommand.new()
	neutral.brake = true
	neutral.jump_cancel = true
	neutral.secondary_held = true
	for bot: MvpBot in world.bots.values():
		bot.body.accept_command(neutral)
	match_state.transition("active", 0)
	match_view = match_state.snapshot()
	match_changed.emit(match_view.duplicate(true))
	session_event.emit("practice_restarted", {})
	return OK

func leave() -> void:
	_clear_reconnect()
	_disconnect()

func _disconnect() -> void:
	if _tearing_down:
		return
	_tearing_down = true
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_state = "offline"
	practice_director = null
	woodland_boss = null
	_server = false
	local_entity = 0
	players.clear()
	peer_entities.clear()
	_pending_peers.clear()
	_control_budget.clear()
	_input_queue.clear()
	_input_highwater.clear()
	_input_budget.clear()
	_last_input_time.clear()
	_loaded.clear()
	_rematch.clear()
	_forfeit.clear()
	_results.clear()
	_local_commands.clear()
	_remote_buffers.clear()
	_last_snapshot_tick.clear()
	_effect_ids.clear()
	_ping_ticks.clear()
	_server_tick_offset = 0.0
	_clock_ready = false
	_clock_samples.clear()
	_client_tick = 0
	_last_ping = 0.0
	network_simulation.pending.clear()
	_client_sequence = 0
	match_state = MatchState.new()
	match_mode = "teams"
	hosted_admission = null
	hosted_config_refresh = Callable()
	match_view = {}
	lobby_view = {}
	pickup_view = {}
	_pickup_revision = -1
	if is_instance_valid(world):
		world.queue_free()
		world = null
	_hello_data.clear()
	session_event.emit("left", {"reconnect_available":can_reconnect()})
	_tearing_down = false

func _make_world() -> void:
	world = AuthorityWorld.new()
	world.arena_id = arena_id
	world.name = "World"
	add_child(world)

func refresh_hosted_admission() -> void:
	if not _server or hosted_admission == null:
		return
	for id: int in players.keys():
		if hosted_admission.retains(players[id], Time.get_unix_time_from_system()):
			continue
		var peer: int = players[id].peer
		if world.bots.has(id):
			world.bots[id].combat.eliminate("allocation revoked")
		if peer != 0:
			_peer_disconnected(peer)
			multiplayer.multiplayer_peer.disconnect_peer(peer)
		if match_state.phase == "lobby":
			players.erase(id)
	_publish_lobby()

func _fail(message: String) -> void:
	leave()
	session_event.emit("error", {"message":message, "reconnect_available":false})

func _transport_failed(message: String) -> void:
	if _tearing_down or connection_state == "offline":
		return
	if not _server and connection_state == "connected" and not reconnect_token.is_empty():
		_reconnect_deadline = Time.get_ticks_msec() + 20000
	elif not _reconnecting:
		_clear_reconnect()
	_reconnecting = false
	_disconnect()
	session_event.emit("error", {"message":message, "reconnect_available":can_reconnect()})

func _connected() -> void:
	_hello.rpc_id(1, WireCodec.json_packet(_hello_data))

func _peer_connected(peer: int) -> void:
	if _server:
		_pending_peers[peer] = _time + 10

func _peer_disconnected(peer: int) -> void:
	_pending_peers.erase(peer)
	_control_budget.erase(peer)
	if not _server or not peer_entities.has(peer):
		return
	var id: int = peer_entities[peer]
	peer_entities.erase(peer)
	players[id].peer = 0
	players[id].ready = false
	players[id].deadline = _time + 20
	_input_queue.erase(id)
	if match_state.phase == "lobby" and hosted_admission == null:
		players.erase(id)
	_publish_lobby()

func _admit(peer: int, draft: Dictionary) -> int:
	var id := _next_entity
	_next_entity += 1
	var counts := [0, 0]
	if match_mode != "ffa":
		for existing: int in players:
			counts[players[existing].team] += 1
	var team := id if match_mode == "ffa" else (0 if counts[0] <= counts[1] else 1)
	players[id] = {"peer":peer, "team":team, "ready":false, "loadout":draft.duplicate(true),
		"token":Crypto.new().generate_random_bytes(32).hex_encode(), "deadline":0.0}
	peer_entities[peer] = id
	return id

@rpc("any_peer", "call_remote", "reliable", 0)
func _hello(packet: PackedByteArray) -> void:
	if not _server:
		return
	var peer := multiplayer.get_remote_sender_id()
	if not _pending_peers.has(peer) or not _control_allowed(peer):
		return
	var data := WireCodec.read_json(packet, 1024)
	if data.get("protocol") != WireCodec.PROTOCOL or data.get("build") != WireCodec.BUILD or data.get("content") != registry.content_hash:
		_rejected.rpc_id(peer, "Protocol, build or content version mismatch")
		return
	var arena_rules: Variant = data.get("arena_rules", 0)
	var peer_rules := int(arena_rules) if arena_rules is int or arena_rules is float else 0
	if peer_rules < ARENA_MIN_RULES.get(arena_id, 0):
		_rejected.rpc_id(peer, "Update the game to join the %s arena" % arena_id.capitalize())
		return
	if hosted_admission != null and hosted_config_refresh.is_valid() and not hosted_config_refresh.call():
		return
	var id := 0
	var token: Variant = data.get("token", "")
	if not token is String or token.length() > 64:
		return
	if not token.is_empty():
		for candidate: int in players:
			if players[candidate].token == token and players[candidate].peer == 0 and players[candidate].deadline > _time:
				if hosted_admission != null and not hosted_admission.retains(players[candidate], Time.get_unix_time_from_system()):
					continue
				id = candidate
				players[id].peer = peer
				players[id].token = Crypto.new().generate_random_bytes(32).hex_encode()
				peer_entities[peer] = id
				break
		if id == 0:
			_rejected.rpc_id(peer, "Reconnect token invalid or expired")
			return
	else:
		if players.size() >= player_capacity or match_state.phase != "lobby":
			_rejected.rpc_id(peer, "Lobby full or match already started")
			return
		var allocation: Dictionary = {}
		if hosted_admission != null:
			allocation = hosted_admission.admit(data.get("admission_ticket", ""), players, Time.get_unix_time_from_system())
			if allocation.is_empty():
				_rejected.rpc_id(peer, "Admission ticket invalid, expired or unavailable")
				return
		id = _admit(peer, registry.starter())
		if not allocation.is_empty():
			players[id].merge(allocation)
			players[id].team = id if match_mode == "ffa" else int(allocation.allocation_slot) % 2
	_pending_peers.erase(peer)
	_input_highwater[id] = -1
	_input_queue[id] = []
	if world.bots.has(id):
		world.bots[id].last_sequence = -1
		world.bots[id].owner_id = peer
	_welcome.rpc_id(peer, id, players[id].token)
	_send_baseline(peer)
	_publish_lobby()

@rpc("authority", "call_remote", "reliable", 0)
func _rejected(message: String) -> void:
	_fail(message)

@rpc("authority", "call_remote", "reliable", 0)
func _welcome(id: int, token: String) -> void:
	if _reconnecting and reconnect_seconds_remaining() <= 0.0:
		_fail("Reconnect window expired; match incomplete")
		return
	var reconnected := _reconnecting or not str(_hello_data.get("token", "")).is_empty()
	_reconnecting = false
	_reconnect_deadline = 0
	local_entity = id
	reconnect_token = token
	connection_state = "connected"
	_client_sequence = 0
	_hello_data.clear()
	session_event.emit("joined", {"entity_id":id, "reconnected":reconnected})

func set_ready(ready: bool) -> void:
	_request_local({"kind":"ready", "value":ready})
func set_loadout(draft: Dictionary) -> void:
	_request_local({"kind":"loadout", "value":draft})
func set_team(team: int) -> void:
	_request_local({"kind":"team", "value":team})
func vote_rematch() -> void:
	_request_local({"kind":"rematch"})
func vote_forfeit() -> void:
	_request_local({"kind":"forfeit"})

func _request_local(data: Dictionary) -> void:
	if _server:
		_handle_request(1, data)
	elif connection_state == "connected":
		_request.rpc_id(1, WireCodec.json_packet(data))

@rpc("any_peer", "call_remote", "reliable", 0)
func _request(packet: PackedByteArray) -> void:
	if _server:
		var peer := multiplayer.get_remote_sender_id()
		if _control_allowed(peer):
			_handle_request(peer, WireCodec.read_json(packet, 4096))

func _control_allowed(peer: int) -> bool:
	var history: Array = _control_budget.get(peer, [])
	while not history.is_empty() and _time - float(history.front()) >= 1:
		history.pop_front()
	if history.size() >= 12:
		return false
	history.append(_time)
	_control_budget[peer] = history
	return true

func _handle_request(peer: int, data: Dictionary) -> void:
	if not peer_entities.has(peer):
		return
	var id: int = peer_entities[peer]
	var kind: String = str(data.get("kind", ""))
	if kind == "loaded" and match_state.phase == "loading" and data.get("match_id") == match_state.match_id:
		_loaded[id] = true
	elif kind == "rematch" and match_state.phase == "results":
		_rematch[id] = true
	elif kind == "forfeit" and match_state.phase in ["active", "overtime"]:
		_forfeit[id] = true
	elif match_state.phase == "lobby":
		if kind == "ready" and data.get("value") is bool:
			players[id].ready = data.value and registry.validate(players[id].loadout).valid
		elif kind == "loadout" and data.get("value") is Dictionary:
			var validation := registry.validate(data.value)
			if validation.valid:
				players[id].loadout = validation.loadout
				players[id].ready = false
			else:
				_request_error(peer, "loadout", "; ".join(validation.reasons))
		elif kind == "team" and hosted_admission != null:
			_request_error(peer, kind, "Allocated teams cannot be changed")
		elif kind == "team" and match_mode == "ffa":
			_request_error(peer, kind, "FFA has no teams")
		# JSON decodes numbers as floats; array membership distinguishes 0.0 from 0.
		elif kind == "team" and (data.get("value") is int or data.get("value") is float) \
			and (data.get("value") == 0 or data.get("value") == 1):
			var count := 0
			for other: int in players:
				count += int(players[other].team == int(data.value) and other != id)
			if count < player_capacity / 2:
				players[id].team = int(data.value)
				for other: int in players:
					players[other].ready = false
	else:
		_request_error(peer, kind, "Request is not allowed in this match phase")
	_publish_lobby()

func _request_error(peer: int, operation: String, message: String) -> void:
	if peer == 1:
		session_event.emit("error", {"operation":operation, "message":message})
	else:
		_control_error.rpc_id(peer, operation, message)

@rpc("authority", "call_remote", "reliable", 0)
func _control_error(operation: String, message: String) -> void:
	session_event.emit("error", {"operation":operation, "message":message})

func _public_lobby() -> Dictionary:
	var slots: Array = []
	for id: int in players:
		var p: Dictionary = players[id]
		slots.append({"entity_id":id, "peer":p.peer, "team":p.team, "ready":p.ready,
			"connected":p.peer != 0, "loadout":p.loadout.duplicate(true)})
	return {"slots":slots, "capacity":player_capacity, "mode":match_state.mode,
		"minimum_players":4 if match_mode == "ffa" else player_capacity, "phase":match_state.phase, "arena":arena_id}

func _public_match() -> Dictionary:
	# Frequent timer/phase updates carry round summaries. Detailed participant
	# history is delivered once with the reliable final result, or on reconnect.
	var view := match_state.snapshot()
	for round_result: Dictionary in view.rounds:
		round_result.erase("participants")
	return view

func _publish_lobby() -> void:
	lobby_view = _public_lobby()
	lobby_changed.emit(lobby_view.duplicate(true))
	for peer: int in peer_entities:
		if peer != 1 and _peer_can_receive(peer):
			_lobby.rpc_id(peer, var_to_bytes(lobby_view))

func _peer_can_receive(peer: int) -> bool:
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null or not peer_entities.has(peer):
		return false
	var remote := transport.get_peer(peer)
	return remote != null and remote.get_state() == ENetPacketPeer.STATE_CONNECTED

@rpc("authority", "call_remote", "reliable", 0)
func _lobby(packet: PackedByteArray) -> void:
	if packet.size() <= 16384:
		lobby_view = bytes_to_var(packet)
		lobby_changed.emit(lobby_view.duplicate(true))

func _start() -> void:
	world.clear_bots()
	woodland_boss = null
	match_state.begin(player_capacity, match_mode)
	_loaded.clear()
	_rematch.clear()
	_forfeit.clear()
	_results.clear()
	var slots := [0, 0]
	var ffa_slot := 0
	for id: int in players:
		var p: Dictionary = players[id]
		var slot: int = ffa_slot if match_mode == "ffa" else slots[p.team]
		if hosted_admission != null:
			slot = int(p.allocation_slot) if match_mode == "ffa" else int(p.allocation_slot) / 2
		var bot := world.spawn(id, p.team, slot, p.loadout, player_capacity / 2, match_mode)
		ffa_slot += 1
		if match_mode != "ffa":
			slots[p.team] += 1
		bot.owner_id = p.peer
		_input_queue[id] = []
		if p.peer == 1:
			_loaded[id] = true
	if arena_id == "woodland" and woodland_boss_online:
		woodland_boss = WoodlandBoss.new()
		_next_entity = woodland_boss.configure(world, _next_entity)
	if pickups_enabled:
		world.begin_pickups(randi())
	_pickup_revision = world.pickups.revision
	pickup_view = _pickup_state(false)
	pickups_changed.emit(pickup_view.duplicate(true))
	for peer: int in peer_entities:
		if peer != 1 and _peer_can_receive(peer):
			_send_baseline(peer)
	_publish_lobby()

func _send_baseline(peer: int) -> void:
	_baseline.rpc_id(peer, var_to_bytes({"lobby":_public_lobby(), "match":_public_match(), "bots":_bot_snapshots(),
		"server_tick":world.tick, "results":_results, "arena":arena_id, "pickups":_pickup_state(false),
		"npcs":{woodland_boss.boss_id:WoodlandBoss.NPC_KIND} if woodland_boss != null and is_instance_valid(woodland_boss.boss) else {}}))

func _bot_snapshots() -> Dictionary:
	var states := {}
	for id: int in world.bots:
		states[id] = WireCodec.encode_bot(world.bots[id], WireCodec.snapshot_epoch(match_state.match_id, match_state.round_index))
	return states

@rpc("authority", "call_remote", "reliable", 0)
func _baseline(packet: PackedByteArray) -> void:
	if packet.size() > MAX_CONTROL_STATE_BYTES:
		return
	var data: Dictionary = bytes_to_var(packet)
	var selected: Variant = data.get("arena", "foundry")
	if not selected is String or selected not in ArenaBounds.IDS:
		session_event.emit("error", {"message":"Unsupported arena from server"})
		leave()
		return
	arena_id = selected
	world.set_arena(arena_id)
	lobby_view = data.lobby
	player_capacity = int(lobby_view.capacity)
	match_mode = "ffa" if lobby_view.mode == "ffa" else "teams"
	match_view = data.match
	_server_tick_offset = float(data.server_tick) - _client_tick
	_clock_ready = false
	_clock_samples.clear()
	world.clear_bots()
	_remote_buffers.clear()
	_last_snapshot_tick.clear()
	_local_commands.clear()
	for slot: Dictionary in lobby_view.slots:
		if not data.bots.has(slot.entity_id):
			continue
		var bot := world.spawn(slot.entity_id, slot.team, 0, slot.loadout, player_capacity / 2, match_mode)
		bot.simulated = false
		bot.body.freeze = true
		bot.body.reset_pose = null
		bot.owner_id = slot.peer
		if bot.entity_id == local_entity:
			diagnostics.correction_m = 0.0
			bot.body.reconciled.connect(_record_local_correction)
		_snapshot(data.bots[slot.entity_id])
	var npcs: Variant = data.get("npcs", {})
	if npcs is Dictionary:
		for id: Variant in npcs:
			# Only the known kind, on its own arena, and never over a player.
			if not id is int or npcs[id] != WoodlandBoss.NPC_KIND or arena_id != "woodland" \
					or world.bots.has(id) or not data.bots.has(id):
				continue
			var giant := WoodlandBoss.replica(world, id)
			if giant == null:
				continue
			giant.simulated = false
			giant.body.freeze = true
			giant.body.reset_pose = null
			_snapshot(data.bots[id])
	pickup_view = {}
	_accept_pickups(data.get("pickups", {}))
	match_changed.emit(match_view.duplicate(true))
	lobby_changed.emit(lobby_view.duplicate(true))
	_accept_results(data.get("results", {}))
	if match_view.phase == "loading":
		_request_local({"kind":"loaded", "match_id":match_view.match_id})

## Measure the displacement actually applied by Jolt, after replay is constrained.
## A queued replay targets the next physics callback; comparing it with the
## snapshot-receipt pose incorrectly counts another tick of ordinary travel.
func _record_local_correction(displacement: Vector3) -> void:
	diagnostics.correction_m = displacement.length()

func submit_local(command: BotCommand) -> void:
	if command == null or not command.is_valid() or local_entity == 0:
		return
	var data := WireCodec.command_to_array(command)
	data[0] = _client_sequence
	_client_sequence += 1
	if _server:
		_accept_inputs(1, [data])
	elif connection_state == "connected":
		_local_commands.append(data)
		if _local_commands.size() > 120:
			_local_commands.pop_front()
		if world.bots.has(local_entity) and match_view.get("phase") in ["active", "overtime"]:
			var bot: MvpBot = world.bots[local_entity]
			if not bot.remote_state.get("eliminated", true):
				var predicted := WireCodec.command_from_array(data)
				bot.body.accept_command(predicted)
				bot.combat.tick_perks(1.0 / 60.0, predicted, true, bot.body.grounded)
				bot.body.nitro_active = bot.combat.nitro_active
				if bot.combat.jump_release_speed > 0.0:
					bot.body.queue_jump(bot.combat.jump_release_speed * sqrt(bot.body.gravity_scale))

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _inputs(packet: PackedByteArray) -> void:
	if not _server or packet.size() > 512:
		return
	var data: Variant = bytes_to_var(packet)
	if data is Array and data.size() <= 4:
		_accept_inputs(multiplayer.get_remote_sender_id(), data)

func _accept_inputs(peer: int, data: Array) -> void:
	if not peer_entities.has(peer):
		return
	var id: int = peer_entities[peer]
	var budget: Array = _input_budget.get(id, [])
	while not budget.is_empty() and _time - float(budget.front()) >= 1:
		budget.pop_front()
	for item: Variant in data:
		var command := WireCodec.command_from_array(item)
		var high: int = _input_highwater.get(id, -1)
		var allowed_gap := maxi(128, ceili((_time - float(_last_input_time.get(id, _time))) * 120))
		if command == null or command.sequence > high + allowed_gap or budget.size() >= 90:
			diagnostics.rejected_inputs += 1
			continue
		if command.sequence <= high:
			continue
		var queue: Array = _input_queue.get(id, [])
		if queue.size() >= 8:
			diagnostics.rejected_inputs += 1
			continue
		queue.append(command)
		_input_queue[id] = queue
		_input_highwater[id] = command.sequence
		_last_input_time[id] = _time
		budget.append(_time)
	_input_budget[id] = budget

func _physics_process(delta: float) -> void:
	if connection_state == "offline" or not is_instance_valid(world):
		return
	_time += delta
	network_simulation.tick(delta)
	if not _server:
		_client_tick += 1
		if connection_state == "connected" and _client_tick % 2 == 0 and not _local_commands.is_empty():
			var packet := var_to_bytes(_local_commands.slice(maxi(0, _local_commands.size() - 4)))
			network_simulation.send(func() -> void: _inputs.rpc_id(1, packet))
		if connection_state == "connected" and _time - _last_ping >= 1:
			_last_ping = _time
			var stamp := Time.get_ticks_msec()
			_ping_ticks[stamp] = _client_tick
			if _ping_ticks.size() > 8:
				_ping_ticks.erase(_ping_ticks.keys().front())
			_ping.rpc_id(1, stamp)
		return
	for peer: int in _pending_peers.keys():
		if _pending_peers[peer] <= _time:
			multiplayer.multiplayer_peer.disconnect_peer(peer)
			_pending_peers.erase(peer)
	if hosted_admission != null and match_state.phase == "lobby":
		var removed_reservation := false
		for id: int in players.keys():
			if players[id].peer == 0 and players[id].deadline <= _time:
				players.erase(id)
				removed_reservation = true
		if removed_reservation:
			_publish_lobby()
	var enough_players := players.size() >= 4 if match_mode == "ffa" else players.size() == player_capacity
	if match_state.phase == "lobby" and enough_players:
		var all_ready := true
		for id: int in players:
			all_ready = all_ready and players[id].ready and players[id].peer != 0
		if all_ready:
			_start()
	if match_state.phase == "loading" and _loaded.size() == players.size():
		match_state.transition("countdown", 5)
	for id: int in players:
		if players[id].peer == 0 and players[id].deadline <= _time and world.bots.has(id):
			world.bots[id].combat.eliminate("disconnect")
		if world.bots.has(id) and _input_queue.has(id) and not _input_queue[id].is_empty():
			world.bots[id].submit_command(_input_queue[id].pop_front())
	var active := match_state.phase in ["active", "overtime"]
	if connection_state == "practice" and practice_director != null:
		practice_director.step(delta)
	if woodland_boss != null and (connection_state == "practice" or active):
		woodland_boss.step(delta)
	world.step(delta, active, match_state.round_index)
	if world.pickups.revision != _pickup_revision:
		_pickup_revision = world.pickups.revision
		_publish_pickups()
	_deliver_refusals()
	if connection_state == "practice":
		for event: Dictionary in world.weapons.events:
			combat_event.emit(event.duplicate(true))
		bot_updated.emit(local_entity, world.bots[local_entity].read_view())
		return
	if active:
		var sides: Array = players.keys() if match_mode == "ffa" else [0, 1]
		for team: int in sides:
			var voters := 0
			var connected := 0
			for id: int in players:
				if players[id].team == team and players[id].peer != 0:
					connected += 1
					voters += int(_forfeit.has(id))
			if connected > 0 and voters == connected:
				for id: int in players:
					if players[id].team == team:
						world.bots[id].combat.eliminate("forfeit")
		for event: Dictionary in world.weapons.events:
			event["match_id"] = match_state.match_id
			combat_event.emit(event.duplicate(true))
			for peer: int in peer_entities:
				if peer != 1 and _peer_can_receive(peer):
					_effect.rpc_id(peer, var_to_bytes(event))
	var old_phase := match_state.phase
	var teams := {}
	# Match rules and results count players only; the Woodland giant is neutral.
	var fighters := {}
	for id: int in players:
		teams[id] = players[id].team
		if world.bots.has(id):
			fighters[id] = world.bots[id].combat
	match_state.advance(delta, fighters, teams, world.tick)
	if old_phase in ["active", "overtime"] and match_state.phase in ["intermission", "results"]:
		var round_stats := {}
		for id: int in fighters:
			round_stats[id] = world.bots[id].combat.snapshot()
		match_state.rounds.back()["participants"] = round_stats
	if old_phase == "intermission" and match_state.phase == "countdown":
		world.reset_round()
		if woodland_boss != null: woodland_boss.restart()
		_forfeit.clear()
	var publish_results := match_state.phase == "results" and _results.is_empty()
	if publish_results:
		_results = {"match":match_state.snapshot(), "content_hash":registry.content_hash, "build":WireCodec.BUILD, "participants":{}}
		for id: int in fighters:
			_results.participants[id] = world.bots[id].combat.snapshot()
			for field: String in ["damage", "eliminations", "assists", "component_disables", "recoveries"]:
				_results.participants[id][field] = 0
				for round_result: Dictionary in match_state.rounds:
					_results.participants[id][field] += round_result.get("participants", {}).get(id, {}).get(field, 0)
			var won: bool = id in match_state.winners if match_mode == "ffa" else 				(players.has(id) and match_state.winner >= 0 and match_state.winner == players[id].team)
			_results.participants[id]["credits"] = MatchPickups.reward(_results.participants[id], won,
				int(world.pickups.credits.get(id, 0)))
		session_event.emit("results", _results.duplicate(true))
	if match_state.phase == "results" and match_mode == "ffa":
		var connected_count := 0
		var all_voted := true
		for id: int in players:
			if players[id].peer != 0:
				connected_count += 1
				all_voted = all_voted and _rematch.has(id)
		if connected_count >= 4 and all_voted:
			for id: int in players.keys():
				if players[id].peer == 0:
					players.erase(id)
			_start()
	elif match_state.phase == "results" and _rematch.size() == player_capacity:
		var connected := true
		for id: int in players:
			connected = connected and players[id].peer != 0
		if connected:
			_start()
	if old_phase != "lobby" and match_state.phase == "lobby":
		for id: int in players.keys():
			players[id].ready = false
			if players[id].peer == 0:
				players.erase(id)
		world.clear_bots()
		pickup_view = {}
		_pickup_revision = world.pickups.revision
		pickups_changed.emit({})
		_publish_lobby()
	if match_state.event_id != _last_event or world.tick % 60 == 0:
		var changed_event := match_state.event_id != _last_event
		_last_event = match_state.event_id
		match_view = _public_match()
		match_changed.emit(match_view.duplicate(true))
		# Round transitions must carry the repaired/spawned state they announce.
		# The existing 1 Hz heartbeat also repairs state when ENet throttles the
		# 20 Hz unreliable stream. Per-entity tick guards reject older checkpoints.
		var include_bots := changed_event or match_state.phase in ["countdown", "active", "overtime"]
		var checkpoint := var_to_bytes({"view":match_view, "results":_results if publish_results else {},
			"bots":_bot_snapshots() if include_bots else {}})
		for peer: int in peer_entities:
			if peer != 1 and _peer_can_receive(peer):
				_match.rpc_id(peer, checkpoint)
	if world.tick % 3 == 0:
		for id: int in world.bots:
			# A reset is applied by Jolt on the next physics step; never label the old
			# physical pose as a state from the new round.
			if world.bots[id].body.reset_pose is Transform3D:
				continue
			var packet := WireCodec.encode_bot(world.bots[id], WireCodec.snapshot_epoch(match_state.match_id, match_state.round_index))
			diagnostics.snapshot_bytes = maxi(diagnostics.snapshot_bytes, packet.size())
			for peer: int in peer_entities:
				if peer != 1:
					network_simulation.send(func() -> void:
						# ENet begins closing before SceneMultiplayer reports peer_disconnected.
						# A delayed snapshot must not target that channel-less transport.
						if _peer_can_receive(peer):
							_snapshot.rpc_id(peer, packet))

@rpc("authority", "call_remote", "reliable", 0)
func _match(packet: PackedByteArray) -> void:
	if packet.size() > MAX_CONTROL_STATE_BYTES:
		return
	var data: Dictionary = bytes_to_var(packet)
	var changed_round: bool = data.view.get("round") != match_view.get("round") or data.view.get("match_id") != match_view.get("match_id")
	match_view = data.view
	if changed_round:
		_remote_buffers.clear()
		_last_snapshot_tick.clear()
		_local_commands.clear()
		for bot: MvpBot in world.bots.values():
			bot.body.correction.clear()
			bot.visual_error = Vector3.ZERO
	if match_view.phase == "lobby":
		world.clear_bots()
		_remote_buffers.clear()
		if not pickup_view.is_empty():
			pickup_view = {}
			pickups_changed.emit({})
	for state: PackedByteArray in data.get("bots", {}).values():
		_snapshot(state)
	match_changed.emit(match_view.duplicate(true))
	_accept_results(data.results)

func _accept_results(results: Dictionary) -> void:
	if not results.is_empty() and _results.get("match", {}).get("match_id", "") != results.match.match_id:
		_results = results
		session_event.emit("results", _results.duplicate(true))

# Each entity has its own tick guard below. ENet's channel-wide ordered stream
# would let a newer packet for one bot discard valid packets for other bots.
@rpc("authority", "call_remote", "unreliable", 2)
func _snapshot(packet: PackedByteArray) -> void:
	if packet.size() > 1200:
		return
	var values: Variant = bytes_to_var(packet)
	if not values is Array or values.size() != WireCodec.SNAPSHOT_FIELDS or not world.bots.has(values[2]):
		return
	var bot: MvpBot = world.bots[values[2]]
	var state := WireCodec.decode_bot(packet, bot.combat.stats)
	var epoch := WireCodec.snapshot_epoch(match_view.get("match_id", ""), match_view.get("round", 0))
	if state.is_empty() or state.epoch != epoch or state.tick <= int(_last_snapshot_tick.get(bot.entity_id, -1)):
		return
	_last_snapshot_tick[bot.entity_id] = state.tick
	diagnostics.snapshots_received += 1
	bot.remote_state = state
	bot.server_tick = state.tick
	var first := not _remote_buffers.has(bot.entity_id)
	state["arrival"] = _time
	var buffer: Array = _remote_buffers.get(bot.entity_id, [])
	buffer.append(state)
	if buffer.size() > 12:
		buffer.pop_front()
	_remote_buffers[bot.entity_id] = buffer
	if bot.entity_id == local_entity:
		bot.combat.heat = state.heat
		bot.combat.overheated = state.overheated
		bot.combat.jump_cooldown = state.jump_cooldown
		while not _local_commands.is_empty() and _local_commands.front()[0] <= state.ack:
			_local_commands.pop_front()
		var pods := int(state.zones.drive_left > 0) + int(state.zones.drive_right > 0)
		bot.body.drive_multiplier = pods * 0.5
		bot.body.steering_multiplier = 0.0 if pods == 0 else (0.6 if pods == 1 else 1.0)
		var active: bool = match_view.get("phase") in ["active", "overtime"] and not state.eliminated
		# Inputs awaiting acknowledgement also include the uplink/queue delay.
		# External motion must advance only by snapshot age, not that whole backlog.
		# Snapshot pose precedes its labelled server step; correction applies on the
		# next Jolt step after receipt. Account for both physics callback boundaries.
		var steps := clampi(roundi(_client_tick + _server_tick_offset - state.tick) + 2, 0, 15) if active else 0
		var replay: Array = _local_commands.slice(maxi(0, _local_commands.size() - steps)) if steps > 0 else []
		while replay.size() < steps:
			var held := BotCommand.new()
			held.brake = true
			held.jump_cancel = true
			replay.append(replay.back() if not replay.is_empty() else WireCodec.command_to_array(held))
		var corrected := DriveModel.replay(state, replay, bot.body.model_config())
		bot.body.freeze = not active
		if bot.body.freeze or first:
			bot.visual_error = Vector3.ZERO
			bot.body.correction.clear()
			# First/reset snapshots establish a trusted pose without extrapolating
			# through static geometry outside the physics callback.
			bot.body.global_transform = state.pose
			bot.body.linear_velocity = state.velocity
			bot.body.angular_velocity = state.angular
		else:
			# Replay has no collision world. Sweep its extrapolation from the
			# authoritative pose when the body consumes it in the physics callback.
			corrected["replay_from"] = state.pose
			bot.body.correction = corrected
			bot.body.sleeping = false
		if _last_arrival > 0:
			interpolation_delay = lerpf(interpolation_delay, clampf(0.075 + absf(_time - _last_arrival - 0.05) * 2, 0.075, 0.15), 0.1)
		_last_arrival = _time
	else:
		bot.body.global_transform = state.pose
	if first:
		bot.presentation.global_transform = state.pose
	bot.body.collision_layer = 0 if state.eliminated else BaselineConfig.BOT_LAYER
	bot.body.collision_mask = 0 if state.eliminated else 3
	bot_updated.emit(bot.entity_id, bot.read_view())

## Effective match loadouts ride with every pickup update, so a client that
## missed nothing and a reconnecting client converge on the same bots.
func _pickup_state(with_events: bool) -> Dictionary:
	var loadouts := {}
	for id: int in world.bots:
		loadouts[id] = world.bots[id].loadout.duplicate(true)
	var state := world.pickups.snapshot()
	state.match_id = match_state.match_id
	state.loadouts = loadouts
	state.events = world.pickups.events.duplicate(true) if with_events else []
	return state

func _publish_pickups() -> void:
	var state := _pickup_state(true)
	pickup_view = state.duplicate(true)
	pickup_view.erase("loadouts")
	pickup_view.erase("events")
	for event: Dictionary in state.events:
		var public := event.duplicate(true)
		public.erase("loadout")
		pickup_collected.emit(public)
	pickups_changed.emit(pickup_view.duplicate(true))
	if connection_state == "practice":
		return
	var packet := var_to_bytes(state)
	for peer: int in peer_entities:
		if peer != 1 and _peer_can_receive(peer):
			_pickups.rpc_id(peer, packet)

## A refusal is private feedback for the bot's owner, not public match state.
func _deliver_refusals() -> void:
	for event: Dictionary in world.pickups.refusals:
		var id: int = event.entity
		var peer: int = players[id].peer if players.has(id) else 0
		if id == local_entity:
			pickup_refused.emit(event.duplicate())
		elif peer != 0 and peer != 1 and _peer_can_receive(peer):
			var packet := event.duplicate()
			packet.match_id = match_state.match_id
			_pickup_refused.rpc_id(peer, var_to_bytes(packet))

@rpc("authority", "call_remote", "reliable", 0)
func _pickup_refused(packet: PackedByteArray) -> void:
	if packet.size() > 1024:
		return
	var event: Variant = bytes_to_var(packet)
	if not event is Dictionary or event.get("match_id") != match_view.get("match_id") \
			or event.get("entity") != local_entity or event.get("reason") not in ["equipped", "incompatible"]:
		return
	event.erase("match_id")
	pickup_refused.emit(event)

@rpc("authority", "call_remote", "reliable", 0)
func _pickups(packet: PackedByteArray) -> void:
	if packet.size() <= MAX_CONTROL_STATE_BYTES:
		_accept_pickups(bytes_to_var(packet))

func _accept_pickups(data: Variant) -> void:
	if not data is Dictionary or not data.get("items") is Array or not data.get("loadouts") is Dictionary:
		return
	if data.get("match_id") != match_view.get("match_id"):
		return
	if pickup_view.get("match_id") == data.match_id and int(data.get("revision", -1)) <= int(pickup_view.get("revision", -1)):
		return
	for id: Variant in data.loadouts:
		if id is int and world.bots.has(id) and data.loadouts[id] is Dictionary:
			world.apply_loadout(id, data.loadouts[id])
	pickup_view = data.duplicate(true)
	pickup_view.erase("loadouts")
	pickup_view.erase("events")
	for event: Variant in data.get("events", []):
		if event is Dictionary:
			var public: Dictionary = event.duplicate(true)
			public.erase("loadout")
			pickup_collected.emit(public)
	pickups_changed.emit(pickup_view.duplicate(true))

func _process(_delta: float) -> void:
	if _reconnect_deadline > 0 and reconnect_seconds_remaining() <= 0.0:
		_fail("Reconnect window expired; match incomplete")
	if _server or not is_instance_valid(world):
		return
	var degraded := false
	for id: int in _remote_buffers:
		if not world.bots.has(id):
			continue
		var bot: MvpBot = world.bots[id]
		var buffer: Array = _remote_buffers[id]
		if buffer.is_empty():
			continue
		var latest: Dictionary = buffer.back()
		degraded = degraded or _time - float(latest.arrival) > 0.25
		if id == local_entity:
			bot.presentation.global_transform = bot.body.interpolated_transform()
			bot.presentation.global_position += bot.visual_error
			continue
		var target_tick: float = latest.tick + (_time - float(latest.arrival) - interpolation_delay) * 60
		var pose: Transform3D = latest.pose
		if target_tick < float(buffer.front().tick):
			pose = buffer.front().pose
		else:
			var interpolated := false
			for index: int in range(1, buffer.size()):
				var older: Dictionary = buffer[index - 1]
				var newer: Dictionary = buffer[index]
				if target_tick >= older.tick and target_tick <= newer.tick:
					pose = older.pose.interpolate_with(newer.pose, (target_tick - older.tick) / float(newer.tick - older.tick))
					interpolated = true
					break
			# Countdown/reset and finished-round poses may retain an old falling
			# velocity. Only a live combatant in an active round may extrapolate.
			var can_extrapolate: bool = match_view.get("phase") in ["active", "overtime"] and not latest.get("eliminated", true)
			if not interpolated and target_tick > latest.tick and can_extrapolate:
				pose.origin += latest.velocity * minf(0.1, (target_tick - latest.tick) / 60.0)
		bot.presentation.global_transform = pose
	diagnostics["degraded"] = degraded
	diagnostics["interpolation_ms"] = interpolation_delay * 1000

@rpc("authority", "call_remote", "unreliable", 2)
func _effect(packet: PackedByteArray) -> void:
	if packet.size() <= 1200:
		var event: Dictionary = bytes_to_var(packet)
		if event.get("match_id") == match_view.get("match_id") and event.get("round") == match_view.get("round"):
			var key := "%s:%s:%s" % [event.match_id, event.round, event.event_id]
			if not _effect_ids.has(key):
				_effect_ids[key] = true
				if _effect_ids.size() > 256:
					_effect_ids.erase(_effect_ids.keys().front())
				combat_event.emit(event)

# Clock synchronization must survive ENet's unreliable-packet throttling after
# a large baseline. At one bounded sample per second, reliable control is small.
@rpc("any_peer", "call_remote", "reliable", 0)
func _ping(stamp: int) -> void:
	if _server and _control_allowed(multiplayer.get_remote_sender_id()):
		_pong.rpc_id(multiplayer.get_remote_sender_id(), stamp, world.tick)

@rpc("authority", "call_remote", "reliable", 0)
func _pong(stamp: int, server_tick: int) -> void:
	if not _ping_ticks.has(stamp):
		return
	diagnostics.rtt_ms = maxf(0, Time.get_ticks_msec() - stamp)
	var elapsed := _client_tick - int(_ping_ticks[stamp])
	var offset := server_tick + elapsed * 0.5 - _client_tick
	if not _clock_ready:
		_clock_samples.clear()
	_clock_samples.append(Vector2(elapsed, offset))
	if _clock_samples.size() > 8:
		_clock_samples.pop_front()
	# Reliable retransmission can add a large delay to only one direction. Prefer
	# the least delayed recent round trip instead of smoothing that bias into the
	# clock for several seconds. The bounded window also retires old estimates.
	var best: Vector2 = _clock_samples.back()
	for sample: Vector2 in _clock_samples:
		if sample.x < best.x:
			best = sample
	_server_tick_offset = best.y
	_clock_ready = true
	_ping_ticks.erase(stamp)

func local_source() -> BotSource:
	return world.bots.get(local_entity) if is_instance_valid(world) else null

func bot_views() -> Array[BotView]:
	# A client bot exists before its first baseline; do not publish its defaults.
	var views: Array[BotView] = []
	if not is_instance_valid(world):
		return views
	for id: int in world.bots:
		if _server or _last_snapshot_tick.has(id):
			views.append(world.bots[id].read_view())
	return views

func audio_views() -> Array[Dictionary]:
	# Physical movement comes from authority, never from differentiated smoothing
	# or the client's predicted body. Position alone follows the displayed bot.
	var records: Array[Dictionary] = []
	if not is_instance_valid(world):
		return records
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		if not _server and not _last_snapshot_tick.has(id):
			continue
		var view := bot.read_view()
		var state: Dictionary
		if _server:
			var resetting := bot.body.reset_pose is Transform3D
			state = {
				"pose": bot.body.reset_pose if resetting else bot.body.global_transform,
				"velocity": Vector3.ZERO if resetting else bot.body.linear_velocity,
				"angular": Vector3.ZERO if resetting else bot.body.angular_velocity,
				"drive_input": 0.0 if resetting else bot.body._drive_input,
				"turn_input": 0.0 if resetting else bot.body._turn_input,
				"grounded": false if resetting else bot.body.grounded,
				"weapon": bot.combat.stats.weapon, "charge": bot.combat.charge,
				"eliminated": bot.combat.eliminated, "tick": bot.server_tick,
			}
		else:
			state = bot.remote_state
			if state.is_empty() or state.get("epoch") != WireCodec.snapshot_epoch(
				match_view.get("match_id", ""), match_view.get("round", 0)):
				continue
		records.append({"entity_id": id, "tick": state.tick,
			"position": view.pose.origin, "pose": state.pose,
			"velocity": state.velocity, "angular": state.angular,
			"drive_input": state.drive_input, "turn_input": state.turn_input,
			"grounded": state.grounded, "weapon": state.weapon,
			"charge": state.charge, "eliminated": state.eliminated,
			"age": 0.0 if _server else maxf(0.0, _time - float(state.arrival))})
	return records

func spectator_sources() -> Array[BotSource]:
	var sources: Array[BotSource] = []
	if not is_instance_valid(world) or not world.bots.has(local_entity):
		return sources
	var local: MvpBot = world.bots[local_entity]
	for id: int in world.bots:
		var bot: MvpBot = world.bots[id]
		if (match_mode == "ffa" or bot.team == local.team) and not bot.read_view().eliminated:
			sources.append(bot)
	return sources
