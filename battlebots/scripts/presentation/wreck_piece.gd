extends RigidBody3D
## One cosmetic piece of a broken bot or prop (#72). It collides with the
## world only: never bots, weapons or camera rays, so no client can disagree
## about gameplay because of where debris came to rest. Cut seams cool from
## glowing to charred. When the client's debris budget is full the oldest
## piece sinks into the ground and frees itself.
const GROUP := &"wreck_debris"

## Monotonic spawn order across all pieces: the budget evicts the lowest first.
static var _spawned := 0

var order := 0
var sinking := false
var _cut_meshes: Array[MeshInstance3D] = []
var _state := Vector4.ZERO
var _heat_seconds := 1.0
var _age := 0.0
var _sink_age := 0.0
var _sink_seconds := 1.0
var _sink_depth := 1.0

func _init() -> void:
	_spawned += 1
	order = _spawned
	collision_layer = 0
	collision_mask = BaselineConfig.WORLD_LAYER
	can_sleep = true
	continuous_cd = false

func _enter_tree() -> void:
	add_to_group(GROUP)

## Meshes carrying the cut shader, and their initial cut_state (x = heat).
func set_cut_meshes(meshes: Array[MeshInstance3D], state: Vector4, heat_seconds: float) -> void:
	_cut_meshes = meshes
	_state = state
	_heat_seconds = maxf(heat_seconds, 0.01)
	set_process(_state.x > 0.0 or sinking)

func _process(delta: float) -> void:
	if not is_finite(delta):
		return
	_age += delta
	if _state.x > 0.0:
		var heat := _state.x * clampf(1.0 - _age / _heat_seconds, 0.0, 1.0)
		for mesh: MeshInstance3D in _cut_meshes:
			if is_instance_valid(mesh):
				mesh.set_instance_shader_parameter("cut_state", Vector4(heat, _state.y, _state.z, _state.w))
		if heat <= 0.0:
			_state.x = 0.0
	if sinking:
		_sink_age += delta
		global_position.y -= _sink_depth * delta / _sink_seconds
		if _sink_age >= _sink_seconds:
			queue_free()
	if _state.x <= 0.0 and not sinking:
		set_process(false)

## Leaves the world: no more collisions, slides under the floor, then frees.
func sink(seconds: float, depth: float) -> void:
	if sinking:
		return
	sinking = true
	remove_from_group(GROUP)
	freeze = true
	collision_mask = 0
	_sink_seconds = maxf(seconds, 0.01)
	_sink_depth = maxf(depth, 0.1)
	set_process(true)

## Keeps at most max_pieces live pieces in this tree, sinking the oldest.
static func enforce_budget(tree: SceneTree, max_pieces: int, seconds: float) -> void:
	var live: Array = tree.get_nodes_in_group(GROUP).filter(func(piece: Node) -> bool: return not piece.sinking)
	if live.size() <= max_pieces:
		return
	live.sort_custom(func(a: Node, b: Node) -> bool: return a.order < b.order)
	for index: int in live.size() - max_pieces:
		var piece: Node = live[index]
		piece.sink(seconds, piece.depth_hint())

## How far a piece must sink to vanish: its own reach.
func depth_hint() -> float:
	var reach := 1.0
	for child: Node in get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			for point: Vector3 in child.shape.points:
				reach = maxf(reach, (point - center_of_mass).length())
	return reach * 2.0
