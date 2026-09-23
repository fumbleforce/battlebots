extends Node3D
## Muzzle pressure rings and post-fire barrel smoke from accepted shot snapshots.
var failures := 0

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)

func shot_view(sequence: int, tick: int) -> BotView:
	var view := BotView.new()
	view.server_tick = tick
	view.shot_sequence = sequence
	view.last_shot_tick = tick
	view.last_shot_from = Vector3(0, 1, -1)
	view.last_shot_to = Vector3(0, 1, -12)
	view.weapon_charge_fraction = 1.0
	return view

func run() -> void:
	var rotor := Node3D.new()
	var muzzle := Node3D.new()
	add_child(rotor)
	add_child(muzzle)
	muzzle.position = Vector3(0, 1, -1)
	var effects := MinigunEffects.new()
	add_child(effects)
	effects.configure(rotor, muzzle, 3.0)
	var tick := 0
	effects.show_state(shot_view(0, tick), 1.0 / 60.0)
	check(effects.ring_count() == 0 and effects.barrel_heat == 0.0, "Baseline snapshot fires nothing")
	for shot: int in range(1, 13):
		tick += 5
		effects.show_state(shot_view(shot, tick), 1.0 / 60.0)
	check(effects.ring_count() >= 1 and effects.ring_count() <= MinigunEffects.RINGS, "Each accepted shot pushes a bounded muzzle ring")
	check(effects.barrel_heat > 0.5, "Sustained fire heats the barrel")
	var ring: MeshInstance3D = effects.find_child("MuzzleRing*", false, false)
	check(ring != null and ring.global_transform.basis.y.normalized().is_equal_approx(Vector3.FORWARD),
		"Ring faces along the shot direction")
	var last := shot_view(12, tick)
	for step: int in 20:
		tick += 1
		last.server_tick = tick
		effects.show_state(last, 1.0 / 60.0)
	check(effects.ring_count() == 0, "Rings expire quickly")
	check(effects.smoke.emitting and effects.smoke.amount_ratio > 0.5, "Barrel smokes after the trigger is released")
	check(effects.smoke.global_position.is_equal_approx(muzzle.global_position), "Smoke rises from the barrel tip")
	for step: int in 360:
		tick += 1
		last.server_tick = tick
		effects.show_state(last, 1.0 / 60.0)
	check(not effects.smoke.emitting and effects.barrel_heat == 0.0, "Barrel cools and stops smoking")
	tick += 5
	effects.show_state(shot_view(13, tick), 1.0 / 60.0)
	effects.clear_effects()
	check(effects.ring_count() == 0 and effects.barrel_heat == 0.0 and not effects.smoke.emitting, "Clear removes rings and smoke")
	effects.free()
	if failures == 0: print("MINIGUN EFFECTS PASS")
	get_tree().quit(0 if failures == 0 else 1)
