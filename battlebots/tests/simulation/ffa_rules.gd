extends Node
## Independent F6 rules checks. Explicit server ticks are authoritative, not order.
var failures := 0
var stats: Dictionary

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func roster(order: Array) -> Dictionary:
	var states := {}
	for id: int in order:
		states[id] = CombatState.new(stats)
	return states

func start(count := 4) -> MatchState:
	var match_state := MatchState.new()
	match_state.begin(count, "ffa")
	match_state.transition("countdown", 5)
	return match_state

func active(count := 4) -> MatchState:
	var match_state := start(count)
	match_state.advance(5, {}, {}, 0)
	return match_state

func eliminate(states: Dictionary, ids: Array) -> void:
	for id: int in ids:
		states[id].eliminate("test")

func ranking(match_state: MatchState) -> Array:
	var result := []
	for entry: Dictionary in match_state.snapshot().placements:
		result.append([entry.entity_id, entry.place, entry.elimination_tick])
	return result

func permutations(values: Array) -> Array:
	if values.is_empty():
		return [[]]
	var result := []
	for value: int in values:
		var rest := values.duplicate()
		rest.erase(value)
		for tail: Array in permutations(rest):
			result.append([value] + tail)
	return result

func run() -> void:
	var registry := ContentRegistry.new()
	stats = registry.validate(registry.starter()).stats
	check_timer_and_reset()
	check_fixed_tick_deadline()
	check_timeout_ordering()
	check_permutations()
	print("FFA RULES PASS" if failures == 0 else "FFA RULES FAIL")
	get_tree().quit(0 if failures == 0 else 1)

func check_fixed_tick_deadline() -> void:
	var states := roster([1, 2, 3, 4])
	var match_state := active()
	for tick: int in range(1, 18000):
		match_state.advance(1.0 / 60.0, states, {}, tick)
	check(match_state.phase == "active", "300-second FFA remains active through physics tick 17999")
	match_state.advance(1.0 / 60.0, states, {}, 18000)
	check(match_state.phase == "results", "300-second FFA ends on physics tick 18000")

func check_timer_and_reset() -> void:
	for count: int in range(4, 9):
		var ids := range(1, count + 1)
		var states := roster(ids)
		var match_state := start(count)
		check(match_state.snapshot().mode == "ffa" and match_state.snapshot().capacity == count, "FFA capacity %d is represented" % count)
		match_state.advance(4.5, states, {}, 50)
		check(match_state.phase == "countdown", "FFA cannot act before five-second countdown")
		match_state.advance(0.5, states, {}, 80)
		check(match_state.phase == "active" and match_state.remaining == 300, "FFA starts exactly 300 seconds")
		match_state.advance(299.5, states, {}, 100)
		check(match_state.phase == "active" and match_state.remaining == 0.5, "FFA remains active before exact deadline")
		match_state.advance(0.5, states, {}, 110)
		check(match_state.phase == "results" and match_state.rounds.size() == 1 and match_state.round_index == 1,
			"FFA timeout finishes one round without overtime/intermission")
		check(match_state.winner == -1 and match_state.winners == ids, "Complete timeout tie shares first place")
		for entry: Dictionary in match_state.placements:
			check(entry.place == 1 and entry.elimination_tick == -1, "Tied survivors share place 1 with no elimination tick")
		match_state.advance(20, states, {}, 130)
		check(match_state.phase == "lobby", "FFA results expiry returns to lobby")
		var prior_id := match_state.match_id
		match_state.begin(count, "ffa")
		check(match_state.match_id != prior_id and match_state.winners.is_empty() and match_state.placements.is_empty()
			and match_state.rounds.is_empty() and match_state.winner == -1 and match_state.scores == [0, 0], "Rematch clears result identity and ranks")
		# An old winner can now be an early elimination with a fresh lower tick.
		match_state.transition("active", 300)
		eliminate(states, [1])
		match_state.advance(0, states, {}, 2)
		eliminate(states, ids.slice(1))
		match_state.advance(0, states, {}, 3)
		check(match_state.placements.back().entity_id == 1 and match_state.placements.back().elimination_tick == 2,
			"Rematch clears elimination bookkeeping and server tick origin")
		match_state.begin()
		check(match_state.mode == "2v2" and match_state.capacity == 4 and match_state.round_seconds == 180
			and match_state.winners.is_empty() and match_state.placements.is_empty(), "Returning to default team mode clears FFA state")

