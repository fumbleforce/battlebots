extends Node3D
## #72 generality: every shipped bot model breaks and sheds parts with no
## per-model authoring. Assembles each real visual (as MvpBot would on a
## client), then checks its part pools and a saw, railgun and mortar break,
## with the time each takes.
const PART_LOSS := preload("res://scripts/presentation/bot_part_loss.gd")
const PIECES := preload("res://scripts/presentation/wreck_pieces.gd")
## Generous per-model ceiling for one break on a headless machine (ms).
const BREAK_BUDGET_MS := 250.0
var failures: Array[String] = []
var registry := ContentRegistry.new()

func _ready() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func models() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	list.append({"label":"sawblade", "draft":SawbladeConfig.starter(registry)})
	list.append({"label":"scorpion", "draft":registry.scorpion()})
	list.append({"label":"atlas", "draft":registry.atlas()})
	for preset: Dictionary in registry.atlas_showcase():
		if preset.name.ends_with("RAIL") or preset.name.ends_with("SHREDDER") or preset.name.ends_with("INFERNO"):
			list.append({"label":preset.name, "draft":preset})
	for preset: Dictionary in registry.nimble():
		list.append({"label":preset.name, "draft":preset})
	for style: String in ["bruiser", "sentry", "wedge"]:
		list.append({"label":"practice " + style, "practice":style, "draft":registry.starter()})
	return list

## The visual MvpBot would build, parented to a presentation root.
func assemble(model: Dictionary, presentation: Node3D, size: Vector3) -> Node3D:
	var draft: Dictionary = model.draft
	var visual: Node3D
	if model.has("practice"):
		visual = PracticeNpcVisual.new()
		presentation.add_child(visual)
		visual.assemble(model.practice, size)
	elif NimbleBots.enabled(draft):
		visual = NimbleVisual.new()
		presentation.add_child(visual)
		visual.assemble(draft, size)
	elif AtlasGeometry.enabled(draft):
		visual = AtlasVisual.new()
		presentation.add_child(visual)
		visual.assemble(draft, size)
	elif ScorpionVisual.enabled(draft):
		visual = ScorpionVisual.new()
		presentation.add_child(visual)
		visual.assemble(draft, size)
	else:
		visual = SawbladeVisual.new()
		presentation.add_child(visual)
		visual.assemble(draft, size)
	return visual

func run() -> void:
	for model: Dictionary in models():
		var validation := registry.validate(model.draft)
		if not validation.valid:
			check(false, "%s preset is legal: %s" % [model.label, validation.reasons])
			continue
		var size: Vector3 = validation.stats.size
		var presentation := Node3D.new()
		add_child(presentation)
		presentation.global_transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(0, 2, 0))
		var visual := assemble(model, presentation, size)
		var groups: Dictionary = visual.component_meshes()
		var loss: Node3D = PART_LOSS.new()
		add_child(loss)
		var started := Time.get_ticks_usec()
		loss.configure(presentation, groups, size, 5)
		var configure_ms := (Time.get_ticks_usec() - started) / 1000.0
		var weapon: int = loss.pools.weapon.size()
		var drives: int = loss.pools.drive_left.size() + loss.pools.drive_right.size()
		var panels := 0
		for face: String in PART_LOSS.FACES:
			panels += loss.pools[face].size()
		check(weapon + drives + panels >= 3, "%s has parts to lose: weapon %d, drive %d, panels %d" % [model.label, weapon, drives, panels])
		var line := "%s: weapon %d, drive %d, panel clusters %d, configure %.1f ms" % [model.label, weapon, drives, panels, configure_ms]
		var frame := presentation.global_transform
		var captured := PIECES.capture(presentation, frame)
		var bounds := PIECES.bounds_of(captured)
		var scale := BotScale.from_size(size)
		for kind: String in ["saw", "railgun", "mortar"]:
			started = Time.get_ticks_usec()
			var death := {"kind":kind, "point":bounds.get_center() + Vector3(0, 0, -bounds.size.z * 0.5),
				"axis":Vector3.RIGHT if kind == "saw" else Vector3.BACK, "force":5.0}
			var layout := PIECES.plan(death, bounds, 5, scale)
			var bodies := PIECES.build(captured, frame, layout, StandardMaterial3D.new())
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			var cut := 0
			var meshes := 0
			for body: RigidBody3D in bodies:
				for child: Node in body.get_children():
					if child is MeshInstance3D:
						meshes += 1
						if child.get_surface_override_material(0) is ShaderMaterial and child.get_surface_override_material(0).shader == PIECES.SURFACE:
							cut += 1
				body.free()
			var expected := 5 if kind == "mortar" else 2
			check(bodies.size() == expected, "%s %s break makes %d pieces: %d" % [model.label, kind, expected, bodies.size()])
			check(cut > 0, "%s %s break cuts real surfaces" % [model.label, kind])
			check(elapsed < BREAK_BUDGET_MS, "%s %s break takes %.1f ms" % [model.label, kind, elapsed])
			line += " | %s %d pieces %d meshes (%d cut) %.1f ms" % [kind, bodies.size(), meshes, cut, elapsed]
		print(line)
		loss.queue_free()
		presentation.queue_free()
		await get_tree().process_frame
	for failure: String in failures:
		push_error(failure)
	print("DESTRUCTION MODELS PASS" if failures.is_empty() else "DESTRUCTION MODELS FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)
