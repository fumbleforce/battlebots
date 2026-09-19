class_name MatchState
extends RefCounted
## All eliminations are applied before advance() is called once per server tick.
var phase := "lobby"
var remaining := 0.0
var round_index := 0
var scores := [0, 0]
var rounds: Array = []
var match_id := ""
var event_id := 0
var winner := -1
var forfeits: Dictionary = {}

func begin() -> void:
	match_id = Crypto.new().generate_random_bytes(12).hex_encode()
	scores = [0, 0]
	rounds.clear()
	round_index = 1
	winner = -1
	forfeits.clear()
	transition("loading", 30.0)

func transition(next: String, seconds: float) -> void:
	phase = next
	remaining = seconds
	event_id += 1

func advance(delta: float, combatants: Dictionary, teams: Dictionary) -> void:
	if phase == "lobby":
		return
	remaining = maxf(0, remaining - delta)
	if phase == "loading" and remaining <= 0:
		transition("lobby", 0)
	elif phase == "countdown" and remaining <= 0:
		transition("active", 180)
	elif phase in ["active", "overtime"]:
		var survivors := [0, 0]
		for id: int in combatants:
			if not combatants[id].eliminated:
				survivors[teams[id]] += 1
		if survivors[0] == 0 or survivors[1] == 0:
			resolve(-1 if survivors[0] == survivors[1] else (0 if survivors[0] > 0 else 1))
		elif remaining <= 0:
			var judged := judge(combatants, teams)
			if judged == -1 and phase == "active":
				transition("overtime", 30)
			else:
				resolve(judged)
	elif phase == "intermission" and remaining <= 0:
		round_index += 1
		forfeits.clear()
		transition("countdown", 5)
	elif phase == "results" and remaining <= 0:
		transition("lobby", 0)

func judge(combatants: Dictionary, teams: Dictionary) -> int:
	var totals := [[0, 0, 0], [0, 0, 0]]
	for id: int in combatants:
		var state: CombatState = combatants[id]
		var team: int = teams[id]
		totals[team][2] += state.effective_damage
		if not state.eliminated:
			totals[team][0] += 1
			totals[team][1] += roundi(state.core / float(state.stats.core) * 1000)
	for criterion: int in range(3):
		if totals[0][criterion] != totals[1][criterion]:
			return 0 if totals[0][criterion] > totals[1][criterion] else 1
	return -1

func resolve(round_winner: int) -> void:
	if round_winner >= 0:
		scores[round_winner] += 1
	rounds.append({"round":round_index, "winner":round_winner})
	if scores.max() >= 2 or round_index >= 5:
		winner = 0 if scores[0] >= 2 else (1 if scores[1] >= 2 else -1)
		transition("results", 20)
	else:
		transition("intermission", 15)

func snapshot() -> Dictionary:
	return {"match_id":match_id, "event_id":event_id, "phase":phase, "remaining":remaining,
		"round":round_index, "scores":scores.duplicate(), "rounds":rounds.duplicate(true), "winner":winner}
