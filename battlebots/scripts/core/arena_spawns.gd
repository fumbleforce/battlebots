class_name ArenaSpawns
extends RefCounted
## Typed view of data/arena_spawns.json: every arena's team lanes, free-for-all
## ring and practice starts (#45). The arena's SpawnPoints markers are placed
## from here, so server and clients start bots at the same poses.
const SCRIPT := "res://scripts/core/arena_spawns.gd"
const PATH := "res://data/arena_spawns.json"
const LANES := 5
const FFA_STARTS := 8

static var _loaded: ArenaSpawns

## Match team size (as a String key) -> lanes used, 1-based.
var team_lanes: Dictionary = {}
## Arena id -> {"team": Array[Vector2], "ffa_radius": float}.
var arenas: Dictionary = {}
var practice_player_lane := 3
var practice_target_gap := 0.0
var practice_pilot_starts: Array[int] = []
## Practice Duel monowheel row (duel.monowheels).
var duel_monowheel_count := 0
var duel_monowheel_rows := 1
var duel_monowheel_gap := 0.0
var duel_monowheel_side := 0.0
## Arena id -> side fraction overriding duel_monowheel_side there.
var duel_monowheel_side_by_arena: Dictionary = {}

static func settings() -> ArenaSpawns:
	if _loaded == null:
		var problems: Array[String] = []
		_loaded = from_json(FileAccess.get_file_as_string(PATH), problems)
		for problem: String in problems:
			push_error("%s: %s" % [PATH, problem])
		assert(_loaded != null, "Invalid arena spawn configuration: " + PATH)
	return _loaded

static func from_json(source: String, problems: Array[String] = []) -> ArenaSpawns:
	var data: Variant = JSON.parse_string(source)
	if not data is Dictionary:
		problems.append("is not a JSON object")
		return null
	# By path, not class name: a checkout launched with a stale editor class
	# cache does not know this class yet (#74).
	var result: ArenaSpawns = load(SCRIPT).new()
	var lanes: Variant = data.get("team_lanes")
	if not lanes is Dictionary:
		problems.append("lacks the team_lanes object")
		return null
	for size: String in ["1", "2", "5"]:
		var list := _indices(lanes.get(size), LANES)
		if list.size() != int(size):
			problems.append("team_lanes.%s needs %s distinct lanes in 1..%d" % [size, size, LANES])
			return null
		result.team_lanes[size] = list
	var arenas: Variant = data.get("arenas")
	if not arenas is Dictionary:
		problems.append("lacks the arenas object")
		return null
	for arena_id: String in ArenaBounds.IDS:
		var entry: Variant = arenas.get(arena_id)
		if not entry is Dictionary or not entry.get("team") is Array or entry.team.size() != LANES:
			problems.append("arenas.%s needs %d team lanes" % [arena_id, LANES])
			return null
		var team: Array[Vector2] = []
		for point: Variant in entry.team:
			if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]):
				problems.append("arenas.%s.team holds a point that is not [x, z]" % arena_id)
				return null
			team.append(Vector2(float(point[0]), float(point[1])))
		var radius: Variant = entry.get("ffa_radius")
		if not _number(radius) or float(radius) <= 0.0:
			problems.append("arenas.%s lacks a positive ffa_radius" % arena_id)
			return null
		result.arenas[arena_id] = {"team":team, "ffa_radius":float(radius)}
	var practice: Variant = data.get("practice")
	if not practice is Dictionary:
		problems.append("lacks the practice object")
		return null
	var player := _indices([practice.get("player_lane")], LANES)
	var gap: Variant = practice.get("target_gap")
	var pilots := _indices(practice.get("pilot_starts"), FFA_STARTS)
	if player.size() != 1 or not _number(gap) or float(gap) < 0.0 or pilots.is_empty():
		problems.append("practice needs player_lane 1..%d, a non-negative target_gap and pilot_starts in 1..%d" % [LANES, FFA_STARTS])
		return null
	result.practice_player_lane = player[0]
	result.practice_target_gap = float(gap)
	result.practice_pilot_starts = pilots
	var duel: Variant = data.get("duel")
	var row: Variant = duel.get("monowheels") if duel is Dictionary else null
	if not row is Dictionary or not _number(row.get("count")) or int(row.count) < 0 or not _number(row.get("gap")) \
			or float(row.gap) < 0.0 or not _number(row.get("side_fraction")) or float(row.side_fraction) < 0.0 \
			or not _number(row.get("rows")) or int(row.rows) < 1:
		problems.append("duel.monowheels needs a non-negative count, gap and side_fraction and at least one row")
		return null
	result.duel_monowheel_count = int(row.count)
	result.duel_monowheel_rows = int(row.rows)
	result.duel_monowheel_gap = float(row.gap)
	result.duel_monowheel_side = float(row.side_fraction)
	var by_arena: Variant = row.get("side_fraction_by_arena", {})
	if not by_arena is Dictionary:
		problems.append("duel.monowheels.side_fraction_by_arena must be an object")
		return null
	for arena_id: String in by_arena:
		if arena_id not in ArenaBounds.IDS or not _number(by_arena[arena_id]) or float(by_arena[arena_id]) < 0.0:
			problems.append("duel.monowheels.side_fraction_by_arena.%s needs a known arena and a non-negative fraction" % arena_id)
			return null
		result.duel_monowheel_side_by_arena[arena_id] = float(by_arena[arena_id])
	return result

