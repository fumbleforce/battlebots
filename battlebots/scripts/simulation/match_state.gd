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
var capacity := 4
var mode := "2v2"
var round_seconds := 180.0
var winners: Array[int] = []
var placements: Array[Dictionary] = []
var _elimination_ticks: Dictionary = {}
var _observed_tick := -1

func configure(player_count: int, match_mode: String = "teams") -> void:
	assert(match_mode in ["teams", "ffa"], "Unknown match mode")
	assert((match_mode == "ffa" and player_count >= 4 and player_count <= 8)
		or (match_mode == "teams" and player_count in [2, 4, 10]), "Unsupported match capacity")
	capacity = player_count
	mode = "ffa" if match_mode == "ffa" else ("5v5" if capacity == 10 else ("1v1" if capacity == 2 else "2v2"))
	round_seconds = 300.0 if mode == "ffa" else (240.0 if capacity == 10 else 180.0)

func begin(player_count: int = 4, match_mode: String = "teams") -> void:
	configure(player_count, match_mode)
	match_id = Crypto.new().generate_random_bytes(12).hex_encode()
	scores = [0, 0]
	rounds.clear()
	round_index = 1
	winner = -1
	winners.clear()
	placements.clear()
	_elimination_ticks.clear()
	_observed_tick = -1
	forfeits.clear()
	transition("loading", 30.0)

func transition(next: String, seconds: float) -> void:
	phase = next
	remaining = seconds
	event_id += 1

func advance(delta: float, combatants: Dictionary, teams: Dictionary, server_tick: int = -1) -> void:
	if phase == "lobby":
		return
	_observed_tick = maxi(_observed_tick, server_tick) if server_tick >= 0 else _observed_tick + 1
	if mode == "ffa" and phase != "results":
		# The caller has finished every combat/disconnect/forfeit decision for
		# this physics tick. Record the whole batch before checking survivors.
		for id: int in combatants:
			if combatants[id].eliminated and not _elimination_ticks.has(id):
				_elimination_ticks[id] = _observed_tick
	remaining = maxf(0, remaining - delta)
	if phase == "loading" and remaining <= 0:
		transition("lobby", 0)
	elif phase == "countdown" and remaining <= 0:
		transition("active", round_seconds)
	elif phase in ["active", "overtime"]:
		if mode == "ffa":
			_advance_ffa(combatants)
			return
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

func _advance_ffa(combatants: Dictionary) -> void:
	var survivors := 0
	for state: CombatState in combatants.values():
		survivors += int(not state.eliminated)
	if survivors > 1 and remaining > 0:
		return
	var ranked: Array[Dictionary] = []
	for id: int in combatants:
		var state: CombatState = combatants[id]
		var tick := int(_elimination_ticks.get(id, -1)) if state.eliminated else -1
		# Eliminated bots rank only by survival time; damage/health/kill counts
		# cannot separate simultaneous eliminations. Survivors outrank every wreck.
		var key := [0, tick, 0] if state.eliminated else [1,
			roundi(state.core / float(state.stats.core) * 1000), state.effective_damage]
		ranked.append({"entity_id":id, "key":key, "elimination_tick":tick})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		for criterion: int in range(3):
			if a.key[criterion] != b.key[criterion]:
				return a.key[criterion] > b.key[criterion]
		return a.entity_id < b.entity_id)
	placements.clear()
	winners.clear()
	var place := 1
	for index: int in range(ranked.size()):
		var entry: Dictionary = ranked[index]
		if index > 0 and entry.key != ranked[index - 1].key:
			place = index + 1
		placements.append({"entity_id":entry.entity_id, "place":place, "elimination_tick":entry.elimination_tick})
		if place == 1:
			winners.append(entry.entity_id)
	winner = winners[0] if winners.size() == 1 else -1
	rounds.append({"round":round_index, "winner":winner, "winners":winners.duplicate(), "placements":placements.duplicate(true)})
	transition("results", 20)

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
		"round":round_index, "scores":scores.duplicate(), "rounds":rounds.duplicate(true), "winner":winner,
		"mode":mode, "capacity":capacity, "winners":winners.duplicate(), "placements":placements.duplicate(true)}
