extends SceneTree
var failures:=0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool,message:String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	var bay:=load("res://assets/models/lunar/baked_service_bay.tscn").instantiate() as Node3D
	var gi:=bay.get_node("IndirectLight") as LightmapGI
	check(gi.light_data!=null and gi.light_data.lightmap_textures.size()>0,"Baked indirect textures present")
	check(gi.light_data.get_user_count()>100,"Outpost geometry is baked")
	for i:int in range(gi.light_data.get_user_count()):
		check(gi.get_node_or_null(gi.light_data.get_user_path(i)) is MeshInstance3D,"Every baked receiver resolves")
	bay.free()
	var world:=AuthorityWorld.new()
	world.arena_id="moon"
	root.add_child(world)
	check(world.arena.find_children("*","FogVolume",true,false).is_empty(),"Headless excludes volumes")
	check(world.arena.find_children("*","GPUParticles3D",true,false).is_empty(),"Headless excludes particles")
	check(world.arena.get_node("FoundryVisuals").get_child_count()==0,"Headless excludes asset kit")
	world.queue_free()
	await process_frame
	print("LUNAR ASSET PASS" if failures==0 else "LUNAR ASSET FAIL")
	quit(0 if failures==0 else 1)
