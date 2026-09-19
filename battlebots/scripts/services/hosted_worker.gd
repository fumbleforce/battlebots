class_name HostedWorker
extends Node
## Dedicated allocation worker. Supervisor-owned configuration is the authority;
## losing its bounded lease or receiving malformed/revoked config ends the worker.
var config_path := ""
var status_path := ""
var policy := HostedAdmission.new()
@onready var session: MvpSession = $Session
var last_poll := 0.0
var stopping := false
var started := false

func _ready() -> void:
	boot.call_deferred()

func boot() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--allocation-config="):
			config_path = argument.trim_prefix("--allocation-config=")
	if config_path.is_empty() or not config_path.is_absolute_path():
		printerr("Hosted worker requires an absolute allocation config path")
		get_tree().quit(1)
		return
	status_path = config_path.get_base_dir().path_join("status.json")
	if not read_config():
		stop_worker("Allocation config invalid or lease expired")
		return
	session.hosted_admission = policy
	session.hosted_config_refresh = refresh_for_admission
	var error := session.host(int(policy.config.port), false, int(policy.config.capacity), policy.config.mode, policy.config.bind_address)
	if error != OK:
		stop_worker("Unable to bind allocated UDP worker: %d" % error)
		return
	if not write_status():
		stop_worker("Unable to publish worker readiness")
		return
	last_poll = Time.get_ticks_msec() / 1000.0
	started = true
	print("HOSTED SERVER READY allocation=", policy.config.allocation_id, " port=", policy.config.port)

func _process(_delta: float) -> void:
	if stopping or not started:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_poll < 1.0:
		return
	last_poll = now
	if not read_config():
		stop_worker("Allocation config invalid, revoked or lease expired")
		return
	session.refresh_hosted_admission()
	if not write_status():
		stop_worker("Worker status publication failed")
	return

func read_config() -> bool:
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return policy.configure(parsed, Time.get_unix_time_from_system(), ContentRegistry.new().content_hash) == OK

func refresh_for_admission() -> bool:
	# The supervisor writes a newly issued ticket immediately before returning
	# it to the client. Do not let the one-second status poll delay admission.
	if not read_config():
		stop_worker("Allocation changed to an invalid, revoked or expired config")
		return false
	session.refresh_hosted_admission()
	return true

func write_status() -> bool:
	var connected: Array[String] = []
	var phase := "lobby"
	if is_instance_valid(session):
		phase = session.match_state.phase
		for player: Dictionary in session.players.values():
			if player.peer != 0:
				connected.append(player.service_player_id)
	var status := {"allocation_id":policy.config.get("allocation_id", ""), "ready":not stopping,
		"state":"draining" if stopping else ("ready" if phase == "lobby" else "active"),
		"phase":phase, "connected_players":connected, "updated_at":Time.get_unix_time_from_system()}
	var temporary := status_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(status))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(temporary, status_path) == OK

func stop_worker(reason: String) -> void:
	if stopping:
		return
	stopping = true
	printerr(reason)
	if not status_path.is_empty():
		write_status()
	if is_instance_valid(session):
		session.leave()
	get_tree().quit(1)
