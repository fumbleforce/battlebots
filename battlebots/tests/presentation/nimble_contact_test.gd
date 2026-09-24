extends Node3D
## Native check that the four nimble bots' running gear meets the ground (#75):
## in ordinary Foundry practice, driven only by normal commands, the lowest
## vertex of each foot, tyre, pad or skate wheel is measured against the floor
## under it every frame. While the hull is supported, some contact part must
## touch the floor (no hovering), and a part touching the floor must not skid
## across it: the material point in contact must stay put from one frame to the
## next (no sliding; rolling wheels pass because their contact point is still).
## Practice NPCs are removed so they cannot collide with the bot under test.
## Runs headless: MvpBot only builds NimbleVisual on a display, so the test
## assembles one on the bot's presentation node and feeds it the bot's view.
## A contact part closer than this to the floor touches it (game metres).
const CONTACT_GAP := 0.08
## Average gap between the supported hull's lowest contact part and the floor.
const MAX_MEAN_GAP := 0.05
## Share of supported frames on which nothing touches the floor.
const MAX_HOVER_SHARE := 0.1
## Average speed (m/s) of material points in floor contact, and its 95th
## percentile, over a course reaching 20-25 m/s. Planted feet and pads measure
## ~0; the residual is a tyre carving at speed (a few per cent of its speed:
## lug polygons, steering about a tilted shin) and a pad's launch frame.
## Before #75: Strider 4.0 / 20, Pogo 9.3 / 21, Skater 1.7 / 5.7 m/s.
const MAX_MEAN_SLIP := 0.75
const MAX_P95_SLIP := 2.0
## Frames with a larger pose jump than this are respawns, not motion.
const SNAP_DISTANCE := 3.0
## Scripted course: [label, frames, throttle, steering, jump].
const COURSE := [
	["idle", 60, 0.0, 0.0, false],
	["run", 180, 1.0, 0.0, false],
	["carve", 120, 1.0, 0.7, false],
	["pivot", 90, 0.0, 1.0, false],
	["stop", 90, 0.0, 0.0, false],
	["reverse", 60, -1.0, 0.0, false],
	["charge", 60, 0.0, 0.0, true],
	["land", 90, 0.0, 0.0, false],
]
var session: MvpSession
var visual: NimbleVisual
var sequence := 0
var command_throttle := 0.0
var command_steering := 0.0
var command_jump := false
var failures := 0
var bot: MvpBot
var contacts: Array[Dictionary] = []
var stats := {}
var measuring := false
var phase_label := ""
var only := ""

func _ready() -> void:
	process_priority = 1000
	only = OS.get_environment("NIMBLE_ONLY")
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		failures += 1
		push_error(message)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(session) or session.local_source() == null: return
	var command := BotCommand.new()
	command.sequence = sequence
	sequence += 1
	command.throttle = command_throttle
	command.steering = command_steering
	command.jump_held = command_jump
	command.brake = command_throttle == 0.0 and command_steering == 0.0 and not command_jump
	session.submit_local(command)

