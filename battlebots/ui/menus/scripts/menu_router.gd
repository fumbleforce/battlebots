extends Node
## Navigation adapter for the supplied menu scenes. The game root owns the session.
signal match_requested(setup: Dictionary)
const SCREENS := {
	"main":"res://ui/menus/screens/main_menu.tscn",
	"online":"res://ui/menus/screens/online.tscn",
	"mode_select":"res://ui/menus/screens/mode_select.tscn",
	"garage":"res://ui/menus/screens/garage.tscn",
	"arena_select":"res://ui/menus/screens/arena_select.tscn",
	"lobby":"res://ui/menus/screens/lobby.tscn",
	"loading":"res://ui/menus/screens/loading.tscn",
	"customize":"res://ui/menus/screens/customize.tscn",
}
var match_setup := {"mode":"duel", "bot":0, "arena":0, "capacity":8}
var lobby_intent := "host"
var arena_intent := "select"
var in_match_flow := false
var current := "main"
var session: MvpSession
var session_notice := ""
var host: Node
var _history: Array[String] = []

func bind(value: Node, active_session: MvpSession) -> void:
	host = value
	session = active_session
	session_notice = ""
	_history.clear()
	current = "main"
	in_match_flow = false
	lobby_intent = "host"
	arena_intent = "select"

func open_practice() -> void:
	arena_intent = "practice"
	_history.clear()
	current = "main"
	goto("arena_select")

func open_host() -> void:
	lobby_intent = "host"
	_history.clear()
	current = "main"
	goto("mode_select")

func open_online() -> void:
	lobby_intent = "online"
	_history.clear()
	current = "main"
	goto("online")

func open_join() -> void:
	lobby_intent = "join"
	_history.clear()
	current = "main"
	goto("lobby")

func goto(screen: String, remember := true) -> void:
	if not SCREENS.has(screen) or not is_instance_valid(host):
		return
	if screen != "arena_select":
		arena_intent = "select"
	if screen in _history:
		_history.resize(_history.find(screen))
	elif remember and screen != current:
		_history.append(current)
	if screen == "mode_select":
		in_match_flow = true
		lobby_intent = "host"
	elif screen == "main":
		in_match_flow = false
		_history.clear()
	current = screen
	host.show_screen.call_deferred(screen)

func back() -> void:
	if current == "online":
		host.cancel_online()
		goto("main", false)
		return
	if current in ["lobby", "loading"]:
		if lobby_intent == "online":
			host.cancel_online()
		if is_instance_valid(session) and session.connection_state != "offline":
			session.leave()
		goto("main", false)
		return
	var target := _history.pop_back() as String if not _history.is_empty() else "main"
	goto(target, false)

func start_practice() -> void:
	if is_instance_valid(host):
		if host.has_method("load_practice"):
			host.load_practice()
		else:
			host.start_practice()

func begin_gameplay() -> void:
	if is_instance_valid(host):
		host.resume_gameplay()

func open_settings() -> void:
	if is_instance_valid(host):
		host.open_settings()

func start_match(_packed: PackedScene = null) -> void:
	# Compatibility hook: only the real session can start a match.
	if is_instance_valid(session) and session.connection_state == "practice":
		begin_gameplay()
