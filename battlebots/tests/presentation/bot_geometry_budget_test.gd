extends Node3D
## Highest-detail geometry inventory, not a GPU frame-time or LOD-selection test.
const DRIVES := ["standard_wheels","agile","traction","walker"]
const WEAPONS := ["vertical_spinner","horizontal_spinner","saw","hammer","lifter"]
var failures: Array[String] = []
var mesh_cache: Dictionary = {}
func _ready() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func triangle_count(primitive: int, count: int) -> int:
	match primitive:
		Mesh.PRIMITIVE_TRIANGLES: return count / 3
		Mesh.PRIMITIVE_TRIANGLE_STRIP: return maxi(0,count - 2)
	return 0
func mesh_counts(mesh: Mesh) -> Dictionary:
	var identity := mesh.get_instance_id()
	if mesh_cache.has(identity): return mesh_cache[identity]
	var result := {"triangles":0,"surfaces":mesh.get_surface_count(),"array_mesh_surfaces":0,
		"surfaces_with_lods":0,"surfaces_with_two_lods":0,"coarsest_lod_triangle_bound":0}
	for surface in mesh.get_surface_count():
		var data := RenderingServer.mesh_get_surface(mesh.get_rid(),surface)
		check(not data.is_empty(),"RenderingServer provides real mesh surface data")
		if data.is_empty(): continue
		var indices: int = data.get("index_count",0)
		var vertices: int = data.get("vertex_count",0)
		var primitive: int = data.get("primitive",Mesh.PRIMITIVE_TRIANGLES)
		var triangles := triangle_count(primitive,indices if indices > 0 else vertices)
		result.triangles += triangles
		var coarsest := triangles
		var lods: Array = data.get("lods",[])
		if mesh is ArrayMesh: result.array_mesh_surfaces += 1
		if not lods.is_empty(): result.surfaces_with_lods += 1
		if lods.size() >= 2: result.surfaces_with_two_lods += 1
		var stride := RenderingServer.mesh_surface_get_format_index_stride(int(data.get("format",0)),vertices)
		for lod: Dictionary in lods:
			var packed: PackedByteArray = lod.get("index_data",PackedByteArray())
			if stride > 0: coarsest = mini(coarsest,triangle_count(primitive,packed.size() / stride))
		result.coarsest_lod_triangle_bound += coarsest
	mesh_cache[identity] = result
	return result
func empty_counts() -> Dictionary:
	return {"mesh_instances":0,"triangles":0,"surfaces":0,"array_mesh_surfaces":0,
		"surfaces_with_lods":0,"surfaces_with_two_lods":0,"coarsest_lod_triangle_bound":0}
func collect(model: Node3D) -> Dictionary:
	var visible := empty_counts()
	var hidden := empty_counts()
	var visible_materials: Dictionary = {}
	var top_meshes: Array[Dictionary] = []
	for node: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null: continue
		var counts := mesh_counts(node.mesh)
		var equipped := node.is_visible_in_tree()
		var target: Dictionary = visible if equipped else hidden
		target.mesh_instances += 1
		for key: String in counts: target[key] += counts[key]
		if equipped:
			top_meshes.append({"name":str(node.name),"triangles":counts.triangles,"surfaces":counts.surfaces,"mesh_class":node.mesh.get_class()})
			for surface in node.mesh.get_surface_count():
				var material := node.get_active_material(surface)
				if material != null: visible_materials[material.get_instance_id()] = true
	visible.unique_material_resources = visible_materials.size()
	top_meshes.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.triangles > b.triangles)
	if top_meshes.size() > 5: top_meshes.resize(5)
	return {"visible_equipped":visible,"hidden_unequipped":hidden,"largest_visible_meshes":top_meshes}
func run() -> void:
	var registry := ContentRegistry.new()
	var rows: Array[Dictionary] = []
	for cosmetics: String in ["default","all_optional_modules"]:
		for drive: String in DRIVES:
			for weapon: String in WEAPONS:
				var draft := SawbladeConfig.starter(registry)
				draft.parts.drive = drive
				draft.parts.weapon = weapon
				if cosmetics == "all_optional_modules":
					draft.cosmetics.sawblade.merge({"armor_side":2,"armor_top":1,"armor_front":1,"armor_rear":1,"exhaust":3},true)
				var validation := registry.validate(draft)
				check(validation.valid,"Audit combination validates: " + drive + "/" + weapon)
				if not validation.valid: continue
				var model := SawbladeVisual.new()
				add_child(model)
				model.assemble(validation.loadout,validation.stats.size)
				var row := collect(model)
				row.drive = drive
				row.weapon = weapon
				row.cosmetics = cosmetics
				rows.append(row)
				check(row.visible_equipped.triangles > 0,"Equipped geometry is nonempty")
				model.free()
	check(rows.size() == 40,"All20 drive/weapon combinations measured in both cosmetic profiles")
	var import_config := ConfigFile.new()
	check(import_config.load("res://assets/models/sawblade_runtime/sawblade_runtime.glb.import") == OK,"Read committed model import settings")
	var import_settings := {}
	for key: String in ["meshes/generate_lods","meshes/create_shadow_meshes","array_mesh/deduplicate_surfaces","meshes/force_disable_compression","_subresources"]:
		import_settings[key] = import_config.get_value("params",key,null)
	var maximum: Dictionary = rows[0]
	for row: Dictionary in rows:
		if row.visible_equipped.triangles > maximum.visible_equipped.triangles: maximum = row
	var report := {"engine":Engine.get_version_info().string,"scope":"Authored body, all four drives and five weapons; default and all optional cosmetics. Base geometry only, excludes damage overlays/particles, shadows, arenas and other render passes.",
		"lod_note":"Coarsest LOD triangle bound sums the smallest available index buffers per surface. It is not an observed camera-distance LOD selection or frame-time measurement.",
		"provisional_triangle_target":[20000,40000],"provisional_target_enforced":false,"import_settings":import_settings,
		"maximum_visible":maximum,"combinations":rows}
	var output := OS.get_environment("TEMP").path_join("bot-geometry-budget.json")
	if OS.get_environment("TEMP").is_empty(): output = "user://bot-geometry-budget.json"
	var file := FileAccess.open(output,FileAccess.WRITE)
	check(file != null,"Write geometry audit JSON")
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("BOT GEOMETRY REPORT ",ProjectSettings.globalize_path(output))
	print("MAX VISIBLE ",maximum.drive,"/",maximum.weapon," ",maximum.cosmetics," triangles=",maximum.visible_equipped.triangles," meshes=",maximum.visible_equipped.mesh_instances," surfaces=",maximum.visible_equipped.surfaces," LOD surfaces=",maximum.visible_equipped.surfaces_with_lods)
	for failure: String in failures: push_error(failure)
	if failures.is_empty(): print("BOT GEOMETRY BUDGET PASS")
	get_tree().quit(0 if failures.is_empty() else 1)
