class_name LobbyCoordinator
extends Node
## Public session requests only. The application retains scene/session ownership.
signal return_requested
signal resume_requested
signal settings_requested
const CONFIRMATION_SECONDS := 3.0
var session: MvpSession
var panel: LobbyPanel
var pending_kind := ""
var notice := ""
var _expected: Variant
var _pending_since := 0
var _endpoint := ""
var _refresh_elapsed := 0.0
var _pending_lobby_seen := false

func bind(value: MvpSession, view: LobbyPanel) -> void:
	_disconnect()
	session = value
	panel = view
	pending_kind = ""
	notice = ""
	_endpoint = ""
	if is_instance_valid(session):
		session.lobby_changed.connect(_on_lobby_changed)
		session.match_changed.connect(_on_match_changed)
		session.session_event.connect(_on_session_event)
	if is_instance_valid(panel):
		for entry: Array in _panel_connections():
			panel.connect(entry[0], entry[1])
	refresh()

func _panel_connections() -> Array:
	return [[&"host_requested", request_host], [&"join_requested", request_join],
		[&"leave_requested", request_leave], [&"ready_requested", request_ready_state],
		[&"team_requested", request_team], [&"loadout_requested", request_loadout],
		[&"return_requested", _return], [&"resume_requested", _resume],
		[&"settings_requested", _settings]]

func _disconnect() -> void:
	if is_instance_valid(session):
		if session.lobby_changed.is_connected(_on_lobby_changed):
			session.lobby_changed.disconnect(_on_lobby_changed)
		if session.match_changed.is_connected(_on_match_changed):
			session.match_changed.disconnect(_on_match_changed)
		if session.session_event.is_connected(_on_session_event):
			session.session_event.disconnect(_on_session_event)
	if is_instance_valid(panel):
		for entry: Array in _panel_connections():
			if panel.is_connected(entry[0], entry[1]):
				panel.disconnect(entry[0], entry[1])

func _exit_tree() -> void:
	_disconnect()

func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.1:
		_refresh_elapsed = 0.0
		refresh()

func _phase() -> String:
	return str(session.match_view.get("phase", session.lobby_view.get("phase", "lobby")))

func _local_slot() -> Dictionary:
	var slots: Variant = session.lobby_view.get("slots", [])
	if slots is Array:
		for slot: Variant in slots:
			if slot is Dictionary and slot.get("entity_id") == session.local_entity:
				return slot
	return {}

func refresh() -> void:
	if not is_instance_valid(panel):
		return
	if not is_instance_valid(session):
		pending_kind = ""
		panel.render("unavailable", {}, 0, {"notice": "Session unavailable.", "pending": true})
		return
	_acknowledge()
	if not pending_kind.is_empty() and Time.get_ticks_msec() - _pending_since >= CONFIRMATION_SECONDS * 1000.0:
		pending_kind = ""
		notice = "No change confirmed by the server. Check the lobby and try again."
	var lobby := session.lobby_view.duplicate(true)
	lobby["phase"] = _phase()
	panel.render(session.connection_state, lobby, session.local_entity, {
		"notice": notice, "pending": not pending_kind.is_empty(), "endpoint": _endpoint,
		"can_resume": session.local_source() != null and _phase() in ["active", "overtime", "intermission"],
		"local_rtt": session.diagnostics.get("rtt_ms") if session.connection_state == "connected" else null,
		"build": WireCodec.BUILD,
	})

func _begin(kind: String, expected: Variant) -> void:
	pending_kind = kind
	_expected = expected
	_pending_since = Time.get_ticks_msec()
	_pending_lobby_seen = false
	notice = "Waiting for server confirmation…"
	refresh()

func _acknowledge() -> void:
	if pending_kind.is_empty():
		return
	if session.connection_state not in ["hosting", "connected"]:
		pending_kind = ""
		return
	var slot := _local_slot()
	var confirmed: bool = _loadout_matches(slot.get("loadout"), _expected) if pending_kind == "loadout" else slot.get(pending_kind) == _expected
	if confirmed and _pending_lobby_seen:
		notice = {"ready": "Readiness confirmed.", "team": "Team confirmed; readiness reset.",
			"loadout": "Build confirmed; readiness reset."}.get(pending_kind, "Change confirmed.")
		pending_kind = ""
	elif _phase() != "lobby":
		pending_kind = ""
		notice = "The match has started. Lobby changes are locked."

