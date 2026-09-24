extends SceneTree
## The hosted worker turns a finished match into the result the matchmaking
## service records (#16 Step B), using the session's real results shape.
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func run() -> void:
	# Kept out of the tree: a worker in the tree boots and quits without an
	# allocation config.
	var worker: Node = load("res://scripts/services/hosted_worker.gd").new()
	var session := MvpSession.new()
	worker.session = session
	session.players = {
		1: {"peer":11, "team":0, "service_player_id":"a".repeat(32)},
		2: {"peer":12, "team":1, "service_player_id":"b".repeat(32)},
		3: {"peer":13, "team":1}}
	var reward := func(total: int) -> Dictionary: return {"pickups":0, "performance":total, "total":total}
	var results := {"match":{"match_id":"c".repeat(24), "mode":"1v1", "winner":1, "winners":[]},
		"content_hash":"x", "build":WireCodec.BUILD, "participants":{
			1:{"damage":12.5, "eliminations":0, "assists":0, "credits":reward.call(20)},
			2:{"damage":80.0, "eliminations":2, "assists":1, "credits":reward.call(55)},
			3:{"damage":0.0, "eliminations":0, "assists":0, "credits":reward.call(5)}}}
	var result: Dictionary = worker.match_result(results)
	check(result.get("match_id") == "c".repeat(24) and result.get("mode") == "teams" and result.get("build") == WireCodec.BUILD,
		"Result names the match, mode family and build")
	var players: Array = result.get("players", [])
	check(players.size() == 2, "Only players with a service identity are reported")
	for entry: Dictionary in players:
		var first: bool = entry.player == "a".repeat(32)
		check(entry.won == (not first) and entry.team == (0 if first else 1), "Winner follows the winning team")
		check(entry.credits == (20 if first else 55) and entry.damage == (12 if first else 80), "Credits are the reward total and stats are whole numbers")
	results.match.mode = "ffa"
	results.match.winners = [1]
	for entry: Dictionary in worker.match_result(results).players:
		check(entry.won == (entry.player == "a".repeat(32)), "Free-for-all winners come from the winners list")
	check(worker.match_result({}).is_empty(), "No results, nothing to record")
	worker.free()
	session.free()
	for failure: String in failures: push_error(failure)
	print("HOSTED WORKER RESULT PASS" if failures.is_empty() else "HOSTED WORKER RESULT FAIL")
	quit(0 if failures.is_empty() else 1)