func run() -> void:
	var registry := ContentRegistry.new()
	for draft: Dictionary in registry.nimble():
		if only.is_empty() or str(draft.parts.chassis) == only:
			await measure(draft)
	print("NIMBLE CONTACT %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)

func measure(draft: Dictionary) -> void:
	session = MvpSession.new()
	session.pickups_enabled = false
	add_child(session)
	check(session.practice(draft, "foundry") == OK, "Practice starts with " + draft.name)
	session.practice_director = null
	for frame: int in 600:
		await get_tree().process_frame
		if session.match_view.get("phase") in ["active", "overtime"] and session.local_source() != null: break
	bot = session.local_source() as MvpBot
	for id: int in session.world.bots.keys():
		if id != session.local_entity:
			session.world.bots[id].queue_free()
			session.world.bots.erase(id)
	visual = bot.nimble_visual
	if visual == null:
		visual = NimbleVisual.new()
		bot.presentation.add_child(visual)
		visual.exclusions = [bot.body.get_rid()]
		visual.assemble(bot.loadout, bot.combat.stats.size)
	_collect_contacts()
	stats = {"supported":0, "hover":0, "gap_sum":0.0, "slips":[], "gaps":[]}
	var by_phase := {}
	for step: Array in COURSE:
		phase_label = step[0]
		command_throttle = step[2]
		command_steering = step[3]
		command_jump = step[4]
		var before := {"supported":stats.supported, "hover":stats.hover, "gap_sum":stats.gap_sum, "slips":stats.slips.size(), "gaps":stats.gaps.size()}
		measuring = true
		for frame: int in int(step[1]):
			await get_tree().process_frame
		var slips: Array = stats.slips.slice(before.slips)
		var supported: int = stats.supported - before.supported
		var gaps: Array = stats.gaps.slice(before.gaps)
		by_phase[phase_label] = "supported %d hover %d gap mean %.3f min %.3f max %.3f slip mean %.2f max %.2f" % [supported,
			stats.hover - before.hover, (stats.gap_sum - before.gap_sum) / maxf(1, supported), _min(gaps), _max(gaps), _mean(slips), _max(slips)]
	measuring = false
	var label: String = draft.name
	for key: String in by_phase: print("  %s %-8s %s" % [label, key, by_phase[key]])
	var supported_frames: int = maxi(1, stats.supported)
	var slips: Array = stats.slips
	slips.sort()
	var p95: float = slips[int(slips.size() * 0.95)] if not slips.is_empty() else 0.0
	check(float(stats.gap_sum) / supported_frames <= MAX_MEAN_GAP, "%s mean ground gap %.3f m <= %.2f" % [label, stats.gap_sum / supported_frames, MAX_MEAN_GAP])
	check(float(stats.hover) / supported_frames <= MAX_HOVER_SHARE, "%s hovers on %d of %d supported frames" % [label, stats.hover, stats.supported])
	check(_mean(slips) <= MAX_MEAN_SLIP, "%s mean contact slip %.2f m/s <= %.2f" % [label, _mean(slips), MAX_MEAN_SLIP])
	check(p95 <= MAX_P95_SLIP, "%s 95th percentile contact slip %.2f m/s <= %.2f" % [label, p95, MAX_P95_SLIP])
	command_throttle = 0.0
	command_steering = 0.0
	command_jump = false
	session.leave()
	session.queue_free()
	contacts.clear()
	for frame: int in 5: await get_tree().process_frame

func _mean(values: Array) -> float:
	var total := 0.0
	for value: float in values: total += value
	return total / maxf(1, values.size())

func _min(values: Array) -> float:
	var low := INF
	for value: float in values: low = minf(low, value)
	return low

func _max(values: Array) -> float:
	var top := 0.0
	for value: float in values: top = maxf(top, value)
	return top

## Every foot, tyre, pad hub and skate wheel, with its mesh vertices.
func _collect_contacts() -> void:
	for key: String in visual.nodes:
		if not (key.begins_with("Foot") or key.begins_with("Wheel") or key == "Hub"): continue
		# The assembly nodes only (their mesh children are named after them).
		if visual.nodes[key] is MeshInstance3D: continue
		var meshes: Array = []
		for mesh: MeshInstance3D in visual._meshes(visual.nodes[key]):
			var unique := {}
			for vertex: Vector3 in mesh.mesh.get_faces(): unique[vertex] = true
			meshes.append({"node":mesh, "vertices":PackedVector3Array(unique.keys())})
		contacts.append({"name":key, "node":visual.nodes[key], "wheel":key.begins_with("Wheel"), "meshes":meshes, "last":null})

func _process(delta: float) -> void:
	if not measuring or not is_instance_valid(bot) or delta <= 0.0: return
	if visual != bot.nimble_visual: visual.show_state(bot.read_view(), delta)
	var supported: bool = bot.body.grounded and not bot.combat.eliminated
	var lowest_gap := INF
	for contact: Dictionary in contacts:
		var low := _lowest(contact)
		# Slip of the material point that touched the floor last frame.
		var last = contact.last
		if last != null and supported:
			var now: Vector3 = (last.node as Node3D).global_transform * (last.point as Vector3)
			var moved := (now - (last.world as Vector3)).slide(Vector3.UP).length()
			# Only while it still touches: a foot lifting off or a pad launching is not a skid.
			if moved < SNAP_DISTANCE and now.y - _floor_at(now) < CONTACT_GAP:
				stats.slips.append(moved / delta)
		contact.last = null
		if low.is_empty(): continue
		var gap: float = low.world.y - _floor_at(low.world)
		lowest_gap = minf(lowest_gap, gap)
		if gap < CONTACT_GAP: contact.last = _material_point(contact, low.world)
	if not supported or lowest_gap == INF: return
	stats.supported += 1
	stats.gaps.append(lowest_gap)
	stats.gap_sum += maxf(0.0, lowest_gap)
	if lowest_gap >= CONTACT_GAP: stats.hover += 1

## The material point of a contact part to follow into the next frame. A foot
## or pad follows its lowest vertex. A tyre is a polygon of lugs: its lowest
## vertex may sit several degrees from the true bottom and moves even when the
## wheel rolls perfectly, so follow the rim point at that vertex's radius and
## axial position exactly under the axle, which a rolling wheel holds still.
func _material_point(contact: Dictionary, world: Vector3) -> Dictionary:
	var node: Node3D = contact.node
	var local := node.global_transform.affine_inverse() * world
	if contact.wheel:
		var down := (node.global_basis.inverse() * Vector3.DOWN)
		var bottom := Vector2(down.y, down.z).normalized()
		var radius := Vector2(local.y, local.z).length()
		local = Vector3(local.x, bottom.x * radius, bottom.y * radius)
	return {"node":node, "point":local, "world":node.global_transform * local}

func _lowest(contact: Dictionary) -> Dictionary:
	var best := {}
	var best_y := INF
	for entry: Dictionary in contact.meshes:
		var mesh: MeshInstance3D = entry.node
		if not mesh.is_visible_in_tree(): continue
		var xf := mesh.global_transform
		for vertex: Vector3 in entry.vertices:
			var world := xf * vertex
			if world.y < best_y:
				best_y = world.y
				best = {"mesh":mesh, "vertex":vertex, "world":world}
	return best

func _floor_at(point: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point + Vector3.DOWN * 20.0,
		BaselineConfig.WORLD_LAYER, [bot.body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return float(hit.position.y) if not hit.is_empty() else -INF