func _loadout_matches(actual: Variant, expected: Variant) -> bool:
	if not actual is Dictionary or not expected is Dictionary or not session.registry.validate(actual).valid:
		return false
	# JSON transports numbers as floats; compare validated schema numerically.
	return actual.schema_version == expected.schema_version and actual.name == expected.name \
		and actual.content_hash == expected.content_hash and actual.parts == expected.parts \
		and actual.cosmetics == expected.cosmetics

func _offline_allowed(port: int) -> bool:
	if not is_instance_valid(session):
		return false
	if session.connection_state != "offline":
		notice = "Leave the current session before hosting or joining another."
		refresh()
		return false
	if port < 1 or port > 65535:
		notice = "UDP port must be between 1 and 65535."
		refresh()
		return false
	return true

func request_host(port: int, player_count: int) -> void:
	if not _offline_allowed(port):
		return
	if player_count not in [2, 4]:
		notice = "Choose 2 players (1v1) or 4 players (2v2)."
		refresh()
		return
	var error := session.host(port, true, player_count)
	if error != OK:
		notice = "Could not host: %s" % error_string(error)
	else:
		var addresses: PackedStringArray = []
		for address: String in IP.get_local_addresses():
			if not address.contains(":") and not address.begins_with("127.") and not address.begins_with("169.254."):
				addresses.append(address)
		_endpoint = "Host address: %s  •  UDP %d" % [", ".join(addresses) if not addresses.is_empty() else "check this computer's LAN address", port]
		notice = "Share a LAN address and port with your teammate."
	refresh()

func request_join(address: String, port: int) -> void:
	if not _offline_allowed(port):
		return
	var target := address.strip_edges()
	if target.is_empty() or target.length() > 253 or target.contains(" ") or target.contains("\n") or target.contains("\t"):
		notice = "Enter the host's IP address or hostname."
		refresh()
		return
	_endpoint = "Joining %s  •  UDP %d" % [target, port]
	notice = "Connecting…"
	var error := session.join(target, port)
	if error != OK:
		notice = "Could not join: %s" % error_string(error)
	refresh()

func request_leave() -> void:
	if is_instance_valid(session):
		pending_kind = ""
		session.leave()
	refresh()

func _edit_allowed() -> bool:
	if not is_instance_valid(session):
		return false
	if not pending_kind.is_empty():
		return false
	if session.connection_state not in ["hosting", "connected"] or _phase() != "lobby" or _local_slot().get("connected") != true:
		notice = "Lobby changes are unavailable in this phase."
		refresh()
		return false
	return true

func request_ready_state(value: bool) -> void:
	if not _edit_allowed():
		return
	var slot := _local_slot()
	if value:
		var validation := session.registry.validate(slot.get("loadout", {}))
		if not validation.valid:
			notice = "Build invalid: %s" % "; ".join(validation.reasons)
			refresh()
			return
	_begin("ready", value)
	session.set_ready(value)
	refresh()

func request_team(team: int) -> void:
	if not _edit_allowed():
		return
	if team not in [0, 1]:
		notice = "Choose Team A or Team B."
		refresh()
		return
	_begin("team", team)
	session.set_team(team)
	refresh()

func request_loadout(draft: Dictionary) -> void:
	if not _edit_allowed():
		return
	var validation := session.registry.validate(draft)
	if not validation.valid:
		notice = "Build invalid: %s" % "; ".join(validation.reasons)
		refresh()
		return
	_begin("loadout", validation.loadout)
	session.set_loadout(validation.loadout)
	refresh()

func _on_lobby_changed(_view: Dictionary) -> void:
	_pending_lobby_seen = not pending_kind.is_empty()
	refresh()

func _on_match_changed(_view: Dictionary) -> void:
	refresh()

func _on_session_event(kind: String, details: Dictionary) -> void:
	if kind == "error":
		notice = str(details.get("message", "Session request failed."))
		pending_kind = ""
	elif kind == "left":
		notice = "Left the session."
		_endpoint = ""
		pending_kind = ""
	elif kind == "joined":
		notice = "Connected. Choose your team and build, then ready up."
	refresh()

func _return() -> void:
	return_requested.emit()

func _resume() -> void:
	if is_instance_valid(session) and session.local_source() != null and _phase() in ["active", "overtime", "intermission"]:
		resume_requested.emit()

func _settings() -> void:
	settings_requested.emit()
