class_name AuthorityWorld
extends Node3D
## Physics-only session world. The session owns timing, commands and match rules.
var bots: Dictionary = {}
var registry := ContentRegistry.new()
var weapons := CombatWorld.new()
var tick := 0
var credited: Dictionary = {}

func _ready() -> void:
	make_box(Vector3(50, 1, 50), Vector3(0, -0.5, 0))
	make_box(Vector3(52, 3, 1), Vector3(0, 1.5, -25.5))
	make_box(Vector3(52, 3, 1), Vector3(0, 1.5, 25.5))
	make_box(Vector3(1, 3, 50), Vector3(-25.5, 1.5, 0))
	make_box(Vector3(1, 3, 50), Vector3(25.5, 1.5, 0))
	for x: int in [-1, 1]:
		for z: int in [-1, 1]:
			# Match B's 2 m chamfer: interior plane passes through (+/-24,+/-24).
			var corner := make_box(Vector3(4.242641, 3, 1), Vector3(x * 24.353553, 1.5, z * 24.353553))
			corner.rotation.y = x * z * PI / 4

func make_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	node.add_child(collision)
	node.position = position
	if DisplayServer.get_name() != "headless":
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.24, 0.29)
		mesh.material = material
		visual.mesh = mesh
		node.add_child(visual)
	add_child(node)
	return node

func spawn(id: int, team: int, slot: int, loadout: Dictionary) -> MvpBot:
	var bot := MvpBot.create(id, team, loadout, registry)
	if bot == null:
		return null
	bot.name = "Bot%d" % id
	add_child(bot)
	var pose := Transform3D(Basis(Vector3.UP, 0.0 if team == 0 else PI), Vector3(-6 if slot == 0 else 6, 0.5, 19 if team == 0 else -19))
	bot.spawn_pose = pose
	bot.body.reset_pose = pose
	bot.previous_pose = pose
	bots[id] = bot
	return bot

func reset_round() -> void:
	weapons = CombatWorld.new()
	credited.clear()
	for id: int in bots:
		bots[id].reset_round()

func step(delta: float, active: bool, round_index: int) -> void:
	tick += 1
	for id: int in bots:
		bots[id].server_tick = tick
		bots[id].step(delta, active)
	if active:
		weapons.step(delta, bots, tick, round_index)
	for id: int in bots:
		var bot: MvpBot = bots[id]
		if not bot.combat.eliminated or credited.has(id):
			continue
		credited[id] = true
		bot.body.collision_layer = 0
		bot.body.collision_mask = 0
		bot.body.freeze = true
		var latest := -1.0
		var killer := 0
		for source_id: int in bot.combat.recent_attackers:
			var at: float = bot.combat.recent_attackers[source_id]
			if weapons.time - at <= 10 and at > latest:
				latest = at
				killer = source_id
		if killer != 0 and bots.has(killer):
			bots[killer].combat.eliminations += 1
		for source_id: int in bot.combat.recent_attackers:
			if source_id != killer and bots.has(source_id) and weapons.time - float(bot.combat.recent_attackers[source_id]) <= 10:
				bots[source_id].combat.assists += 1

func combatants() -> Dictionary:
	var result := {}
	for id: int in bots:
		result[id] = bots[id].combat
	return result

func clear_bots() -> void:
	for id: int in bots:
		bots[id].queue_free()
	bots.clear()
	credited.clear()
	weapons = CombatWorld.new()
