class_name HammerSlamDetector
extends Node
## Presentation only. Spots a hammer strike that lands on the arena instead of a
## bot and asks the impact visuals for a ground shockwave. Head placement mirrors
## the end of the authority's swing (combat_world.gd); bot hits stay event-driven,
## so this never creates damage, events or network traffic.
const MIN_GAP := 0.5
var loadout: Dictionary = {}
var size := Vector3.ONE
var exclude: Array[RID] = []
var source_id := 0
var _primed := false
var _last_state := ""
var _last_cooldown := 0.0
var _since := MIN_GAP

func configure(bot_loadout: Dictionary, hull_size: Vector3, own_body: RID, entity_id := 0) -> void:
	source_id = entity_id
	loadout = bot_loadout
	size = hull_size
	exclude = [own_body]

## Snapshots can skip the single-tick "strike" state, so a fresh cooldown also counts.
static func strike_edge(previous_state: String, previous_cooldown: float, state: String, cooldown: float) -> bool:
	if state == "strike": return previous_state != "strike"
	return previous_state != "strike" and cooldown > previous_cooldown + 0.5

## Body-local head centre at the end of the swing and its half height.
static func head_end(bot_loadout: Dictionary, hull_size: Vector3) -> Dictionary:
	var linear := BotScale.from_size(hull_size)
	if ScorpionGeometry.enabled(bot_loadout):
		return {"center":ScorpionGeometry.hammer_transform(hull_size, 1.0).origin,
			"half":ScorpionGeometry.HEAD_SIZE.y * 0.5 * linear}
	if SawbladeConfig.enabled(bot_loadout) and not AtlasGeometry.enabled(bot_loadout):
		return {"center":SawbladeGeometry.hammer_center(hull_size, SawbladeGeometry.HAMMER_SWING),
			"half":0.405 * SawbladeGeometry.scale_for(hull_size).y * 0.5}
	var pivot := Vector3(0, hull_size.y * 0.5, -hull_size.z * 0.5 + 0.15 * linear)
	return {"center":pivot + Basis(Vector3.RIGHT, -PI / 6.0) * Vector3(0, 0, -1.2 * linear),
		"half":0.2 * linear}

func observe(view: BotView, delta: float) -> void:
	if view == null or not is_finite(delta): return
	_since += maxf(delta, 0.0)
	var state := str(view.weapon_state)
	var edge := _primed and strike_edge(_last_state, _last_cooldown, state, view.weapon_cooldown)
	_primed = true
	_last_state = state
	_last_cooldown = view.weapon_cooldown
	if not edge or view.eliminated or _since < MIN_GAP or not is_inside_tree(): return
	_since = 0.0
	var landing := find_landing(view.pose)
	if not landing.is_empty():
		get_tree().call_group(&"combat_impact_visuals", &"spawn_ground_slam", landing.position, landing.normal, 0.8, source_id)

## World surface under the swung head, or empty when a bot (or nothing) is there.
func find_landing(pose: Transform3D) -> Dictionary:
	var head := head_end(loadout, size)
	var center: Vector3 = pose * (head.center as Vector3)
	var half: float = head.half
	var reach := 0.5 * BotScale.from_size(size)
	# Start well above the head: a ray beginning inside a victim would skip it.
	var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * (half + reach * 4.0), center - Vector3.UP * (half + reach),
		BaselineConfig.WORLD_LAYER | BaselineConfig.BOT_LAYER, exclude)
	var space := get_viewport().world_3d.direct_space_state
	var hit := space.intersect_ray(ray)
	if hit.is_empty(): return {}
	var collider := hit.collider as CollisionObject3D
	if collider == null or collider.collision_layer & BaselineConfig.BOT_LAYER: return {}
	return {"position":hit.position, "normal":hit.normal}
