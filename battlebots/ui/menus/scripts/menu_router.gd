extends Node
## Navigation adapter for the supplied menu scenes. The game root owns the session.
signal match_requested(setup: Dictionary)
const SCREENS := {
	"main":"res://ui/menus/screens/main_menu.tscn",
	"mode_select":"res://ui/menus/screens/mode_select.tscn",
	"garage":"res://ui/menus/screens/garage.tscn",
	"arena_select":"res://ui/menus/screens/arena_select.tscn",
	"lobby":"res://ui/menus/screens/lobby.tscn",
	"loading":"res://ui/menus/screens/loading.tscn",
	"customize":"res://ui/menus/screens/customize.tscn",
	"shop":"res://ui/menus/screens/upgrade_shop.tscn",
}
var match_setup := {"mode":"team", "bot":0, "arena":0}
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

func goto(screen: String, remember := true) -> void:
	if not SCREENS.has(screen) or not is_instance_valid(host):
		return
	if remember and screen != current:
		_history.append(current)
	if screen == "mode_select":
		in_match_flow = true
	elif screen == "main":
		in_match_flow = false
		_history.clear()
	current = screen
	host.show_screen.call_deferred(screen)

func back() -> void:
	if current in ["lobby", "loading"] and is_instance_valid(session) and session.connection_state != "offline":
		session.leave()
	var target := _history.pop_back() as String if not _history.is_empty() else "main"
	goto(target, false)

func start_practice() -> void:
	if is_instance_valid(host):
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