## Practice Duel monowheel block offset (fraction of the half-extent) on an arena.
func duel_monowheel_side_for(arena_id: String) -> float:
	return float(duel_monowheel_side_by_arena.get(arena_id, duel_monowheel_side))

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

## Distinct whole numbers in 1..limit, or an empty list when any entry is not.
static func _indices(value: Variant, limit: int) -> Array[int]:
	var list: Array[int] = []
	if not value is Array: return list
	for item: Variant in value:
		if not _number(item) or float(item) != floorf(float(item)) or int(item) < 1 or int(item) > limit or int(item) in list:
			return []
		list.append(int(item))
	return list

## Lane (1..5) of a team's slot for a match of team_size.
func lane(team_size: int, slot: int) -> int:
	var list: Array = team_lanes.get(str(team_size), team_lanes["5"])
	return list[clampi(slot, 0, list.size() - 1)]

## Authored start of a team lane, facing the arena centre.
func team_start(arena_id: String, team: int, lane_number: int) -> Transform3D:
	var point: Vector2 = arenas[_known(arena_id)].team[lane_number - 1]
	# Team 2 mirrors team 1 through the centre, so lanes pair up across it.
	return _facing_centre(point if team == 0 else -point)

## Free-for-all start 1..8 on the arena's ring, facing the centre.
func ffa_start(arena_id: String, number: int) -> Transform3D:
	var angle := TAU * float(number - 1) / float(FFA_STARTS)
	return _facing_centre(Vector2(sin(angle), cos(angle)) * float(arenas[_known(arena_id)].ffa_radius))

## Every team and free-for-all start of an arena, as floor points.
func points(arena_id: String) -> PackedVector2Array:
	var result := PackedVector2Array()
	for team: int in 2:
		for number: int in range(1, LANES + 1):
			var at := team_start(arena_id, team, number).origin
			result.append(Vector2(at.x, at.z))
	for number: int in range(1, FFA_STARTS + 1):
		var at := ffa_start(arena_id, number).origin
		result.append(Vector2(at.x, at.z))
	return result

## Moves the arena's Team%d_%d and FFA_%d markers onto this arena's starts.
func place_markers(arena: Node3D, arena_id: String) -> void:
	var markers := arena.get_node("SpawnPoints")
	for team: int in 2:
		for number: int in range(1, LANES + 1):
			_place(markers.get_node("Team%d_%d" % [team + 1, number]), team_start(arena_id, team, number))
	for number: int in range(1, FFA_STARTS + 1):
		_place(markers.get_node("FFA_%d" % number), ffa_start(arena_id, number))

static func _place(marker: Node3D, pose: Transform3D) -> void:
	# Keep the authored marker height; clear_spawn_pose sets the real floor.
	marker.transform = Transform3D(pose.basis, Vector3(pose.origin.x, marker.position.y, pose.origin.z))

func _known(arena_id: String) -> String:
	return arena_id if arenas.has(arena_id) else "foundry"

static func _facing_centre(point: Vector2) -> Transform3D:
	# -Z forward: yaw so the bot looks from point towards the origin.
	return Transform3D(Basis(Vector3.UP, atan2(point.x, point.y)), Vector3(point.x, 0.0, point.y))