func check_timeout_ordering() -> void:
	var states := roster([11, 22, 33, 44, 55, 66, 77, 88])
	var match_state := active(8)
	states[11].core = stats.core * 0.90004
	states[22].core = stats.core * 0.90001
	states[33].core = stats.core * 0.8994
	states[44].core = stats.core * 0.01
	states[11].effective_damage = 10
	states[22].effective_damage = 11
	states[33].effective_damage = 99999
	states[44].effective_damage = 999999
	states[11].eliminations = 999 # Kill count must not break a tie or outrank damage.
	eliminate(states, [55, 66])
	match_state.advance(0, states, {}, 20)
	eliminate(states, [77, 88])
	states[55].effective_damage = 999999
	states[77].effective_damage = 1
	states[88].effective_damage = 900
	match_state.advance(300, states, {}, 30)
	check(match_state.winner == 22 and match_state.winners == [22], "Rounded-health tie is broken by effective damage, not raw health/kills")
	check(ranking(match_state) == [[22, 1, -1], [11, 2, -1], [33, 3, -1], [44, 4, -1],
		[77, 5, 30], [88, 5, 30], [55, 7, 20], [66, 7, 20]],
		"Timeout ranks survivor/core/damage, then elimination tick with competition placements")
	var copy := match_state.snapshot()
	copy.placements[0].place = 99
	copy.winners.clear()
	copy.rounds[0].placements[0].place = 99
	check(match_state.placements[0].place == 1 and match_state.winners == [22]
		and match_state.rounds[0].placements[0].place == 1, "Snapshot consumers cannot mutate authoritative placements")
	states = roster([4, 2, 3, 1])
	match_state = active()
	states[1].core = stats.core * 0.90001
	states[2].core = stats.core * 0.90004
	states[3].core = stats.core * 0.8
	states[4].core = stats.core * 0.7
	states[1].effective_damage = 50
	states[2].effective_damage = 50
	states[2].eliminations = 999
	match_state.advance(300, states, {}, 200)
	check(match_state.winner == -1 and match_state.winners == [1, 2]
		and ranking(match_state) == [[1, 1, -1], [2, 1, -1], [3, 3, -1], [4, 4, -1]],
		"Partially tied timeout uses 1,1,3,4 competition ranking and ignores kill count")
	states = roster([1, 2, 3, 4])
	match_state = active()
	eliminate(states, [1])
	match_state.advance(0, states, {})
	eliminate(states, [2, 3])
	match_state.advance(0, states, {})
	check(ranking(match_state) == [[4, 1, -1], [2, 2, 2], [3, 2, 2], [1, 4, 1]],
		"Optional tick argument retains deterministic monotonic fallback for isolated callers")

func check_permutations() -> void:
	var orders := permutations([1, 2, 3, 4])
	for order: Array in orders:
		var states := roster(order)
		var match_state := active()
		eliminate(states, [1, 2])
		match_state.advance(0, states, {}, 17)
		# Re-observing already eliminated combatants must not move their tick.
		match_state.advance(0, states, {}, 22)
		eliminate(states, [3, 4])
		states[3].effective_damage = 1000
		states[4].eliminations = 50
		match_state.advance(0, states, {}, 29)
		check(match_state.winners == [3, 4] and match_state.winner == -1,
			"Final simultaneous eliminations share first regardless of roster order")
		check(ranking(match_state) == [[3, 1, 29], [4, 1, 29], [1, 3, 17], [2, 3, 17]],
			"Elimination batches retain original ticks and competition rank")
		states = roster(order)
		match_state = active()
		eliminate(states, [1, 2, 3, 4])
		match_state.advance(0, states, {}, 50)
		check(match_state.winners == [1, 2, 3, 4] and ranking(match_state) == [[1, 1, 50], [2, 1, 50], [3, 1, 50], [4, 1, 50]],
			"Same-tick total wipe shares first for all")
		# Every identity can be the last survivor; eliminate the others in every
		# permutation to exercise ranking independently of dictionary iteration.
		states = roster([4, 3, 2, 1])
		match_state = active()
		for index: int in range(3):
			eliminate(states, [order[index]])
			match_state.advance(0, states, {}, 100 + index)
		check(match_state.winner == order[3] and match_state.winners == [order[3]], "Last survivor wins without waiting for timeout")
		check(ranking(match_state) == [[order[3], 1, -1], [order[2], 2, 102], [order[1], 3, 101], [order[0], 4, 100]],
			"Later eliminations outrank earlier eliminations")
	print("FFA permutation coverage: %d roster orders, shared wipes and every elimination sequence" % orders.size())
